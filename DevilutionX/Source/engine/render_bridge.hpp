#pragma once
#include <cstdint>
#include <cstddef>
#include <atomic>
#include <filesystem>
#include <vector>
#include <string>
#include <SDL.h>
#include "engine/point.hpp"
#include "engine/direction.hpp"

namespace devilution {

#pragma pack(push, 1)
struct D1BridgeTorch {
	float normX;
	float normY;
	float intensity;
	float pad;
};

struct D1InputMsg {
	uint32_t type;  // 1 = MOUSE_MOTION, 2 = MOUSE_BUTTON, 3 = KEY
	uint32_t code;  // 1 = Left, 2 = Middle, 3 = Right, or SDL keycode
	uint32_t state; // 1 = pressed/down, 0 = released/up
	int32_t x;
	int32_t y;
};

constexpr size_t D1_INPUT_RING_SIZE = 128;

struct D1BridgeHeader {
	uint32_t magic;      // 0x44315242 ("D1RB")
	uint32_t version;    // 1
	uint32_t width;
	uint32_t height;
	uint32_t pitch;
	uint32_t frameId;
	uint32_t timestamp;  // SDL_GetTicks()
	float playerNormX;   // Hero screen position (0.0..1.0)
	float playerNormY;   // Hero screen position (0.0..1.0)
	int32_t zoomMode;    // 1 = 1.0x, 2 = 1.5x, 3 = 2.0x
	uint32_t torchCount;
	D1BridgeTorch torches[16];
	uint32_t readyFlag;  // 1 = new frame written

	// Bidirectional Input Queue (Written by Godot 4, Read by DevilutionX)
	uint32_t inputWriteIdx;
	uint32_t inputReadIdx;
	D1InputMsg inputQueue[D1_INPUT_RING_SIZE];

