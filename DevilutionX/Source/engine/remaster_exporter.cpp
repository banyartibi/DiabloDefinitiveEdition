/**
 * @file remaster_exporter.cpp
 *
 * Full Master 4x-UltraSharp AI sprite export and remastering pipeline.
 */
#include "engine/remaster_exporter.hpp"

#include <SDL.h>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

#include "cursor.h"
#include "engine/assets.hpp"
#include "engine/clx_sprite.hpp"
#include "engine/dx.h"
#include "engine/load_cel.hpp"
#include "engine/load_cl2.hpp"
#include "engine/palette.h"
#include "engine/render/clx_render.hpp"
#include "engine/surface.hpp"
#include "misdat.h"
#include "objdat.h"
#include "utils/log.hpp"
#include "utils/png.h"

namespace fs = std::filesystem;

namespace devilution {

namespace {

// Level theme palettes available in the MPQs. A monster, missile or object CEL
// stores palette indices that only carry colour in the palette of the level
// theme it belongs to; the wrong palette renders a pure-black silhouette.
const char *const kLevelPaletteCandidates[] = {
	"levels\\l1data\\l1_1.pal", "levels\\l1data\\l1_2.pal", "levels\\l1data\\l1_3.pal", "levels\\l1data\\l1_4.pal",
	"levels\\l2data\\l2_1.pal", "levels\\l2data\\l2_2.pal", "levels\\l2data\\l2_3.pal", "levels\\l2data\\l2_4.pal",
	"levels\\l3data\\l3_1.pal", "levels\\l3data\\l3_2.pal", "levels\\l3data\\l3_3.pal", "levels\\l3data\\l3_4.pal",
	"levels\\l4data\\l4_1.pal", "levels\\l4data\\l4_2.pal", "levels\\l4data\\l4_3.pal", "levels\\l4data\\l4_4.pal",
	"nlevels\\l5data\\l5_1.pal", "nlevels\\l5data\\l5_2.pal", "nlevels\\l5data\\l5_3.pal", "nlevels\\l5data\\l5_4.pal",
	"nlevels\\l5data\\l5base.pal",
	"nlevels\\l6data\\l6_1.pal", "nlevels\\l6data\\l6_2.pal", "nlevels\\l6data\\l6_3.pal", "nlevels\\l6data\\l6_4.pal",
	"nlevels\\l7data\\l7_1.pal", "nlevels\\l7data\\l7_2.pal", "nlevels\\l7data\\l7_3.pal", "nlevels\\l7data\\l7_4.pal",
	"nlevels\\l8data\\l8_1.pal", "nlevels\\l8data\\l8_2.pal", "nlevels\\l8data\\l8_3.pal", "nlevels\\l8data\\l8_4.pal",
	"levels\\l11data\\l11_1.pal", "levels\\l13data\\l13_1.pal", "levels\\l15data\\l15_1.pal", "levels\\l16data\\l16_1.pal",
	"levels\\towndata\\town.pal",
};

// Palette indices actually used by the first non-empty sprite of a CL2/CEL.
// Index 0 is the transparent index.
bool CollectCelPaletteIndices(const std::string &assetPath, uint16_t widthHint, std::array<bool, 256> &used)
{
	std::optional<OwnedClxSpriteListOrSheet> clx;
	if (FindAsset((assetPath + ".cl2").c_str()).ok()) {
		clx.emplace(LoadCl2ListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widthHint)));
	} else if (FindAsset((assetPath + ".cel").c_str()).ok()) {
		clx.emplace(LoadCelListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widthHint)));
	} else {
		return false;
	}
	if (clx->dataSize() == 0)
		return false;
	ClxSpriteList list = clx->isSheet() ? clx->sheet()[0] : clx->list();
	for (size_t f = 0; f < list.numSprites(); ++f) {
		ClxSprite sprite = list[f];
		const int w = sprite.width();
		const int h = sprite.height();
		if (w <= 0 || h <= 0)
			continue;
		SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
		if (surface8 == nullptr)
			return false;
		std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);
		Surface out(surface8);
		RenderClxSprite(out, sprite, { 0, 0 });
		const uint8_t *px = static_cast<const uint8_t *>(surface8->pixels);
		for (int y = 0; y < h; ++y) {
			for (int x = 0; x < w; ++x) {
				const uint8_t index = px[y * surface8->pitch + x];
				if (index != 0)
					used[index] = true;
			}
		}
		SDL_FreeSurface(surface8);
		return true;
	}
	return false;
}

