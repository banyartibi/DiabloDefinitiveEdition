#include "engine/render_bridge.hpp"
#include "stores.h"
#include "gmenu.h"
#include "multi.h"
#include "options.h"
#include "loadsave.h"
#include "engine/render/scrollrt.h"
#include "engine/render/clx_render.hpp"
#include "engine/load_cel.hpp"
#include "utils/clx_decode.hpp"
#include "engine/render/dun_render.hpp"
#include "engine/dx.h"
#include "engine/backbuffer_state.hpp"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <signal.h>
#include <cstring>
#include <mutex>
#include <condition_variable>
#include <vector>
#include <thread>
#include <chrono>
#include <atomic>
#include <fmt/format.h>
#include "pfile.h"

#include "control.h"
#include "player.h"
#include "monster.h"
#include "levels/gendung.h"
#include "diablo.h"
#include "utils/paths.h"
#include "engine.h"
#include "engine/assets.hpp"
#include "panels/spell_icons.hpp"
#include "panels/spell_book.hpp"
#include "utils/language.h"
#include "utils/format_int.hpp"
#include "engine/palette.h"
#include "engine/sound_defs.hpp"
#include "engine/surface.hpp"
#include "items.h"
#include "quests.h"
#include "minitext.h"
#include "inv.h"
#include "qol/stash.h"
#include "DiabloUI/diabloui.h"
#include "msg.h"
#include "cursor.h"
#include "init.h"
#include "sound.h"
#include "effects.h"
#include "lighting.h"
#include "objects.h"
#include "objdat.h"
#include "itemdat.h"
#include "dead.h"
#include "missiles.h"
#include "towners.h"
#include "stores.h"
#include "help.h"
#include "gmenu.h"
#include "qol/chatlog.h"
#include "qol/itemlabels.h"
#include "automap.h"
#include <cmath>

namespace devilution {

bool gbGodotBridgeActive = true;
bool gbHideVanillaHUD = false;
std::atomic<bool> g_D1LevelTransitioning{false};
D1EngineData g_D1EngineData;

bool IsBridgeSafeToRead()
{
	return gbRunGame && !g_D1LevelTransitioning.load() && sgbFadedIn.load() && MyPlayer != nullptr && MyPlayer->_pmode != PM_NEWLVL && !MyPlayer->_pLvlChanging;
}

void SetVanillaHUDHidden(bool hidden)
{
	gbHideVanillaHUD = hidden;
	CalculatePanelAreas();
}

namespace {
int g_ShmFd = -1;
void *g_ShmMapped = nullptr;
size_t g_ShmTotalSize = 0;
uint32_t g_BridgeFrameCount = 0;

std::mutex g_D1FrameMutex;
std::vector<uint8_t> g_D1InternalFrame;

std::mutex g_DirectInputMutex;
std::vector<D1InputMsg> g_DirectInputQueue;

// Queued high-level game actions (modal activations, belt/spell clicks, toggles, ...).
// These are pushed by the Godot layer and drained ONLY on this engine thread so they never race
// with the engine thread's own RenderPresent()/game state. See PushBridgeAction / D1BridgeActionType.
struct D1BridgeJob {
	D1BridgeActionType type;
	int a = 0, b = 0, c = 0, d = 0;
};
std::mutex g_BridgeJobMutex;
std::vector<D1BridgeJob> g_BridgeJobs;

std::thread g_DiabloThread;
} // namespace

std::atomic<bool> g_DiabloThreadRunning{false};
std::atomic<bool> g_D1EngineQuitRequested{false};

void InitGodotBridge(int width, int height)
{
	size_t payloadSize = static_cast<size_t>(width) * height * 4;
	size_t reqSize = sizeof(D1BridgeHeader) + payloadSize;

	if (g_ShmMapped != nullptr && g_ShmTotalSize == reqSize)
		return;

	// Resize the SHM mapping when its size changes WITHOUT requesting an engine quit.
	// ExportGodotFrame() calls this every frame, and D1 renders at different resolutions during
	// intro/cutscene/level transitions (storm_svid.cpp sets the renderer logical size to the video
	// dimensions). The previous implementation called CleanupGodotBridge(), which invoked
	// RequestDevilutionXQuit() - aborting gameplay mid-transition. Now we simply release and
	// recreate the mapping at the new size; no quit is requested.
	if (g_ShmMapped != nullptr) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		hdr->magic = 0xDEADBEEF;
		munmap(g_ShmMapped, g_ShmTotalSize);
		g_ShmMapped = nullptr;
		if (g_ShmFd >= 0) { close(g_ShmFd); g_ShmFd = -1; }
		shm_unlink("/dev/shm/d1_godot_frame");
	}

	g_ShmTotalSize = reqSize;
	g_ShmFd = open("/dev/shm/d1_godot_frame", O_RDWR | O_CREAT, 0666);
	if (g_ShmFd >= 0) {
		if (ftruncate(g_ShmFd, reqSize) == 0) {
			g_ShmMapped = mmap(nullptr, reqSize, PROT_READ | PROT_WRITE, MAP_SHARED, g_ShmFd, 0);
		}
	}
}

void ExportGodotFrame(const SDL_Surface *surface)
{
	if (!gbGodotBridgeActive || surface == nullptr || surface->pixels == nullptr || surface->w <= 0 || surface->h <= 0)
		return;

	const SDL_Surface *srcSurface = surface;
	SDL_Surface *converted = nullptr;

	// Godot's Image::create_from_data(FORMAT_RGBA8) expects memory layout R,G,B,A,
	// which on little-endian is SDL_PIXELFORMAT_RGBA32 (== ABGR8888). D1's output surfaces vary:
	//  - OpenGL upscale path: 24-bit RGB888 (no alpha channel at all),
	//  - Vulkan readback path: ARGB8888 (memory B,G,R,A; GPU readback leaves alpha=0).
	// Converting to ARGB8888 used to export memory layout B,G,R,A with alpha=0, which Godot
	// interpreted as R/B-swapped and fully transparent -> black viewport. Always normalize
	// to RGBA32 and force opaque alpha so the exported frame is never transparent.
	const Uint32 targetFormat = SDL_PIXELFORMAT_RGBA32;
	if (surface->format == nullptr || surface->format->format != targetFormat) {
		converted = SDL_ConvertSurfaceFormat(const_cast<SDL_Surface *>(surface), targetFormat, 0);
		if (converted != nullptr && converted->pixels != nullptr) {
			srcSurface = converted;

			// Force opaque alpha: D1 surfaces carry no meaningful per-pixel alpha.
			const int w = srcSurface->w;
			const int h = srcSurface->h;
			uint8_t *px = static_cast<uint8_t *>(srcSurface->pixels);
			for (int y = 0; y < h; ++y) {
				uint8_t *row = px + y * srcSurface->pitch;
				for (int x = 0; x < w; ++x) {
					row[x * 4 + 3] = 255; // alpha byte in RGBA32 memory layout
				}
			}
		} else {
			if (converted != nullptr) SDL_FreeSurface(converted);
			return;
		}
	}

	// 1. Update In-Process Direct Engine Data (Zero IPC!)
	{
		std::lock_guard<std::mutex> lock(g_D1FrameMutex);
		g_BridgeFrameCount++;
		g_D1EngineData.frameId = g_BridgeFrameCount;
		g_D1EngineData.width = srcSurface->w;
		g_D1EngineData.height = srcSurface->h;
		g_D1EngineData.playerNormX = 0.50f;
		g_D1EngineData.playerNormY = 0.52f;

		if (MyPlayer != nullptr) {
			g_D1EngineData.playerTileX = MyPlayer->position.tile.x;
			g_D1EngineData.playerTileY = MyPlayer->position.tile.y;
			g_D1EngineData.playerHp = MyPlayer->_pHitPoints >> 6;
			g_D1EngineData.playerMaxHp = MyPlayer->_pMaxHP >> 6;
			g_D1EngineData.playerMana = MyPlayer->_pMana >> 6;
			g_D1EngineData.playerMaxMana = MyPlayer->_pMaxMana >> 6;
			g_D1EngineData.playerGold = MyPlayer->_pGold;
			g_D1EngineData.playerClass = static_cast<int>(MyPlayer->_pClass);
			g_D1EngineData.playerLevel = MyPlayer->_pLevel;
			g_D1EngineData.playerExp = MyPlayer->_pExperience;
			g_D1EngineData.playerNextExp = MyPlayer->_pNextExper;
			g_D1EngineData.playerSpell = static_cast<int>(MyPlayer->_pRSpell);
			g_D1EngineData.playerSpellType = static_cast<int>(MyPlayer->_pRSplType);

			for (size_t i = 0; i < 8; ++i) {
				if (i < sizeof(MyPlayer->SpdList) / sizeof(MyPlayer->SpdList[0]) && !MyPlayer->SpdList[i].isEmpty()) {
					const Item &item = MyPlayer->SpdList[i];
					int type = 11;
					if (item._iMiscId == IMISC_HEAL) type = 1;
					else if (item._iMiscId == IMISC_FULLHEAL) type = 2;
					else if (item._iMiscId == IMISC_MANA) type = 3;
					else if (item._iMiscId == IMISC_FULLMANA) type = 4;
					else if (item._iMiscId == IMISC_REJUV) type = 5;
					else if (item._iMiscId == IMISC_FULLREJUV) type = 6;
					else if (item._iMiscId > IMISC_OILFIRST && item._iMiscId < IMISC_OILLAST) type = 9;
					else if (item.isScroll()) type = 8;
					else if (item.isRune()) type = 10;
					else if (item._iMiscId == IMISC_ELIXSTR || item._iMiscId == IMISC_ELIXMAG || item._iMiscId == IMISC_ELIXDEX || item._iMiscId == IMISC_ELIXVIT) type = 7;
					g_D1EngineData.beltTypes[i] = type;
					g_D1EngineData.beltCounts[i] = 1;
					std::strncpy(g_D1EngineData.beltNames[i], item._iIName, 63);
					g_D1EngineData.beltNames[i][63] = '\0';
				} else {
					g_D1EngineData.beltTypes[i] = 0;
					g_D1EngineData.beltCounts[i] = 0;
					g_D1EngineData.beltNames[i][0] = '\0';
				}
			}
		}

		g_D1EngineData.currentLevel = currlevel;
		g_D1EngineData.dungeonType = leveltype;
		g_D1EngineData.leftPanelOpen = IsLeftPanelOpen();
		g_D1EngineData.rightPanelOpen = IsRightPanelOpen();
		const Rectangle &lp = GetLeftPanel();
		g_D1EngineData.leftPanelX = lp.position.x;
		g_D1EngineData.leftPanelY = lp.position.y;
		g_D1EngineData.leftPanelW = lp.size.width;
		g_D1EngineData.leftPanelH = lp.size.height;

		const Rectangle &rp = GetRightPanel();
		g_D1EngineData.rightPanelX = rp.position.x;
		g_D1EngineData.rightPanelY = rp.position.y;
		g_D1EngineData.rightPanelW = rp.size.width;
		g_D1EngineData.rightPanelH = rp.size.height;

		g_D1EngineData.isSpeedbookOpen = spselflag;
		if (spselflag) {
			const Rectangle &mp = GetMainPanel();
			g_D1EngineData.speedbookX = mp.position.x;
			g_D1EngineData.speedbookY = mp.position.y - 320;
			g_D1EngineData.speedbookW = 640;
			g_D1EngineData.speedbookH = 320 + mp.size.height;
		} else {
			g_D1EngineData.speedbookX = 0;
			g_D1EngineData.speedbookY = 0;
			g_D1EngineData.speedbookW = 0;
			g_D1EngineData.speedbookH = 0;
		}

		// Export Hover Item Info
		if (!InfoString.empty() && gbRunGame) {
			g_D1EngineData.hasHoverInfo = true;
			string_view fullInfo = InfoString.str();
			size_t firstNl = fullInfo.find('\n');
			if (firstNl != string_view::npos) {
				string_view nameStr = fullInfo.substr(0, firstNl);
				string_view statsStr = fullInfo.substr(firstNl + 1);
				std::strncpy(g_D1EngineData.hoverItemName, nameStr.data(), std::min(sizeof(g_D1EngineData.hoverItemName) - 1, nameStr.size()));
				g_D1EngineData.hoverItemName[std::min(sizeof(g_D1EngineData.hoverItemName) - 1, nameStr.size())] = '\0';
				std::strncpy(g_D1EngineData.hoverItemStats, statsStr.data(), std::min(sizeof(g_D1EngineData.hoverItemStats) - 1, statsStr.size()));
				g_D1EngineData.hoverItemStats[std::min(sizeof(g_D1EngineData.hoverItemStats) - 1, statsStr.size())] = '\0';
			} else {
				std::strncpy(g_D1EngineData.hoverItemName, fullInfo.data(), std::min(sizeof(g_D1EngineData.hoverItemName) - 1, fullInfo.size()));
				g_D1EngineData.hoverItemName[std::min(sizeof(g_D1EngineData.hoverItemName) - 1, fullInfo.size())] = '\0';
				g_D1EngineData.hoverItemStats[0] = '\0';
			}

			if (HasAnyOf(InfoColor, UiFlags::ColorBlue))
				g_D1EngineData.hoverItemQuality = 1;
			else if (HasAnyOf(InfoColor, UiFlags::ColorWhitegold))
				g_D1EngineData.hoverItemQuality = 2;
			else if (HasAnyOf(InfoColor, UiFlags::ColorRed))
				g_D1EngineData.hoverItemQuality = 3;
			else
				g_D1EngineData.hoverItemQuality = 0;

			g_D1EngineData.hoverMouseX = MousePosition.x;
			g_D1EngineData.hoverMouseY = MousePosition.y;

			const Rectangle &rpRect = GetRightPanel();
			g_D1EngineData.isInventoryHover = IsRightPanelOpen() &&
				(MousePosition.x >= rpRect.position.x && MousePosition.x <= rpRect.position.x + rpRect.size.width &&
				 MousePosition.y >= rpRect.position.y && MousePosition.y <= rpRect.position.y + rpRect.size.height);
			g_D1EngineData.isMonsterHover = (pcursmonst != -1);
		} else {
			g_D1EngineData.hasHoverInfo = false;
			g_D1EngineData.hoverItemName[0] = '\0';
			g_D1EngineData.hoverItemStats[0] = '\0';
			g_D1EngineData.hoverItemQuality = 0;
			g_D1EngineData.isInventoryHover = false;
			g_D1EngineData.isMonsterHover = false;
		}

		g_D1EngineData.isGameRunning = gbRunGame;
		g_D1EngineData.zoomMode = static_cast<int>(CurrentZoomMode);
		g_D1EngineData.isModalActive = (stextflag != TalkID::None || HelpFlag || ChatLogFlag || talkflag || qtextflag || gmenu_is_active() || PauseMode != 0 || MyPlayerIsDead);
		g_D1EngineData.isTextInputActive = IsTextInputActiveLive();
		g_D1EngineData.isPlayerDead = MyPlayerIsDead || (MyPlayer != nullptr && MyPlayer->_pmode == PM_DEATH);

		size_t reqBytes = static_cast<size_t>(srcSurface->w) * srcSurface->h * 4;
		if (g_D1InternalFrame.size() != reqBytes) {
			g_D1InternalFrame.resize(reqBytes);
		}
		std::memcpy(g_D1InternalFrame.data(), srcSurface->pixels, reqBytes);
	}

	// 2. Also write to POSIX SHM for backward compatibility
	InitGodotBridge(srcSurface->w, srcSurface->h);
	if (g_ShmMapped != nullptr) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		hdr->magic = 0x44315242; // "D1RB"
		hdr->version = 1;
		hdr->width = srcSurface->w;
		hdr->height = srcSurface->h;
		hdr->pitch = srcSurface->pitch;
		hdr->frameId = g_BridgeFrameCount;
		hdr->timestamp = SDL_GetTicks();
		hdr->playerNormX = 0.50f;
		hdr->playerNormY = 0.52f;
		hdr->zoomMode = static_cast<int32_t>(CurrentZoomMode) + 1;
		hdr->torchCount = 0;

		// Export UI Panel States (Character sheet, Inventory, Quest log, Spellbook)
		hdr->torches[0].normX = g_D1EngineData.leftPanelOpen ? 1.0f : 0.0f;
		hdr->torches[0].normY = g_D1EngineData.rightPanelOpen ? 1.0f : 0.0f;

		// Copy pixels directly to shared memory
		uint8_t *dstPixels = static_cast<uint8_t *>(g_ShmMapped) + sizeof(D1BridgeHeader);
		std::memcpy(dstPixels, srcSurface->pixels, srcSurface->w * srcSurface->h * 4);

		hdr->readyFlag = 1;
	}

	if (converted != nullptr) {
		SDL_FreeSurface(converted);
	}
}

void PushBridgeAction(D1BridgeActionType type, int arg1, int arg2, int arg3, int arg4)
{
	D1BridgeJob job;
	job.type = type;
	job.a = arg1;
	job.b = arg2;
	job.c = arg3;
	job.d = arg4;
	// Only enqueue; execution happens on the engine thread in the drain below.
	std::lock_guard<std::mutex> lock(g_BridgeJobMutex);
	g_BridgeJobs.push_back(job);
}