	uint8_t reserved[4096 - (44 + 256 + 4 + 8 + 128 * sizeof(D1InputMsg))];
};
#pragma pack(pop)

static_assert(sizeof(D1BridgeHeader) == 4096, "D1BridgeHeader must be exactly 4096 bytes");

extern bool gbGodotBridgeActive;
extern std::atomic<bool> g_D1LevelTransitioning;

struct D1EngineData {
	uint32_t frameId = 0;
	int width = 2560;
	int height = 1440;
	int playerTileX = 25;
	int playerTileY = 25;
	float playerNormX = 0.5f;
	float playerNormY = 0.52f;
	int playerHp = 100;
	int playerMaxHp = 100;
	int playerMana = 50;
	int playerMaxMana = 50;
	// HP/mana are stored in 64ths internally. The display values above are raw >> 6, which throws
	// away the remainder; a native mirror that predicts gains must see the raw values or it will
	// be off by one display unit whenever the remainder is non-zero.
	int playerHpRaw = 6400;
	int playerMaxHpRaw = 6400;
	int playerManaRaw = 3200;
	int playerMaxManaRaw = 3200;
	uint32_t playerIFlags = 0;   // accumulated ItemSpecialEffect flags from equipment
	int playerGold = 0;
	int playerClass = 0;
	int currentLevel = 0;
	int dungeonType = 0;
	bool leftPanelOpen = false;
	bool rightPanelOpen = false;
	bool isGameRunning = false;
	int playerLevel = 1;
	int playerExp = 0;
	int playerNextExp = 0;
	int playerSpell = 0;
	int playerSpellType = 0;
	int beltTypes[8] = { 0 };
	int beltCounts[8] = { 0 };
	char beltNames[8][64] = { { 0 } };
	int leftPanelX = 0;
	int leftPanelY = 0;
	int leftPanelW = 320;
	int leftPanelH = 352;
	int rightPanelX = 0;
	int rightPanelY = 0;
	int rightPanelW = 320;
	int rightPanelH = 352;
	bool isSpeedbookOpen = false;
	int speedbookX = 0;
	int speedbookY = 0;
	int speedbookW = 0;
	int speedbookH = 0;
	bool hasHoverInfo = false;
	char hoverItemName[128] = { 0 };
	char hoverItemStats[512] = { 0 };
	int hoverItemQuality = 0;
	bool isInventoryHover = false;
	bool isMonsterHover = false;
	bool isModalActive = false;
	bool isTextInputActive = false;
	bool isPlayerDead = false;
	int hoverMouseX = 0;
	int hoverMouseY = 0;
	int zoomMode = 2; // 0=1.0x, 1=1.5x, 2=2.0x, 3=2.5x, 4=3.0x
};

struct AvailableSpellItem {
	int id = 0;
	int type = 0;
	char name[64] = { 0 };
	int manaCost = 0;
	char hotkey[16] = { 0 };
};

extern D1EngineData g_D1EngineData;
extern bool gbHideVanillaHUD;
void SetVanillaHUDHidden(bool hidden);
bool IsTextInputActiveLive();
bool IsPlayerDeadLive();
std::vector<uint8_t> GetSpellIconRgba(int spellId, int spellType);
std::vector<AvailableSpellItem> GetAvailableSpells();
void SelectSpell(int spellId, int spellType);
void UseBeltSlot(int slotIndex);
void ClickBeltSlot(int slotIndex);

struct D1PotionSummary {
	int hpCount = 0;
	int hpBestType = 0; // 0=None, 1=Full Heal, 2=Heal, 3=Scroll of Heal
	int manaCount = 0;
	int manaBestType = 0; // 0=None, 1=Full Mana, 2=Mana
	int rejuvCount = 0;
	int rejuvBestType = 0; // 0=None, 1=Full Rejuv, 2=Rejuv
};

struct D1TownPortalSummary {
	bool hasSpell = false;
	int spellManaCost = 0;
	bool canCastSpell = false;
	int scrollCount = 0;
	int chargeCount = 0;
	int bestMode = 0; // 0=None, 1=Spell, 2=Scroll, 3=Charges
};

struct D1TargetMonsterSummary {
	bool hasTarget = false;
	bool isHovered = false;
	int monsterId = -1;
	char name[64] = { 0 };
	int hp = 0;
	int maxHp = 0;
	int mode = 0;
	bool isUnique = false;
	bool isChampion = false;
	int monsterClass = 0; // 0=Animal/Beast, 1=Demon, 2=Undead
	char classText[32] = { 0 };
	char resistText[64] = { 0 };
	char immuneText[64] = { 0 };
	int killCount = 0;
};

D1PotionSummary GetPotionSummary();
void UseSmartPotion(int category);
D1TownPortalSummary GetTownPortalSummary();
void UseSmartTownPortal();
D1TargetMonsterSummary GetTargetMonsterSummary(int targetId = -1);
void BindSpellHotkey(int spellId, int spellType, int slotIdx);
void QuickCastHotkey(int slotIdx);

void InitGodotBridge(int width, int height);
void ExportGodotFrame(const SDL_Surface *surface);
void PollGodotBridgeInput();
void CleanupGodotBridge();

// High-level game actions dispatched from the Godot layer. These MUST run on the DevilutionX
// ENGINE thread (drained here each frame), never directly from Godot's main thread: calling them
// inline mutates engine state and can trigger a full RenderPresent() cycle, which races with the
// engine thread's own rendering and corrupts SDL/heap state ("malloc(): unsorted double linked list
// corrupted"). See CODEBASE_DOCUMENTATION.md "Bridge Thread-Safety" section.
enum class D1BridgeActionType : int {
	ActivateModal = 0,
	SelectModal = 1,
	UseBeltSlot = 2,
	ClickBeltSlot = 3,
	SetVanillaHUDHidden = 4,
	DismissQText = 5,
	SelectSpell = 6,
	AddAttributePoint = 7,
	ToggleCharacterSheet = 8,
	SelectQuest = 9,
	ToggleQuestLog = 10,
	ToggleInventory = 11,
	ClickInventorySlot = 12,
	UseInventorySlot = 13,
	// Options-menu settings (Music/Sound volume, Gamma, Speed/tick-rate). Applied on the
	// engine thread so they never race RenderPresent()/SDL state from Godot's main thread.
	SetMusicVolume = 14,
	SetSoundVolume = 15,
	SetGamma = 16,
	SetSpeed = 17,
	// Stash actions
	CloseStash = 18,
	StashChangePage = 19,
	StashSetPage = 20,
	ClickStashSlot = 21,
	StashWithdrawGold = 22,
	// Spellbook actions
	ToggleSpellBook = 23,
	SetSpellBookPage = 24,
	SelectSpellBookEntry = 25,
	// Zoom-scaled vision radius
	SetZoomVisionRadius = 26,
	// Smart Potion & Spell Binding actions
	UseSmartPotion = 27,
	BindSpellHotkey = 28,
	QuickCastHotkey = 29,
	UseSmartTownPortal = 30,
	SetActiveUiPanel = 31,
	CloseAllUiPanels = 32,
	CancelTargetingCursor = 33
};

void PushBridgeAction(D1BridgeActionType type, int arg1 = 0, int arg2 = 0, int arg3 = 0, int arg4 = 0);

// Read-only parity helpers: LCG state captured at the moment the last queued job was executed
// on the engine thread, and that job's type. Safe to call from Godot's main thread (atomics).
uint32_t GetLastBridgeActionSeed();
int GetLastBridgeActionType();
uint64_t GetLastBridgeActionSeq();

void SetActiveUiPanel(int panel);
void CloseAllUiPanels();
int GetActiveUiPanel();

void StartDevilutionXThread(const char *basePath);
void PushDevilutionXInput(uint32_t type, uint32_t code, uint32_t state, int32_t x, int32_t y);
bool CopyD1FrameBytes(uint8_t *dest, size_t maxBytes, uint32_t *outFrameId, int *outW, int *outH);
void CopyD1DungeonGrid(int32_t *dest, size_t maxTiles);

extern std::atomic<bool> g_D1EngineQuitRequested;
extern std::atomic<bool> g_DiabloThreadRunning;
bool IsDevilutionXRunning();
bool IsDevilutionXQuitRequested();
void RequestDevilutionXQuit();
bool IsGameRunningLive();

// Native Godot Audio Interception
struct D1AudioEvent {
	enum Type : uint32_t {
		MUSIC_PLAY = 1,
		MUSIC_STOP = 2,
		SFX_PLAY = 3,
		STREAM_PLAY = 4,
		STREAM_STOP = 5,
	} type;
	char path[128];
	int32_t volume;
	int32_t pan;
	int32_t tileX;
	int32_t tileY;
	bool hasPos;
};

void PushDevilutionXAudioEvent(D1AudioEvent::Type type, const char *path, int32_t volume = 0, int32_t pan = 0, int32_t tileX = 0, int32_t tileY = 0, bool hasPos = false);
size_t PopDevilutionXAudioEvents(D1AudioEvent *outEvents, size_t maxEvents);
std::vector<uint8_t> LoadDevilutionXAsset(const char *path);

// Native Godot 3D Lighting & Shadows
struct D1EngineLight {
	float normX = 0.5f;
	float normY = 0.5f;
	float radius = 5.0f;
	int type = 0; // 0: Player Torch, 1: Wall Torch / Brazier, 2: Missile / Spell, 3: Monster / Ambient
	int tileX = 0;
	int tileY = 0;
};

struct D1WallOccluder {
	float normX = 0.0f;
	float normY = 0.0f;
};

// Native Godot 3D GPUParticles Visual Events
struct D1VisualEvent {
	uint32_t type = 0; // 1: Blood Splatter, 2: Bone Shards, 3: Fireball Explosion, 4: Hit Sparks
	float normX = 0.5f;
	float normY = 0.5f;
	int tileX = 0;
	int tileY = 0;
	float dirX = 0.0f;
	float dirY = -1.0f;
	float intensity = 1.0f;
};

void PushVisualEvent(uint32_t type, Point tile, Displacement offset, Direction dir, float intensity = 1.0f);
std::vector<D1EngineLight> GetActiveEngineLights();
std::vector<D1WallOccluder> GetActiveWallOccluders();
std::vector<D1VisualEvent> DrainVisualEvents();

struct D1ItemIconRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};
D1ItemIconRgba GetBeltItemIconRgba(int slotIndex);

