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
#include "engine/load_file.hpp"
#include "engine/palette.h"
#include "engine/render/clx_render.hpp"
#include "engine/surface.hpp"
#include "misdat.h"
#include "monstdat.h"
#include "objdat.h"
#include "playerdat.hpp"
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

// True while hero CELs are being exported. player.cpp applies the class .trn
// to the animation CELs (ClxApplyTrans) before drawing, so the game never looks
// up a raw player CEL index in the palette. Exporting without that transform
// resolves raw indices against a dark region of the level palette and every
// frame comes out a pure-black silhouette — which is what happened to all 1056
// deployed plrgfx folders. While this is set the transform is already folded
// into orig_palette, so palette re-picking must be skipped.
bool gPlayerTrnApplied = false;

// Folds plrgfx\<class>.trn into orig_palette (palette' = palette ∘ trn), which
// is equivalent to the ClxApplyTrans the game performs on the sprites.
void ApplyClassTrnToPalette(const std::string &classDir)
{
	// The MPQ spells the sorcerer's animation directory 'sorceror'; probe the
	// plausible transform names rather than trusting one spelling.
	const std::string trnName = classDir;
	std::array<uint8_t, 256> trn{};
	std::string foundPath;
	for (const std::string &cand : { trnName + ".trn", std::string("sorcerer.trn"), std::string("sorceror.trn") }) {
		const std::string path = "plrgfx\\" + cand;
		if (cand == "sorcerer.trn" && trnName != "sorceror" && trnName != "sorcerer")
			continue;
		if (LoadOptionalFileInMem(path.c_str(), &trn[0], 256)) {
			foundPath = path;
			break;
		}
	}
	if (foundPath.empty()) {
		Log("Remaster exporter: no plrgfx transform for '{}' — exporting with the raw CEL indices", classDir);
		return;
	}
	const std::array<SDL_Color, 256> base = orig_palette;
	for (int i = 1; i < 256; ++i)
		orig_palette[i] = base[trn[i]];
	gPlayerTrnApplied = true;
	Log("Remaster exporter: applied {} to the palette", foundPath);
}

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
	// The class transform is already baked into orig_palette; re-picking a level
	// palette would drop it and score the raw (dark) indices as black.
	if (gPlayerTrnApplied)
		return;
	std::array<bool, 256> used{};
	if (!CollectCelPaletteIndices(assetPath, widthHint, used))
		return;
	if (ScoreCurrentPalette(used) > 0)
		return;
	const char *picked = PickLevelPalette({ assetPath }, widthHint);
	if (picked != nullptr)
		LoadPalette(picked);
}

// D1DE_REMASTER_RAW_ONLY: write the authentic 1x frames and skip the GPU
// upscale, so the raw pass runs in seconds and the 4x leg is batched
// separately by tools/hd_upscale_batch.py.
bool RemasterRawOnly()
{
	return std::getenv("D1DE_REMASTER_RAW_ONLY") != nullptr;
}

std::string SanitizeBaseName(std::string baseName)
{
	for (char &c : baseName) {
		if (c == '\\' || c == '/')
			c = '_';
	}
	return baseName;
}

void ExportClxSpriteToPng(ClxSprite sprite, const SDL_Color *origPalette, const char *pngPath)
{
	const int w = sprite.width();
	const int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 1024 || h > 1024)
		return;

	SDL_Surface *surface0 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
	SDL_Surface *surface1 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 8, SDL_PIXELFORMAT_INDEX8);
	if (!surface0 || !surface1) {
		if (surface0)
			SDL_FreeSurface(surface0);
		if (surface1)
			SDL_FreeSurface(surface1);
		return;
	}

	// Render onto two differently cleared 8-bit buffers so opaque palette index 0
	// (pure black interior shadow pixels in chests/objects) stays opaque while
	// untouched transparent background pixels differ between the two buffers.
	std::memset(surface0->pixels, 0x00, surface0->pitch * surface0->h);
	std::memset(surface1->pixels, 0xFF, surface1->pitch * surface1->h);

	Surface out0(surface0);
	Surface out1(surface1);
	RenderClxSprite(out0, sprite, { 0, 0 });
	RenderClxSprite(out1, sprite, { 0, 0 });

	SDL_Surface *surface32 = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
	if (surface32) {
		const uint8_t *src0 = static_cast<const uint8_t *>(surface0->pixels);
		const uint8_t *src1 = static_cast<const uint8_t *>(surface1->pixels);
		uint32_t *dst = static_cast<uint32_t *>(surface32->pixels);
		const int dstPitch = surface32->pitch / 4;
		for (int y = 0; y < h; ++y) {
			for (int x = 0; x < w; ++x) {
				const uint8_t idx0 = src0[y * surface0->pitch + x];
				const uint8_t idx1 = src1[y * surface1->pitch + x];
				if (idx0 != idx1) {
					dst[y * dstPitch + x] = 0; // Transparent background
				} else {
					const SDL_Color c = origPalette[idx0];
					dst[y * dstPitch + x] = (0xFFU << 24)
					    | (static_cast<uint32_t>(c.b) << 16)
					    | (static_cast<uint32_t>(c.g) << 8)
					    | static_cast<uint32_t>(c.r);
				}
			}
		}
		IMG_SavePNG(surface32, pngPath);
		SDL_FreeSurface(surface32);
	}

	SDL_FreeSurface(surface0);
	SDL_FreeSurface(surface1);
}