void PollGodotBridgeInput()
{
	// Drain queued high-level game actions on the ENGINE thread. This runs every frame from
	// PollEvent(), i.e. on g_DiabloThread, so these state-mutating calls (which can trigger a full
	// RenderPresent cycle) never run concurrently with the engine thread's own rendering. Calling
	// them directly from Godot's main thread races on shared SDL/heap state and corrupts the heap.
	// Snapshot and clear queued jobs UNDER the lock, then execute them OUTSIDE the lock.
	// Long-running actions (e.g. Save Game -> DrawAndBlit / interface_msg_pump) must never run
	// while holding g_BridgeJobMutex: that would block any re-entrant PushBridgeAction() from Godot
	// and can deadlock/freeze the engine thread. Clearing first also removes the unlocked-clear
	// data race on the previous implementation.
	std::vector<D1BridgeJob> drainedJobs;
	{
		std::lock_guard<std::mutex> lock(g_BridgeJobMutex);
		drainedJobs.swap(g_BridgeJobs);
	}
	for (const auto &job : drainedJobs) {
		switch (job.type) {
		case D1BridgeActionType::ActivateModal:       ActivateModalItem(job.a); break;
		case D1BridgeActionType::SelectModal:         SelectModalItem(job.a); break;
		case D1BridgeActionType::UseBeltSlot:         UseBeltSlot(job.a); break;
		case D1BridgeActionType::ClickBeltSlot:       ClickBeltSlot(job.a); break;
		case D1BridgeActionType::SetVanillaHUDHidden: SetVanillaHUDHidden(job.a != 0); break;
		case D1BridgeActionType::DismissQText:        DismissQText(); break;
		case D1BridgeActionType::SelectSpell:         SelectSpell(job.a, job.b); break;
		case D1BridgeActionType::AddAttributePoint:   AddAttributePoint(job.a); break;
		case D1BridgeActionType::ToggleCharacterSheet: ToggleCharacterSheet(); break;
		case D1BridgeActionType::SelectQuest:         SelectQuest(job.a); break;
		case D1BridgeActionType::ToggleQuestLog:      ToggleQuestLog(); break;
		case D1BridgeActionType::ToggleInventory:     ToggleInventory(); break;
		case D1BridgeActionType::ClickInventorySlot:  ClickInventorySlot(job.a, job.b, job.c != 0, job.d != 0); break;
		case D1BridgeActionType::UseInventorySlot:    UseInventorySlot(job.a, job.b); break;
		case D1BridgeActionType::SetMusicVolume: {
			int volume = job.a;
			if (volume < VOLUME_MIN) volume = VOLUME_MIN;
			else if (volume > VOLUME_MAX) volume = VOLUME_MAX;
			sound_get_or_set_music_volume(volume);
			// Keep gbMusicOn in sync with the slider, mirroring D1's own options
			// screen: dragging to minimum mutes music, dragging up resumes it.
			if (volume > VOLUME_MIN && !gbMusicOn) {
				gbMusicOn = true;
				music_start(GetLevelMusic(leveltype));
			} else if (volume == VOLUME_MIN && gbMusicOn) {
				gbMusicOn = false;
				music_stop();
			}
			break;
		}
		case D1BridgeActionType::SetSoundVolume: {
			int volume = job.a;
			if (volume < VOLUME_MIN) volume = VOLUME_MIN;
			else if (volume > VOLUME_MAX) volume = VOLUME_MAX;
			sound_get_or_set_sound_volume(volume);
			// Keep gbSoundOn in sync with the slider, mirroring D1's own options screen.
			if (volume > VOLUME_MIN && !gbSoundOn) {
				gbSoundOn = true;
			} else if (volume == VOLUME_MIN && gbSoundOn) {
				gbSoundOn = false;
				sound_stop();
			}
			break;
		}
		case D1BridgeActionType::SetGamma:            UpdateGamma(job.a); break;
		case D1BridgeActionType::SetSpeed: {
			int rate = job.a;
			if (rate < 20) rate = 20;
			else if (rate > 50) rate = 50;
			sgGameInitInfo.nTickRate = static_cast<uint8_t>(rate);
			gnTickDelay = static_cast<uint16_t>(1000 / rate);
			sgOptions.Gameplay.tickRate.SetValue(rate);
			break;
		}
		case D1BridgeActionType::CloseStash:          CloseStash(); break;
		case D1BridgeActionType::StashChangePage:     StashChangePage(job.a); break;
		case D1BridgeActionType::StashSetPage:        StashSetPage(job.a); break;
		case D1BridgeActionType::ClickStashSlot:      ClickStashSlot(job.a, job.b != 0, job.c != 0); break;
		case D1BridgeActionType::StashWithdrawGold:   StashWithdrawGold(job.a); break;
		case D1BridgeActionType::ToggleSpellBook:     ToggleSpellBook(); break;
		case D1BridgeActionType::SetSpellBookPage:    SetSpellBookPage(job.a); break;
		case D1BridgeActionType::SelectSpellBookEntry: SelectSpellBookEntry(job.a, job.b); break;
		case D1BridgeActionType::SetZoomVisionRadius: {
			if (MyPlayer != nullptr && MyPlayer->lightId != NO_LIGHT) {
				int rad = std::clamp(job.a, 10, 15);
				ChangeLightRadius(MyPlayer->lightId, static_cast<uint8_t>(rad));
				ChangeVisionRadius(MyPlayer->getId(), rad);
			}
			break;
		}
		case D1BridgeActionType::UseSmartPotion:      UseSmartPotion(job.a); break;
		case D1BridgeActionType::BindSpellHotkey:     BindSpellHotkey(job.a, job.b, job.c); break;
		case D1BridgeActionType::QuickCastHotkey:     QuickCastHotkey(job.a); break;
		case D1BridgeActionType::UseSmartTownPortal:  UseSmartTownPortal(); break;
		case D1BridgeActionType::SetActiveUiPanel:   SetActiveUiPanel(job.a); break;
		case D1BridgeActionType::CloseAllUiPanels:   CloseAllUiPanels(); break;
		case D1BridgeActionType::CancelTargetingCursor: CancelTargetingCursor(); break;
		default: break;
	}
	}

	// 1. Process in-process GDExtension direct input queue
	{
		std::lock_guard<std::mutex> lock(g_DirectInputMutex);
		for (const auto &msg : g_DirectInputQueue) {
			SDL_Event ev {};
			if (msg.type == 1) { // Mouse Motion
				ev.type = SDL_MOUSEMOTION;
				ev.motion.x = msg.x;
				ev.motion.y = msg.y;
				SDL_PushEvent(&ev);
			} else if (msg.type == 2) { // Mouse Button
				ev.type = (msg.state != 0) ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
				ev.button.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
				ev.button.button = (msg.code == 1) ? SDL_BUTTON_LEFT : ((msg.code == 2) ? SDL_BUTTON_MIDDLE : SDL_BUTTON_RIGHT);
				ev.button.x = msg.x;
				ev.button.y = msg.y;
				SDL_PushEvent(&ev);
			} else if (msg.type == 3) { // Key
				ev.type = (msg.state != 0) ? SDL_KEYDOWN : SDL_KEYUP;
				ev.key.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
				SDL_Keymod mod = KMOD_NONE;
				if (msg.y & 1) mod = static_cast<SDL_Keymod>(mod | KMOD_SHIFT);
				if (msg.y & 2) mod = static_cast<SDL_Keymod>(mod | KMOD_CTRL);
				if (msg.y & 4) mod = static_cast<SDL_Keymod>(mod | KMOD_ALT);
				ev.key.keysym.mod = mod;
				SDL_SetModState(mod);

				// Prefer printable Unicode character (msg.x) to preserve casing and symbols for text entry
				if (msg.state != 0 && msg.x >= 32) {
					ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.x);
				} else {
					ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.code);
				}
				SDL_PushEvent(&ev);
			} else if (msg.type == 4) { // Zoom In
				ZoomInMode();
			} else if (msg.type == 5) { // Zoom Out
				ZoomOutMode();
			}
		}
		g_DirectInputQueue.clear();
	}

	// 2. Process external SHM input ringbuffer (if running with external frontend)
	if (g_ShmMapped != nullptr) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		if (hdr->magic == 0x44315242) {
			while (hdr->inputReadIdx < hdr->inputWriteIdx) {
				const D1InputMsg &msg = hdr->inputQueue[hdr->inputReadIdx % D1_INPUT_RING_SIZE];
				hdr->inputReadIdx++;

				SDL_Event ev {};
				if (msg.type == 1) { // Mouse Motion
					ev.type = SDL_MOUSEMOTION;
					ev.motion.x = msg.x;
					ev.motion.y = msg.y;
					SDL_PushEvent(&ev);
				} else if (msg.type == 2) { // Mouse Button
					ev.type = (msg.state != 0) ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
					ev.button.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
					ev.button.button = (msg.code == 1) ? SDL_BUTTON_LEFT : ((msg.code == 2) ? SDL_BUTTON_MIDDLE : SDL_BUTTON_RIGHT);
					ev.button.x = msg.x;
					ev.button.y = msg.y;
					SDL_PushEvent(&ev);
				} else if (msg.type == 3) { // Key
					ev.type = (msg.state != 0) ? SDL_KEYDOWN : SDL_KEYUP;
					ev.key.state = (msg.state != 0) ? SDL_PRESSED : SDL_RELEASED;
					SDL_Keymod mod = KMOD_NONE;
					if (msg.y & 1) mod = static_cast<SDL_Keymod>(mod | KMOD_SHIFT);
					if (msg.y & 2) mod = static_cast<SDL_Keymod>(mod | KMOD_CTRL);
					if (msg.y & 4) mod = static_cast<SDL_Keymod>(mod | KMOD_ALT);
					ev.key.keysym.mod = mod;
					SDL_SetModState(mod);

					if (msg.state != 0 && msg.x >= 32) {
						ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.x);
					} else {
						ev.key.keysym.sym = static_cast<SDL_Keycode>(msg.code);
					}
					SDL_PushEvent(&ev);
				} else if (msg.type == 4) { // Zoom In
					ZoomInMode();
				} else if (msg.type == 5) { // Zoom Out
					ZoomOutMode();
				}
			}
		}
	}
}

namespace {
void (*g_PrevTermHandler)(int) = nullptr;

// Invoked on SIGINT/SIGTERM (e.g. Ctrl+C or `kill`). RequestDevilutionXQuit() stops the
// engine and, when this runs off the main thread, joins g_DiabloThread so it is no longer
// destroyed joinable at static destruction (which used to abort with std::terminate). We
// then chain back to the previous handler so Godot's own SIGINT/SIGTERM handling still runs.
void d1_term_handler(int sig)
{
	RequestDevilutionXQuit();
	if (g_PrevTermHandler != nullptr && g_PrevTermHandler != reinterpret_cast<void (*)(int)>(SIG_DFL)
		&& g_PrevTermHandler != reinterpret_cast<void (*)(int)>(SIG_IGN)) {
		g_PrevTermHandler(sig);
	}
}
} // namespace

void StartDevilutionXThread(const char *basePath)
{
	if (g_DiabloThreadRunning)
		return;

	g_DiabloThreadRunning = true;
	setenv("D1_MINIMIZE_WINDOW", "1", 1);

	// A forced Ctrl+C / `kill` may otherwise terminate the engine thread out from under us,
	// leaving g_DiabloThread joinable at static destruction -> std::terminate. Stop+join it first.
	g_PrevTermHandler = reinterpret_cast<void (*)(int)>(signal(SIGINT, d1_term_handler));
	signal(SIGTERM, d1_term_handler);

	static std::string s_BasePath = (basePath != nullptr && basePath[0] != '\0')
		? basePath
		: "/home/biti/.local/share/diasurgical/devilution";

	// If a previous engine run was not yet joined, finish it before starting a new one.
	if (g_DiabloThread.joinable()) {
		g_DiabloThread.join();
	}

	g_DiabloThread = std::thread([]() {
		// Chain SIGINT/SIGTERM handling to the engine thread too (best-effort: it can join
		// only if delivered off-engine). The process-wide handler set above already covers the
		// main-thread case, which is where these signals normally land.
		signal(SIGINT, d1_term_handler);
		signal(SIGTERM, d1_term_handler);

		char arg0[] = "devilutionx";
		char arg1[] = "--data-dir";
		std::vector<char> arg2(s_BasePath.begin(), s_BasePath.end());
		arg2.push_back('\0');
		char arg3[] = "--config-dir";
		std::vector<char> arg4(s_BasePath.begin(), s_BasePath.end());
		arg4.push_back('\0');
		char arg5[] = "--hellfire";

		char *argv[] = { arg0, arg1, arg2.data(), arg3, arg4.data(), arg5, nullptr };
		int argc = 6;

		const char *envA = std::getenv("D1_ASSETS_DIR");
		if (envA != nullptr && envA[0] != '\0') {
			devilution::paths::SetAssetsPath(envA);
		} else {
			devilution::paths::SetAssetsPath("/home/biti/antigravity/magical-bell/assets/");
		}
		devilution::DiabloMain(argc, argv);
		g_DiabloThreadRunning = false;
	});
}

void PushDevilutionXInput(uint32_t type, uint32_t code, uint32_t state, int32_t x, int32_t y)
{
	std::lock_guard<std::mutex> lock(g_DirectInputMutex);
	g_DirectInputQueue.push_back({ type, code, state, x, y });
}

bool CopyD1FrameBytes(uint8_t *dest, size_t maxBytes, uint32_t *outFrameId, int *outW, int *outH)
{
	std::lock_guard<std::mutex> lock(g_D1FrameMutex);
	if (g_D1InternalFrame.empty() || dest == nullptr)
		return false;

	size_t toCopy = std::min(maxBytes, g_D1InternalFrame.size());
	std::memcpy(dest, g_D1InternalFrame.data(), toCopy);

	if (outFrameId) *outFrameId = g_D1EngineData.frameId;
	if (outW) *outW = g_D1EngineData.width;
	if (outH) *outH = g_D1EngineData.height;

	return true;
}

void CopyD1DungeonGrid(int32_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				dest[idx] = static_cast<int32_t>(dPiece[x][y]);
			}
		}
	}
}

void CleanupGodotBridge()
{
	RequestDevilutionXQuit();
	if (g_ShmMapped != nullptr && g_ShmTotalSize > 0) {
		D1BridgeHeader *hdr = static_cast<D1BridgeHeader *>(g_ShmMapped);
		hdr->magic = 0xDEADBEEF;
		munmap(g_ShmMapped, g_ShmTotalSize);
		g_ShmMapped = nullptr;
	}
	if (g_ShmFd >= 0) {
		close(g_ShmFd);
		g_ShmFd = -1;
	}
	shm_unlink("/dev/shm/d1_godot_frame");
	g_ShmTotalSize = 0;
}

bool IsDevilutionXRunning()
{
	return g_DiabloThreadRunning.load();
}

bool IsGameRunningLive()
{
	return gbRunGame && (GetBridgeMenuMode() == D1MenuMode::None);
}

bool IsDevilutionXQuitRequested()
{
	return g_D1EngineQuitRequested.load();
}

void RequestDevilutionXQuit()
{
	if (!g_D1EngineQuitRequested.exchange(true)) {
		// Break DiabloMain's SDL event loop (mainmenu_loop) so the engine thread exits
		// promptly via the pushed SDL_QUIT.
		SDL_Event quitEv {};
		quitEv.type = SDL_QUIT;
		SDL_PushEvent(&quitEv);

		const bool onEngineThread =
			g_DiabloThread.joinable() && (g_DiabloThread.get_id() == std::this_thread::get_id());
		if (!onEngineThread && g_DiabloThread.joinable()) {
			// Invoked off-engine: from a SIGINT/SIGTERM handler or Godot's main thread.
			// Wait (bounded) for the engine thread to finish its wind-down after SDL_QUIT, then JOIN
			// it so it is fully stopped BEFORE Godot tears down the shared libSDL2/Vulkan resources.
			// Detaching (the previous approach) left the thread racing with Godot's shutdown ->
			// SIGSEGV at static destruction. If the thread does not finish within the timeout, fall
			// back to detach to avoid an infinite hang.
			bool finished = false;
			for (int i = 0; i < 100; ++i) { // up to ~5s
				if (!g_DiabloThreadRunning.load()) { finished = true; break; }
				std::this_thread::sleep_for(std::chrono::milliseconds(50));
			}
			if (finished && g_DiabloThread.joinable()) {
				g_DiabloThread.join();
			} else {
				g_DiabloThread.detach(); // fallback: avoid infinite hang if thread did not wind down
			}
		}
		g_DiabloThreadRunning = false;
	}
}

namespace {
std::mutex g_AudioEventMutex;
std::vector<D1AudioEvent> g_AudioEventQueue;
} // namespace

void PushDevilutionXAudioEvent(D1AudioEvent::Type type, const char *path, int32_t volume, int32_t pan, int32_t tileX, int32_t tileY, bool hasPos)
{
	std::lock_guard<std::mutex> lock(g_AudioEventMutex);
	D1AudioEvent ev;
	ev.type = type;
	ev.path[0] = '\0';
	if (path != nullptr) {
		std::strncpy(ev.path, path, sizeof(ev.path) - 1);
		ev.path[sizeof(ev.path) - 1] = '\0';
	}
	ev.volume = volume;
	ev.pan = pan;
	ev.tileX = tileX;
	ev.tileY = tileY;
	ev.hasPos = hasPos;
	g_AudioEventQueue.push_back(ev);
}

size_t PopDevilutionXAudioEvents(D1AudioEvent *outEvents, size_t maxEvents)
{
	std::lock_guard<std::mutex> lock(g_AudioEventMutex);
	if (outEvents == nullptr || maxEvents == 0 || g_AudioEventQueue.empty())
		return 0;
	size_t count = std::min(maxEvents, g_AudioEventQueue.size());
	for (size_t i = 0; i < count; ++i) {
		outEvents[i] = g_AudioEventQueue[i];
	}
	g_AudioEventQueue.erase(g_AudioEventQueue.begin(), g_AudioEventQueue.begin() + count);
	return count;
}

std::vector<uint8_t> LoadDevilutionXAsset(const char *path)
{
	if (path == nullptr || path[0] == '\0')
		return {};

	AssetRef ref = FindAsset(path);
	if (!ref.ok())
		return {};

	size_t sz = ref.size();
	if (sz == 0)
		return {};

	AssetHandle handle = OpenAsset(std::move(ref), /*threadsafe=*/true);
	if (!handle.ok())
		return {};

	std::vector<uint8_t> buffer(sz);
	if (!handle.read(buffer.data(), sz))
		return {};

	return buffer;
}

// Native Godot Diablo IV Inventory Bridge Synchronization
static std::mutex g_InventoryMutex;
static std::atomic<uint32_t> g_InventoryVersion { 1 };

uint32_t GetInventoryVersion()
{
	return g_InventoryVersion.load();
}

void UseBeltSlot(int slotIndex)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	if (pcurs > CURSOR_HAND && pcurs < CURSOR_FIRSTITEM) {
		NewCursor(CURSOR_HAND);
		CalcPlrInv(*MyPlayer, true);
		g_InventoryVersion.fetch_add(1);
		return;
	}
	if (slotIndex < 0 || slotIndex >= 8)
		return;
	Player &myPlayer = *MyPlayer;
	if (!myPlayer.SpdList[slotIndex].isEmpty() && myPlayer.SpdList[slotIndex]._itype != ItemType::Gold) {
		int prevCurs = pcurs;
		pcurs = CURSOR_HAND;
		UseInvItem(INVITEM_BELT_FIRST + slotIndex);
		if (pcurs == CURSOR_HAND) {
			pcurs = prevCurs;
		}
		CalcPlrInv(myPlayer, true);
		g_InventoryVersion.fetch_add(1);
	}
}

void ClickBeltSlot(int slotIndex)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	if (slotIndex < 0 || slotIndex >= 8)
		return;
	Player &player = *MyPlayer;
	if (player._pmode > PM_WALK_SIDEWAYS)
		return;

	if (player.HoldItem.isEmpty()) {
		// Pick up item from belt onto cursor
		Item &beltItem = player.SpdList[slotIndex];
		if (!beltItem.isEmpty()) {
			player.HoldItem = beltItem;
			player.RemoveSpdBarItem(slotIndex);
			PlaySFX(IS_IGRAB);
			NewCursor(player.HoldItem);
			NetSendCmdChBeltItem(false, slotIndex);
		}
	} else {
		// Place held item into belt slot or swap
		if (CanBePlacedOnBelt(player.HoldItem)) {
			if (player.SpdList[slotIndex].isEmpty()) {
				player.SpdList[slotIndex] = player.HoldItem.pop();
			} else {
				std::swap(player.SpdList[slotIndex], player.HoldItem);
			}
			PlaySFX(ItemInvSnds[ItemCAnimTbl[player.SpdList[slotIndex]._iCurs]]);
			NewCursor(player.HoldItem);
			NetSendCmdChBeltItem(false, slotIndex);
		}
	}
	CalcPlrInv(player, true);
	g_InventoryVersion.fetch_add(1);
}