// Native Godot Diablo IV Character Sheet & Quest Log
struct D1CharacterInfo {
	char name[32] = { 0 };
	int playerClass = 0;
	int level = 1;
	int exp = 0;
	int nextExp = 0;
	int gold = 0;

	int strBase = 0;
	int strNow = 0;
	int strMax = 0;

	int magBase = 0;
	int magNow = 0;
	int magMax = 0;

	int dexBase = 0;
	int dexNow = 0;
	int dexMax = 0;

	int vitBase = 0;
	int vitNow = 0;
	int vitMax = 0;

	int statPts = 0;

	int hp = 0;
	int maxHp = 0;
	int mana = 0;
	int maxMana = 0;

	int armor = 0;
	int toHit = 0;
	int dmgMin = 0;
	int dmgMax = 0;

	int resMagic = 0;
	int resFire = 0;
	int resLightning = 0;
};

D1CharacterInfo GetCharacterInfo();
void AddAttributePoint(int attrIdx);
bool IsCharacterSheetOpen();
void ToggleCharacterSheet();

struct D1QuestEntry {
	int idx = 0;
	char name[64] = { 0 };
	bool isFinished = false;
	int level = 0;
};

std::vector<D1QuestEntry> GetQuestsInfo();
void SelectQuest(int questIdx);
bool IsQuestLogOpen();
void ToggleQuestLog();