// How many of the CEL's colour indices the currently loaded palette renders in
// colour rather than black. 0 means the sprite would export as a silhouette.
int ScoreCurrentPalette(const std::array<bool, 256> &used)
{
	const SDL_Color *colors = orig_palette.data();
	int score = 0;
	for (int i = 1; i < 256; ++i) {
		if (!used[i])
			continue;
		if (colors[i].r + colors[i].g + colors[i].b > 30)
			++score;
	}
	return score;
}

// Picks the level palette that gives a CEL the most colour.
const char *PickLevelPalette(const std::vector<std::string> &assetPaths, uint16_t widthHint)
{
	std::array<bool, 256> used{};
	for (const std::string &path : assetPaths)
		CollectCelPaletteIndices(path, widthHint, used);
	const int usedCount = static_cast<int>(std::count(used.begin(), used.end(), true));
	if (usedCount == 0) {
		Log("PickLevelPalette: {} produced no palette indices", assetPaths.empty() ? "<none>" : assetPaths[0]);
		return nullptr;
	}
	const char *best = nullptr;
	int bestScore = 0;
	int foundPals = 0;
	for (const char *pal : kLevelPaletteCandidates) {
		if (!FindAsset(pal).ok())
			continue;
		++foundPals;
		LoadPalette(pal, false);
		const int score = ScoreCurrentPalette(used);
		if (score > bestScore) {
			bestScore = score;
			best = pal;
		}
	}
	Log("PickLevelPalette: {} uses {} indices, {} candidate palettes available, best {} scores {}", assetPaths[0], usedCount, foundPals, best != nullptr ? best : "<none>", bestScore);
	if (best != nullptr)
		LoadPalette(best);
	return best;
}

// Keeps the palette that colours this CEL. A CEL whose colour indices all map
// to black in the currently loaded palette would export as a pure silhouette
// (that is how 101 of 254 monster folders ended up black), so in that case
// switch to the level palette that actually colours it.
void EnsurePaletteColours(const std::string &assetPath, uint16_t widthHint)
{
	std::array<bool, 256> used{};
	if (!CollectCelPaletteIndices(assetPath, widthHint, used))
		return;
	if (ScoreCurrentPalette(used) > 0)
		return;
	const char *picked = PickLevelPalette({ assetPath }, widthHint);
	if (picked != nullptr)
		LoadPalette(picked);
}

