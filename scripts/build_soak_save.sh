#!/usr/bin/env bash
# Build the soak fixture generator (tests/make_soak_save.cpp).
# Links against the DevilutionX build tree's object files, so it uses the exact same
# save-codec / MPQ code the game itself uses.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
B="$root/DevilutionX/build"
O="$B/Source/CMakeFiles/libdevilutionx.dir"
L="$B/3rdParty"

INC="-I $root/DevilutionX/Source -I $root/DevilutionX/3rdParty/tl"
INC="$INC -I $B/_deps/sdl2-src/include -I $B/_deps/libmpq-src -I $B/_deps/libfmt-src/include"
INC="$INC -I $B/_deps/sdl_audiolib-src/include -I $B/_deps/sdl_audiolib-build"

g++ -std=c++17 $INC "$root/tests/make_soak_save.cpp" \
  "$O/codec.cpp.o" "$O/encrypt.cpp.o" "$O/sha.cpp.o" \
  "$O/mpq/mpq_reader.cpp.o" "$O/mpq/mpq_writer.cpp.o" \
  "$O/utils/logged_fstream.cpp.o" "$O/utils/file_util.cpp.o" \
  "$O/engine/direction.cpp.o" \
  "$L/libmpq/CMakeFiles/libmpq.dir/__/__/_deps/libmpq-src/libmpq"/*.o \
  "$L/PKWare/CMakeFiles/PKWare.dir"/*.o \
  "$L/bzip2/CMakeFiles/BZip2.dir/__/__/_deps/bzip2-src"/*.o \
  "$L/bzip2/CMakeFiles/BZip2.dir/bz_internal_error.c.o" \
  "$B/_deps/libfmt-build/libfmt.a" -lz \
  "$B/_deps/sdl2-build/libSDL2-2.0.so" \
  -o "$root/tools/make_soak_save"

echo "built: $root/tools/make_soak_save"

# Fixture slots: copies of a real hero with low HP/mana so the checks exercise real effects instead
# of trivial 0 == 0. The sources are chosen to cover every class-bonus branch in
# RestorePartialLife/RestorePartialMana (Warrior/Barbarian *2, Rogue/Monk/Bard +1/2, Sorcerer *2),
# so each fixture is a genuinely distinct parity case, not padding.
SAVE_DIR="${SAVE_DIR:-$HOME/.local/share/diasurgical/devilution}"
# slot source div
FIXTURE_SPECS="${FIXTURE_SPECS:-8 0 8  9 2 4  10 3 2  11 4 16  12 1 8}"
if [[ "${FIXTURES:-1}" == "1" ]]; then
  read -ra specs <<< "$FIXTURE_SPECS"
  i=0
  while (( i + 2 < ${#specs[@]} )); do
    slot=${specs[i]}; src_slot=${specs[i+1]}; div=${specs[i+2]}
    i=$((i + 3))
    src="$SAVE_DIR/single_$src_slot.hsv"
    [[ -f "$src" ]] || { echo "no source save: $src" >&2; continue; }
    cp "$src" "$SAVE_DIR/single_$slot.hsv"
    "$root/tools/make_soak_save" "$SAVE_DIR" "$slot" "$div"
  done
fi