bool IsInventoryOpen();
void ToggleInventory();

// Native Godot Diablo IV Inventory
struct D1InvItemData {
	int slotId = 0; // 0..6 for equipment (SLOTXY_HEAD..SLOTXY_CHEST), or 0..39 for backpack index
	int type = 0;
	int miscId = 0; // item_misc_id, needed by the native logic layer (D1ItemLogic)
	int curs = 0;
	int cursId = 0;
	int quality = 0; // 0=normal, 1=magic, 2=unique
	char name[64] = { 0 };
	char stats[256] = { 0 };
	int cellX = 0;
	int cellY = 0;
	int cellW = 1;
	int cellH = 1;
	bool canUse = true;
	bool isIdentified = true;
	int durability = 0;
	int maxDurability = 0;
	int value = 0;
	int invListIndex = -1;
};

std::vector<D1InvItemData> GetPlayerEquipmentData();
std::vector<D1InvItemData> GetPlayerBackpackData();
D1InvItemData GetPlayerHoldItemData();
int GetPlayerGold();
D1ItemIconRgba GetItemSpriteRgba(int cursId);
void ClickInventorySlot(int slotType, int slotIdx, bool isShift = false, bool isCtrl = false);
void UseInventorySlot(int slotType, int slotIdx);
void CancelTargetingCursor();
int GetCurrentCursorId();
uint32_t GetInventoryVersion();

// Equipment Durability Damage Warning Indicators
struct D1DurabilityWarning {
	int slotId = 0;       // 0=Head, 6=Chest, 4=HandLeft, 5=HandRight
	int iconIdx = 0;      // 0=Shield, 1=Sword, 2=Chest, 3=Head, 4=Mace, 5=Axe, 6=Bow, 7=Staff
	int frameIdx = 0;     // 0..7 for Red, 8..15 for Gold
	int durability = 0;
	int maxDurability = 0;
	int status = 0;       // 1 = Gold Warning (<=5), 2 = Red Critical/Broken (<=2)
	char name[64] = { 0 };
};

std::vector<D1DurabilityWarning> GetPlayerDurabilityWarnings();
D1ItemIconRgba GetDurabilityIconRgba(int frameIdx);
D1ItemIconRgba GetDurabilityCompositeIconRgba(int iconIdx, int durability);

// Native Godot 3D Sandbox & Spatial Entity Tracking
struct D1MonsterEntityData {
	int id = 0;
	char name[64] = { 0 };
	int type = 0;
	float posX = 0.0f;
	float posY = 0.0f;
	int dir = 0;
	int hp = 0;
	int maxHp = 0;
	bool isAlive = true;
	bool isWalking = false;
	int mode = 0;
	int animFrame = 0;
	bool isVisible = true;
};

struct D1PlayerEntityData {
	float posX = 0.0f;
	float posY = 0.0f;
	int tileX = 0;
	int tileY = 0;
	int dir = 0;
	bool isWalking = false;
	int mode = 0;
	int animFrame = 0;
};

D1PlayerEntityData GetPlayerEntityData();
std::vector<D1MonsterEntityData> GetActiveMonstersData();
std::vector<uint8_t> GetDungeonSolidityGrid();

// Native Godot 3D Billboard Sprite Extraction
struct D1SpriteFrameRgba {
	int width = 0;
	int height = 0;
	int frame = 0;
	int dir = 0;
	std::vector<uint8_t> rgba;
};

D1SpriteFrameRgba GetPlayerSpriteRgba();
D1SpriteFrameRgba GetMonsterSpriteRgba(int monsterId);

// Native Godot 2.5D Dungeon Piece Extraction
struct D1TilePieceRgba {
	int width = 0;
	int height = 0;
	int numRows = 0;
	std::vector<uint8_t> rgba;
};

D1TilePieceRgba GetDungeonPieceRgba(int pieceId);

// Special CELs (Archways, Column Tops, Doorways)
struct D1SpecialCelRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};

D1SpecialCelRgba GetSpecialCelRgba(int specialId);
void CopyD1SpecialGrid(int32_t *dest, size_t maxTiles);