void ExportAndUpscaleCl2(const std::string &assetPath, uint16_t widthHint = 128)
{
	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	bool force = (std::getenv("D1DE_FORCE_REMASTER") != nullptr);
	if (!force && fs::exists(hdDir) && !fs::is_empty(hdDir)) {
		return;
	}

	std::string fullCl2 = assetPath + ".cl2";
	AssetRef ref = FindAsset(fullCl2.c_str());
	if (!ref.ok()) {
		return;
	}

	EnsurePaletteColours(assetPath, widthHint);

	Log("========================================================");
	Log("Processing Asset: {}", assetPath);

	OwnedClxSpriteListOrSheet clx = LoadCl2ListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widthHint));
	if (clx.dataSize() == 0) {
		return;
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	// Get system palette
	const SDL_Color *origPalette = orig_palette.data();

	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		size_t frameCount = list.numSprites();
		for (size_t f = 0; f < frameCount; ++f) {
			ClxSprite sprite = list[f];
			int w = sprite.width();
			int h = sprite.height();
			if (w <= 0 || h <= 0)
				continue;

			SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
			if (!surface8)
				continue;

			SDL_SetPaletteColors(surface8->format->palette, origPalette, 0, 256);
			std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);

			Surface out(surface8);
			RenderClxSprite(out, sprite, { 0, 0 });

			// Convert to 32-bit RGBA
			SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
			if (surface32) {
				const uint8_t *src = static_cast<const uint8_t *>(surface8->pixels);
				uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
				for (int y = 0; y < h; ++y) {
					for (int x = 0; x < w; ++x) {
						uint8_t palIdx = src[y * surface8->pitch + x];
						if (palIdx == 0) {
							dst[y * (surface32->pitch / 4) + x] = 0; // Transparent
						} else {
							SDL_Color c = origPalette[palIdx];
							dst[y * (surface32->pitch / 4) + x] = (0xFF << 24) | (c.b << 16) | (c.g << 8) | c.r;
						}
					}
				}

				char pngPath[512];
				std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
				IMG_SavePNG(surface32, pngPath);
				SDL_FreeSurface(surface32);
			}

			SDL_FreeSurface(surface8);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	// Run 4x-UltraSharp on GPU!
	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportAndUpscaleCel(const std::string &assetPath, uint16_t widthHint = 128)
{
	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	bool force = (std::getenv("D1DE_FORCE_REMASTER") != nullptr);
	if (!force && fs::exists(hdDir) && !fs::is_empty(hdDir)) {
		return;
	}

	std::string fullCel = assetPath + ".cel";
	AssetRef ref = FindAsset(fullCel.c_str());
	if (!ref.ok()) {
		return;
	}

	EnsurePaletteColours(assetPath, widthHint);

	Log("========================================================");
	Log("Processing CEL Asset: {}", assetPath);

	OwnedClxSpriteListOrSheet clx = LoadCelListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widthHint));
	if (clx.dataSize() == 0) {
		return;
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	const SDL_Color *origPalette = orig_palette.data();

	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		size_t frameCount = list.numSprites();
		for (size_t f = 0; f < frameCount; ++f) {
			ClxSprite sprite = list[f];
			int w = sprite.width();
			int h = sprite.height();
			if (w <= 0 || h <= 0)
				continue;

			SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
			if (!surface8)
				continue;

			SDL_SetPaletteColors(surface8->format->palette, origPalette, 0, 256);
			std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);

			Surface out(surface8);
			RenderClxSprite(out, sprite, { 0, 0 });

			SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
			if (surface32) {
				const uint8_t *src = static_cast<const uint8_t *>(surface8->pixels);
				uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
				for (int y = 0; y < h; ++y) {
					for (int x = 0; x < w; ++x) {
						uint8_t palIdx = src[y * surface8->pitch + x];
						if (palIdx == 0) {
							dst[y * (surface32->pitch / 4) + x] = 0;
						} else {
							SDL_Color c = origPalette[palIdx];
							dst[y * (surface32->pitch / 4) + x] = (0xFF << 24) | (c.b << 16) | (c.g << 8) | c.r;
						}
					}
				}

				char pngPath[512];
				std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
				IMG_SavePNG(surface32, pngPath);
				SDL_FreeSurface(surface32);
			}

			SDL_FreeSurface(surface8);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled CEL asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportAndUpscaleCelWidths(const std::string &assetPath, const uint16_t *widths)
{
	std::string baseName = assetPath;
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}

	std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	bool force = (std::getenv("D1DE_FORCE_REMASTER") != nullptr);
	if (!force && fs::exists(hdDir) && !fs::is_empty(hdDir)) {
		return;
	}

	std::string fullCel = assetPath + ".cel";
	AssetRef ref = FindAsset(fullCel.c_str());
	if (!ref.ok()) {
		return;
	}

	EnsurePaletteColours(assetPath, widths[0]);

	Log("========================================================");
	Log("Processing CEL Asset (Variable Widths): {}", assetPath);

	OwnedClxSpriteListOrSheet clx = LoadCelListOrSheet(assetPath.c_str(), PointerOrValue<uint16_t>(widths));
	if (clx.dataSize() == 0) {
		return;
	}

	std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	const SDL_Color *origPalette = orig_palette.data();

	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		size_t frameCount = list.numSprites();
		for (size_t f = 0; f < frameCount; ++f) {
			ClxSprite sprite = list[f];
			int w = sprite.width();
			int h = sprite.height();
			if (w <= 0 || h <= 0)
				continue;

			SDL_Surface *surface8 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
			if (!surface8)
				continue;

			SDL_SetPaletteColors(surface8->format->palette, origPalette, 0, 256);
			std::memset(surface8->pixels, 0, surface8->pitch * surface8->h);

			Surface out(surface8);
			RenderClxSprite(out, sprite, { 0, 0 });

			SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
			if (surface32) {
				const uint8_t *src = static_cast<const uint8_t *>(surface8->pixels);
				uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
				for (int y = 0; y < h; ++y) {
					for (int x = 0; x < w; ++x) {
						uint8_t palIdx = src[y * surface8->pitch + x];
						if (palIdx == 0) {
							dst[y * (surface32->pitch / 4) + x] = 0;
						} else {
							SDL_Color c = origPalette[palIdx];
							dst[y * (surface32->pitch / 4) + x] = (0xFF << 24) | (c.b << 16) | (c.g << 8) | c.r;
						}
					}
				}

				char pngPath[512];
				std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
				IMG_SavePNG(surface32, pngPath);
				SDL_FreeSurface(surface32);
			}

			SDL_FreeSurface(surface8);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled CEL asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportMonsterFamily(const std::string &basePrefix, uint16_t widthHint, const char *palPath = nullptr)
{
	if (palPath != nullptr)
		LoadPalette(palPath);
	const char *actions[] = { "a", "d", "h", "s", "w", "t" };
	for (const char *act : actions) {
		ExportAndUpscaleCl2("monsters\\" + basePrefix + act, widthHint);
	}
}

void ExportPlayerClass(const char *classDir, char classChar)
{
	const char armors[] = { 'a', 'l', 'm', 'h' };
	const char weapons[] = { 'n', 's', 'a', 'b', 'm', 't', 'u', 'd', 'h' };
	const char *actions[] = { "as", "st", "aw", "wl", "at", "ht", "lm", "fm", "qm", "dt", "bl" };

	for (char a : armors) {
		for (char w : weapons) {
			char prefix[4] = { classChar, a, w, '\0' };
			for (const char *act : actions) {
				std::string path = "plrgfx\\" + std::string(classDir) + "\\" + prefix + "\\" + prefix + act;
				ExportAndUpscaleCl2(path, 128);
			}
		}
	}
}

} // namespace

void RemasterWarriorClass()
{
	Log("========================================================");
	Log("   Starting 4x-UltraSharp Warrior HD Remastering        ");
	Log("========================================================");
	// Player CELs use the system palette (class .trn applied at render time);
	// a level palette maps their indices to black silhouettes.
	ExportPlayerClass("warrior", 'w');
}

void RemasterPlayerSet(const std::string &spec)
{
	// spec = "<classDir>:<gfxPrefix>", e.g. "monk:mha". Exports the 11 player
	// animation CELs of one armor/weapon set instead of the full 396-CEL class.
	const size_t sep = spec.find(':');
	if (sep == std::string::npos || sep == 0 || sep + 1 >= spec.size()) {
		Log("RemasterPlayerSet: expected <classDir>:<prefix>, got '{}'", spec);
		return;
	}
	const std::string classDir = spec.substr(0, sep);
	const std::string prefix = spec.substr(sep + 1);
	std::vector<std::string> wanted;
	const size_t sep2 = prefix.find(':');
	std::string gfxPrefix = prefix;
	if (sep2 != std::string::npos) {
		gfxPrefix = prefix.substr(0, sep2);
		// Optional third field: comma separated action codes (debug/partial runs).
		std::string acts = prefix.substr(sep2 + 1);
		size_t pos = 0;
		while (pos < acts.size()) {
			size_t comma = acts.find(',', pos);
			wanted.push_back(acts.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos));
			if (comma == std::string::npos)
				break;
			pos = comma + 1;
		}
	}
	Log("========================================================");
	Log("   Starting HD Remastering for player set: {}          ", spec);
	Log("========================================================");
	// Player CEL indices live in the level palette space (same as monsters);
	// without any palette orig_palette stays black and every frame is a silhouette.
	LoadPalette("levels\\l1data\\l1_1.pal");
	const char *actions[] = { "as", "st", "aw", "wl", "at", "ht", "lm", "fm", "qm", "dt", "bl" };
	for (const char *act : actions) {
		if (!wanted.empty()
		    && std::find(wanted.begin(), wanted.end(), std::string(act)) == wanted.end())
			continue;
		std::string path = "plrgfx\\" + classDir + "\\" + gfxPrefix + "\\" + gfxPrefix + act;
		ExportAndUpscaleCl2(path, 128);
	}
	Log("========================================================");
	Log("   Player set {} remastering completed!          ", spec);
	Log("========================================================");
}

