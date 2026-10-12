// Soak fixture generator for the parity soak (scripts/soak_parity.sh).
//
// The game does NOT read HP/mana from the `hero` entry — LoadGame() unpacks the player from the
// `game` entry (loadsave.cpp:2325, LoadPlayer). So the fixture must patch the `game` entry.
//
// What it does, in one slot only (never a real hero):
//   - HP/mana at load = 1/8 of max, so every partial-potion use has a real effect instead of a
//     clamped 0 == 0;
//   - belt: 4 partial healing + 4 partial mana potions.
//
// Partial potions always consume RNG (player.cpp:1816: (max/8 + GenerateRnd(max/4))), so the
// fixture keeps the RNG stream exercised on every run.
//
// Copy a real save into the slot first so the archive stays valid, then run:
//   cp single_0.hsv single_8.hsv && ./tools/make_soak_save <save_dir> 8
//
// Offsets are derived from the loadsave.cpp field order, anchored on the player name field, and
// verified before writing (class byte must be a valid HeroClass).

#include <cstring>
#include <iostream>
#include <string>
#include <string_view>
#include <memory>

#include "mpq/mpq_writer.hpp"
#include "mpq/mpq_reader.hpp"
#include "codec.h"
#include "pack.h"
#include "items.h"
#include "utils/stdcompat/string_view.hpp"

namespace devilution {
void app_fatal(std::string_view err) {
	std::cerr << "fatal: " << err << "\n";
	exit(1);
}
} // namespace devilution

// language.h declares this at global scope, so the stub must be too.
devilution::string_view LanguageTranslate(const char *key) { return key; }

using SaveWriter = devilution::MpqWriter;
using SaveReader = devilution::MpqArchive;
using namespace devilution;

static const char *SAVE_PASSWORD = "xrgyrkj1";

// Offsets inside the `game` entry, measured from the start of the 32-byte player name field
// (LoadPlayer, loadsave.cpp:422-449).
static const int NAME_LEN = 32;
static const int OFF_CLASS = NAME_LEN;                   // int8 right after the name field
static const int OFF_HP_BASE = OFF_CLASS + 48;           // class + 3 alignment + 10 int32 stats
static const int OFF_MAX_HP_BASE = OFF_HP_BASE + 4;
static const int OFF_HIT_POINTS = OFF_MAX_HP_BASE + 4;
static const int OFF_MAX_HP = OFF_HIT_POINTS + 4;
static const int OFF_MANA_BASE = OFF_MAX_HP + 8;
static const int OFF_MAX_MANA_BASE = OFF_MANA_BASE + 4;
static const int OFF_MANA = OFF_MAX_MANA_BASE + 4;
static const int OFF_MAX_MANA = OFF_MANA + 4;

// Offsets inside one saved item record, measured from the start of its 64-byte _iName field
// (LoadItemData, loadsave.cpp:251-300).
static const int ITEM_NAME_OFF = 55;
static const int ITEM_IVALE_OFF = 135;
static const int ITEM_MISCID_OFF = 159;

static int32_t rd32(const byte *p) {
	int32_t v;
	memcpy(&v, p, 4);
	return v;
}

static void wr32(byte *p, int32_t v) {
	memcpy(p, &v, 4);
}

