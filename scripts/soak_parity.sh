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

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$REPO/tools/godot4/godot4}"
TARGET="${SOAK_TARGET:-200}"
MAX_RUNS="${SOAK_RUNS:-80}"
SAVES="${SOAK_SAVES:-0 1 2 3 4 5 6 7}"
STATE="$REPO/godot_d1_3d/logs/parity_state.json"

if [[ ! -x "$GODOT" ]]; then
	echo "Godot binary not found: $GODOT (set GODOT=...)" >&2
	exit 1
fi

echo "[SOAK] target=$TARGET runs<=${MAX_RUNS} saves=(${SAVES}) state=$STATE"

pass=0
for run in $(seq 1 "$MAX_RUNS"); do
	for slot in $SAVES; do
		out="$(SOAK_SAVE=$slot "$GODOT" --headless --path "$REPO/godot_d1_3d" --script res://test_parity_soak.gd 2>&1 | grep -v 'Texture format not supported')"
		echo "$out" | grep -E '^\[PARITY\]|^\[SOAK\]'
		if echo "$out" | grep -q '"promotable": true'; then
			echo "[SOAK] target reached after $run pass(es)"
			exit 0
		fi
		if echo "$out" | grep -q 'MISMATCH'; then
			echo "[SOAK] mismatch recorded — stopping (a mismatch invalidates promotion)"
			exit 1
		fi
	done
	pass=$((pass + 1))
done

echo "[SOAK] final state:"
grep -E '"checks"|"distinct"|"mismatches"|"promotable"|"authority"' "$STATE" | head -25