std::vector<uint8_t> GetSpellIconRgba(int spellId, int spellType)
{
	if (!gbRunGame || spellId <= 0 || spellId > static_cast<int>(SpellID::LAST))
		return {};

	// system_palette holds the active, gamma-corrected master palette loaded from town/dungeon data
	const auto &pal = sgbFadedIn.load() ? system_palette : orig_palette;
	bool paletteReady = false;
	for (int i = 16; i < 256; ++i) {
		if (pal[i].r > 40 || pal[i].g > 40 || pal[i].b > 40) {
			paletteReady = true;
			break;
		}
	}
	if (!paletteReady)
		return {};

	if (!HasLargeSpellIcons()) {
		LoadLargeSpellIcons();
		if (!HasLargeSpellIcons())
			return {};
	}

	OwnedSurface surface(56, 56);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	SpellType st = static_cast<SpellType>(spellType);
	if (st == SpellType::Invalid || static_cast<int>(st) < 0 || static_cast<int>(st) > 3) {
		st = SpellType::Spell;
	}
	SetSpellTrans(st);
	DrawLargeSpellIcon(surface, { 0, 55 }, static_cast<SpellID>(spellId));

	bool hasPixels = false;
	std::vector<uint8_t> rgba(56 * 56 * 4, 0);
	for (int y = 0; y < 56; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = rgba.data() + (y * 56 * 4);
		for (int x = 0; x < 56; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				if (c.r > 30 || c.g > 30 || c.b > 30) {
					hasPixels = true;
				}
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return rgba;
}

D1ItemIconRgba GetBeltItemIconRgba(int slotIndex)
{
	if (!gbRunGame || MyPlayer == nullptr || slotIndex < 0 || slotIndex >= 8)
		return {};

	if (MyPlayer->SpdList[slotIndex].isEmpty())
		return {};

	const Item &item = MyPlayer->SpdList[slotIndex];
	int cursId = item._iCurs + CURSOR_FIRSTITEM;
	const ClxSprite sprite = GetInvItemSprite(cursId);
	int w = sprite.width();
	int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 64 || h > 64)
		return {};

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	ClxDraw(surface, { 0, h - 1 }, sprite);

	const auto &pal = sgbFadedIn.load() ? system_palette : orig_palette;
	D1ItemIconRgba res;
	res.width = w;
	res.height = h;
	res.rgba.resize(w * h * 4, 0);

	bool hasPixels = false;
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = res.rgba.data() + (y * w * 4);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				hasPixels = true;
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return res;
}

std::vector<AvailableSpellItem> GetAvailableSpells()
{
	if (!gbRunGame || MyPlayer == nullptr)
		return {};

	std::vector<AvailableSpellItem> result;
	Player &myPlayer = *MyPlayer;

	for (auto i : enum_values<SpellType>()) {
		uint64_t mask = 0;
		switch (static_cast<SpellType>(i)) {
		case SpellType::Skill:
			mask = myPlayer._pAblSpells;
			break;
		case SpellType::Spell:
			mask = myPlayer._pMemSpells;
			break;
		case SpellType::Scroll:
			mask = myPlayer._pScrlSpells;
			break;
		case SpellType::Charges:
			mask = myPlayer._pISpells;
			break;
		default:
			continue;
		}

		int8_t j = static_cast<int8_t>(SpellID::Firebolt);
		for (uint64_t spl = 1; j < MAX_SPELLS; spl <<= 1, j++) {
			if ((mask & spl) == 0)
				continue;
			SpellID splId = static_cast<SpellID>(j);
			AvailableSpellItem item;
			item.id = static_cast<int>(splId);
			item.type = static_cast<int>(i);
			string_view name = pgettext("spell", GetSpellData(splId).sNameText);
			std::strncpy(item.name, name.data(), std::min(sizeof(item.name) - 1, name.size()));
			item.name[std::min(sizeof(item.name) - 1, name.size())] = '\0';
			if (static_cast<SpellType>(i) == SpellType::Spell) {
				item.manaCost = GetManaAmount(myPlayer, splId) >> 6;
			} else {
				item.manaCost = 0;
			}

			for (size_t t = 0; t < NumHotkeys; t++) {
				if (myPlayer._pSplHotKey[t] == splId && myPlayer._pSplTHotKey[t] == static_cast<SpellType>(i)) {
					std::snprintf(item.hotkey, sizeof(item.hotkey), "F%zu", t + 1);
					break;
				}
			}

			result.push_back(item);
		}
	}
	return result;
}

void SelectSpell(int spellId, int spellType)
{
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	MyPlayer->_pRSpell = static_cast<SpellID>(spellId);
	MyPlayer->_pRSplType = static_cast<SpellType>(spellType);
	spselflag = false;
	RedrawEverything();
}

void BindSpellHotkey(int spellId, int spellType, int slotIdx)
{
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	if (slotIdx < 0 || slotIdx >= static_cast<int>(NumHotkeys))
		return;

	Player &myPlayer = *MyPlayer;
	SpellID splId = static_cast<SpellID>(spellId);
	SpellType splType = static_cast<SpellType>(spellType);

	// If already bound to this slot, unbind it
	if (myPlayer._pSplHotKey[slotIdx] == splId && myPlayer._pSplTHotKey[slotIdx] == splType) {
		myPlayer._pSplHotKey[slotIdx] = SpellID::Invalid;
		myPlayer._pSplTHotKey[slotIdx] = SpellType::Invalid;
		return;
	}

	// Remove this spell from any other hotkey slot
	for (size_t i = 0; i < NumHotkeys; ++i) {
		if (myPlayer._pSplHotKey[i] == splId && myPlayer._pSplTHotKey[i] == splType) {
			myPlayer._pSplHotKey[i] = SpellID::Invalid;
			myPlayer._pSplTHotKey[i] = SpellType::Invalid;
		}
	}

	myPlayer._pSplHotKey[slotIdx] = splId;
	myPlayer._pSplTHotKey[slotIdx] = splType;
}

void QuickCastHotkey(int slotIdx)
{
	if (!gbRunGame || MyPlayer == nullptr)
		return;
	if (slotIdx < 0 || slotIdx >= static_cast<int>(NumHotkeys))
		return;

	Player &myPlayer = *MyPlayer;
	SpellID spell = myPlayer._pSplHotKey[slotIdx];
	SpellType spellType = myPlayer._pSplTHotKey[slotIdx];

	if (!IsValidSpell(spell) || spellType == SpellType::Invalid)
		return;

	// Verify player still has access to this spell / scroll / charges
	uint64_t spells = 0;
	switch (spellType) {
	case SpellType::Skill:
		spells = myPlayer._pAblSpells;
		break;
	case SpellType::Spell:
		spells = myPlayer._pMemSpells;
		break;
	case SpellType::Scroll:
		spells = myPlayer._pScrlSpells;
		break;
	case SpellType::Charges:
		spells = myPlayer._pISpells;
		break;
	default:
		return;
	}

	uint64_t spl = GetSpellBitmask(spell);
	if ((spells & spl) == 0)
		return;

	myPlayer._pRSpell = spell;
	myPlayer._pRSplType = spellType;
	CheckPlrSpell(false, spell, spellType);
	RedrawEverything();
}

static std::mutex g_VisualEventMutex;
static std::vector<D1VisualEvent> g_VisualEventQueue;

static bool IsTorchOrFireObject(int objType)
{
	switch (objType) {
	case OBJ_TORCHL:
	case OBJ_TORCHR:
	case OBJ_TORCHL2:
	case OBJ_TORCHR2:
	case OBJ_L1LIGHT:
	case OBJ_SKFIRE:
	case OBJ_CANDLE1:
	case OBJ_CANDLE2:
	case OBJ_CANDLEO:
	case OBJ_BOOKCANDLE:
	case OBJ_STORYCANDLE:
	case OBJ_L5CANDLE:
	case OBJ_BCROSS:
	case OBJ_TBCROSS:
	case OBJ_FLAMEHOLE:
		return true;
	default:
		return false;
	}
}

void PushVisualEvent(uint32_t type, Point tile, Displacement offset, Direction dir, float intensity)
{
	// Resurrected Effects ON/OFF (Options): when disabled no VFX are queued in any display mode.
	if (*sgOptions.Resurrected.resurrectedEffects == false)
		return;

	Point screenPos = TileToScreenCoords(tile, offset);
	int yOffset = 22;
	if (CurrentZoomMode == ZoomMode::Balanced_1_5x) yOffset = 33;
	else if (CurrentZoomMode == ZoomMode::Zoomed_2x) yOffset = 44;
	else if (CurrentZoomMode == ZoomMode::UltraClose_2_5x) yOffset = 55;
	else if (CurrentZoomMode == ZoomMode::MacroClose_3x) yOffset = 66;
	screenPos.y -= yOffset;

	float normX = (gnScreenWidth > 0) ? (static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth)) : 0.5f;
	float normY = (gnScreenHeight > 0) ? (static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight)) : 0.5f;

	Displacement dirDisp = Displacement(dir);
	float len = std::sqrt(static_cast<float>(dirDisp.deltaX * dirDisp.deltaX + dirDisp.deltaY * dirDisp.deltaY));
	float dx = 0.0f;
	float dy = -1.0f;
	if (len > 0.001f) {
		dx = static_cast<float>(dirDisp.deltaX) / len;
		dy = static_cast<float>(dirDisp.deltaY) / len;
	}

	D1VisualEvent ev;
	ev.type = type;
	ev.normX = normX;
	ev.normY = normY;
	ev.tileX = tile.x;
	ev.tileY = tile.y;
	ev.dirX = dx;
	ev.dirY = dy;
	ev.intensity = intensity;

	std::lock_guard<std::mutex> lock(g_VisualEventMutex);
	if (g_VisualEventQueue.size() < 64) {
		g_VisualEventQueue.push_back(ev);
	}
}

std::vector<D1VisualEvent> DrainVisualEvents()
{
	std::vector<D1VisualEvent> result;
	std::lock_guard<std::mutex> lock(g_VisualEventMutex);
	result.swap(g_VisualEventQueue);
	return result;
}

std::vector<D1EngineLight> GetActiveEngineLights()
{
	std::vector<D1EngineLight> lights;
	if (MyPlayer == nullptr || gnScreenWidth <= 0 || gnScreenHeight <= 0)
		return lights;

	// 1. Hero Torch (Type 0)
	{
		D1EngineLight heroLight;
		heroLight.normX = g_D1EngineData.playerNormX;
		heroLight.normY = g_D1EngineData.playerNormY;
		heroLight.radius = static_cast<float>(MyPlayer->_pLightRad);
		heroLight.type = 0; // Hero Torch
		heroLight.tileX = MyPlayer->position.tile.x;
		heroLight.tileY = MyPlayer->position.tile.y;
		lights.push_back(heroLight);
	}

	// 2. Static Dungeon Torches, Braziers & Candles (Type 1)
	for (int i = 0; i < ActiveObjectCount; ++i) {
		const Object &obj = Objects[ActiveObjects[i]];
		if (!IsTorchOrFireObject(obj._otype))
			continue;

		Point screenPos = TileToScreenCoords(obj.position);
		int yOffset = 22;
		if (obj._otype == OBJ_TORCHL || obj._otype == OBJ_TORCHR || obj._otype == OBJ_TORCHL2 || obj._otype == OBJ_TORCHR2) {
			yOffset = 28;
		} else if (obj._otype == OBJ_SKFIRE || obj._otype == OBJ_L1LIGHT) {
			yOffset = 24;
		}

		if (CurrentZoomMode == ZoomMode::Balanced_1_5x) yOffset = (yOffset * 3) / 2;
		else if (CurrentZoomMode == ZoomMode::Zoomed_2x) yOffset *= 2;
		else if (CurrentZoomMode == ZoomMode::UltraClose_2_5x) yOffset = (yOffset * 5) / 2;
		else if (CurrentZoomMode == ZoomMode::MacroClose_3x) yOffset *= 3;
		screenPos.y -= yOffset;

		float normX = static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth);
		float normY = static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight);

		if (normX < -0.2f || normX > 1.2f || normY < -0.2f || normY > 1.2f)
			continue;

		float rad = 8.0f;
		if (obj._otype == OBJ_L1LIGHT || obj._otype == OBJ_SKFIRE) rad = 7.0f;
		else if (obj._otype == OBJ_CANDLE1 || obj._otype == OBJ_CANDLE2 || obj._otype == OBJ_CANDLEO || obj._otype == OBJ_BOOKCANDLE || obj._otype == OBJ_STORYCANDLE || obj._otype == OBJ_L5CANDLE) rad = 4.0f;

		D1EngineLight el;
		el.normX = normX;
		el.normY = normY;
		el.radius = rad;
		el.tileX = obj.position.x;
		el.tileY = obj.position.y;
		el.type = 1;
		lights.push_back(el);

		if (lights.size() >= 16)
			break;
	}

	// 3. Dynamic Engine Lights (Missiles, Spells, Special Lights) (Type 2)
	for (int i = 0; i < ActiveLightCount; ++i) {
		int lid = ActiveLights[i];
		if (lid < 0 || lid >= MAXLIGHTS) continue;
		const Light &light = Lights[lid];
		if (light.isInvalid) continue;

		// Skip hero torch
		if (lid == MyPlayer->lightId) continue;
		if (light.position.tile == MyPlayer->position.tile) continue;

		Point screenPos = TileToScreenCoords(light.position.tile, light.position.offset);
		float normX = static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth);
		float normY = static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight);

		if (normX < -0.25f || normX > 1.25f || normY < -0.25f || normY > 1.25f)
			continue;

		D1EngineLight el;
		el.normX = normX;
		el.normY = normY;
		el.radius = static_cast<float>(light.radius);
		el.tileX = light.position.tile.x;
		el.tileY = light.position.tile.y;
		el.type = 2; // Missile/Spell
		lights.push_back(el);

		if (lights.size() >= 24)
			break;
	}

	return lights;
}

std::vector<D1WallOccluder> GetActiveWallOccluders()
{
	std::vector<D1WallOccluder> occluders;
	if (MyPlayer == nullptr || gnScreenWidth <= 0 || gnScreenHeight <= 0)
		return occluders;

	auto lights = GetActiveEngineLights();
	bool visited[112][112] = { false };

	for (const auto &light : lights) {
		int startX = std::max(0, light.tileX - 6);
		int endX = std::min(111, light.tileX + 6);
		int startY = std::max(0, light.tileY - 6);
		int endY = std::min(111, light.tileY + 6);

		for (int y = startY; y <= endY; ++y) {
			for (int x = startX; x <= endX; ++x) {
				if (visited[x][y]) continue;
				visited[x][y] = true;

				if (TileHasAny(dPiece[x][y], TileProperties::BlockLight)) {
					Point screenPos = TileToScreenCoords(Point{ x, y });
					int yOffset = 16;
					if (CurrentZoomMode == ZoomMode::Balanced_1_5x) yOffset = 24;
					else if (CurrentZoomMode == ZoomMode::Zoomed_2x) yOffset = 32;
					else if (CurrentZoomMode == ZoomMode::UltraClose_2_5x) yOffset = 40;
					else if (CurrentZoomMode == ZoomMode::MacroClose_3x) yOffset = 48;
					screenPos.y -= yOffset;

					float normX = static_cast<float>(screenPos.x) / static_cast<float>(gnScreenWidth);
					float normY = static_cast<float>(screenPos.y) / static_cast<float>(gnScreenHeight);
					if (normX >= -0.1f && normX <= 1.1f && normY >= -0.1f && normY <= 1.1f) {
						occluders.push_back(D1WallOccluder{ normX, normY });
						if (occluders.size() >= 64)
							return occluders;
					}
				}
			}
		}
	}
	return occluders;
}

D1CharacterInfo GetCharacterInfo()
{
	D1CharacterInfo info;
	if (MyPlayer == nullptr)
		return info;

	Player &p = *MyPlayer;
	std::strncpy(info.name, p._pName, sizeof(info.name) - 1);
	info.playerClass = static_cast<int>(p._pClass);
	info.level = p._pLevel;
	info.exp = p._pExperience;
	info.nextExp = p._pNextExper;
	info.gold = p._pGold;

	info.strBase = p._pBaseStr;
	info.strNow = p._pStrength;
	info.strMax = p.GetMaximumAttributeValue(CharacterAttribute::Strength);

	info.magBase = p._pBaseMag;
	info.magNow = p._pMagic;
	info.magMax = p.GetMaximumAttributeValue(CharacterAttribute::Magic);

	info.dexBase = p._pBaseDex;
	info.dexNow = p._pDexterity;
	info.dexMax = p.GetMaximumAttributeValue(CharacterAttribute::Dexterity);

	info.vitBase = p._pBaseVit;
	info.vitNow = p._pVitality;
	info.vitMax = p.GetMaximumAttributeValue(CharacterAttribute::Vitality);

	info.statPts = p._pStatPts;

	info.hp = p._pHitPoints >> 6;
	info.maxHp = p._pMaxHP >> 6;
	info.mana = p._pMana >> 6;
	info.maxMana = p._pMaxMana >> 6;

	info.armor = p.GetArmor() + p._pLevel * 2;
	info.toHit = (p.InvBody[INVLOC_HAND_LEFT]._itype == ItemType::Bow) ? p.GetRangedToHit() : p.GetMeleeToHit();

	int damageMod = p._pIBonusDamMod;
	if (p.InvBody[INVLOC_HAND_LEFT]._itype == ItemType::Bow && p._pClass != HeroClass::Rogue) {
		damageMod += p._pDamageMod / 2;
	} else {
		damageMod += p._pDamageMod;
	}
	info.dmgMin = p._pIMinDam + p._pIBonusDam * p._pIMinDam / 100 + damageMod;
	info.dmgMax = p._pIMaxDam + p._pIBonusDam * p._pIMaxDam / 100 + damageMod;

	info.resMagic = p._pMagResist;
	info.resFire = p._pFireResist;
	info.resLightning = p._pLghtResist;

	return info;
}