// Per-Tile Lighting & Transparency (Fog of War & Room Transparency)
void CopyD1LightGrid(uint8_t *dest, size_t maxTiles);
void CopyD1FlagsGrid(uint8_t *dest, size_t maxTiles);
void CopyD1TransGrid(uint8_t *dest, size_t maxTiles);
void CopyD1TransparencyMask(uint8_t *dest, size_t maxTiles);
std::vector<uint8_t> GetTransList();

// Native Godot 2.5D Dungeon Objects (Torches, Barrels, Chests, Shrines)
struct D1ObjectInfo {
	int id;
	int type;
	int tileX;
	int tileY;
	int animFrame;
	int animTotal;
	bool preFlag;
	bool solid;
	bool selectable;
	int width;
	int height;
};

struct D1ObjectSpriteRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};

std::vector<D1ObjectInfo> GetActiveObjectsList();

// Level transition triggers (Source/levels/trigs.h). Walking onto one of these tiles is what
// makes the engine change level, so a soak can drive a real transition instead of only ever
// observing the steady state.
struct D1LevelTrigger
{
	int x = 0;
	int y = 0;
	int msg = 0;          // interface_mode (WM_DIABNEXTLVL = 0)
	int targetLevel = 0;  // _tlvl
};

std::vector<D1LevelTrigger> GetLevelTriggers();
D1ObjectSpriteRgba GetObjectSpriteRgba(int objectId);
int GetModalType();
bool IsModalActiveLive();
bool IsAutomapActive();

// Godot native-modal-overlay bridge: active menu items + selection for the
// current D1 modal (pause/gamemenu, dialog/store, death-restart).
struct D1MenuItemInfo {
	std::string text;
	bool enabled = true;
	bool selectable = true;
	int price = 0;
};
std::vector<D1MenuItemInfo> GetCurrentMenuItems();
int GetCurrentModalSelectionIndex();
int GetBridgeStoreGold();
void ActivateModalItem(int index);
void SelectModalItem(int index);
bool IsQTextActive();
std::vector<std::string> GetQTextLines();
std::string GetQTextTitle();
void SetActiveQuestTitle(std::string_view title);
void DismissQText();

// Native Godot Modern Stash Bridge
struct D1StashInfo {
	int page = 0;
	int totalPages = 100;
	int gold = 0;
};
bool IsBridgeStashOpen();
void CloseBridgeStash();
D1StashInfo GetStashInfo();
std::vector<D1InvItemData> GetStashItems();
void StashChangePage(int delta);
void StashSetPage(int page);
void ClickStashSlot(int cellIdx, bool isShift = false, bool isCtrl = false);
void StashWithdrawGold(int amount);

// Native Godot Modern SpellBook Bridge
struct D1SpellBookEntry {
	int spellId = 0;
	int spellType = 0; // 0: Spell, 1: Skill, 2: Charges
	std::string name;
	std::string typeText;
	int level = 0;
	int mana = 0;
	std::string detail;
	bool isEquipped = false;
	bool canCast = true;
};
bool IsSpellBookOpen();
void ToggleSpellBook();
int GetSpellBookPage();
void SetSpellBookPage(int page);
std::vector<D1SpellBookEntry> GetSpellBookEntries();
void SelectSpellBookEntry(int spellId, int spellType);

struct D1AutomapRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};
D1AutomapRgba GetAutomapRgba();

// Native Godot 2.5D Ground Items & Loot
struct D1ItemInfo {
	int id;
	int tileX;
	int tileY;
	int cursId;
	int quality;
	bool identified;
	char name[64];
	int width;
	int height;
	int animFrame;
};

struct D1ItemSpriteRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};

std::vector<D1ItemInfo> GetActiveItemsList();
D1ItemSpriteRgba GetGroundItemSpriteRgba(int itemId);
bool IsItemLabelHighlightEnabled();

// Native Godot 2.5D Corpses & Fallen Monsters
struct D1CorpseInfo {
	int tileX;
	int tileY;
	int corpseIdx;
	int dir;
	int frame;
	int width;
	int height;
	char monsterName[64] = { 0 };
};

struct D1CorpseSpriteRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};

std::vector<D1CorpseInfo> GetActiveCorpsesList();
D1CorpseSpriteRgba GetCorpseSpriteRgba(int corpseIdx, int dir);

// Isometric <-> Screen Coordinate Mapping
Point MapIsometricToScreenCoords(float isoX, float isoY);

// Missiles & Spell Projectiles (Firebolt, Holy Bolt, Fireball, Lightning, Arrows)
struct D1MissileInfo {
	int id;
	int type;
	int dir;
	float posX;
	float posY;
	int tileX;
	int tileY;
	int animFrame;
	int width;
	int height;
	bool lightFlag;
	bool preFlag;
};

