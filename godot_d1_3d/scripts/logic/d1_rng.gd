class_name D1RNG
extends RefCounted

## Native Godot mirror of the DevilutionX vanilla LCG (Source/engine/random.cpp).
## std::linear_congruential_engine<uint32_t, 0x015A4E35, 1, 0>
## Deterministic and side-effect free: the native logic layer must be able to
## reproduce the C++ RNG stream exactly, otherwise parity tests are meaningless.

const LCG_MULTIPLIER := 0x015A4E35
const LCG_INCREMENT := 1
const UINT32_MASK := 0xFFFFFFFF
const INT32_MIN := -2147483648

var seed := 0


func _init(initial_seed: int = 0) -> void:
	seed = initial_seed & UINT32_MASK


func generate_seed() -> int:
	seed = (seed * LCG_MULTIPLIER + LCG_INCREMENT) & UINT32_MASK
	return seed


func advance_rnd_seed() -> int:
	var s := generate_seed()
	var signed := s - 0x100000000 if s >= 0x80000000 else s
	if signed == INT32_MIN:
		return INT32_MIN
	return abs(signed)


func generate_rnd(v: int) -> int:
	if v <= 0:
		return 0
	if v <= 0x7FFF:
		# High bits are used to correct LCG bias (vanilla behaviour).
		return (advance_rnd_seed() >> 16) % v
	return advance_rnd_seed() % v


func flip_coin(frequency: int) -> bool:
	return generate_rnd(frequency) == 0


func snapshot() -> Dictionary:
	return {"seed": seed, "name": "D1RNG"}