void AddAttributePoint(int attrIdx)
{
	if (MyPlayer == nullptr || MyPlayer->_pStatPts <= 0)
		return;

	CharacterAttribute attr = static_cast<CharacterAttribute>(attrIdx);
	if (MyPlayer->GetBaseAttributeValue(attr) >= MyPlayer->GetMaximumAttributeValue(attr))
		return;

	switch (attr) {
	case CharacterAttribute::Strength:
		NetSendCmdParam1(true, CMD_ADDSTR, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	case CharacterAttribute::Magic:
		NetSendCmdParam1(true, CMD_ADDMAG, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	case CharacterAttribute::Dexterity:
		NetSendCmdParam1(true, CMD_ADDDEX, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	case CharacterAttribute::Vitality:
		NetSendCmdParam1(true, CMD_ADDVIT, 1);
		MyPlayer->_pStatPts -= 1;
		break;
	}
}

bool IsCharacterSheetOpen()
{
	return chrflag;
}

void ToggleCharacterSheet()
{
	PlaySFX(IS_TITLEMOV);
	chrflag = !chrflag;
	if (chrflag && QuestLogIsOpen)
		QuestLogIsOpen = false;
}

bool IsQuestLogOpen()
{
	return QuestLogIsOpen;
}

void ToggleQuestLog()
{
	PlaySFX(IS_TITLEMOV);
	QuestLogIsOpen = !QuestLogIsOpen;
	if (QuestLogIsOpen) {
		if (chrflag) chrflag = false;
		StartQuestlog();
	}
}

bool IsInventoryOpen()
{
	return invflag;
}

void ToggleInventory()
{
	PlaySFX(IS_TITLEMOV);
	sbookflag = false;
	CloseGoldWithdraw();
	CloseStash();
	invflag = !invflag;
	if (DropGoldFlag) {
		CloseGoldDrop();
	}
}

void SetActiveUiPanel(int panel)
{
	if (!gbRunGame) return;
	// panel: 0 = Character, 1 = Inventory, 2 = SpellBook, 3 = QuestLog, -1 = Close all
	if (panel == -1) {
		CloseAllUiPanels();
		return;
	}
	PlaySFX(IS_TITLEMOV);
	if (panel != 0 && chrflag) chrflag = false;
	if (panel != 1 && invflag) {
		invflag = false;
		CloseGoldWithdraw();
		CloseStash();
		if (DropGoldFlag) CloseGoldDrop();
	}
	if (panel != 2 && sbookflag) sbookflag = false;
	if (panel != 3 && QuestLogIsOpen) QuestLogIsOpen = false;

	if (panel == 0 && !chrflag) chrflag = true;
	if (panel == 1 && !invflag) {
		invflag = true;
		CloseGoldWithdraw();
		CloseStash();
		if (DropGoldFlag) CloseGoldDrop();
	}
	if (panel == 2 && !sbookflag) sbookflag = true;
	if (panel == 3 && !QuestLogIsOpen) StartQuestlog();
}

void CloseAllUiPanels()
{
	if (!gbRunGame) return;
	bool had_open = chrflag || invflag || sbookflag || QuestLogIsOpen;
	if (chrflag) chrflag = false;
	if (invflag) {
		invflag = false;
		CloseGoldWithdraw();
		CloseStash();
		if (DropGoldFlag) CloseGoldDrop();
	}
	if (sbookflag) sbookflag = false;
	if (QuestLogIsOpen) QuestLogIsOpen = false;
	if (had_open) PlaySFX(IS_TITLEMOV);
}

int GetActiveUiPanel()
{
	if (!IsBridgeSafeToRead()) return -1;
	if (invflag) return 1;
	if (chrflag) return 0;
	if (sbookflag) return 2;
	if (QuestLogIsOpen) return 3;
	return -1;
}


std::vector<D1QuestEntry> GetQuestsInfo()
{
	std::vector<D1QuestEntry> list;
	// 1. Active quests with log flag
	for (const auto &quest : Quests) {
		if (quest._qactive == QUEST_ACTIVE && quest._qlog) {
			D1QuestEntry qe;
			qe.idx = quest._qidx;
			std::string_view sv = _(QuestsData[quest._qidx]._qlstr);
			size_t len = std::min(sv.size(), sizeof(qe.name) - 1);
			std::memcpy(qe.name, sv.data(), len);
			qe.name[len] = '\0';
			qe.isFinished = false;
			qe.level = quest._qlevel;
			list.push_back(qe);
		}
	}
	// 2. Finished quests
	for (const auto &quest : Quests) {
		if (quest._qactive == QUEST_DONE || quest._qactive == QUEST_HIVE_DONE) {
			D1QuestEntry qe;
			qe.idx = quest._qidx;
			std::string_view sv = _(QuestsData[quest._qidx]._qlstr);
			size_t len = std::min(sv.size(), sizeof(qe.name) - 1);
			std::memcpy(qe.name, sv.data(), len);
			qe.name[len] = '\0';
			qe.isFinished = true;
			qe.level = quest._qlevel;
			list.push_back(qe);
		}
	}
	return list;
}

static std::string g_ActiveQuestTitle = "";

void SetActiveQuestTitle(std::string_view title)
{
	g_ActiveQuestTitle = std::string(title);
}

void SelectQuest(int questIdx)
{
	if (questIdx >= 0 && questIdx < MAXQUESTS) {
		_speech_id msg = Quests[questIdx]._qmsg;
		if (msg == TEXT_NONE || msg < 0) {
			msg = QuestsData[questIdx]._qdmsg;
		}
		if (msg != TEXT_NONE && msg >= 0) {
			std::string_view sv = _(QuestsData[questIdx]._qlstr);
			g_ActiveQuestTitle = std::string(sv);
			InitQTextMsg(msg);
			PlaySFX(IS_TITLSLCT);
			QuestLogIsOpen = false;
		}
	}
}

static std::string SanitizeUtf8(std::string_view sv)
{
	std::string out;
	out.reserve(sv.size());
	for (size_t i = 0; i < sv.size(); ++i) {
		unsigned char c = static_cast<unsigned char>(sv[i]);
		if (c >= 32 && c <= 126) {
			out.push_back(c);
		} else if (c == '\n' || c == '\t' || c == '\r') {
			out.push_back(c);
		} else if (c >= 0xC0 && c <= 0xFD && i + 1 < sv.size()) {
			out.push_back(c);
			while (i + 1 < sv.size() && (static_cast<unsigned char>(sv[i + 1]) & 0xC0) == 0x80) {
				out.push_back(sv[++i]);
			}
		} else if (c == 0xA0) {
			out.push_back(' ');
		}
	}
	return out;
}

static std::string FormatItemStats(const Item &item)
{
	std::string res;
	auto addLine = [&](const std::string &line) {
		if (line.empty()) return;
		if (!res.empty()) res += "\n";
		res += line;
	};

	if (item._iClass == ICLASS_WEAPON) {
		if (item._iMinDam == item._iMaxDam) {
			if (item._iMaxDur == DUR_INDESTRUCTIBLE)
				addLine(fmt::format("Damage: {:d}  Indestructible", item._iMinDam));
			else
				addLine(fmt::format("Damage: {:d}  Dur: {:d}/{:d}", item._iMinDam, item._iDurability, item._iMaxDur));
		} else {
			if (item._iMaxDur == DUR_INDESTRUCTIBLE)
				addLine(fmt::format("Damage: {:d}-{:d}  Indestructible", item._iMinDam, item._iMaxDam));
			else
				addLine(fmt::format("Damage: {:d}-{:d}  Dur: {:d}/{:d}", item._iMinDam, item._iMaxDam, item._iDurability, item._iMaxDur));
		}
	}
	if (item._iClass == ICLASS_ARMOR) {
		if (item._iMaxDur == DUR_INDESTRUCTIBLE)
			addLine(fmt::format("Armor: {:d}  Indestructible", item._iAC));
		else
			addLine(fmt::format("Armor: {:d}  Dur: {:d}/{:d}", item._iAC, item._iDurability, item._iMaxDur));
	}
	if (item._iMiscId == IMISC_STAFF && item._iMaxCharges != 0) {
		addLine(fmt::format("Charges: {:d}/{:d}", item._iCharges, item._iMaxCharges));
	}
	if (item._iIdentified) {
		if (item._iPrePower != -1) {
			addLine(std::string(PrintItemPower(item._iPrePower, item).str()));
		}
		if (item._iSufPower != -1) {
			addLine(std::string(PrintItemPower(item._iSufPower, item).str()));
		}
		if (item._iMagical == ITEM_QUALITY_UNIQUE && item._iUid >= 0) {
			addLine("Unique Item");
			const UniqueItem &uitem = UniqueItems[item._iUid];
			for (const auto &power : uitem.powers) {
				if (power.type == IPL_INVALID) break;
				addLine(std::string(PrintItemPower(power.type, item).str()));
			}
		}
	} else {
		if (item._iMagical != ITEM_QUALITY_NORMAL) {
			addLine("Not Identified");
		}
	}

	if (item._iMinStr > 0) addLine(fmt::format("Required Strength: {:d}", item._iMinStr));
	if (item._iMinMag > 0) addLine(fmt::format("Required Magic: {:d}", item._iMinMag));
	if (item._iMinDex > 0) addLine(fmt::format("Required Dexterity: {:d}", item._iMinDex));

	return SanitizeUtf8(res);
}

static D1InvItemData ConvertItemToInvData(const Item &item, int slotId, int cellX, int cellY, int invListIndex)
{
	D1InvItemData data;
	data.slotId = slotId;
	data.type = static_cast<int>(item._itype);
	data.curs = item._iCurs;
	data.cursId = item._iCurs + CURSOR_FIRSTITEM;
	data.quality = static_cast<int>(item._iMagical);

	std::string cleanName = SanitizeUtf8(item.getName());
	size_t nameLen = std::min(cleanName.size(), sizeof(data.name) - 1);
	std::memcpy(data.name, cleanName.data(), nameLen);
	data.name[nameLen] = '\0';

	std::string statsStr = FormatItemStats(item);
	size_t statsLen = std::min(statsStr.size(), sizeof(data.stats) - 1);
	std::memcpy(data.stats, statsStr.data(), statsLen);
	data.stats[statsLen] = '\0';

	data.cellX = cellX;
	data.cellY = cellY;
	Size sz = GetInventorySize(item);
	data.cellW = sz.width;
	data.cellH = sz.height;

	if (MyPlayer != nullptr) {
		data.canUse = MyPlayer->CanUseItem(item);
	} else {
		data.canUse = true;
	}

	data.isIdentified = item._iIdentified;
	data.durability = item._iDurability;
	data.maxDurability = item._iMaxDur;
	data.value = item._ivalue;
	data.invListIndex = invListIndex;
	return data;
}

std::vector<D1InvItemData> GetPlayerEquipmentData()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return {};

	std::vector<D1InvItemData> result;
	Player &player = *MyPlayer;
	for (int s = 0; s < NUM_INVLOC; ++s) {
		const Item &item = player.InvBody[s];
		if (!item.isEmpty()) {
			result.push_back(ConvertItemToInvData(item, s, 0, 0, -1));
		}
	}
	return result;
}

std::vector<D1InvItemData> GetPlayerBackpackData()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return {};

	std::vector<D1InvItemData> result;
	Player &player = *MyPlayer;
	for (int j = 0; j < InventoryGridCells; ++j) {
		if (player.InvGrid[j] > 0) {
			int ii = player.InvGrid[j] - 1;
			if (ii >= 0 && ii < player._pNumInv) {
				const Item &item = player.InvList[ii];
				Size sz = GetInventorySize(item);
				int cellX = j % 10;
				int bottomRow = j / 10;
				int cellY = bottomRow - (sz.height - 1);
				result.push_back(ConvertItemToInvData(item, j, cellX, cellY, ii));
			}
		}
	}
	return result;
}

D1InvItemData GetPlayerHoldItemData()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr || MyPlayer->HoldItem.isEmpty())
		return {};

	return ConvertItemToInvData(MyPlayer->HoldItem, -1, 0, 0, -1);
}

int GetPlayerGold()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return 0;
	return MyPlayer->_pGold;
}

D1ItemIconRgba GetItemSpriteRgba(int cursId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (cursId <= 0 || !IsInvItemSpriteLoaded() || cursId > static_cast<int>(GetNumInvItems()))
		return {};

	const ClxSprite sprite = GetInvItemSprite(cursId);
	int w = sprite.width();
	int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 128 || h > 128)
		return {};

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	ClxDraw(surface, { 0, h - 1 }, sprite);

	const auto &pal = orig_palette;
	D1ItemIconRgba res;
	res.width = w;
	res.height = h;
	res.rgba.resize(w * h * 4, 0);

	bool hasPixels = false;
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = res.rgba.data() + (y * w * 4);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				hasPixels = true;
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return res;
}

static int GetDurIconIndex(const Item &item, inv_body_loc slot)
{
	if (slot == INVLOC_HEAD)
		return 3;
	if (slot == INVLOC_CHEST)
		return 2;
	switch (item._itype) {
	case ItemType::Sword:
		return 1;
	case ItemType::Axe:
		return 5;
	case ItemType::Bow:
		return 6;
	case ItemType::Mace:
		return 4;
	case ItemType::Staff:
		return 7;
	case ItemType::Shield:
	default:
		return 0;
	}
}

std::vector<D1DurabilityWarning> GetPlayerDurabilityWarnings()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return {};

	const int durabilityThresholdGold = 5;
	const int durabilityThresholdRed = 2;

	std::vector<D1DurabilityWarning> result;
	Player &myPlayer = *MyPlayer;

	// In Diablo 1, the slots checked are Head, Chest, Hand Left, Hand Right
	const inv_body_loc slotsToCheck[] = { INVLOC_HEAD, INVLOC_CHEST, INVLOC_HAND_LEFT, INVLOC_HAND_RIGHT };

	for (inv_body_loc slot : slotsToCheck) {
		const Item &item = myPlayer.InvBody[slot];
		if (item.isEmpty())
			continue;
		if (item._iMaxDur <= 0)
			continue;
		if (item._iDurability > durabilityThresholdGold)
			continue;

		D1DurabilityWarning w;
		w.slotId = static_cast<int>(slot);
		w.durability = item._iDurability;
		w.maxDurability = item._iMaxDur;
		w.iconIdx = GetDurIconIndex(item, slot);

		if (item._iDurability <= durabilityThresholdRed) {
			w.status = 2; // Critical / Red
			w.frameIdx = w.iconIdx;
		} else {
			w.status = 1; // Warning / Gold
			w.frameIdx = w.iconIdx + 8;
		}

		std::string cleanName = SanitizeUtf8(item.getName());
		size_t nameLen = std::min(cleanName.size(), sizeof(w.name) - 1);
		std::memcpy(w.name, cleanName.data(), nameLen);
		w.name[nameLen] = '\0';

		result.push_back(w);
	}

	return result;
}

D1ItemIconRgba GetDurabilityIconRgba(int frameIdx)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (frameIdx < 0 || frameIdx >= 16)
		return {};

	if (!pDurIcons) {
		if (!FindAsset("items\\duricons" DEVILUTIONX_CEL_EXT).ok())
			return {};
		pDurIcons = LoadCel("items\\duricons", 32);
		if (!pDurIcons)
			return {};
	}

	if (frameIdx >= static_cast<int>((*pDurIcons).numSprites()))
		return {};

	const ClxSprite sprite = (*pDurIcons)[frameIdx];
	int w = sprite.width();
	int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 128 || h > 128)
		return {};

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	ClxDraw(surface, { 0, h - 1 }, sprite);

	const auto &pal = sgbFadedIn.load() ? system_palette : orig_palette;
	D1ItemIconRgba res;
	res.width = w;
	res.height = h;
	res.rgba.resize(w * h * 4, 0);

	bool hasPixels = false;
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = res.rgba.data() + (y * w * 4);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				hasPixels = true;
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return res;
}

D1ItemIconRgba GetDurabilityCompositeIconRgba(int iconIdx, int durability)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (iconIdx < 0 || iconIdx >= 8)
		return {};

	if (!pDurIcons) {
		if (!FindAsset("items\\duricons" DEVILUTIONX_CEL_EXT).ok())
			return {};
		pDurIcons = LoadCel("items\\duricons", 32);
		if (!pDurIcons)
			return {};
	}

	if (iconIdx + 8 >= static_cast<int>((*pDurIcons).numSprites()))
		return {};

	const int durabilityThresholdGold = 5;
	const int durabilityThresholdRed = 2;

	const ClxSprite redSprite = (*pDurIcons)[iconIdx];
	const ClxSprite goldSprite = (*pDurIcons)[iconIdx + 8];

	int w = redSprite.width();
	int h = redSprite.height();
	if (w <= 0 || h <= 0 || w > 128 || h > 128)
		return {};

	int partition = 0;
	if (durability > durabilityThresholdRed) {
		int current = std::min(durability, durabilityThresholdGold) - durabilityThresholdRed;
		partition = (h * current) / (durabilityThresholdGold - durabilityThresholdRed);
	}

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	if (partition > 0) {
		const Surface stenciledBuffer = surface.subregionY(h - partition, partition);
		ClxDraw(stenciledBuffer, { 0, partition }, goldSprite);
	}
	if (partition != h) {
		const Surface stenciledBuffer = surface.subregionY(0, h - partition);
		ClxDraw(stenciledBuffer, { 0, h }, redSprite);
	}

	const auto &pal = sgbFadedIn.load() ? system_palette : orig_palette;

	D1ItemIconRgba res;
	res.width = w;
	res.height = h;
	res.rgba.resize(w * h * 4, 0);

	bool hasPixels = false;
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		uint8_t *dst = res.rgba.data() + (y * w * 4);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				hasPixels = true;
				dst[x * 4 + 0] = c.r;
				dst[x * 4 + 1] = c.g;
				dst[x * 4 + 2] = c.b;
				dst[x * 4 + 3] = 255;
			}
		}
	}
	if (!hasPixels)
		return {};

	return res;
}

