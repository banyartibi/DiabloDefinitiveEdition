class_name UpscalerModelConfig
## Central configuration for the Multi-Model Neural Upscaler system.
## Defines 6 offline AI upscaling models, their directory suffixes, display names,
## and provides helper functions for resolving asset paths with graceful fallback.
##
## Models run offline via realesrgan-ncnn-vulkan / ChaiNNer-cli on Vulkan GPU.
## Each model stores its pre-upscaled assets in parallel directory structures.

## Model indices — used throughout the engine as int IDs
enum Model {
	ULTRASHARP = 0,   ## Real-ESRGAN 4x-UltraSharp (default, sharpest photo-realistic)
	X4PLUS = 1,       ## Real-ESRGAN x4plus (general purpose, slightly softer)
	HAT_S = 2,        ## Nomos8k HAT-S (Hybrid Attention Transformer — best dither→photo)
	HAT_L = 3,        ## HAT-L (Large HAT — highest quality, slowest)
	NMKD = 4,         ## 4x_NMKD_Superscale (retro CGI / game textures, grim-dark gothic)
	OMNISR = 5,       ## Compact / OmniSR (fastest, minimal VRAM)
}

## Directory suffixes appended to base tile folder names (e.g. "dungeon_pbr_cathedral_4x" + suffix)
const TILE_SUFFIXES: Array[String] = [
	"",             # 0: Real-ESRGAN 4x-UltraSharp (default — no suffix, uses existing _4x dirs)
	"_x4plus",      # 1: Real-ESRGAN x4plus
	"_hat_s",       # 2: Nomos8k HAT-S
	"_hat_l",       # 3: HAT-L
	"_nmkd",        # 4: 4x_NMKD_Superscale
	"_omnisr",      # 5: Compact / OmniSR
]

## Human-readable display names for the pause-menu UI
const MODEL_NAMES: Array[String] = [
	"Real-ESRGAN 4x-UltraSharp (Default)",
	"Real-ESRGAN x4plus (General)",
	"Nomos8k HAT-S (Hybrid Attention)",
	"HAT-L (Large Hybrid Attention)",
	"4x_NMKD_Superscale (Retro Gothic)",
	"Compact / OmniSR (Fast)",
]

## Short names for OSD display
const MODEL_SHORT_NAMES: Array[String] = [
	"UltraSharp",
	"x4plus",
	"HAT-S",
	"HAT-L",
	"NMKD",
	"OmniSR",
]

## Directory suffixes for HD sprite folders (e.g. "hd_sprites" + suffix)
const SPRITE_SUFFIXES: Array[String] = [
	"",             # 0: hd_sprites/
	"_x4plus",      # 1: hd_sprites_x4plus/
	"_hat_s",       # 2: hd_sprites_hat_s/
	"_hat_l",       # 3: hd_sprites_hat_l/
	"_nmkd",        # 4: hd_sprites_nmkd/
	"_omnisr",      # 5: hd_sprites_omnisr/
]

## Total number of available models
static func get_model_count() -> int:
	return MODEL_NAMES.size()

static func _get_base_tile_folder(level_idx: int) -> String:
	if level_idx <= 0:
		return "res://assets/dungeon_pbr_town_4x"
	elif level_idx >= 1 and level_idx <= 4:
		return "res://assets/dungeon_pbr_cathedral_4x"
	elif level_idx >= 5 and level_idx <= 8:
		return "res://assets/dungeon_pbr_catacombs_4x"
	elif level_idx >= 9 and level_idx <= 12:
		return "res://assets/dungeon_pbr_caves_4x"
	else:
		return "res://assets/dungeon_pbr_hell_4x"

## Returns the full tile folder path for a given level index and model ID.
## For model 0 (UltraSharp), returns the existing directory without suffix.
## For other models, appends the model's suffix to the base folder name.
static func get_tile_folder(level_idx: int, model_id: int) -> String:
	var base = _get_base_tile_folder(level_idx)
	if base == "":
		return ""
	var safe_id = clampi(model_id, 0, TILE_SUFFIXES.size() - 1)
	return base + TILE_SUFFIXES[safe_id]

## Returns the HD sprite folder path for a given model ID.
static func get_sprite_folder(model_id: int) -> String:
	var safe_id = clampi(model_id, 0, SPRITE_SUFFIXES.size() - 1)
	return "res://assets/hd_sprites" + SPRITE_SUFFIXES[safe_id]

## Checks whether a model has offline assets installed (either 4X tiles or HD sprites).
## Returns true if the model is ready to use in the engine.
static func model_available(_level_idx: int, model_id: int) -> bool:
	var safe_id = clampi(model_id, 0, MODEL_NAMES.size() - 1)
	if safe_id == 0:
		return true
	# Check dedicated HD sprites folder
	var sprite_folder = get_sprite_folder(safe_id)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(sprite_folder)):
		return true
	# Check dedicated 4X PBR tiles folder (Cathedral L1 theme)
	var cath_folder = get_tile_folder(1, safe_id)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cath_folder + "/albedo")):
		return true
	return false

## Returns the display name for a given model ID, with "(Not Installed)" suffix
## if the model's assets are not found for the specified level.
static func get_model_display_name(model_id: int, level_idx: int = 1) -> String:
	var safe_id = clampi(model_id, 0, MODEL_NAMES.size() - 1)
	var name = MODEL_NAMES[safe_id]
	if safe_id > 0 and not model_available(level_idx, safe_id):
		name += " (Not Installed)"
	return name

## Returns the OSD-friendly short name for a given model ID.
static func get_model_short_name(model_id: int) -> String:
	var safe_id = clampi(model_id, 0, MODEL_SHORT_NAMES.size() - 1)
	return MODEL_SHORT_NAMES[safe_id]

## Returns the secondary fallback folder for Cathedral levels (the generic dungeon_pbr_4x).
## This is used when the primary model-specific folder doesn't have a specific piece.
static func get_fallback_tile_folder(level_idx: int, model_id: int) -> String:
	# For Cathedral levels, try the generic dungeon_pbr_4x folder as secondary fallback
	if level_idx >= 1 and level_idx <= 4:
		var safe_id = clampi(model_id, 0, TILE_SUFFIXES.size() - 1)
		return "res://assets/dungeon_pbr_4x" + TILE_SUFFIXES[safe_id]
	return ""
