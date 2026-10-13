#!/usr/bin/env bash
# Build soak fixture variants.
#
# A real hero loaded at full HP/mana produces no evidence: the first potion tops the hero up and
# every later check is a trivial 0 == 0. The fixture generator copies a real save to a scratch
# slot and drops HP/mana there, so the predicted gain is actually observable.
#
# Real saves (slots 0-12) are never modified - the variants live in slots 20+ (MAX_CHARACTERS is
# 99, see Source/pfile.h). Each variant keeps its source hero's class, level and glSeedTbl, so
# the RNG stream differs per variant and the checks are genuinely distinct cases rather than the
# same deterministic case repeated.
#
# Usage: ./scripts/build_soak_fixtures.sh                 # slots 0-7 -> 20-27, HP/mana = max/8
#        SOAK_SRC="0 2 4" SOAK_DIV=16 ./scripts/build_soak_fixtures.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAVE_DIR="${SAVE_DIR:-$HOME/.local/share/diasurgical/devilution}"
BASE="${SOAK_BASE_SLOT:-20}"
DIV="${SOAK_DIV:-8}"
SRCS="${SOAK_SRC:-0 1 2 3 4 5 6 7}"
TOOL="$REPO/tools/make_soak_save"

if [[ ! -x "$TOOL" ]]; then
	echo "fixture tool not built: $TOOL (run ./scripts/build_soak_save.sh)" >&2
	exit 1
fi

built=0
for src in $SRCS; do
	src_file="$SAVE_DIR/single_${src}.hsv"
	if [[ ! -f "$src_file" ]]; then
		echo "[FIXTURE] skip slot $src (no save)"
		continue
	fi
	slot=$((BASE + src))
	dst="$SAVE_DIR/single_${slot}.hsv"
	rm -f "$dst"
	cp "$src_file" "$dst"
	if "$TOOL" "$SAVE_DIR" "$slot" "$DIV"; then
		built=$((built + 1))
	else
		echo "[FIXTURE] failed for slot $src -> $slot" >&2
		rm -f "$dst"
	fi
done
echo "[FIXTURE] built $built variant(s) in slots ${BASE}+ under $SAVE_DIR"