void ClickInventorySlot(int slotType, int slotIdx, bool isShift, bool isCtrl)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return;

	Player &player = *MyPlayer;
	if (player._pmode > PM_WALK_SIDEWAYS)
		return;

	// Targeting cursors (CURSOR_IDENTIFY, CURSOR_REPAIR, CURSOR_RECHARGE, CURSOR_OIL)
	if (pcurs > CURSOR_HAND && pcurs < CURSOR_FIRSTITEM) {
		int targetCii = -1;
		Item *targetItem = nullptr;

		if (slotType == 0) {
			// Equipment slot (0..6)
			if (slotIdx >= 0 && slotIdx <= 6 && !player.InvBody[slotIdx].isEmpty()) {
				targetCii = slotIdx;
				targetItem = &player.InvBody[slotIdx];
			}
		} else if (slotType == 1) {
			// Backpack grid cell (0..39)
			if (slotIdx >= 0 && slotIdx < 40 && player.InvGrid[slotIdx] != 0) {
				int itemIndex = std::abs(player.InvGrid[slotIdx]) - 1;
				if (itemIndex >= 0 && itemIndex < player._pNumInv) {
					targetCii = INVITEM_INV_FIRST + itemIndex;
					targetItem = &player.InvList[itemIndex];
				}
			} else if (slotIdx >= 0 && slotIdx < player._pNumInv) {
				targetCii = INVITEM_INV_FIRST + slotIdx;
				targetItem = &player.InvList[slotIdx];
			}
		} else if (slotType == 2) {
			// Direct InvList index
			if (slotIdx >= 0 && slotIdx < player._pNumInv) {
				targetCii = INVITEM_INV_FIRST + slotIdx;
				targetItem = &player.InvList[slotIdx];
			}
		}

		if (targetCii != -1 && targetItem != nullptr) {
			if (pcurs == CURSOR_IDENTIFY) {
				CheckIdentify(player, targetCii);
				PlaySFX(ItemInvSnds[ItemCAnimTbl[targetItem->_iCurs]]);
				NewCursor(CURSOR_HAND);
			} else if (pcurs == CURSOR_REPAIR) {
				DoRepair(player, targetCii);
				NewCursor(CURSOR_HAND);
			} else if (pcurs == CURSOR_RECHARGE) {
				DoRecharge(player, targetCii);
				NewCursor(CURSOR_HAND);
			} else if (pcurs == CURSOR_OIL) {
				if (DoOil(player, targetCii))
					NewCursor(CURSOR_HAND);
			}
		} else {
			// Clicked on empty space while in targeting mode -> cancel targeting cursor
			NewCursor(CURSOR_HAND);
		}

		CalcPlrInv(player, true);
		g_InventoryVersion.fetch_add(1);
		return;
	}

	if (slotType == 0) {
		// Equipment slot (0..6: Head, RingL, RingR, Amulet, HandL, HandR, Chest)
		if (slotIdx < 0 || slotIdx > 6)
			return;

		Point clickPos { InvRect[slotIdx].Center().x + GetRightPanel().position.x, InvRect[slotIdx].Center().y + GetRightPanel().position.y };
		if (!player.HoldItem.isEmpty()) {
			DoCheckInvPaste(player, clickPos);
		} else {
			DoCheckInvCut(player, clickPos, isShift, isCtrl);
		}
	} else if (slotType == 1) {
		// Backpack slot (0..39)
		if (slotIdx < 0 || slotIdx >= 40)
			return;

		int cellX = slotIdx % 10;
		int cellY = slotIdx / 10;

		if (!player.HoldItem.isEmpty()) {
			Size itemSize = GetInventorySize(player.HoldItem);
			int clickCol = std::clamp(cellX + (itemSize.width - 1) / 2, 0, 9);
			int clickRow = std::clamp(cellY + (itemSize.height - 1) / 2, 0, 3);
			int targetSlot = SLOTXY_INV_FIRST + clickRow * 10 + clickCol;
			Point clickPos { InvRect[targetSlot].Center().x + GetRightPanel().position.x, InvRect[targetSlot].Center().y + GetRightPanel().position.y };
			DoCheckInvPaste(player, clickPos);
		} else {
			if (isCtrl && devilution::IsStashOpen && player.InvGrid[slotIdx] != 0) {
				int iv = std::abs(player.InvGrid[slotIdx]) - 1;
				if (iv >= 0 && iv < player._pNumInv) {
					if (devilution::AutoPlaceItemInStash(player, player.InvList[iv], true)) {
						player.RemoveInvItem(iv, true);
						CalcPlrInv(player, true);
						g_InventoryVersion.fetch_add(1);
						return;
					}
				}
			}
			int targetSlot = SLOTXY_INV_FIRST + slotIdx;
			Point clickPos { InvRect[targetSlot].Center().x + GetRightPanel().position.x, InvRect[targetSlot].Center().y + GetRightPanel().position.y };
			DoCheckInvCut(player, clickPos, isShift, isCtrl);
		}
	}
	CalcPlrInv(player, true);
	g_InventoryVersion.fetch_add(1);
}

void UseInventorySlot(int slotType, int slotIdx)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return;

	Player &player = *MyPlayer;
	if (player._pmode > PM_WALK_SIDEWAYS)
		return;

	// Right-click while targeting cancels targeting mode
	if (pcurs > CURSOR_HAND && pcurs < CURSOR_FIRSTITEM) {
		NewCursor(CURSOR_HAND);
		CalcPlrInv(player, true);
		g_InventoryVersion.fetch_add(1);
		return;
	}

	if (slotType == 0) {
		// Equipment slot unequip
		if (slotIdx < 0 || slotIdx > 6)
			return;
		if (!player.InvBody[slotIdx].isEmpty()) {
			if (AutoPlaceItemInInventory(player, player.InvBody[slotIdx], true)) {
				RemoveEquipment(player, static_cast<inv_body_loc>(slotIdx), false);
				PlaySFX(ItemInvSnds[ItemCAnimTbl[player.InvBody[slotIdx]._iCurs]]);
				CalcPlrInv(player, true);
			}
		}
	} else if (slotType == 1 || slotType == 2) {
		// Backpack item right-click:
		// slotType == 2: direct InvList index (0.._pNumInv-1)
		// slotType == 1: backpack grid cell (0..39)
		int itemIndex = -1;
		if (slotType == 2) {
			if (slotIdx >= 0 && slotIdx < player._pNumInv) {
				itemIndex = slotIdx;
			}
		} else {
			if (slotIdx >= 0 && slotIdx < 40 && player.InvGrid[slotIdx] != 0) {
				itemIndex = abs(player.InvGrid[slotIdx]) - 1;
			} else if (slotIdx >= 0 && slotIdx < player._pNumInv) {
				itemIndex = slotIdx;
			}
		}

		if (itemIndex >= 0 && itemIndex < player._pNumInv) {
			Item &item = player.InvList[itemIndex];
			if (item.isUsable()) {
				int prevCurs = pcurs;
				pcurs = CURSOR_HAND;
				UseInvItem(INVITEM_INV_FIRST + itemIndex);
				// If UseInvItem changed cursor to targeting mode (e.g. CURSOR_TELEPORT, CURSOR_IDENTIFY), preserve it!
				if (pcurs == CURSOR_HAND) {
					pcurs = prevCurs;
				}
				CalcPlrInv(player, true);
			} else if (player.CanUseItem(item)) {
				// Auto-equip weapon/armor/ring/amulet
				AutoEquip(player, item);
				PlaySFX(ItemInvSnds[ItemCAnimTbl[item._iCurs]]);
				CalcPlrInv(player, true);
			}
		}
	}
	g_InventoryVersion.fetch_add(1);
}

void CancelTargetingCursor()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame)
		return;
	if (pcurs > CURSOR_HAND && pcurs < CURSOR_FIRSTITEM) {
		NewCursor(CURSOR_HAND);
		if (MyPlayer != nullptr)
			CalcPlrInv(*MyPlayer, true);
		g_InventoryVersion.fetch_add(1);
	}
}

int GetCurrentCursorId()
{
	if (!IsBridgeSafeToRead())
		return CURSOR_HAND;
	return pcurs;
}

D1PotionSummary GetPotionSummary()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1PotionSummary sum;
	if (!IsBridgeSafeToRead() || MyPlayer == nullptr)
		return sum;

	const Player &myPlayer = *MyPlayer;

	auto examineItem = [&](const Item &item) {
		if (item.isEmpty()) return;

		// Health
		if (item._iMiscId == IMISC_FULLHEAL) {
			sum.hpCount++;
			if (sum.hpBestType == 0 || sum.hpBestType > 1) sum.hpBestType = 1;
		} else if (item._iMiscId == IMISC_HEAL) {
			sum.hpCount++;
			if (sum.hpBestType == 0 || sum.hpBestType > 2) sum.hpBestType = 2;
		} else if (item.isScrollOf(SpellID::Healing)) {
			sum.hpCount++;
			if (sum.hpBestType == 0) sum.hpBestType = 3;
		}

		// Mana
		if (item._iMiscId == IMISC_FULLMANA) {
			sum.manaCount++;
			if (sum.manaBestType == 0 || sum.manaBestType > 1) sum.manaBestType = 1;
		} else if (item._iMiscId == IMISC_MANA) {
			sum.manaCount++;
			if (sum.manaBestType == 0) sum.manaBestType = 2;
		}

		// Rejuv
		if (item._iMiscId == IMISC_FULLREJUV) {
			sum.rejuvCount++;
			if (sum.rejuvBestType == 0 || sum.rejuvBestType > 1) sum.rejuvBestType = 1;
		} else if (item._iMiscId == IMISC_REJUV) {
			sum.rejuvCount++;
			if (sum.rejuvBestType == 0) sum.rejuvBestType = 2;
		}
	};

	// 1. Belt items
	for (int i = 0; i < 8; ++i) {
		examineItem(myPlayer.SpdList[i]);
	}
	// 2. Backpack items
	for (int i = 0; i < myPlayer._pNumInv; ++i) {
		examineItem(myPlayer.InvList[i]);
	}

	return sum;
}

void UseSmartPotion(int category)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return;

	Player &myPlayer = *MyPlayer;

	auto matchesTarget = [&](const Item &item, int priority) -> bool {
		if (item.isEmpty()) return false;
		if (category == 0) { // HP
			if (priority == 1) return item._iMiscId == IMISC_FULLHEAL;
			if (priority == 2) return item._iMiscId == IMISC_HEAL;
			if (priority == 3) return item.isScrollOf(SpellID::Healing);
		} else if (category == 1) { // Mana
			if (priority == 1) return item._iMiscId == IMISC_FULLMANA;
			if (priority == 2) return item._iMiscId == IMISC_MANA;
		} else if (category == 2) { // Rejuv
			if (priority == 1) return item._iMiscId == IMISC_FULLREJUV;
			if (priority == 2) return item._iMiscId == IMISC_REJUV;
		}
		return false;
	};

	int maxPrio = (category == 0) ? 3 : 2;
	for (int prio = 1; prio <= maxPrio; ++prio) {
		// Belt first
		for (int i = 0; i < 8; ++i) {
			if (matchesTarget(myPlayer.SpdList[i], prio)) {
				UseInvItem(INVITEM_BELT_FIRST + i);
				g_InventoryVersion.fetch_add(1);
				return;
			}
		}
		// Backpack next
		for (int i = 0; i < myPlayer._pNumInv; ++i) {
			if (matchesTarget(myPlayer.InvList[i], prio)) {
				int prevCurs = pcurs;
				pcurs = CURSOR_HAND;
				UseInvItem(INVITEM_INV_FIRST + i);
				pcurs = prevCurs;
				g_InventoryVersion.fetch_add(1);
				return;
			}
		}
	}
}

D1TownPortalSummary GetTownPortalSummary()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1TownPortalSummary s;
	if (!gbRunGame || MyPlayer == nullptr)
		return s;

	const Player &myPlayer = *MyPlayer;
	uint64_t tpMask = GetSpellBitmask(SpellID::TownPortal);

	// 1. Check learned spell
	if ((myPlayer._pMemSpells & tpMask) != 0) {
		s.hasSpell = true;
		s.spellManaCost = GetManaAmount(myPlayer, SpellID::TownPortal) >> 6;
		int curMana = myPlayer._pMana >> 6;
		s.canCastSpell = (curMana >= s.spellManaCost);
	}

	// 2. Count scrolls in belt and backpack
	for (int i = 0; i < 8; ++i) {
		const auto &item = myPlayer.SpdList[i];
		if (!item.isEmpty() && item.isScrollOf(SpellID::TownPortal)) {
			s.scrollCount++;
		}
	}
	for (int i = 0; i < myPlayer._pNumInv; ++i) {
		const auto &item = myPlayer.InvList[i];
		if (!item.isEmpty() && item.isScrollOf(SpellID::TownPortal)) {
			s.scrollCount++;
		}
	}

	// 3. Count staff/charges
	if ((myPlayer._pISpells & tpMask) != 0) {
		for (const auto &item : myPlayer.InvBody) {
			if (!item.isEmpty() && item._iSpell == SpellID::TownPortal && item._iCharges > 0) {
				s.chargeCount += item._iCharges;
			}
		}
	}

	// Determine best mode
	if (s.hasSpell && s.canCastSpell) {
		s.bestMode = 1;
	} else if (s.scrollCount > 0) {
		s.bestMode = 2;
	} else if (s.chargeCount > 0) {
		s.bestMode = 3;
	} else if (s.hasSpell) {
		s.bestMode = 1;
	} else {
		s.bestMode = 0;
	}

	return s;
}

void UseSmartTownPortal()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr)
		return;

	Player &myPlayer = *MyPlayer;
	uint64_t tpMask = GetSpellBitmask(SpellID::TownPortal);

	// Case 1: Player knows spell and has enough mana
	if ((myPlayer._pMemSpells & tpMask) != 0) {
		int manaCost = GetManaAmount(myPlayer, SpellID::TownPortal) >> 6;
		int curMana = myPlayer._pMana >> 6;
		if (curMana >= manaCost) {
			myPlayer._pRSpell = SpellID::TownPortal;
			myPlayer._pRSplType = SpellType::Spell;
			CheckPlrSpell(false, SpellID::TownPortal, SpellType::Spell);
			RedrawEverything();
			return;
		}
	}

	// Case 2: Use scroll (from belt or inventory)
	for (int i = 0; i < 8; ++i) {
		if (!myPlayer.SpdList[i].isEmpty() && myPlayer.SpdList[i].isScrollOf(SpellID::TownPortal)) {
			UseInvItem(INVITEM_BELT_FIRST + i);
			g_InventoryVersion.fetch_add(1);
			return;
		}
	}
	for (int i = 0; i < myPlayer._pNumInv; ++i) {
		if (!myPlayer.InvList[i].isEmpty() && myPlayer.InvList[i].isScrollOf(SpellID::TownPortal)) {
			int prevCurs = pcurs;
			pcurs = CURSOR_HAND;
			UseInvItem(INVITEM_INV_FIRST + i);
			pcurs = prevCurs;
			g_InventoryVersion.fetch_add(1);
			return;
		}
	}

	// Case 3: Use charges if available
	if ((myPlayer._pISpells & tpMask) != 0) {
		myPlayer._pRSpell = SpellID::TownPortal;
		myPlayer._pRSplType = SpellType::Charges;
		CheckPlrSpell(false, SpellID::TownPortal, SpellType::Charges);
		RedrawEverything();
		return;
	}

	// Case 4: Fallback to spell if learned (to trigger "Not enough mana" sound)
	if ((myPlayer._pMemSpells & tpMask) != 0) {
		myPlayer._pRSpell = SpellID::TownPortal;
		myPlayer._pRSplType = SpellType::Spell;
		CheckPlrSpell(false, SpellID::TownPortal, SpellType::Spell);
		RedrawEverything();
		return;
	}
}

D1TargetMonsterSummary GetTargetMonsterSummary(int targetId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1TargetMonsterSummary s;
	if (!gbRunGame || leveltype == DTYPE_TOWN) {
		return s;
	}

	int mIdx = targetId;
	if (mIdx < 0) {
		mIdx = pcursmonst;
	}

	if (mIdx < 0 || mIdx >= static_cast<int>(MaxMonsters)) {
		return s;
	}

	const Monster &m = Monsters[mIdx];
	if (m.isInvalid || m.isPlayerMinion()) {
		return s;
	}

	s.hasTarget = true;
	s.isHovered = (pcursmonst == mIdx);
	s.monsterId = mIdx;

	string_view nView = m.name();
	size_t nLen = std::min(nView.size(), sizeof(s.name) - 1);
	std::memcpy(s.name, nView.data(), nLen);
	s.name[nLen] = '\0';

	s.hp = std::max(0, m.hitPoints >> 6);
	s.maxHp = std::max(1, m.maxHitPoints >> 6);
	s.mode = static_cast<int>(m.mode);
	s.isUnique = m.isUnique();
	s.isChampion = (m.leader != Monster::NoLeader);
	s.monsterClass = static_cast<int>(m.data().monsterClass);

	const char *classStr = "";
	switch (m.data().monsterClass) {
	case MonsterClass::Undead:
		classStr = "Undead";
		break;
	case MonsterClass::Demon:
		classStr = "Demon";
		break;
	case MonsterClass::Animal:
		classStr = "Animal";
		break;
	default:
		break;
	}
	std::strncpy(s.classText, classStr, sizeof(s.classText) - 1);

	int mt = m.type().type;
	s.killCount = (mt >= 0 && mt < NUM_MTYPES) ? MonsterKillCounts[mt] : 0;

	// Resistances and Immunities
	if (m.isUnique() || s.killCount >= 15) {
		std::string resists;
		if ((m.resistance & RESIST_MAGIC) != 0) resists += "Magic, ";
		if ((m.resistance & RESIST_FIRE) != 0) resists += "Fire, ";
		if ((m.resistance & RESIST_LIGHTNING) != 0) resists += "Lightning, ";
		if (!resists.empty()) {
			resists.resize(resists.size() - 2);
			std::strncpy(s.resistText, resists.c_str(), sizeof(s.resistText) - 1);
		}

		std::string immunes;
		if ((m.resistance & IMMUNE_MAGIC) != 0) immunes += "Magic, ";
		if ((m.resistance & IMMUNE_FIRE) != 0) immunes += "Fire, ";
		if ((m.resistance & IMMUNE_LIGHTNING) != 0) immunes += "Lightning, ";
		if (!immunes.empty()) {
			immunes.resize(immunes.size() - 2);
			std::strncpy(s.immuneText, immunes.c_str(), sizeof(s.immuneText) - 1);
		}
	}

	return s;
}

D1PlayerEntityData GetPlayerEntityData()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1PlayerEntityData data;
	if (!IsBridgeSafeToRead())
		return data;

	const Player &player = *MyPlayer;
	data.tileX = player.position.tile.x;
	data.tileY = player.position.tile.y;
	data.dir = static_cast<int>(player._pdir);
	data.mode = static_cast<int>(player._pmode);
	data.isWalking = player.isWalking();
	data.animFrame = player.AnimInfo.getFrameToUseForRendering();

	if (player.isWalking()) {
		Point origin = player.position.tile;
		Point target = player.position.future;
		if (player._pmode == PM_WALK_SOUTHWARDS) {
			origin = player.position.temp;
			target = player.position.tile;
		}
		float progress = static_cast<float>(player.AnimInfo.getAnimationProgress()) / static_cast<float>(AnimationInfo::baseValueFraction);
		progress = std::clamp(progress, 0.0f, 1.0f);
		data.posX = static_cast<float>(origin.x) + static_cast<float>(target.x - origin.x) * progress;
		data.posY = static_cast<float>(origin.y) + static_cast<float>(target.y - origin.y) * progress;
	} else {
		data.posX = static_cast<float>(player.position.tile.x);
		data.posY = static_cast<float>(player.position.tile.y);
	}
	return data;
}