void RemasterSingleFamily(const std::string &familyPrefix, uint16_t widthHint, const char *pal)
{
	Log("========================================================");
	Log("   Starting Remastering for Single Monster: {}          ", familyPrefix);
	Log("========================================================");
	ExportMonsterFamily(familyPrefix, widthHint, pal);
}

void RemasterTowners()
{
	Log("========================================================");
	Log("   Starting Remastering for Town Residents & Animals    ");
	Log("========================================================");
	LoadPalette("levels\\towndata\\town.pal");
	ExportAndUpscaleCel("towners\\smith\\smithn", 96);
	ExportAndUpscaleCel("towners\\twnf\\twnfn", 96);
	ExportAndUpscaleCel("towners\\butch\\deadguy", 96);
	ExportAndUpscaleCel("towners\\townwmn1\\witch", 96);
	ExportAndUpscaleCel("towners\\townwmn1\\wmnn", 96);
	ExportAndUpscaleCel("towners\\townboy\\pegkid1", 96);
	ExportAndUpscaleCel("towners\\healer\\healer", 96);
	ExportAndUpscaleCel("towners\\strytell\\strytell", 96);
	ExportAndUpscaleCel("towners\\drunk\\twndrunk", 96);
	ExportAndUpscaleCel("towners\\farmer\\farmrn2", 96);
	ExportAndUpscaleCel("towners\\girl\\girlw1", 96);
	ExportAndUpscaleCel("towners\\girl\\girls1", 96);
	ExportAndUpscaleCel("towners\\farmer\\mfrmrn2", 96);
	ExportAndUpscaleCel("towners\\animals\\cow", 128);
}