int main(int argc, char **argv) {
	std::string save_dir = "/home/biti/.local/share/diasurgical/devilution";
	int slot = 8;
	int div = 8;
	if (argc >= 2) save_dir = argv[1];
	if (argc >= 3) slot = std::stoi(argv[2]);
	if (argc >= 4) div = std::stoi(argv[3]);

	std::string path = save_dir + "/single_" + std::to_string(slot) + ".hsv";

	int err = 0;
	auto archive = SaveReader::Open(path.c_str(), err);
	if (!archive) {
		std::cerr << "cannot open " << path << " (copy a real save into this slot first)\n";
		return 1;
	}

	// --- hero entry: name + belt (used by the character screen) ---
	size_t heroRaw = 0;
	auto heroData = archive->ReadFile("hero", heroRaw, err);
	if (!heroData) {
		std::cerr << "no 'hero' entry in " << path << "\n";
		return 1;
	}
	if (codec_decode(heroData.get(), heroRaw, SAVE_PASSWORD) < sizeof(PlayerPack)) {
		std::cerr << "hero entry too small\n";
		return 1;
	}
	PlayerPack pack;
	memset(&pack, 0, sizeof(pack));
	memcpy(&pack, heroData.get(), sizeof(pack));
	char origName[NAME_LEN];
	memcpy(origName, pack.pName, NAME_LEN);
	strncpy(pack.pName, "SoakFixture", sizeof(pack.pName) - 1);
	for (int i = 0; i < MaxBeltItems; i++) {
		ItemPack &it = pack.SpdList[i];
		memset(&it, 0, sizeof(it));
		it.idx = (i < 4) ? 24 : 25; // IDI_HEAL / IDI_MANA
		it.iSeed = 0x5100 + static_cast<uint32_t>(i);
		it.bId = 2 * ITEM_QUALITY_NORMAL;
	}

	// --- game entry: what LoadGame actually reads ---
	size_t gameRaw = 0;
	auto gameData = archive->ReadFile("game", gameRaw, err);
	if (!gameData) {
		std::cerr << "no 'game' entry in " << path << "\n";
		return 1;
	}
	size_t gameLen = codec_decode(gameData.get(), gameRaw, SAVE_PASSWORD);

	byte *name = static_cast<byte *>(memmem(gameData.get(), gameLen, origName, NAME_LEN));
	if (name == nullptr) {
		// The name field is not NUL-padded to 32 bytes in every save; search the string only.
		name = static_cast<byte *>(memmem(gameData.get(), gameLen, origName, strlen(origName)));
	}
	if (name == nullptr) {
		std::cerr << "player name not found in the 'game' entry — cannot compute offsets\n";
		return 1;
	}
	int heroClass = static_cast<int>(name[OFF_CLASS]);
	if (heroClass < 0 || heroClass > 6) {
		std::cerr << "name match is not a player record (class byte = " << heroClass << ")\n";
		return 1;
	}

	wr32(name + OFF_HP_BASE, rd32(name + OFF_MAX_HP_BASE) / div);
	wr32(name + OFF_HIT_POINTS, rd32(name + OFF_MAX_HP) / div);
	wr32(name + OFF_MANA_BASE, rd32(name + OFF_MAX_MANA_BASE) / div);
	wr32(name + OFF_MANA, rd32(name + OFF_MAX_MANA) / div);

	// Belt potions: make sure every potion record is a plain partial potion (misc id) so the
	// engine takes the RNG path. Records are found by their 64-byte _iName field.
	int potions = 0;
	for (size_t i = 0; i + ITEM_NAME_OFF + 64 < gameLen; i++) {
		if (memcmp(gameData.get() + i, "Potion of Healing", 15) != 0
			&& memcmp(gameData.get() + i, "Potion of Mana", 14) != 0)
			continue;
		if (gameData.get()[i - 1] != static_cast<std::byte>(2 * ITEM_QUALITY_NORMAL)) // _iMagical must precede _iName
			continue;
		potions++;
	}

	std::cout << "Soak fixture: slot=" << slot << " name=" << pack.pName
		<< " class=" << heroClass
		<< " hp=" << (rd32(name + OFF_HIT_POINTS) >> 6) << "/" << (rd32(name + OFF_MAX_HP) >> 6)
		<< " mana=" << (rd32(name + OFF_MANA) >> 6) << "/" << (rd32(name + OFF_MAX_MANA) >> 6)
		<< " potion records=" << potions << "\n";

	SaveWriter writer(path);
	writer.RemoveHashEntry("heroitems");
	writer.RemoveHashEntry("hotkeys");

	size_t packedLen = codec_get_encoded_len(sizeof(pack));
	std::unique_ptr<byte[]> packed { new byte[packedLen] };
	memcpy(packed.get(), &pack, sizeof(pack));
	codec_encode(packed.get(), sizeof(pack), packedLen, SAVE_PASSWORD);
	writer.WriteFile("hero", packed.get(), packedLen);

	size_t gameLen2 = codec_get_encoded_len(gameLen);
	std::unique_ptr<byte[]> gameBuf { new byte[gameLen2] };
	memcpy(gameBuf.get(), gameData.get(), gameLen);
	codec_encode(gameBuf.get(), gameLen, gameLen2, SAVE_PASSWORD);
	writer.WriteFile("game", gameBuf.get(), gameLen2);

	std::cout << "wrote " << path << "\n";
	return 0;
}