std::vector<D1MonsterEntityData> GetActiveMonstersData()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<D1MonsterEntityData> result;
	if (!IsBridgeSafeToRead())
		return result;

	if (currlevel == 0) {
		// Town has Towners (Griswold, Pepin, Cain, Wirt, Ogden, Adria, Gillian, Farnham, Cows...)
		for (int i = 0; i < NUM_TOWNERS; ++i) {
			const auto &towner = Towners[i];
			if (!towner.ownedAnim.has_value() || !towner.anim.has_value() || static_cast<int>(towner._ttype) < 0 || towner._ttype >= NUM_TOWNER_TYPES || (towner.position.x == 0 && towner.position.y == 0))
				continue;

			D1MonsterEntityData med;
			med.id = i;
			med.type = 1000 + static_cast<int>(towner._ttype);
			med.dir = 0;
			med.mode = 0;
			med.hp = 100;
			med.maxHp = 100;
			med.isAlive = true;
			med.isWalking = false;
			med.animFrame = towner._tAnimFrame;

			string_view nameView = towner.name;
			size_t copyLen = std::min(nameView.size(), sizeof(med.name) - 1);
			std::memcpy(med.name, nameView.data(), copyLen);
			med.name[copyLen] = '\0';

			med.posX = static_cast<float>(towner.position.x);
			med.posY = static_cast<float>(towner.position.y);
			med.isVisible = true;

			result.push_back(med);
		}
		return result;
	}

	size_t count = std::min(ActiveMonsterCount, MaxMonsters);
	result.reserve(count);

	for (size_t i = 0; i < count; ++i) {
		int mIdx = ActiveMonsters[i];
		if (mIdx < 0 || mIdx >= static_cast<int>(MaxMonsters))
			continue;

		const Monster &m = Monsters[mIdx];
		if (!m.animInfo.sprites.has_value() || (m.hitPoints <= 0 && m.mode != MonsterMode::Death))
			continue;
		D1MonsterEntityData med;
		med.id = mIdx;
		med.type = static_cast<int>(m.type().type);
		med.dir = static_cast<int>(m.direction);
		med.mode = static_cast<int>(m.mode);
		med.hp = m.hitPoints >> 6;
		med.maxHp = m.maxHitPoints >> 6;
		med.isAlive = (m.hitPoints > 0 || m.mode == MonsterMode::Death);
		med.isWalking = m.isWalking();
		med.animFrame = m.animInfo.sprites ? m.animInfo.getFrameToUseForRendering() : 0;

		string_view nameView = m.name();
		size_t copyLen = std::min(nameView.size(), sizeof(med.name) - 1);
		std::memcpy(med.name, nameView.data(), copyLen);
		med.name[copyLen] = '\0';

		if (m.isWalking() && m.animInfo.numberOfFrames > 0) {
			Point origin = m.position.tile;
			Point target = m.position.future;
			if (m.mode == MonsterMode::MoveSouthwards) {
				origin = m.position.old;
				target = m.position.tile;
			}
			float progress = static_cast<float>(m.animInfo.currentFrame) / static_cast<float>(m.animInfo.numberOfFrames);
			progress = std::clamp(progress, 0.0f, 1.0f);
			med.posX = static_cast<float>(origin.x) + static_cast<float>(target.x - origin.x) * progress;
			med.posY = static_cast<float>(origin.y) + static_cast<float>(target.y - origin.y) * progress;
		} else {
			med.posX = static_cast<float>(m.position.tile.x);
			med.posY = static_cast<float>(m.position.tile.y);
		}

		Point mTile = m.position.tile;
		bool isLit = IsTileLit(mTile);
		bool isVis = IsTileVisible(mTile);
		if (m.isWalking()) {
			isLit = isLit || IsTileLit(m.position.future);
			isVis = isVis || IsTileVisible(m.position.future);
		}
		bool hasInfra = (MyPlayer != nullptr && MyPlayer->_pInfraFlag);
		med.isVisible = (isVis && isLit) || (hasInfra && isLit);

		result.push_back(med);
	}
	return result;
}

std::vector<uint8_t> GetDungeonSolidityGrid()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<uint8_t> grid(MAXDUNX * MAXDUNY, 0);
	if (!IsBridgeSafeToRead())
		return grid;

	for (int y = 0; y < MAXDUNY; ++y) {
		for (int x = 0; x < MAXDUNX; ++x) {
			uint16_t piece = dPiece[x][y];
			if (piece >= MAXTILES) {
				grid[y * MAXDUNX + x] = 0;
				continue;
			}

			// In town and dungeons, piece 0 can be a valid piece if it has microtiles!
			if (piece == 0 && currlevel != 0 && !LevelCelBlock(DPieceMicros[0].mt[0]).hasValue()) {
				grid[y * MAXDUNX + x] = 0; // Truly empty void
				continue;
			}

			// In dungeons, tiles outside the generated bounds are TRULY EMPTY VOID
			if (currlevel != 0) {
				if (x < 16 || x >= 96 || y < 16 || y >= 96) {
					grid[y * MAXDUNX + x] = 0;
					continue;
				}
			}

			if (TileHasAny(piece, TileProperties::Solid)) {
				grid[y * MAXDUNX + x] = 2; // Solid Wall / Pillar
			} else if (dSpecial[x][y] != 0) {
				grid[y * MAXDUNX + x] = 3; // Doorway / Archway
			} else {
				grid[y * MAXDUNX + x] = 1; // Walkable Floor
			}
		}
	}
	return grid;
}

static void RasterizeClxSpriteRgba(const ClxSprite &sprite, int &outW, int &outH, std::vector<uint8_t> &outRgba, const uint8_t *trn = nullptr)
{
	int w = sprite.width();
	int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 1024 || h > 1024) {
		outW = 0;
		outH = 0;
		outRgba.clear();
		return;
	}

	outW = w;
	outH = h;
	outRgba.assign(w * h * 4, 0);

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	if (trn != nullptr) {
		ClxDrawTRN(surface, { 0, h - 1 }, sprite, trn);
	} else {
		ClxDraw(surface, { 0, h - 1 }, sprite);
	}

	// Ensure we use a valid non-black palette (system_palette if faded in and non-black, else orig_palette)
	bool sys_has_color = (system_palette[1].r != 0 || system_palette[1].g != 0 || system_palette[1].b != 0 ||
	                      system_palette[2].r != 0 || system_palette[2].g != 0 || system_palette[2].b != 0);
	const auto &pal = (sgbFadedIn.load() && sys_has_color) ? system_palette : orig_palette;

	uint8_t *dst = outRgba.data();
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = pal[idx];
				int px = (y * w + x) * 4;
				dst[px + 0] = c.r;
				dst[px + 1] = c.g;
				dst[px + 2] = c.b;
				dst[px + 3] = 255;
			}
		}
	}
}

D1SpriteFrameRgba GetPlayerSpriteRgba()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1SpriteFrameRgba result;
	if (!IsBridgeSafeToRead())
		return result;

	const Player &player = *MyPlayer;
	if (!player.AnimInfo.sprites)
		return result;

	const ClxSprite sprite = (player._pmode == PM_STAND && player.previewCelSprite) ? *player.previewCelSprite : player.AnimInfo.currentSprite();
	result.frame = player.AnimInfo.getFrameToUseForRendering();
	result.dir = static_cast<int>(player._pdir);
	RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba);
	return result;
}

D1SpriteFrameRgba GetMonsterSpriteRgba(int monsterId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1SpriteFrameRgba result;
	if (!IsBridgeSafeToRead() || g_D1LevelTransitioning.load() || monsterId < 0)
		return result;

	if (currlevel == 0) {
		if (monsterId >= NUM_TOWNERS)
			return result;
		const auto &towner = Towners[monsterId];
		if (!towner.ownedAnim.has_value() || !towner.anim.has_value() || static_cast<int>(towner._ttype) < 0 || towner._ttype >= NUM_TOWNER_TYPES || towner.anim->numSprites() == 0)
			return result;
		size_t frameIdx = static_cast<size_t>(towner._tAnimFrame);
		if (frameIdx >= towner.anim->numSprites())
			frameIdx = 0;
		const ClxSprite sprite = (*towner.anim)[frameIdx];
		result.frame = static_cast<int>(frameIdx);
		result.dir = 0;
		RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba);
		return result;
	}

	if (monsterId >= static_cast<int>(MaxMonsters))
		return result;

	const Monster &m = Monsters[monsterId];
	if (!m.animInfo.sprites.has_value() || m.animInfo.sprites->numSprites() == 0)
		return result;
	if (m.hitPoints <= 0 && m.mode != MonsterMode::Death)
		return result;

	size_t mFrame = static_cast<size_t>(m.animInfo.getFrameToUseForRendering());
	if (mFrame >= m.animInfo.sprites->numSprites())
		mFrame = 0;
	const ClxSprite sprite = (*m.animInfo.sprites)[mFrame];
	result.frame = static_cast<int>(mFrame);
	result.dir = static_cast<int>(m.direction);

	const uint8_t *trn = nullptr;
	if (m.isUnique())
		trn = m.uniqueMonsterTRN.get();

	RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba, trn);
	return result;
}

D1TilePieceRgba GetDungeonPieceRgba(int pieceId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1TilePieceRgba result;
	if (!IsBridgeSafeToRead() || pieceId < 0 || pieceId >= MAXTILES || pDungeonCels == nullptr)
		return result;

	const MICROS &micros = DPieceMicros[pieceId];
	int maxRow = -1;
	uint_fast8_t numMicros = std::min<uint_fast8_t>(MicroTileLen, 16);
	for (int i = 0; i < numMicros; i += 2) {
		if (LevelCelBlock(micros.mt[i]).hasValue() || (i + 1 < numMicros && LevelCelBlock(micros.mt[i + 1]).hasValue())) {
			maxRow = i / 2;
		}
	}
	if (maxRow < 0)
		return result;

	int numRows = maxRow + 1;
	int w = 64;
	int h = numRows * 32;

	result.width = w;
	result.height = h;
	result.numRows = numRows;

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());

	const uint8_t *tbl = LightTables[0].data();

	Point renderPos { 0, h - 1 };

	for (int r = 0; r < numRows; ++r) {
		int i = r * 2;
		LevelCelBlock leftBlock { micros.mt[i] };
		if (leftBlock.hasValue()) {
			RenderTile(surface, renderPos, leftBlock, MaskType::Solid, tbl);
		}
		if (i + 1 < numMicros) {
			LevelCelBlock rightBlock { micros.mt[i + 1] };
			if (rightBlock.hasValue()) {
				RenderTile(surface, renderPos + Displacement { 32, 0 }, rightBlock, MaskType::Solid, tbl);
			}
		}
		renderPos.y -= 32;
	}

	result.rgba.resize(w * h * 4, 0);
	uint8_t *dst = result.rgba.data();
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = (sgbFadedIn.load() ? system_palette : orig_palette)[idx];
				int px = (y * w + x) * 4;
				dst[px + 0] = c.r;
				dst[px + 1] = c.g;
				dst[px + 2] = c.b;
				dst[px + 3] = 255;
			}
		}
	}

	return result;
}

D1SpecialCelRgba GetSpecialCelRgba(int specialId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1SpecialCelRgba result;
	if (!IsBridgeSafeToRead() || !pSpecialCels.has_value() || specialId <= 0 || static_cast<size_t>(specialId) > pSpecialCels->numSprites())
		return result;

	const ClxSprite sprite = (*pSpecialCels)[specialId - 1];
	int w = sprite.width();
	int h = sprite.height();
	if (w <= 0 || h <= 0 || w > 512 || h > 512)
		return result;

	result.width = w;
	result.height = h;

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());
	RenderClxSprite(surface, sprite, { 0, 0 });

	result.rgba.resize(w * h * 4, 0);
	uint8_t *dst = result.rgba.data();
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = (sgbFadedIn.load() ? system_palette : orig_palette)[idx];
				int px = (y * w + x) * 4;
				dst[px + 0] = c.r;
				dst[px + 1] = c.g;
				dst[px + 2] = c.b;
				dst[px + 3] = 255;
			}
		}
	}
	return result;
}

void CopyD1SpecialGrid(int32_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	if (!IsBridgeSafeToRead()) {
		std::memset(dest, 0, count * sizeof(int32_t));
		return;
	}
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				dest[idx] = static_cast<int32_t>(dSpecial[x][y]);
			}
		}
	}
}

void CopyD1LightGrid(uint8_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	if (!IsBridgeSafeToRead()) {
		std::memset(dest, 15, count);
		return;
	}
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				dest[idx] = dLight[x][y];
			}
		}
	}
}

void CopyD1FlagsGrid(uint8_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	if (!IsBridgeSafeToRead()) {
		std::memset(dest, 0, count);
		return;
	}
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				dest[idx] = static_cast<uint8_t>(dFlags[x][y]);
			}
		}
	}
}

void CopyD1TransGrid(uint8_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	if (!IsBridgeSafeToRead()) {
		std::memset(dest, 0, count);
		return;
	}
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				dest[idx] = static_cast<uint8_t>(dTransVal[x][y]);
			}
		}
	}
}

void CopyD1TransparencyMask(uint8_t *dest, size_t maxTiles)
{
	if (dest == nullptr) return;
	size_t count = std::min<size_t>(maxTiles, 112 * 112);
	if (!IsBridgeSafeToRead()) {
		std::memset(dest, 0, count);
		return;
	}
	for (size_t y = 0; y < 112; ++y) {
		for (size_t x = 0; x < 112; ++x) {
			size_t idx = y * 112 + x;
			if (idx < count) {
				int piece = dPiece[x][y];
				dest[idx] = (piece > 0 && TileHasAny(piece, TileProperties::Transparent)) ? 1 : 0;
			}
		}
	}
}

std::vector<uint8_t> GetTransList()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<uint8_t> result(256, 0);
	if (!IsBridgeSafeToRead())
		return result;
	for (size_t i = 0; i < 256; ++i) {
		result[i] = TransList[i] ? 1 : 0;
	}
	return result;
}

std::vector<D1ObjectInfo> GetActiveObjectsList()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<D1ObjectInfo> list;
	if (!IsBridgeSafeToRead() || currlevel == 0) return list;

	int count = std::min(ActiveObjectCount, MAXOBJECTS);
	for (int i = 0; i < count; ++i) {
		int oi = ActiveObjects[i];
		if (oi < 0 || oi >= MAXOBJECTS) continue;
		const Object &obj = Objects[oi];

		D1ObjectInfo info;
		info.id = oi;
		info.type = obj._otype;
		info.tileX = obj.position.x;
		info.tileY = obj.position.y;
		info.animFrame = obj._oAnimFrame;
		info.animTotal = obj._oAnimLen;
		info.preFlag = obj._oPreFlag;
		info.solid = obj._oSolidFlag;
		info.selectable = (obj._oSelFlag != 0);
		info.width = 0;
		info.height = 0;
		if (obj._oAnimData.has_value() && obj._oAnimFrame > 0 &&
		    static_cast<size_t>(obj._oAnimFrame) <= (*obj._oAnimData).numSprites()) {
			const ClxSprite sprite = (*obj._oAnimData)[obj._oAnimFrame - 1];
			info.width = sprite.width();
			info.height = sprite.height();
		}
		list.push_back(info);
	}
	return list;
}

D1ObjectSpriteRgba GetObjectSpriteRgba(int objectId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1ObjectSpriteRgba result;
	if (!IsBridgeSafeToRead() || currlevel == 0 || objectId < 0 || objectId >= MAXOBJECTS) return result;
	const Object &obj = Objects[objectId];
	if (!obj._oAnimData.has_value() || obj._oAnimFrame <= 0 ||
	    static_cast<size_t>(obj._oAnimFrame) > (*obj._oAnimData).numSprites())
		return result;

	const ClxSprite sprite = (*obj._oAnimData)[obj._oAnimFrame - 1];
	RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba);
	return result;
}

std::vector<D1ItemInfo> GetActiveItemsList()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<D1ItemInfo> list;
	if (!IsBridgeSafeToRead()) return list;

	for (int y = 0; y < 112; ++y) {
		for (int x = 0; x < 112; ++x) {
			int8_t bItem = dItem[x][y];
			if (bItem <= 0) continue;
			int ii = bItem - 1;
			if (ii < 0 || ii >= MAXITEMS) continue;
			Item &item = Items[ii];
			if (item.isEmpty()) continue;

			if (!item.AnimInfo.sprites.has_value()) {
				GetItemFrm(item);
			}

			D1ItemInfo info;
			info.id = ii;
			info.tileX = x;
			info.tileY = y;
			info.cursId = item._iCurs;
			info.quality = static_cast<int>(item._iMagical);
			info.identified = item._iIdentified;
			if (item._itype == ItemType::Gold) {
				std::string goldStr = fmt::format(fmt::runtime(_("{:s} gold")), FormatInteger(item._ivalue));
				strncpy(info.name, goldStr.c_str(), sizeof(info.name) - 1);
			} else {
				std::string cleanName = SanitizeUtf8(item.getName());
				size_t copyLen = std::min(cleanName.size(), sizeof(info.name) - 1);
				std::memcpy(info.name, cleanName.data(), copyLen);
				info.name[copyLen] = '\0';
			}
			info.name[sizeof(info.name) - 1] = '\0';
			info.width = 0;
			info.height = 0;
			info.animFrame = item.AnimInfo.sprites.has_value() ? item.AnimInfo.currentFrame : 0;
			if (item.AnimInfo.sprites.has_value()) {
				const ClxSprite sprite = item.AnimInfo.currentSprite();
				info.width = sprite.width();
				info.height = sprite.height();
			}
			list.push_back(info);
		}
	}
	return list;
}

D1ItemSpriteRgba GetGroundItemSpriteRgba(int itemId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1ItemSpriteRgba result;
	if (!IsBridgeSafeToRead() || itemId < 0 || itemId >= MAXITEMS) return result;
	Item &item = Items[itemId];
	if (!item.AnimInfo.sprites.has_value()) {
		GetItemFrm(item);
	}
	if (!item.AnimInfo.sprites.has_value()) return result;

	const ClxSprite sprite = item.AnimInfo.currentSprite();
	RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba);
	return result;
}

bool IsItemLabelHighlightEnabled()
{
	if (!IsBridgeSafeToRead()) return true;
	return devilution::IsHighlightingLabelsEnabled();
}

std::vector<D1CorpseInfo> GetActiveCorpsesList()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<D1CorpseInfo> list;
	if (!IsBridgeSafeToRead()) return list;

	for (int y = 0; y < 112; ++y) {
		for (int x = 0; x < 112; ++x) {
			int8_t bDead = dCorpse[x][y];
			if (bDead == 0) continue;
			int corpseIdx = (bDead & 0x1F) - 1;
			if (corpseIdx < 0 || corpseIdx >= static_cast<int>(MaxCorpses)) continue;
			int dir = (bDead >> 5) & 7;
			const Corpse &corpse = Corpses[corpseIdx];
			if (!corpse.sprites.has_value()) continue;

			D1CorpseInfo info;
			info.tileX = x;
			info.tileY = y;
			info.corpseIdx = corpseIdx;
			info.dir = dir;
			info.frame = corpse.frame;
			info.width = corpse.width;
			info.height = 0;

			// Lookup monster name corresponding to this corpse
			const char *mName = "";
			if (corpse.translationPaletteIndex != 0 && static_cast<size_t>(corpse.translationPaletteIndex - 1) < MaxMonsters) {
				auto nv = Monsters[corpse.translationPaletteIndex - 1].name();
				size_t clen = std::min(nv.size(), sizeof(info.monsterName) - 1);
				std::memcpy(info.monsterName, nv.data(), clen);
				info.monsterName[clen] = '\0';
			} else {
				for (size_t i = 0; i < LevelMonsterTypeCount; ++i) {
					if (LevelMonsterTypes[i].corpseId == (corpseIdx + 1)) {
						if (LevelMonsterTypes[i].data != nullptr) {
							mName = LevelMonsterTypes[i].data->name;
						}
						break;
					}
				}
				if (mName != nullptr && mName[0] != '\0') {
					strncpy(info.monsterName, mName, sizeof(info.monsterName) - 1);
					info.monsterName[sizeof(info.monsterName) - 1] = '\0';
				}
			}

			list.push_back(info);
		}
	}
	return list;
}