struct D1MissileSpriteRgba {
	int width = 0;
	int height = 0;
	std::vector<uint8_t> rgba;
};

std::vector<D1MissileInfo> GetActiveMissilesList();
D1MissileSpriteRgba GetMissileSpriteRgba(int missileId);

bool IsBridgeSafeToRead();

// The individual inputs of IsBridgeSafeToRead(), exposed so a native mirror of the safety
// contract can be compared against the engine's own answer state by state.
struct D1BridgeReadGate
{
	bool gameRunning = false;
	bool playerReady = false;
	int pmode = 0;
	bool lvlChanging = false;
	bool transitioning = false;
	bool fadedIn = false;
	bool safe = false;
};

D1BridgeReadGate GetBridgeReadGate();

// Native Godot Menu Bridge (Main Menu, Character Select, New Hero)
enum class D1MenuMode : int32_t {
	None = 0,
	MainMenu = 1,
	CharacterSelect = 2,
};

struct D1HeroEntry {
	uint32_t saveNumber;
	char name[16];
	uint8_t level;
	int heroClass;
	uint8_t heroRank;
	uint16_t strength;
	uint16_t magic;
	uint16_t dexterity;
	uint16_t vitality;
	bool hasSaved;
};

struct D1ClassDefaultStats {
	uint16_t strength;
	uint16_t magic;
	uint16_t dexterity;
	uint16_t vitality;
};

enum _mainmenu_selections : uint8_t;
enum _selhero_selections : uint8_t;
enum _difficulty : uint8_t;
struct _uiheroinfo;
struct _uidefaultstats;

D1MenuMode GetBridgeMenuMode();
std::vector<D1HeroEntry> GetBridgeHeroList();
D1ClassDefaultStats GetBridgeClassStats(int heroClass);
std::string GetBridgeRandomName(int heroClass);
bool BridgeCreateHero(const char *name, int heroClass);
bool BridgeDeleteHero(uint32_t saveNumber);
void BridgeSelectSinglePlayer();
void BridgeSelectMultiplayer();
void BridgeShowCredits();
void BridgeLaunchHero(uint32_t saveNumber, int difficulty, bool loadExisting);
void BridgeCancelHeroSelect();
void BridgeExitGame();
bool IsHellfireMode();
bool IsClassAllowed(int heroClass);
std::string GetBridgeLanguageCode();

bool GodotBridgeMainMenuDialog(_mainmenu_selections *pdwResult);
void GodotBridgeSelHeroDialog(
    bool (*fninfo)(bool (*fninfofunc)(_uiheroinfo *)),
    bool (*fncreate)(_uiheroinfo *),
    bool (*fnremove)(_uiheroinfo *),
    void (*fnstats)(unsigned int, _uidefaultstats *),
    _selhero_selections *dlgresult,
    uint32_t *saveNumber,
    _difficulty *difficulty);

// Native Godot Full DevilutionX Settings Bridge
struct D1SettingCategory {
	int id;
	std::string name;
	std::string description;
};

struct D1SettingEntry {
	int id;
	int categoryId;
	std::string name;
	std::string description;
	int type; // 0=Boolean, 1=List, 2=Key, 3=PadButton
	std::string valueStr;
	bool boolValue;
	int listIndex;
	std::vector<std::string> listOptions;
};

std::vector<D1SettingCategory> GetBridgeSettingsCategories();
std::vector<D1SettingEntry> GetBridgeSettingsEntries(int categoryId);
void SetBridgeSettingBool(int categoryId, int entryId, bool value);
void SetBridgeSettingList(int categoryId, int entryId, int listIndex);
void SaveBridgeSettings();

// V-Sync & Show FPS state for the Godot host window.
bool GetVsyncEnabled();
bool GetShowFpsEnabled();

int GetResurrectedDisplayMode();
int GetModeSwitchKey();
uint8_t GetModeSwitchMods();
void SetModeSwitchBinding(int key, uint8_t mods);

// Resurrected display effect states (Mode 0), polled by the Godot side.
bool GetResurrectedTorchlight();
int GetResurrectedFogLevel();
int GetResurrectedColorProfile();
int GetResurrectedHdrLevel();
int GetResurrectedUpscalerMode();
int GetResurrectedReliefMode();
bool GetResurrectedWetFloor();
int GetResurrectedTileModel();
void SetResurrectedTileModel(int model);

} // namespace devilution

