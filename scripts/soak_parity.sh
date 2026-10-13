#!/usr/bin/env bash
# Parity soak driver: run the soak harness repeatedly until the shadow subsystems reach the
# promotion gate. Each run loads one hero from disk (so the run starts from a known state), and
# the driver cycles through the save slots so the checks cover different heroes, states and RNG
# streams — 200 repeats of the same deterministic case would prove nothing, which is why the
# authority also requires MIN_DISTINCT distinct cases.
#
# Counters accumulate in godot_d1_3d/logs/parity_state.json.
#
# Usage: ./scripts/soak_parity.sh                 # 200 checks, up to 80 passes
#        SOAK_TARGET=20 SOAK_RUNS=8 ./scripts/soak_parity.sh
#        SOAK_TRANSITION=1 -> also drive real level changes (walk the hero onto a stairs
#        trigger); slow, but it is the only way to cover the transition window.
#        SOAK_RESET=all   -> zero the counters before the first run (required after any change
#                            to the mirrors: old evidence describes code that no longer exists).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$REPO/tools/godot4/godot4}"
TARGET="${SOAK_TARGET:-200}"
MAX_RUNS="${SOAK_RUNS:-80}"
SAVES="${SOAK_SAVES:-0 1 2 3 4 5 6 7 8 9 10 11 12}"
STATE="$REPO/godot_d1_3d/logs/parity_state.json"
SAVE_DIR="${SOAK_SAVE_DIR:-$HOME/.local/share/diasurgical/devilution}"
FIXTURE_SLOT="${SOAK_FIXTURE_SLOT:-8}"
FIXTURE_SRC="${SOAK_FIXTURE_SRC:-0}"
FIXTOOL="$REPO/tools/make_soak_save"

# The harness reads SOAK_* straight from its own environment. Anything the user exports for this
# driver has to be captured into driver-local names and removed from the environment, otherwise it
# leaks into EVERY godot process. That leak was fatal once: SOAK_RESET=all in the environment made
# each of the nine processes zero the counters it had just loaded, so the evidence never
# accumulated across saves and the counters sat at exactly one process' worth forever.
RESET="${SOAK_RESET:-}"; unset SOAK_RESET
PROMOTE="${SOAK_PROMOTE:-}"; unset SOAK_PROMOTE
ITEMS="${SOAK_ITEMS:-}"; unset SOAK_ITEMS
TRANSITION="${SOAK_TRANSITION:-}"; unset SOAK_TRANSITION
unset SOAK_TARGET SOAK_SAVE

# The fixture hero starts nearly empty so the item effects are non-zero (a full hero predicts a
# zero effect, which the harness skips). The seed is varied per pass because the draws — and with
# them the effects and the distinct-case signatures — follow glSeedTbl[currlevel], not the HP or
# mana values: re-running the same fixture only ever replays the same three cases.
DIVISORS=(48 24 12 6 3 2)
SEEDS=(987654321 123456789 2024010101 55512345 777777777 314159265 161803398 8675309)

if [[ ! -x "$GODOT" ]]; then
	echo "Godot binary not found: $GODOT (set GODOT=...)" >&2
	exit 1
fi

echo "[SOAK] target=$TARGET runs<=${MAX_RUNS} saves=(${SAVES}) state=$STATE"

pass=0
first=1
for run in $(seq 1 "$MAX_RUNS"); do
	for slot in $SAVES; do
		env_args=(SOAK_SAVE="$slot" SOAK_TARGET="$TARGET")
		[[ -n "$TRANSITION" ]] && env_args+=(SOAK_TRANSITION="$TRANSITION")
		[[ -n "$ITEMS" ]] && env_args+=(SOAK_ITEMS="$ITEMS")
		if [[ $first == 1 && -n "$RESET" ]]; then
			env_args+=(SOAK_RESET="$RESET")
			first=0
		fi

		if [[ "$slot" == "$FIXTURE_SLOT" && -x "$FIXTOOL" ]]; then
			i=$(( (pass - 1) % ${#DIVISORS} ))
			j=$(( ((pass - 1) * ${#SAVES} + run) % ${#SEEDS} ))
			cp -f "$SAVE_DIR/single_${FIXTURE_SRC}.hsv" "$SAVE_DIR/single_${slot}.hsv" \
				|| { echo "[SOAK] cannot copy fixture source single_${FIXTURE_SRC}.hsv" >&2; exit 1; }
			"$FIXTOOL" "$SAVE_DIR" "$slot" "${DIVISORS[$i]}" "${SEEDS[$j]}" \
				| sed 's/^/[SOAK] fixture: /'
		fi

		out="$(env "${env_args[@]}" "$GODOT" --headless --path "$REPO/godot_d1_3d" --script res://test_parity_soak.gd 2>&1 | grep -v 'Texture format not supported')"
		echo "$out" | grep -E '^\[PARITY\]|^\[SOAK\] (rng|level|save|RNG|GATE|restored)'
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

if [[ -n "$PROMOTE" ]]; then
	echo "[SOAK] attempting handover for: $PROMOTE"
	env SOAK_PROMOTE="$PROMOTE" "$GODOT" --headless --path "$REPO/godot_d1_3d" \
		--script res://test_parity_soak.gd 2>&1 | grep -E '^\[SOAK\] (PROMOTED|NOT)'
fi

echo "[SOAK] final state:"
grep -E '"checks"|"distinct"|"mismatches"|"promotable"|"authority"' "$STATE" | head -25