D1CorpseSpriteRgba GetCorpseSpriteRgba(int corpseIdx, int dir)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1CorpseSpriteRgba result;
	if (!IsBridgeSafeToRead() || corpseIdx < 0 || corpseIdx >= static_cast<int>(MaxCorpses))
		return result;

	const Corpse &corpse = Corpses[corpseIdx];
	if (!corpse.sprites.has_value())
		return result;

	Direction d = static_cast<Direction>(std::clamp(dir, 0, 7));
	auto sprites = corpse.spritesForDirection(d);
	if (sprites.numSprites() == 0)
		return result;

	int frameIdx = std::clamp(corpse.frame, 0, static_cast<int>(sprites.numSprites()) - 1);
	const ClxSprite sprite = sprites[frameIdx];
	const uint8_t *trn = nullptr;
	if (corpse.translationPaletteIndex != 0 && static_cast<size_t>(corpse.translationPaletteIndex - 1) < MaxMonsters) {
		trn = Monsters[corpse.translationPaletteIndex - 1].uniqueMonsterTRN.get();
	}
	RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba, trn);
	return result;
}

Point MapIsometricToScreenCoords(float isoX, float isoY)
{
	float fx = (isoX / 32.0f + isoY / 16.0f) * 0.5f;
	float fy = (isoY / 16.0f - isoX / 32.0f) * 0.5f;
	int tx = static_cast<int>(std::floor(fx));
	int ty = static_cast<int>(std::floor(fy));
	float subX = fx - static_cast<float>(tx);
	float subY = fy - static_cast<float>(ty);
	int dx = static_cast<int>((subX - subY) * 32.0f);
	int dy = static_cast<int>((subX + subY) * 16.0f);
	return TileToScreenCoords(Point { tx, ty }, Displacement { dx, dy });
}

std::vector<D1MissileInfo> GetActiveMissilesList()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	std::vector<D1MissileInfo> list;
	if (!IsBridgeSafeToRead()) return list;

	int index = 0;
	for (const auto &missile : Missiles) {
		int currentId = index++;
		if (!missile._miDrawFlag || !missile._miAnimData.has_value() || missile._miAnimFrame <= 0 ||
		    static_cast<size_t>(missile._miAnimFrame) > (*missile._miAnimData).numSprites()) {
			continue;
		}

		const ClxSprite sprite = (*missile._miAnimData)[missile._miAnimFrame - 1];
		int w = sprite.width();
		int h = sprite.height();

		Point mTile = (missile.position.tileForRendering != Point { 0, 0 }) ? missile.position.tileForRendering : missile.position.tile;
		Displacement mOffset = (missile.position.offsetForRendering != Displacement {}) ? missile.position.offsetForRendering : missile.position.offset;

		float isoX = static_cast<float>(mTile.x - mTile.y) * 32.0f + static_cast<float>(mOffset.deltaX);
		float isoY = static_cast<float>(mTile.x + mTile.y) * 16.0f + static_cast<float>(mOffset.deltaY);

		D1MissileInfo info;
		info.id = currentId;
		info.type = static_cast<int>(missile._miAnimType);
		info.dir = static_cast<int>(missile._mimfnum);
		info.posX = isoX;
		info.posY = isoY;
		info.tileX = mTile.x;
		info.tileY = mTile.y;
		info.animFrame = missile._miAnimFrame;
		info.width = w;
		info.height = h;
		info.lightFlag = missile._miLightFlag;
		info.preFlag = missile._miPreFlag;
		list.push_back(info);
	}
	return list;
}

D1MissileSpriteRgba GetMissileSpriteRgba(int missileId)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1MissileSpriteRgba result;
	if (!IsBridgeSafeToRead() || missileId < 0) return result;

	int index = 0;
	for (const auto &missile : Missiles) {
		if (index++ == missileId) {
			if (!missile._miAnimData.has_value() || missile._miAnimFrame <= 0 ||
			    static_cast<size_t>(missile._miAnimFrame) > (*missile._miAnimData).numSprites()) {
				return result;
			}
			const ClxSprite sprite = (*missile._miAnimData)[missile._miAnimFrame - 1];
			const uint8_t *trn = nullptr;
			if (missile._miUniqTrans != 0 && missile._misource >= 0 && static_cast<size_t>(missile._misource) < MaxMonsters) {
				trn = Monsters[missile._misource].uniqueMonsterTRN.get();
			}
			RasterizeClxSpriteRgba(sprite, result.width, result.height, result.rgba, trn);
			return result;
		}
	}
	return result;
}

int GetModalType()
{
	if (!IsBridgeSafeToRead()) return 0;
	if (gmenu_is_active() || PauseMode != 0 || MyPlayerIsDead) return 1; // Esc Menu / Pause / Death Menu
	if (stextflag != TalkID::None || qtextflag || talkflag) return 2; // NPC Dialog / Store
	if (HelpFlag || ChatLogFlag) return 1;
	return 0;
}

bool IsModalActiveLive()
{
	if (!IsBridgeSafeToRead()) return false;
	return (stextflag != TalkID::None || HelpFlag || ChatLogFlag || talkflag || qtextflag || gmenu_is_active() || PauseMode != 0 || MyPlayerIsDead);
}

bool IsAutomapActive()
{
	if (!IsBridgeSafeToRead()) return false;
	return AutomapActive;
}

bool IsTextInputActiveLive()
{
	if (IsTextInputActive()) return true;
	if (gbRunGame && (talkflag || DropGoldFlag || IsWithdrawGoldOpen)) return true;
	return false;
}

bool IsPlayerDeadLive()
{
	if (!IsBridgeSafeToRead()) return false;
	return MyPlayerIsDead || (MyPlayer != nullptr && MyPlayer->_pmode == PM_DEATH);
}

// =====================================================================
// Godot native-modal-overlay bridge.
// Exports the ACTIVE menu items + current selection for every D1 modal
// (pause/gamemenu, dialog/store, death-restart) so the Godot overlay can
// render D1's own menus with Control nodes instead of blitting its vanilla
// frame onto the mesh. Selection/buy/enter actions stay handled by D1's own
// keyboard input; Godot just renders rows and forwards keys.
// =====================================================================

std::vector<D1MenuItemInfo> GetCurrentMenuItems()
{
	auto out = std::vector<D1MenuItemInfo>();
	if (!IsBridgeSafeToRead())
		return out;
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	const int t = GetModalType();
	if (t == 2) {
		if (qtextflag) {
			return out;
		}
		// Dialog / store: stext lines.
		auto lines = devilution::GetStoreDialogLines();
		for (const auto &s : lines)
			out.push_back(D1MenuItemInfo{ s.text, true, s.selectable, s.price });
	} else if (t == 1) {
		// Pause / death-restart: gamemenu items.
		auto items = devilution::GetCurrentGamemenuItems();
		for (const auto &it : items)
			out.push_back(D1MenuItemInfo{ it.text, it.enabled, it.enabled });
	}
	return out;
}

int GetCurrentModalSelectionIndex()
{
	if (!IsBridgeSafeToRead()) return -1;
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	const int t = GetModalType();
	if (t == 2) return devilution::GetCurrentStextSel();
	if (t == 1) return GetCurrentGamemenuSelection();
	return -1;
}

void ActivateModalItem(int index)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!IsBridgeSafeToRead()) return;
	const int t = GetModalType();
	if (t == 1) {
		devilution::ActivateGamemenuItem(index);
	} else if (t == 2) {
		if (qtextflag) {
			devilution::DismissQText();
		} else {
			devilution::ActivateStextItem(index);
		}
	}
}

void SelectModalItem(int index)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!IsBridgeSafeToRead()) return;
	const int t = GetModalType();
	if (t == 1) {
		devilution::SelectGamemenuItem(index);
	} else if (t == 2) {
		devilution::SelectStextItem(index);
	}
}

bool IsQTextActive()
{
	if (!IsBridgeSafeToRead()) return false;
	return qtextflag;
}

std::vector<std::string> GetQTextLines()
{
	if (!IsBridgeSafeToRead() || !qtextflag) return {};
	return devilution::GetRawQTextLines();
}

std::string GetQTextTitle()
{
	if (!IsBridgeSafeToRead()) return "";
	if (qtextflag && !g_ActiveQuestTitle.empty()) {
		return g_ActiveQuestTitle;
	}

	if (qtextflag && g_ActiveSpeechId >= 0 && g_ActiveSpeechId < 258) {
		_speech_id sid = static_cast<_speech_id>(g_ActiveSpeechId);
		_sfx_id sfx = Speeches[sid].sfxnr;

		// Match any quest from QuestsData FIRST!
		for (size_t q = 0; q < MAXQUESTS; ++q) {
			if (QuestsData[q]._qdmsg == sid || Quests[q]._qmsg == sid) {
				return std::string(_(QuestsData[q]._qlstr));
			}
		}

		// Towners
		if (sfx >= TSFX_STORY0 && sfx <= TSFX_STORY38) return std::string(_("Cain the Elder"));
		if (sfx >= TSFX_TAVERN0 && sfx <= TSFX_TAVERN45) return std::string(_("Ogden the Tavern Owner"));
		if (sfx >= TSFX_HEALER1 && sfx <= TSFX_HEALER47) return std::string(_("Pepin the Healer"));
		if (sfx >= TSFX_BMAID1 && sfx <= TSFX_BMAID40) return std::string(_("Gillian the Barmaid"));
		if (sfx >= TSFX_SMITH1 && sfx <= TSFX_SMITH56) return std::string(_("Griswold the Blacksmith"));
		if (sfx >= TSFX_DRUNK1 && sfx <= TSFX_DRUNK35) return std::string(_("Farnham the Drunk"));
		if (sfx >= TSFX_WITCH1 && sfx <= TSFX_WITCH42) return std::string(_("Adria the Witch"));
		if (sfx >= TSFX_PEGBOY1 && sfx <= TSFX_PEGBOY43) return std::string(_("Wirt the Peg-legged boy"));
		if (sfx >= TSFX_COW1 && sfx <= TSFX_COW8) return std::string(_("Complete Nut"));
		if (sfx >= TSFX_FARMER1 && sfx <= TSFX_FARMER9) return std::string(_("Lester the Farmer"));
		if (sid >= TEXT_GIRL1 && sid <= TEXT_GIRL4) return std::string(_("Celia"));

		// Bosses & Unique Monsters
		if (sfx == USFX_CLEAVER) return std::string(_("The Butcher"));
		if (sfx >= USFX_GARBUD1 && sfx <= USFX_GARBUD4) return std::string(_("Gharbad the Weak"));
		if (sfx >= USFX_LACH1 && sfx <= USFX_LACH3) return std::string(_("Lachdanan"));
		if (sfx == USFX_LAZ1 || sfx == USFX_LAZ2) return std::string(_("Archbishop Lazarus"));
		if (sfx == USFX_SKING1) return std::string(_("The Skeleton King"));
		if (sfx >= USFX_SNOT1 && sfx <= USFX_SNOT3) return std::string(_("Snotspill"));
		if (sfx == USFX_WARLRD1 || sfx == USFX_WLOCK1) return std::string(_("Warlord of Blood"));
		if (sfx == USFX_ZHAR1 || sfx == USFX_ZHAR2) return std::string(_("Zhar the Mad"));
		if (sfx >= USFX_DEFILER1 && sfx <= USFX_DEFILER8) return std::string(_("The Defiler"));
		if (sfx >= USFX_NAKRUL1 && sfx <= USFX_NAKRUL6) return std::string(_("Na-Krul"));

		// Dungeon books / special lore speeches
		if (sid == TEXT_BOOK9) return std::string(_("Tome of Knowledge"));
		if (sid == TEXT_BUTCH9) return std::string(_("Wounded Townsman"));
		if (sid >= TEXT_BLOOD1 && sid <= TEXT_BLOOD8) return std::string(_("Book of Blood"));
		if (sid == TEXT_BLOODWAR) return std::string(_("Book of Blood"));
		if (sid >= TEXT_BLIND1 && sid <= TEXT_BLIND8) return std::string(_("Book of the Blind"));
		if (sid == TEXT_BLINDING) return std::string(_("Book of the Blind"));
		if (sid >= TEXT_BONE1 && sid <= TEXT_BONE8) return std::string(_("Mythical Book"));
		if (sid == TEXT_BONER || sid == TEXT_BLOODY) return std::string(_("Mythical Book"));
	}

	if (stextflag != TalkID::None && leveltype == DTYPE_TOWN) {
		return devilution::GetActiveTalkerName();
	}

	return "Dialogue";
}

void DismissQText()
{
	g_ActiveQuestTitle.clear();
	if (!IsBridgeSafeToRead()) return;
	devilution::DismissRawQText();
}

D1AutomapRgba GetAutomapRgba()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	D1AutomapRgba result;
	if (!IsBridgeSafeToRead() || !AutomapActive || gnScreenWidth <= 0 || gnViewportHeight <= 0)
		return result;

	int w = gnScreenWidth;
	int h = gnViewportHeight;
	result.width = w;
	result.height = h;

	OwnedSurface surface(w, h);
	std::memset(surface.begin(), 0, surface.pitch() * surface.h());
	DrawAutomap(surface);

	result.rgba.resize(static_cast<size_t>(w) * h * 4, 0);
	uint8_t *dst = result.rgba.data();
	for (int y = 0; y < h; ++y) {
		const uint8_t *src = surface.at(0, y);
		for (int x = 0; x < w; ++x) {
			uint8_t idx = src[x];
			if (idx != 0) {
				SDL_Color c = system_palette[idx];
				int px = (y * w + x) * 4;
				dst[px + 0] = c.r;
				dst[px + 1] = c.g;
				dst[px + 2] = c.b;
				dst[px + 3] = 220;
			}
		}
	}
	return result;
}

int GetBridgeStoreGold()
{
	if (!IsBridgeSafeToRead()) return -1;
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!devilution::IsRenderGold()) return -1;
	return static_cast<int>(devilution::GetStoreGold());
}

bool IsBridgeStashOpen()
{
	if (!IsBridgeSafeToRead()) return false;
	return devilution::IsStashOpen;
}

void CloseBridgeStash()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame) return;
	devilution::CloseStash();
	g_InventoryVersion.fetch_add(1);
}

D1StashInfo GetStashInfo()
{
	D1StashInfo info;
	if (!IsBridgeSafeToRead()) return info;
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	info.page = devilution::Stash.GetPage() + 1;
	info.totalPages = 100;
	info.gold = devilution::Stash.gold;
	return info;
}

std::vector<D1InvItemData> GetStashItems()
{
	if (!IsBridgeSafeToRead() || !devilution::IsStashOpen) return {};
	std::lock_guard<std::mutex> lock(g_InventoryMutex);

	std::vector<D1InvItemData> result;
	for (int y = 0; y < 10; ++y) {
		for (int x = 0; x < 10; ++x) {
			Point slot { x, y };
			devilution::StashStruct::StashCell itemId = devilution::Stash.GetItemIdAtPosition(slot);
			if (itemId == devilution::StashStruct::EmptyCell)
				continue;
			if (itemId >= devilution::Stash.stashList.size())
				continue;
			const Item &item = devilution::Stash.stashList[itemId];
			if (item.position != slot)
				continue; // Only take the root slot of multi-cell items
			Size sz = GetInventorySize(item);
			int topX = item.position.x;
			int topY = item.position.y - (sz.height - 1);
			result.push_back(ConvertItemToInvData(item, topY * 10 + topX, topX, topY, itemId));
		}
	}
	return result;
}

void StashChangePage(int delta)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || !devilution::IsStashOpen) return;
	if (delta > 0)
		devilution::Stash.NextPage(static_cast<unsigned>(delta));
	else if (delta < 0)
		devilution::Stash.PreviousPage(static_cast<unsigned>(-delta));
	g_InventoryVersion.fetch_add(1);
}

void StashSetPage(int page)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || !devilution::IsStashOpen) return;
	if (page >= 1 && page <= 100)
		devilution::Stash.SetPage(static_cast<unsigned>(page - 1));
	g_InventoryVersion.fetch_add(1);
}

void ClickStashSlot(int cellIdx, bool isShift, bool isCtrl)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr || !devilution::IsStashOpen)
		return;

	if (cellIdx < 0 || cellIdx >= 100)
		return;

	int cellX = cellIdx % 10;
	int cellY = cellIdx / 10;
	Point slot { cellX, cellY };

	// Targeting cursors in stash (CURSOR_IDENTIFY, CURSOR_REPAIR, CURSOR_RECHARGE, CURSOR_OIL)
	if (pcurs > CURSOR_HAND && pcurs < CURSOR_FIRSTITEM) {
		devilution::StashStruct::StashCell itemId = devilution::Stash.GetItemIdAtPosition(slot);
		if (itemId != devilution::StashStruct::EmptyCell && itemId < devilution::Stash.stashList.size()) {
			Item &item = devilution::Stash.stashList[itemId];
			if (pcurs == CURSOR_IDENTIFY) {
				item._iIdentified = true;
				PlaySFX(ItemInvSnds[ItemCAnimTbl[item._iCurs]]);
				NewCursor(CURSOR_HAND);
			} else if (pcurs == CURSOR_REPAIR) {
				RepairItem(item, MyPlayer->_pLevel);
				NewCursor(CURSOR_HAND);
			} else if (pcurs == CURSOR_RECHARGE) {
				RechargeItem(item, *MyPlayer);
				NewCursor(CURSOR_HAND);
			} else if (pcurs == CURSOR_OIL) {
				if (ApplyOilToItem(item, *MyPlayer))
					NewCursor(CURSOR_HAND);
			}
		} else {
			NewCursor(CURSOR_HAND);
		}
		CalcPlrInv(*MyPlayer, true);
		g_InventoryVersion.fetch_add(1);
		return;
	}

	if (!MyPlayer->HoldItem.isEmpty()) {
		devilution::PasteItemToStashSlot(slot);
	} else if (isCtrl) {
		devilution::StashStruct::StashCell itemId = devilution::Stash.GetItemIdAtPosition(slot);
		if (itemId != devilution::StashStruct::EmptyCell) {
			devilution::TransferItemToInventory(*MyPlayer, itemId);
		}
	} else {
		devilution::CutItemFromStashSlot(slot, isShift);
	}

	CalcPlrInv(*MyPlayer, true);
	g_InventoryVersion.fetch_add(1);
}

void StashWithdrawGold(int amount)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr || !devilution::IsStashOpen)
		return;
	if (amount <= 0 || amount > devilution::Stash.gold)
		amount = devilution::Stash.gold;
	if (amount <= 0)
		return;
	int leftover = AddGoldToInventory(*MyPlayer, amount);
	int taken = amount - leftover;
	devilution::Stash.gold -= taken;
	devilution::Stash.dirty = true;
	CalcPlrInv(*MyPlayer, true);
	g_InventoryVersion.fetch_add(1);
}

bool IsSpellBookOpen()
{
	if (!IsBridgeSafeToRead()) return false;
	return devilution::sbookflag;
}

void ToggleSpellBook()
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame) return;
	devilution::SpellBookKeyPressed();
	g_InventoryVersion.fetch_add(1);
}

int GetSpellBookPage()
{
	if (!IsBridgeSafeToRead()) return 0;
	return devilution::sbooktab;
}

void SetSpellBookPage(int page)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame) return;
	int maxTab = gbIsHellfire ? 4 : 3;
	devilution::sbooktab = std::clamp(page, 0, maxTab);
}