void RemasterAllMonsters()
{
	Log("========================================================");
	Log("   Starting Remastering for All 57 Monster Families     ");
	Log("========================================================");

	// Cathedral (L1) - Priority
	Log("--- Remastering Cathedral (L1) Monsters ---");
	ExportMonsterFamily("fatc\\fatc", 128, "levels\\l1data\\l1_1.pal"); // The Butcher
	ExportMonsterFamily("sking\\sking", 160, "levels\\l1data\\l1_1.pal"); // King Leoric
	ExportMonsterFamily("skelaxe\\sklax", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("skelsd\\sklsr", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("skelbow\\sklbw", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("demskel\\demskl", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("zombie\\zombie", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("falspear\\phall", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("falsword\\fall", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("bigfall\\fallg", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("scav\\scav", 128, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("rat\\rat", 104, "levels\\l1data\\l1_1.pal");

	// Catacombs (L2)
	Log("--- Remastering Catacombs (L2) Monsters ---");
	ExportMonsterFamily("bat\\bat", 96, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("bspidr\\bspidr", 148, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("gargoyle\\gargo", 160, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("goatbow\\goatb", 128, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("goatlord\\goatl", 160, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("goatmace\\goat", 128, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("horkd\\horkd", 138, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("scorp\\scorp", 64, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("spider\\spider", 148, "levels\\l2data\\l2_1.pal");
	ExportMonsterFamily("thin\\thin", 160, "levels\\l2data\\l2_1.pal");

	// Caves (L3)
	Log("--- Remastering Caves (L3) Monsters ---");
	ExportMonsterFamily("acid\\acid", 128, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("antworm\\worm", 192, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("bubba\\bubba", 154, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("byclps\\byclps", 180, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("clasp\\clasp", 176, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("fork\\fork", 188, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("magma\\magma", 128, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("rhino\\rhino", 160, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("worm\\worm", 160, "levels\\l3data\\l3_1.pal");
	ExportMonsterFamily("wscorp\\wscorp", 86, "levels\\l3data\\l3_1.pal");

	// Hell (L4)
	Log("--- Remastering Hell (L4) Monsters ---");
	ExportMonsterFamily("black\\black", 160, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("darkmage\\dmage", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("diablo\\diablo", 160, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("eye\\eye", 156, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("eye2\\eye2", 140, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("fat\\fat", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("fireman\\firem", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("flesh\\flesh", 164, "levels\\l4data\\l4_1.pal");
	// Golem is a Cathedral-summoned construct: its CEL indices address the L1
	// grey-stone ramp. l4_1.pal maps those indices to pure black.
	ExportMonsterFamily("golem\\golem", 96, "levels\\l1data\\l1_1.pal");
	ExportMonsterFamily("gravdg\\gravdg", 124, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("hellbat\\helbat", 96, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("hellbat2\\bhelbt", 96, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("hellbug\\hellbg", 198, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("lich\\lich", 96, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("lich2\\lich2", 136, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("mage\\mage", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("mega\\mega", 160, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("nkr\\nkr", 226, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("reaper\\reap", 180, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("snake\\snake", 160, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("sneak\\sneak", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("spawn\\spawn", 164, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("succ\\scbs", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("tsneak\\tsneak", 128, "levels\\l4data\\l4_1.pal");
	ExportMonsterFamily("unrav\\unrav", 96, "levels\\l4data\\l4_1.pal");
}

void RemasterInventoryIcons()
{
	Log("========================================================");
	Log("   Starting Remastering for Inventory Icons & Spells    ");
	Log("========================================================");
	LoadPalette("levels\\towndata\\town.pal");
	ExportAndUpscaleCelWidths("data\\inv\\objcurs", InvItemWidth1);
	ExportAndUpscaleCelWidths("data\\inv\\objcurs2", InvItemWidth2);
	ExportAndUpscaleCel("data\\spelli2", 37);
	ExportAndUpscaleCel("data\\spelicon", 56);
	ExportAndUpscaleCel("data\\spellbk", 320);
	ExportAndUpscaleCel("data\\spellbkb", 76);
}

void RemasterObjects()
{
	Log("========================================================");
	Log("   Starting Remastering for Interactive Objects         ");
	Log("========================================================");
	LoadPalette("levels\\l1data\\l1_1.pal");
	uint16_t objectWidths[65] = {};
	for (const ObjectData &objectData : AllObjects) {
		if (objectData.ofindex >= 0 && objectData.ofindex < 65 && objectData.animWidth > 0) {
			objectWidths[objectData.ofindex] = objectData.animWidth;
		}
	}
	for (int i = 0; i < 65; i++) {
		if (objectWidths[i] > 0) {
			std::string path = "objects\\" + std::string(ObjMasterLoadList[i]);
			ExportAndUpscaleCel(path, objectWidths[i]);
		}
	}
}

void RemasterMissiles()
{
	Log("========================================================");
	Log("   Starting Remastering for Missiles & Projectiles      ");
	Log("========================================================");
	LoadPalette("levels\\l1data\\l1_1.pal");
	for (size_t mi = 0; MissileSpriteData[mi].animFAmt != 0; mi++) {
		const auto &ms = MissileSpriteData[mi];
		if (ms.name[0] == '\0')
			continue;
		std::vector<std::string> paths;
		if (ms.animFAmt == 1) {
			paths.push_back("missiles\\" + std::string(ms.name));
		} else {
			for (size_t i = 1; i <= ms.animFAmt; i++)
				paths.push_back("missiles\\" + std::string(ms.name) + std::to_string(i));
		}
		// Missile CELs are spread over every level theme palette; the cathedral
		// palette alone leaves 13 of 245 families black. ExportAndUpscaleCl2
		// re-picks the palette per CEL when the current one renders it black.
		for (const std::string &path : paths) {
			ExportAndUpscaleCl2(path, ms.animWidth);
		}
	}
}

void RemasterLevelSpecials()
{
	Log("========================================================");
	Log("   Starting Remastering for Level Specials              ");
	Log("========================================================");
	LoadPalette("levels\\towndata\\town.pal");
	ExportAndUpscaleCel("levels\\towndata\\towns", 64);
	LoadPalette("levels\\l1data\\l1_1.pal");
	ExportAndUpscaleCel("levels\\l1data\\l1s", 64);
	LoadPalette("levels\\l2data\\l2_1.pal");
	ExportAndUpscaleCel("levels\\l2data\\l2s", 64);
	LoadPalette("levels\\l1data\\l1_1.pal");
	ExportAndUpscaleCel("nlevels\\l5data\\l5s", 64);
}

void RemasterDroppedItems()
{
	Log("========================================================");
	Log("   Starting Dropped Ground Items Remastering            ");
	Log("========================================================");
	LoadPalette("levels\\towndata\\town.pal");
	const char *const dropNames[] = {
		"armor2", "axe", "fbttle", "bow", "goldflip", "helmut", "mace", "shield", "swrdflip",
		"rock", "cleaver", "staff", "ring", "crownf", "larmor", "wshield", "scroll",
		"fplatear", "fbook", "food", "fbttlebb", "fbttledy", "fbttleor", "fbttlebr",
		"fbttlebl", "fbttleby", "fbttlewh", "fbttledb", "fear", "fbrain", "fmush",
		"innsign", "bldstn", "fanvil", "flazstaf", "bombs1", "halfps1", "wholeps1",
		"runes1", "teddys1", "cows1", "donkys1", "mooses1"
	};
	for (const char *name : dropNames) {
		std::string path = "items\\" + std::string(name);
		ExportAndUpscaleCel(path, 96);
	}
	Log("========================================================");
	Log("   Dropped Ground Items Remastering Completed!          ");
	Log("========================================================");
}

void RemasterAllCoreAssets()
{
	Log("========================================================");
	Log("   Starting 4x-UltraSharp Core Gameplay Remastering     ");
	Log("========================================================");
	RemasterTowners();
	RemasterInventoryIcons();
	RemasterDroppedItems();
	RemasterObjects();
	RemasterMissiles();
	RemasterLevelSpecials();
	RemasterAllMonsters();
}

void RunRemasterAssetPipeline()
{
	Log("========================================================");
	Log("   Starting 4x-UltraSharp Full Master AI Remastering    ");
	Log("========================================================");

	RemasterAllCoreAssets();

	// Player classes (system palette; see RemasterWarriorClass)
	ExportPlayerClass("warrior", 'w');
	ExportPlayerClass("rogue", 'r');
	ExportPlayerClass("sorceror", 's'); // Diablo 1 MPQ directory is 'sorceror'
	ExportPlayerClass("monk", 'm');
	ExportPlayerClass("barbarian", 'a');
	ExportPlayerClass("bard", 'b');

	Log("========================================================");
	Log("   4x-UltraSharp Full AI Remastering Completed!         ");
	Log("========================================================");
}

} // namespace devilution