void ExportClxAndMaybeUpscale(const std::string &baseName, const OwnedClxSpriteListOrSheet &clx, const std::string &rawDir, const std::string &hdDir, bool rawOnly)
{
	fs::create_directories(rawDir);
	fs::create_directories(hdDir);

	const SDL_Color *origPalette = orig_palette.data();
	auto processList = [&](ClxSpriteList list, size_t groupIndex) {
		const uint32_t frameCount = list.numSprites();
		const uint32_t listSize = list.dataSize();
		const uint32_t minOffset = 4U + (frameCount + 1U) * 4U;
		if (frameCount == 0 || frameCount > 1024 || listSize < minOffset) {
			Log("Skipping corrupt group {} of {} (frames={}, listSize={})", groupIndex, baseName, frameCount, listSize);
			return;
		}
		for (size_t f = 0; f < frameCount; ++f) {
			const uint32_t begin = list.spriteOffset(f);
			const uint32_t end = list.spriteOffset(f + 1);
			if (begin < minOffset || end <= begin || end > listSize) {
				Log("Skipping corrupt frame {} in group {} of {} (begin={}, end={}, listSize={})", f, groupIndex, baseName, begin, end, listSize);
				continue;
			}
			char pngPath[512];
			std::snprintf(pngPath, sizeof(pngPath), "%s/g%zu_f%03zu.png", rawDir.c_str(), groupIndex, f);
			ExportClxSpriteToPng(list[f], origPalette, pngPath);
		}
	};

	if (clx.isSheet()) {
		ClxSpriteSheet sheet = clx.sheet();
		for (size_t g = 0; g < sheet.numLists(); ++g) {
			const uint32_t gOff = sheet.sheetOffset(g);
			if (gOff < 4U * sheet.numLists()) {
				Log("Skipping corrupt sheet group {} of {} (offset={})", g, baseName, gOff);
				continue;
			}
			processList(sheet[g], g);
		}
	} else {
		processList(clx.list(), 0);
	}

	if (rawOnly)
		return;
	std::string cmd = "/home/biti/antigravity/magical-bell/tools/realesrgan/upscale_folder.sh " + rawDir + " " + hdDir + " 4x-UltraSharp";
	int ret = std::system(cmd.c_str());
	if (ret == 0) {
		Log("Successfully upscaled asset {} with 4x-UltraSharp AI!", baseName);
	}
}

void ExportAndUpscaleCl2(const std::string &assetPath, uint16_t widthHint = 128)
{
	const std::string baseName = SanitizeBaseName(assetPath);
	const std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	const std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	const bool rawOnly = RemasterRawOnly();
	const std::string skipDir = rawOnly ? rawDir : hdDir;
	const bool force = (std::getenv("D1DE_FORCE_REMASTER") != nullptr);
	if (!force && fs::exists(skipDir) && !fs::is_empty(skipDir)) {
		return;
	}

	const std::string fullCl2 = assetPath + ".cl2";
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

	ExportClxAndMaybeUpscale(baseName, clx, rawDir, hdDir, rawOnly);
}

void ExportAndUpscaleCel(const std::string &assetPath, uint16_t widthHint = 128)
{
	const std::string baseName = SanitizeBaseName(assetPath);
	const std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	const std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	const bool rawOnly = RemasterRawOnly();
	const std::string skipDir = rawOnly ? rawDir : hdDir;
	const bool force = (std::getenv("D1DE_FORCE_REMASTER") != nullptr);
	if (!force && fs::exists(skipDir) && !fs::is_empty(skipDir)) {
		return;
	}

	const std::string fullCel = assetPath + ".cel";
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

	ExportClxAndMaybeUpscale(baseName, clx, rawDir, hdDir, rawOnly);
}

