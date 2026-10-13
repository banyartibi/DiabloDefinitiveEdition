#!/usr/bin/env bash
# Parity soak driver: run the soak harness repeatedly until `inventory_item_use` reaches the
# promotion threshold. Each run loads one hero from disk (so the run starts from a known state),
# and the driver cycles through the save slots so the checks cover different heroes, states and
# RNG streams — 200 repeats of the same deterministic case would prove nothing, which is why the
# authority also requires MIN_DISTINCT distinct cases.
#
# Counters accumulate in godot_d1_3d/logs/parity_state.json.
#
# Usage: ./scripts/soak_parity.sh                 # 200 checks, up to 80 runs
#        SOAK_TARGET=20 SOAK_RUNS=8 ./scripts/soak_parity.sh
#        SOAK_TRANSITION=1 -> also drive real level changes (walk the hero onto a stairs
#        trigger); slow, but it is the only way to cover the transition window.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$REPO/tools/godot4/godot4}"
TARGET="${SOAK_TARGET:-200}"
MAX_RUNS="${SOAK_RUNS:-80}"
SAVES="${SOAK_SAVES:-0 1 2 3 4 5 6 7 8 9 10 11 12}"
STATE="$REPO/godot_d1_3d/logs/parity_state.json"
# Both are opt-in pass-throughs to the harness. They MUST have defaults: under `set -u` an
# unset variable aborts the command line, which silently skipped every godot invocation and
# left the counters frozen at whatever the previous manual run had recorded.
SOAK_TRANSITION="${SOAK_TRANSITION:-}"
SOAK_RESET="${SOAK_RESET:-}"

if [[ ! -x "$GODOT" ]]; then
	echo "Godot binary not found: $GODOT (set GODOT=...)" >&2
	exit 1
fi

echo "[SOAK] target=$TARGET runs<=${MAX_RUNS} saves=(${SAVES}) state=$STATE"

pass=0
# Reset is opt-in: SOAK_RESET=all re-measures from zero, which is required whenever the mirror
# itself changed (evidence recorded against old code describes code that no longer exists).
first=1
for run in $(seq 1 "$MAX_RUNS"); do
	for slot in $SAVES; do
		if [[ $first == 1 && -n "${SOAK_RESET:-}" ]]; then
			out="$(SOAK_SAVE=$slot SOAK_RESET="$SOAK_RESET" SOAK_TRANSITION="$SOAK_TRANSITION" "$GODOT" --headless --path "$REPO/godot_d1_3d" --script res://test_parity_soak.gd 2>&1 | grep -v 'Texture format not supported')"
			first=0
		else
			out="$(SOAK_SAVE=$slot SOAK_TRANSITION="$SOAK_TRANSITION" "$GODOT" --headless --path "$REPO/godot_d1_3d" --script res://test_parity_soak.gd 2>&1 | grep -v 'Texture format not supported')"
		fi
		echo "$out" | grep -E '^\[PARITY\]|^\[SOAK\] (rng|level|save|RNG|GATE)'
		if echo "$out" | grep -q 'MISMATCH'; then
			echo "[SOAK] mismatch recorded — stopping (a mismatch invalidates promotion)"
			exit 1
		fi
	done
	pass=$((pass + 1))
	report="$(python3 - "$STATE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
rep = {s: (d["checks"].get(s, 0), len(d.get("seen", {}).get(s, {})), d["mismatches"].get(s, 0), d["authority"].get(s)) for s in d["checks"]}
print(" ".join(f"{s}:checks={v[0]} distinct={v[1]} bad={v[2]}" for s, v in rep.items()))
done = all(d["mismatches"].get(s, 0) == 0 and d["checks"].get(s, 0) >= 200 and len(d.get("seen", {}).get(s, {})) >= 12
           for s in ("inventory_item_use", "rng"))
sys.exit(0 if done else 7)
PY
)"
	rc=$?
	echo "[SOAK] pass $pass -> $report"
	if [[ $rc == 0 ]]; then
		echo "[SOAK] inventory_item_use and rng reached the gate after $pass pass(es)"
		break
	fi
done

echo "[SOAK] final state:"
grep -E '"checks"|"distinct"|"mismatches"|"promotable"|"authority"' "$STATE" | head -25