std::vector<D1SpellBookEntry> GetSpellBookEntries()
{
	if (!IsBridgeSafeToRead() || MyPlayer == nullptr) return {};
	std::lock_guard<std::mutex> lock(g_InventoryMutex);

	std::vector<D1SpellBookEntry> result;
	Player &player = *MyPlayer;
	uint64_t spl = player._pMemSpells | player._pISpells | player._pAblSpells;

	for (size_t pageEntry = 0; pageEntry < 7; pageEntry++) {
		SpellID sn = devilution::GetSpellFromSpellPage(devilution::sbooktab, pageEntry);
		if (IsValidSpell(sn) && (spl & GetSpellBitmask(sn)) != 0) {
			D1SpellBookEntry entry;
			entry.spellId = static_cast<int>(sn);
			SpellType st = devilution::GetSBookTrans(sn, true);
			entry.spellType = static_cast<int>(st);
			entry.name = pgettext("spell", GetSpellData(sn).sNameText);
			entry.isEquipped = (sn == player._pRSpell && st == player._pRSplType);
			entry.level = player.GetSpellLevel(sn);
			entry.mana = GetManaAmount(player, sn) >> 6;
			entry.canCast = (st != SpellType::Invalid);

			switch (devilution::GetSBookTrans(sn, false)) {
			case SpellType::Skill:
				entry.typeText = _("Skill");
				break;
			case SpellType::Charges: {
				int charges = player.InvBody[INVLOC_HAND_LEFT]._iCharges;
				entry.typeText = fmt::format(fmt::runtime(ngettext("Staff ({:d} charge)", "Staff ({:d} charges)", charges)), charges);
			} break;
			default:
				entry.typeText = fmt::format(fmt::runtime(_("Level {:d}")), entry.level);
				if (entry.level == 0) {
					entry.detail = _("Unusable");
				} else {
					if (sn != SpellID::BoneSpirit) {
						int minDmg = 0;
						int maxDmg = 0;
						GetDamageAmt(sn, &minDmg, &maxDmg);
						if (minDmg != -1) {
							if (sn == SpellID::Healing || sn == SpellID::HealOther) {
								entry.detail = fmt::format(fmt::runtime(_("Heals: {:d} - {:d}")), minDmg, maxDmg);
							} else {
								entry.detail = fmt::format(fmt::runtime(_("Damage: {:d} - {:d}")), minDmg, maxDmg);
							}
						}
					} else {
						entry.detail = _("Dmg: 1/3 target hp");
					}
				}
				break;
			}
			result.push_back(entry);
		}
	}
	return result;
}

void SelectSpellBookEntry(int spellId, int spellType)
{
	std::lock_guard<std::mutex> lock(g_InventoryMutex);
	if (!gbRunGame || MyPlayer == nullptr) return;

	SpellID sn = static_cast<SpellID>(spellId);
	if (!IsValidSpell(sn)) return;

	Player &player = *MyPlayer;
	uint64_t spl = player._pMemSpells | player._pISpells | player._pAblSpells;
	if ((spl & GetSpellBitmask(sn)) == 0) return;

	SpellType st = static_cast<SpellType>(spellType);
	player._pRSpell = sn;
	player._pRSplType = st;
}

// -----------------------------------------------------------------------------
// Native Godot Menu Bridge Implementation
// -----------------------------------------------------------------------------
static std::mutex g_MenuMutex;
static std::condition_variable g_MenuCond;
static D1MenuMode g_CurrentMenuMode = D1MenuMode::None;
static _mainmenu_selections g_PendingMainMenuResult = static_cast<_mainmenu_selections>(0); // MAINMENU_NONE

static bool (*g_pfnHeroInfo)(bool (*fninfofunc)(_uiheroinfo *)) = nullptr;
static bool (*g_pfnHeroCreate)(_uiheroinfo *) = nullptr;
static bool (*g_pfnHeroRemove)(_uiheroinfo *) = nullptr;
static void (*g_pfnHeroStats)(unsigned int, _uidefaultstats *) = nullptr;

static bool g_HeroSelectDone = false;
static _selhero_selections g_HeroSelectResult = static_cast<_selhero_selections>(3); // SELHERO_PREVIOUS
static uint32_t g_SelectedSaveNumber = 0;
static _difficulty g_SelectedDifficulty = static_cast<_difficulty>(0); // DIFF_NORMAL

D1MenuMode GetBridgeMenuMode()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	return g_CurrentMenuMode;
}

static std::vector<D1HeroEntry> *g_pTempHeroList = nullptr;

static bool AccumulateHeroInfoBridge(_uiheroinfo *info)
{
	if (g_pTempHeroList != nullptr && info != nullptr) {
		if (!IsClassAllowed(static_cast<int>(info->heroclass)))
			return true;
		D1HeroEntry entry {};
		entry.saveNumber = info->saveNumber;
		std::strncpy(entry.name, info->name, sizeof(entry.name) - 1);
		entry.name[sizeof(entry.name) - 1] = '\0';
		entry.level = info->level;
		entry.heroClass = static_cast<int>(info->heroclass);
		entry.heroRank = info->herorank;
		entry.strength = info->strength;
		entry.magic = info->magic;
		entry.dexterity = info->dexterity;
		entry.vitality = info->vitality;
		entry.hasSaved = info->hassaved;
		g_pTempHeroList->push_back(entry);
	}
	return true;
}

std::vector<D1HeroEntry> GetBridgeHeroList()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	std::vector<D1HeroEntry> heroes;
	if (g_pfnHeroInfo != nullptr) {
		g_pTempHeroList = &heroes;
		g_pfnHeroInfo(AccumulateHeroInfoBridge);
		g_pTempHeroList = nullptr;
	}
	return heroes;
}

D1ClassDefaultStats GetBridgeClassStats(int heroClass)
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	_uidefaultstats rawStats {};
	if (g_pfnHeroStats != nullptr) {
		g_pfnHeroStats(static_cast<unsigned int>(heroClass), &rawStats);
	} else {
		pfile_ui_set_class_stats(static_cast<unsigned int>(heroClass), &rawStats);
	}
	D1ClassDefaultStats stats;
	stats.strength = rawStats.strength;
	stats.magic = rawStats.magic;
	stats.dexterity = rawStats.dexterity;
	stats.vitality = rawStats.vitality;
	return stats;
}

std::string GetBridgeRandomName(int heroClass)
{
	static const char *const Names[6][10] = {
		{ "Aidan", "Qarak", "Born", "Cathan", "Halbu", "Lenalas", "Maximus", "Vane", "Myrdgar", "Rothat" },
		{ "Moreina", "Akara", "Kashya", "Flavie", "Divo", "Oriana", "Iantha", "Shikha", "Basanti", "Elexa" },
		{ "Jazreth", "Drognan", "Armin", "Fauztin", "Jere", "Kazzulk", "Ranslor", "Sarnakyle", "Valthek", "Horazon" },
		{ "Akyev", "Dvorak", "Kekegi", "Kharazim", "Mikulov", "Shenlong", "Vedenin", "Vhalit", "Vylnas", "Zhota" },
		{ "Moreina", "Akara", "Kashya", "Flavie", "Divo", "Oriana", "Iantha", "Shikha", "Basanti", "Elexa" },
		{ "Alaric", "Barloc", "Egtheow", "Guthlaf", "Heorogar", "Hrothgar", "Oslaf", "Qual-Kehk", "Ragnar", "Ulf" }
	};
	int c = std::max(0, std::min(5, heroClass));
	int idx = rand() % 10;
	return Names[c][idx];
}

bool BridgeCreateHero(const char *name, int heroClass)
{
	if (!IsClassAllowed(heroClass))
		return false;
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	_uiheroinfo info {};
	info.saveNumber = pfile_ui_get_first_unused_save_num();
	std::strncpy(info.name, name, sizeof(info.name) - 1);
	info.name[sizeof(info.name) - 1] = '\0';
	info.heroclass = static_cast<HeroClass>(heroClass);
	info.level = 1;
	info.herorank = 0;
	info.hassaved = false;
	info.spawned = false;

	_uidefaultstats rawStats {};
	if (g_pfnHeroStats != nullptr) {
		g_pfnHeroStats(static_cast<unsigned int>(heroClass), &rawStats);
	} else {
		pfile_ui_set_class_stats(static_cast<unsigned int>(heroClass), &rawStats);
	}
	info.strength = rawStats.strength;
	info.magic = rawStats.magic;
	info.dexterity = rawStats.dexterity;
	info.vitality = rawStats.vitality;

	if (g_pfnHeroCreate != nullptr) {
		return g_pfnHeroCreate(&info);
	}
	return pfile_ui_save_create(&info);
}

bool BridgeDeleteHero(uint32_t saveNumber)
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	_uiheroinfo info {};
	info.saveNumber = saveNumber;
	if (g_pfnHeroRemove != nullptr) {
		return g_pfnHeroRemove(&info);
	}
	return pfile_delete_save(&info);
}

void BridgeSelectSinglePlayer()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	g_PendingMainMenuResult = MAINMENU_SINGLE_PLAYER;
	g_MenuCond.notify_all();
}

void BridgeSelectMultiplayer()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	g_PendingMainMenuResult = MAINMENU_MULTIPLAYER;
	g_MenuCond.notify_all();
}

void BridgeShowCredits()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	g_PendingMainMenuResult = MAINMENU_SHOW_CREDITS;
	g_MenuCond.notify_all();
}

void BridgeLaunchHero(uint32_t saveNumber, int difficulty, bool loadExisting)
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	g_SelectedSaveNumber = saveNumber;
	g_SelectedDifficulty = static_cast<_difficulty>(difficulty);
	g_HeroSelectResult = loadExisting ? SELHERO_CONTINUE : SELHERO_NEW_DUNGEON;
	g_HeroSelectDone = true;
	g_MenuCond.notify_all();
}

void BridgeCancelHeroSelect()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	g_HeroSelectResult = SELHERO_PREVIOUS;
	g_HeroSelectDone = true;
	g_MenuCond.notify_all();
}

void BridgeExitGame()
{
	std::lock_guard<std::mutex> lock(g_MenuMutex);
	g_PendingMainMenuResult = MAINMENU_EXIT_DIABLO;
	g_MenuCond.notify_all();
}

bool GodotBridgeMainMenuDialog(_mainmenu_selections *pdwResult)
{
	{
		std::lock_guard<std::mutex> frameLock(g_D1FrameMutex);
		g_D1EngineData.isGameRunning = false;
	}
	std::unique_lock<std::mutex> lock(g_MenuMutex);
	g_CurrentMenuMode = D1MenuMode::MainMenu;
	g_PendingMainMenuResult = MAINMENU_NONE;

	while (g_PendingMainMenuResult == MAINMENU_NONE && !g_D1EngineQuitRequested.load()) {
		g_MenuCond.wait_for(lock, std::chrono::milliseconds(50));
	}

	if (g_D1EngineQuitRequested.load()) {
		*pdwResult = MAINMENU_EXIT_DIABLO;
		g_CurrentMenuMode = D1MenuMode::None;
		return true;
	}

	*pdwResult = g_PendingMainMenuResult;
	g_CurrentMenuMode = D1MenuMode::None;
	return true;
}

void GodotBridgeSelHeroDialog(
    bool (*fninfo)(bool (*fninfofunc)(_uiheroinfo *)),
    bool (*fncreate)(_uiheroinfo *),
    bool (*fnremove)(_uiheroinfo *),
    void (*fnstats)(unsigned int, _uidefaultstats *),
    _selhero_selections *dlgresult,
    uint32_t *saveNumber,
    _difficulty *difficulty)
{
	{
		std::lock_guard<std::mutex> frameLock(g_D1FrameMutex);
		g_D1EngineData.isGameRunning = false;
	}
	std::unique_lock<std::mutex> lock(g_MenuMutex);
	g_pfnHeroInfo = fninfo;
	g_pfnHeroCreate = fncreate;
	g_pfnHeroRemove = fnremove;
	g_pfnHeroStats = fnstats;
	g_HeroSelectDone = false;
	g_CurrentMenuMode = D1MenuMode::CharacterSelect;

	while (!g_HeroSelectDone && !g_D1EngineQuitRequested.load()) {
		g_MenuCond.wait_for(lock, std::chrono::milliseconds(50));
	}

	if (g_D1EngineQuitRequested.load()) {
		*dlgresult = SELHERO_PREVIOUS;
		g_CurrentMenuMode = D1MenuMode::None;
		return;
	}

	*dlgresult = g_HeroSelectResult;
	*saveNumber = g_SelectedSaveNumber;
	*difficulty = g_SelectedDifficulty;
	g_CurrentMenuMode = D1MenuMode::None;
}

static bool IsValidOptionEntry(OptionEntryBase *pOptionEntry)
{
	auto flags = pOptionEntry->GetFlags();
	if (HasAnyOf(flags, OptionEntryFlags::NeedDiabloMpq) && !HaveDiabdat())
		return false;
	if (HasAnyOf(flags, OptionEntryFlags::NeedHellfireMpq) && !HaveHellfire())
		return false;
	return HasNoneOf(flags, OptionEntryFlags::Invisible | (gbIsHellfire ? OptionEntryFlags::OnlyDiablo : OptionEntryFlags::OnlyHellfire));
}

std::vector<D1SettingCategory> GetBridgeSettingsCategories()
{
	std::vector<D1SettingCategory> result;
	auto categories = sgOptions.GetCategories();
	for (size_t i = 0; i < categories.size(); ++i) {
		auto *cat = categories[i];
		D1SettingCategory sc;
		sc.id = static_cast<int>(i);
		sc.name = std::string(cat->GetName());
		sc.description = std::string(cat->GetDescription());
		result.push_back(sc);
	}
	return result;
}

std::vector<D1SettingEntry> GetBridgeSettingsEntries(int categoryId)
{
	std::vector<D1SettingEntry> result;
	if (SDL_WasInit(SDL_INIT_VIDEO) == 0) {
		SDL_InitSubSystem(SDL_INIT_VIDEO);
	}
	auto categories = sgOptions.GetCategories();
	if (categoryId < 0 || categoryId >= static_cast<int>(categories.size()))
		return result;

	auto entries = categories[categoryId]->GetEntries();
	for (size_t i = 0; i < entries.size(); ++i) {
		auto *entry = entries[i];
		if (!entry || !IsValidOptionEntry(entry))
			continue;

		D1SettingEntry se;
		se.id = static_cast<int>(i);
		se.categoryId = categoryId;
		se.name = std::string(entry->GetName());
		se.description = std::string(entry->GetDescription());
		se.valueStr = std::string(entry->GetValueDescription());

		auto type = entry->GetType();
		se.type = static_cast<int>(type);
		se.boolValue = false;
		se.listIndex = 0;

		if (type == OptionEntryType::Boolean) {
			auto *bEntry = static_cast<OptionEntryBoolean *>(entry);
			se.boolValue = **bEntry;
		} else if (type == OptionEntryType::List) {
			auto *lEntry = static_cast<OptionEntryListBase *>(entry);
			se.listIndex = static_cast<int>(lEntry->GetActiveListIndex());
			size_t listSize = lEntry->GetListSize();
			for (size_t l = 0; l < listSize; ++l) {
				se.listOptions.push_back(std::string(lEntry->GetListDescription(l)));
			}
		}
		result.push_back(se);
	}
	return result;
}

void SetBridgeSettingBool(int categoryId, int entryId, bool value)
{
	auto categories = sgOptions.GetCategories();
	if (categoryId < 0 || categoryId >= static_cast<int>(categories.size()))
		return;
	auto entries = categories[categoryId]->GetEntries();
	if (entryId < 0 || entryId >= static_cast<int>(entries.size()))
		return;
	auto *entry = entries[entryId];
	if (entry && entry->GetType() == OptionEntryType::Boolean) {
		static_cast<OptionEntryBoolean *>(entry)->SetValue(value);
	}
}

void SetBridgeSettingList(int categoryId, int entryId, int listIndex)
{
	auto categories = sgOptions.GetCategories();
	if (categoryId < 0 || categoryId >= static_cast<int>(categories.size()))
		return;
	auto entries = categories[categoryId]->GetEntries();
	if (entryId < 0 || entryId >= static_cast<int>(entries.size()))
		return;
	auto *entry = entries[entryId];
	if (entry && entry->GetType() == OptionEntryType::List) {
		auto *lEntry = static_cast<OptionEntryListBase *>(entry);
		if (listIndex >= 0 && listIndex < static_cast<int>(lEntry->GetListSize())) {
			lEntry->SetActiveListIndex(static_cast<size_t>(listIndex));
		}
	}
}

void SaveBridgeSettings()
{
	SaveOptions();
}

bool GetVsyncEnabled()
{
	return static_cast<bool>(*sgOptions.Graphics.vSync);
}

bool GetShowFpsEnabled()
{
	return static_cast<bool>(*sgOptions.Graphics.showFPS);
}

int GetResurrectedDisplayMode()
{
	return static_cast<int>(*sgOptions.Resurrected.displayMode);
}

int GetModeSwitchKey()
{
	return sgOptions.Resurrected.modeSwitchBinding.GetKey();
}

uint8_t GetModeSwitchMods()
{
	return sgOptions.Resurrected.modeSwitchBinding.GetMods();
}

void SetModeSwitchBinding(int key, uint8_t mods)
{
	sgOptions.Resurrected.modeSwitchBinding.SetValue(key, static_cast<uint8_t>(mods));
}

bool GetResurrectedTorchlight()
{
	return static_cast<bool>(*sgOptions.Resurrected.softTorchlight);
}

int GetResurrectedFogLevel()
{
	return static_cast<int>(*sgOptions.Resurrected.atmosphericFog);
}

int GetResurrectedColorProfile()
{
	return static_cast<int>(*sgOptions.Resurrected.colorProfile);
}

int GetResurrectedHdrLevel()
{
	return static_cast<int>(*sgOptions.Resurrected.hdrLevel);
}

int GetResurrectedUpscalerMode()
{
	return static_cast<int>(*sgOptions.Resurrected.upscalerMode);
}

int GetResurrectedReliefMode()
{
	return static_cast<int>(*sgOptions.Resurrected.reliefMode);
}

bool GetResurrectedWetFloor()
{
	return static_cast<bool>(*sgOptions.Resurrected.wetFloor);
}

int GetResurrectedTileModel()
{
	return static_cast<int>(*sgOptions.Resurrected.tileModel);
}

void SetResurrectedTileModel(int model)
{
	if (model >= 0 && model <= 5) {
		sgOptions.Resurrected.tileModel.SetValue(static_cast<TileModel>(model));
	}
}

bool IsHellfireMode()
{
	return gbIsHellfire;
}

bool IsClassAllowed(int heroClass)
{
	switch (heroClass) {
	case 0: // Warrior
	case 1: // Rogue
	case 2: // Sorcerer
		return true;
	case 3: // Monk
		return gbIsHellfire;
	case 4: // Bard
		return gbIsHellfire && (gbBard || *sgOptions.Gameplay.testBard);
	case 5: // Barbarian
		return gbIsHellfire && (gbBarbarian || *sgOptions.Gameplay.testBarbarian);
	default:
		return false;
	}
}

std::string GetBridgeLanguageCode()
{
	return std::string(*sgOptions.Language.code);
}

} // namespace devilution