void ExportAndUpscaleCelWidths(const std::string &assetPath, const uint16_t *widths)
{
	const std::string baseName = SanitizeBaseName(assetPath);
	const std::string hdDir = "/home/biti/antigravity/magical-bell/scratch/hd_sprites/" + baseName;
	const std::string rawDir = "/home/biti/antigravity/magical-bell/scratch/raw_sprites/" + baseName;
	const bool rawOnly = RemasterRawOnly();
	const std::string skipDir = rawOnly ? rawDir : hdDir;
	const bool force = (std::getenv("D1DE_FORCE_REMASTER") != nullptr);
	if (!force && fs::exists(skipDir) && !fs::is_empty(skipDir)) {
		return;
	}

	const std::string fullCel = assetPath + ".cel";
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

	ExportClxAndMaybeUpscale(baseName, clx, rawDir, hdDir, rawOnly);
}

uint16_t GetPlayerExportWidthHint(const std::string &classDir, const std::string &gfxPrefix, const std::string &act)
{
	HeroClass cls = HeroClass::Warrior;
	if (classDir == "rogue")
		cls = HeroClass::Rogue;
	else if (classDir == "sorceror" || classDir == "sorcerer")
		cls = HeroClass::Sorcerer;
	else if (classDir == "monk")
		cls = HeroClass::Monk;
	else if (classDir == "bard")
		cls = HeroClass::Bard;
	else if (classDir == "barbarian")
		cls = HeroClass::Barbarian;

	const PlayerSpriteData &sd = PlayersSpriteData[static_cast<size_t>(cls)];
	if (act == "as" || act == "st")
		return sd.stand;
	if (act == "aw" || act == "wl")
		return sd.walk;
	if (act == "at")
		return (gfxPrefix.size() >= 3 && gfxPrefix[2] == 'b') ? sd.bow : sd.attack;
	if (act == "ht")
		return sd.swHit;
	if (act == "bl")
		return sd.block;
	if (act == "lm")
		return sd.lightning;
	if (act == "fm")
		return sd.fire;
	if (act == "qm")
		return sd.magic;
	if (act == "dt")
		return sd.death;
	return 128;
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
	LoadPalette("levels\\l1data\\l1_1.pal");
	ApplyClassTrnToPalette(classDir);
	const char armors[] = { 'a', 'l', 'm', 'h' };
	const char weapons[] = { 'n', 's', 'a', 'b', 'm', 't', 'u', 'd', 'h' };
	const char *actions[] = { "as", "st", "aw", "wl", "at", "ht", "lm", "fm", "qm", "dt", "bl" };

	for (char a : armors) {
		for (char w : weapons) {
			char prefix[4] = { classChar, a, w, '\0' };
			for (const char *act : actions) {
				std::string path = "plrgfx\\" + std::string(classDir) + "\\" + prefix + "\\" + prefix + act;
				ExportAndUpscaleCl2(path, GetPlayerExportWidthHint(classDir, prefix, act));
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
	// Hero CELs are indexed in the level-palette space (same character-colour
	// region across themes) and the game draws them through the class .trn.
	// Both are required: with no palette orig_palette stays black, and with the
	// palette but no transform every frame is a silhouette.
	LoadPalette("levels\\l1data\\l1_1.pal");
	ApplyClassTrnToPalette(classDir);
	const char *actions[] = { "as", "st", "aw", "wl", "at", "ht", "lm", "fm", "qm", "dt", "bl" };
	for (const char *act : actions) {
		if (!wanted.empty()
		    && std::find(wanted.begin(), wanted.end(), std::string(act)) == wanted.end())
			continue;
		std::string path = "plrgfx\\" + classDir + "\\" + gfxPrefix + "\\" + gfxPrefix + act;
		ExportAndUpscaleCl2(path, GetPlayerExportWidthHint(classDir, gfxPrefix, act));
	}
	Log("========================================================");
	Log("   Player set {} remastering completed!          ", spec);
	Log("========================================================");
}

uint16_t GetMonsterExportWidthHint(const std::string &familyPrefix, uint16_t fallbackWidth)
{
	if (fallbackWidth != 128)
		return fallbackWidth;
	for (size_t i = 0; i < NUM_MTYPES; ++i) {
		const MonsterData &md = MonstersData[i];
		if (md.assetsSuffix != nullptr && familyPrefix == md.assetsSuffix && md.width > 0)
			return md.width;
	}
	return fallbackWidth;
}

void RemasterSingleFamily(const std::string &familyPrefix, uint16_t widthHint, const char *pal)
{
	Log("========================================================");
	Log("   Starting Remastering for Single Monster: {}          ", familyPrefix);
	Log("========================================================");
	ExportMonsterFamily(familyPrefix, GetMonsterExportWidthHint(familyPrefix, widthHint), pal);
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
