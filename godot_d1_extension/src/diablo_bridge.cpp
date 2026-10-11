#include "diablo_bridge.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/image.hpp>

#include "engine/render_bridge.hpp"
#include "engine/sound.h"    // sound_get_or_set_music_volume / sound_get_or_set_sound_volume
#include "engine/palette.h"  // UpdateGamma (0 = read-only)
#include "multi.h"           // sgGameInitInfo.nTickRate

using namespace godot;

void DiabloBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init_engine", "mpq_dir"), &DiabloBridge::init_engine);
	ClassDB::bind_method(D_METHOD("step_tick"), &DiabloBridge::step_tick);
	ClassDB::bind_method(D_METHOD("is_engine_ready"), &DiabloBridge::is_engine_ready);
	ClassDB::bind_method(D_METHOD("is_engine_running"), &DiabloBridge::is_engine_running);
	ClassDB::bind_method(D_METHOD("is_quit_requested"), &DiabloBridge::is_quit_requested);
	ClassDB::bind_method(D_METHOD("quit_engine"), &DiabloBridge::quit_engine);

	// Player Stats & Status
	ClassDB::bind_method(D_METHOD("get_player_tile_pos"), &DiabloBridge::get_player_tile_pos);
	ClassDB::bind_method(D_METHOD("get_player_norm_pos"), &DiabloBridge::get_player_norm_pos);
	ClassDB::bind_method(D_METHOD("get_player_hp"), &DiabloBridge::get_player_hp);
	ClassDB::bind_method(D_METHOD("get_player_max_hp"), &DiabloBridge::get_player_max_hp);
	ClassDB::bind_method(D_METHOD("get_player_mana"), &DiabloBridge::get_player_mana);
	ClassDB::bind_method(D_METHOD("get_player_max_mana"), &DiabloBridge::get_player_max_mana);
	ClassDB::bind_method(D_METHOD("get_player_gold"), &DiabloBridge::get_player_gold);
	ClassDB::bind_method(D_METHOD("get_player_class"), &DiabloBridge::get_player_class);
	ClassDB::bind_method(D_METHOD("get_current_level"), &DiabloBridge::get_current_level);
	ClassDB::bind_method(D_METHOD("get_dungeon_type"), &DiabloBridge::get_dungeon_type);
	ClassDB::bind_method(D_METHOD("is_left_panel_open"), &DiabloBridge::is_left_panel_open);
	ClassDB::bind_method(D_METHOD("is_right_panel_open"), &DiabloBridge::is_right_panel_open);
	ClassDB::bind_method(D_METHOD("get_left_panel_rect"), &DiabloBridge::get_left_panel_rect);
	ClassDB::bind_method(D_METHOD("get_right_panel_rect"), &DiabloBridge::get_right_panel_rect);
	ClassDB::bind_method(D_METHOD("is_speedbook_open"), &DiabloBridge::is_speedbook_open);
	ClassDB::bind_method(D_METHOD("get_speedbook_rect"), &DiabloBridge::get_speedbook_rect);
	ClassDB::bind_method(D_METHOD("get_player_level"), &DiabloBridge::get_player_level);
	ClassDB::bind_method(D_METHOD("get_player_xp"), &DiabloBridge::get_player_xp);
	ClassDB::bind_method(D_METHOD("get_player_next_xp"), &DiabloBridge::get_player_next_xp);
	ClassDB::bind_method(D_METHOD("get_player_spell"), &DiabloBridge::get_player_spell);
	ClassDB::bind_method(D_METHOD("get_player_spell_type"), &DiabloBridge::get_player_spell_type);
	ClassDB::bind_method(D_METHOD("get_belt_items"), &DiabloBridge::get_belt_items);
	ClassDB::bind_method(D_METHOD("use_belt_slot", "slot_index"), &DiabloBridge::use_belt_slot);
	ClassDB::bind_method(D_METHOD("click_belt_slot", "slot_index"), &DiabloBridge::click_belt_slot);
	ClassDB::bind_method(D_METHOD("set_vanilla_hud_hidden", "hidden"), &DiabloBridge::set_vanilla_hud_hidden);
	ClassDB::bind_method(D_METHOD("is_vanilla_hud_hidden"), &DiabloBridge::is_vanilla_hud_hidden);
	ClassDB::bind_method(D_METHOD("is_game_running"), &DiabloBridge::is_game_running);
	ClassDB::bind_method(D_METHOD("is_level_loading"), &DiabloBridge::is_level_loading);
	ClassDB::bind_method(D_METHOD("is_modal_active"), &DiabloBridge::is_modal_active);
	ClassDB::bind_method(D_METHOD("is_text_input_active"), &DiabloBridge::is_text_input_active);
	ClassDB::bind_method(D_METHOD("is_player_dead"), &DiabloBridge::is_player_dead);
	ClassDB::bind_method(D_METHOD("get_modal_type"), &DiabloBridge::get_modal_type);
	ClassDB::bind_method(D_METHOD("get_current_menu_items"), &DiabloBridge::get_current_menu_items);
	ClassDB::bind_method(D_METHOD("get_modal_selection_index"), &DiabloBridge::get_modal_selection_index);
	ClassDB::bind_method(D_METHOD("get_store_gold"), &DiabloBridge::get_store_gold);
	ClassDB::bind_method(D_METHOD("activate_modal_item", "index"), &DiabloBridge::activate_modal_item);
	ClassDB::bind_method(D_METHOD("select_modal_item", "index"), &DiabloBridge::select_modal_item);
	ClassDB::bind_method(D_METHOD("is_qtext_active"), &DiabloBridge::is_qtext_active);
	ClassDB::bind_method(D_METHOD("get_qtext_lines"), &DiabloBridge::get_qtext_lines);
	ClassDB::bind_method(D_METHOD("get_qtext_title"), &DiabloBridge::get_qtext_title);
	ClassDB::bind_method(D_METHOD("dismiss_qtext"), &DiabloBridge::dismiss_qtext);
	ClassDB::bind_method(D_METHOD("is_automap_active"), &DiabloBridge::is_automap_active);
	ClassDB::bind_method(D_METHOD("get_automap_texture"), &DiabloBridge::get_automap_texture);
	ClassDB::bind_method(D_METHOD("get_spell_icon_texture", "spell_id", "spell_type"), &DiabloBridge::get_spell_icon_texture);
	ClassDB::bind_method(D_METHOD("get_belt_item_texture", "slot_index"), &DiabloBridge::get_belt_item_texture);
	ClassDB::bind_method(D_METHOD("has_hover_item"), &DiabloBridge::has_hover_item);
	ClassDB::bind_method(D_METHOD("get_hover_item_info"), &DiabloBridge::get_hover_item_info);
	ClassDB::bind_method(D_METHOD("get_available_spells"), &DiabloBridge::get_available_spells);
	ClassDB::bind_method(D_METHOD("select_spell", "spell_id", "spell_type"), &DiabloBridge::select_spell);
	ClassDB::bind_method(D_METHOD("get_potion_summary"), &DiabloBridge::get_potion_summary);
	ClassDB::bind_method(D_METHOD("use_smart_potion", "category"), &DiabloBridge::use_smart_potion);
	ClassDB::bind_method(D_METHOD("get_town_portal_summary"), &DiabloBridge::get_town_portal_summary);
	ClassDB::bind_method(D_METHOD("use_smart_town_portal"), &DiabloBridge::use_smart_town_portal);
	ClassDB::bind_method(D_METHOD("get_target_monster_summary", "target_id"), &DiabloBridge::get_target_monster_summary, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("bind_spell_hotkey", "spell_id", "spell_type", "slot_idx"), &DiabloBridge::bind_spell_hotkey);
	ClassDB::bind_method(D_METHOD("quick_cast_hotkey", "slot_idx"), &DiabloBridge::quick_cast_hotkey);
	ClassDB::bind_method(D_METHOD("get_zoom_mode"), &DiabloBridge::get_zoom_mode);

	// Native Godot Options menu (Music/Sound/Gamma/Speed)
	ClassDB::bind_method(D_METHOD("get_music_volume"), &DiabloBridge::get_music_volume);
	ClassDB::bind_method(D_METHOD("get_sound_volume"), &DiabloBridge::get_sound_volume);
	ClassDB::bind_method(D_METHOD("get_gamma"), &DiabloBridge::get_gamma);
	ClassDB::bind_method(D_METHOD("get_speed"), &DiabloBridge::get_speed);
	ClassDB::bind_method(D_METHOD("set_music_volume", "volume"), &DiabloBridge::set_music_volume);
	ClassDB::bind_method(D_METHOD("set_sound_volume", "volume"), &DiabloBridge::set_sound_volume);
	ClassDB::bind_method(D_METHOD("set_gamma", "gamma"), &DiabloBridge::set_gamma);
	ClassDB::bind_method(D_METHOD("set_speed", "tick_rate"), &DiabloBridge::set_speed);

	// Native Godot Diablo IV Character Sheet & Quest Log
	ClassDB::bind_method(D_METHOD("get_character_info"), &DiabloBridge::get_character_info);
	ClassDB::bind_method(D_METHOD("add_attribute_point", "attr_idx"), &DiabloBridge::add_attribute_point);
	ClassDB::bind_method(D_METHOD("is_character_open"), &DiabloBridge::is_character_open);
	ClassDB::bind_method(D_METHOD("toggle_character_sheet"), &DiabloBridge::toggle_character_sheet);
	ClassDB::bind_method(D_METHOD("get_quests_info"), &DiabloBridge::get_quests_info);
	ClassDB::bind_method(D_METHOD("select_quest", "quest_idx"), &DiabloBridge::select_quest);
	ClassDB::bind_method(D_METHOD("is_quest_log_open"), &DiabloBridge::is_quest_log_open);
	ClassDB::bind_method(D_METHOD("toggle_quest_log"), &DiabloBridge::toggle_quest_log);
	ClassDB::bind_method(D_METHOD("is_inventory_open"), &DiabloBridge::is_inventory_open);
	ClassDB::bind_method(D_METHOD("toggle_inventory"), &DiabloBridge::toggle_inventory);
	ClassDB::bind_method(D_METHOD("set_active_ui_panel", "panel"), &DiabloBridge::set_active_ui_panel);
	ClassDB::bind_method(D_METHOD("close_all_ui_panels"), &DiabloBridge::close_all_ui_panels);
	ClassDB::bind_method(D_METHOD("get_active_ui_panel"), &DiabloBridge::get_active_ui_panel);

	// Native Godot Diablo IV Inventory
	ClassDB::bind_method(D_METHOD("get_inventory_version"), &DiabloBridge::get_inventory_version);
	ClassDB::bind_method(D_METHOD("get_player_equipment"), &DiabloBridge::get_player_equipment);
	ClassDB::bind_method(D_METHOD("get_player_backpack"), &DiabloBridge::get_player_backpack);
	ClassDB::bind_method(D_METHOD("get_player_hold_item"), &DiabloBridge::get_player_hold_item);
	ClassDB::bind_method(D_METHOD("get_item_texture", "curs_id"), &DiabloBridge::get_item_texture);
	ClassDB::bind_method(D_METHOD("click_inventory_slot", "slot_type", "slot_idx", "is_shift", "is_ctrl"), &DiabloBridge::click_inventory_slot, DEFVAL(false), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("use_inventory_slot", "slot_type", "slot_idx"), &DiabloBridge::use_inventory_slot);
	ClassDB::bind_method(D_METHOD("get_cursor_id"), &DiabloBridge::get_cursor_id);
	ClassDB::bind_method(D_METHOD("cancel_targeting_cursor"), &DiabloBridge::cancel_targeting_cursor);
	ClassDB::bind_method(D_METHOD("get_cursor_texture", "curs_id"), &DiabloBridge::get_cursor_texture);
	ClassDB::bind_method(D_METHOD("get_player_durability_warnings"), &DiabloBridge::get_player_durability_warnings);
	ClassDB::bind_method(D_METHOD("get_durability_icon", "frame_idx"), &DiabloBridge::get_durability_icon);
	ClassDB::bind_method(D_METHOD("get_durability_icon_composite", "icon_idx", "durability"), &DiabloBridge::get_durability_icon_composite);

	// Native Godot Diablo IV Stash
	ClassDB::bind_method(D_METHOD("is_stash_open"), &DiabloBridge::is_stash_open);
	ClassDB::bind_method(D_METHOD("close_stash"), &DiabloBridge::close_stash);
	ClassDB::bind_method(D_METHOD("get_stash_info"), &DiabloBridge::get_stash_info);
	ClassDB::bind_method(D_METHOD("get_stash_items"), &DiabloBridge::get_stash_items);
	ClassDB::bind_method(D_METHOD("stash_change_page", "delta"), &DiabloBridge::stash_change_page);
	ClassDB::bind_method(D_METHOD("stash_set_page", "page"), &DiabloBridge::stash_set_page);
	ClassDB::bind_method(D_METHOD("click_stash_slot", "cell_idx", "is_shift", "is_ctrl"), &DiabloBridge::click_stash_slot, DEFVAL(false), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("stash_withdraw_gold", "amount"), &DiabloBridge::stash_withdraw_gold);

	// Native Godot Diablo IV SpellBook
	ClassDB::bind_method(D_METHOD("is_spell_book_open"), &DiabloBridge::is_spell_book_open);
	ClassDB::bind_method(D_METHOD("toggle_spell_book"), &DiabloBridge::toggle_spell_book);
	ClassDB::bind_method(D_METHOD("get_spell_book_page"), &DiabloBridge::get_spell_book_page);
	ClassDB::bind_method(D_METHOD("set_spell_book_page", "page"), &DiabloBridge::set_spell_book_page);
	ClassDB::bind_method(D_METHOD("get_spell_book_entries"), &DiabloBridge::get_spell_book_entries);
	ClassDB::bind_method(D_METHOD("select_spell_book_entry", "spell_id", "spell_type"), &DiabloBridge::select_spell_book_entry);

	// Native Godot Menu Bridge
	ClassDB::bind_method(D_METHOD("get_menu_mode"), &DiabloBridge::get_menu_mode);
	ClassDB::bind_method(D_METHOD("is_hellfire"), &DiabloBridge::is_hellfire);
	ClassDB::bind_method(D_METHOD("is_class_allowed", "hero_class"), &DiabloBridge::is_class_allowed);
	ClassDB::bind_method(D_METHOD("get_allowed_classes"), &DiabloBridge::get_allowed_classes);
	ClassDB::bind_method(D_METHOD("get_language_code"), &DiabloBridge::get_language_code);
	ClassDB::bind_method(D_METHOD("menu_select_single_player"), &DiabloBridge::menu_select_single_player);
	ClassDB::bind_method(D_METHOD("menu_select_multiplayer"), &DiabloBridge::menu_select_multiplayer);
	ClassDB::bind_method(D_METHOD("menu_show_credits"), &DiabloBridge::menu_show_credits);
	ClassDB::bind_method(D_METHOD("menu_exit_game"), &DiabloBridge::menu_exit_game);
	ClassDB::bind_method(D_METHOD("get_hero_list"), &DiabloBridge::get_hero_list);
	ClassDB::bind_method(D_METHOD("get_class_base_stats", "hero_class"), &DiabloBridge::get_class_base_stats);
	ClassDB::bind_method(D_METHOD("get_random_hero_name", "hero_class"), &DiabloBridge::get_random_hero_name);
	ClassDB::bind_method(D_METHOD("create_hero", "name", "hero_class"), &DiabloBridge::create_hero);
	ClassDB::bind_method(D_METHOD("delete_hero", "save_num"), &DiabloBridge::delete_hero);
	ClassDB::bind_method(D_METHOD("launch_hero_game", "save_num", "difficulty", "load_saved"), &DiabloBridge::launch_hero_game);
	ClassDB::bind_method(D_METHOD("cancel_hero_select"), &DiabloBridge::cancel_hero_select);

	// Native Godot Full DevilutionX Settings Bridge
	ClassDB::bind_method(D_METHOD("get_settings_categories"), &DiabloBridge::get_settings_categories);
	ClassDB::bind_method(D_METHOD("get_settings_entries", "category_id"), &DiabloBridge::get_settings_entries);
	ClassDB::bind_method(D_METHOD("set_setting_bool", "category_id", "entry_id", "value"), &DiabloBridge::set_setting_bool);
	ClassDB::bind_method(D_METHOD("set_setting_list", "category_id", "entry_id", "list_index"), &DiabloBridge::set_setting_list);
	ClassDB::bind_method(D_METHOD("save_settings"), &DiabloBridge::save_settings);
	ClassDB::bind_method(D_METHOD("get_vsync_enabled"), &DiabloBridge::get_vsync_enabled);
	ClassDB::bind_method(D_METHOD("get_show_fps"), &DiabloBridge::get_show_fps);
	ClassDB::bind_method(D_METHOD("get_d1de_display_mode"), &DiabloBridge::get_d1de_display_mode);
	ClassDB::bind_method(D_METHOD("get_resurrected_display_mode"), &DiabloBridge::get_resurrected_display_mode);
	ClassDB::bind_method(D_METHOD("get_mode_switch_key"), &DiabloBridge::get_mode_switch_key);
	ClassDB::bind_method(D_METHOD("get_mode_switch_mods"), &DiabloBridge::get_mode_switch_mods);
	ClassDB::bind_method(D_METHOD("set_mode_switch_binding", "key", "mods"), &DiabloBridge::set_mode_switch_binding);

	ClassDB::bind_method(D_METHOD("get_d1de_torchlight"), &DiabloBridge::get_d1de_torchlight);
	ClassDB::bind_method(D_METHOD("get_d1de_fog_level"), &DiabloBridge::get_d1de_fog_level);
	ClassDB::bind_method(D_METHOD("get_d1de_color_profile"), &DiabloBridge::get_d1de_color_profile);
	ClassDB::bind_method(D_METHOD("get_d1de_hdr_level"), &DiabloBridge::get_d1de_hdr_level);
	ClassDB::bind_method(D_METHOD("get_d1de_upscaler_mode"), &DiabloBridge::get_d1de_upscaler_mode);
	ClassDB::bind_method(D_METHOD("get_d1de_relief_mode"), &DiabloBridge::get_d1de_relief_mode);
	ClassDB::bind_method(D_METHOD("get_d1de_wet_floor"), &DiabloBridge::get_d1de_wet_floor);
	ClassDB::bind_method(D_METHOD("get_d1de_tile_model"), &DiabloBridge::get_d1de_tile_model);
	ClassDB::bind_method(D_METHOD("set_d1de_tile_model", "model"), &DiabloBridge::set_d1de_tile_model);

	ClassDB::bind_method(D_METHOD("get_resurrected_torchlight"), &DiabloBridge::get_resurrected_torchlight);
	ClassDB::bind_method(D_METHOD("get_resurrected_fog_level"), &DiabloBridge::get_resurrected_fog_level);
	ClassDB::bind_method(D_METHOD("get_resurrected_color_profile"), &DiabloBridge::get_resurrected_color_profile);
	ClassDB::bind_method(D_METHOD("get_resurrected_hdr_level"), &DiabloBridge::get_resurrected_hdr_level);
	ClassDB::bind_method(D_METHOD("get_resurrected_upscaler_mode"), &DiabloBridge::get_resurrected_upscaler_mode);
	ClassDB::bind_method(D_METHOD("get_resurrected_relief_mode"), &DiabloBridge::get_resurrected_relief_mode);
	ClassDB::bind_method(D_METHOD("get_resurrected_wet_floor"), &DiabloBridge::get_resurrected_wet_floor);
	ClassDB::bind_method(D_METHOD("get_resurrected_tile_model"), &DiabloBridge::get_resurrected_tile_model);
	ClassDB::bind_method(D_METHOD("set_resurrected_tile_model", "model"), &DiabloBridge::set_resurrected_tile_model);

	// 112x112 Dungeon Grid
	ClassDB::bind_method(D_METHOD("get_dungeon_grid"), &DiabloBridge::get_dungeon_grid);
	ClassDB::bind_method(D_METHOD("get_dungeon_tile", "x", "y"), &DiabloBridge::get_dungeon_tile);
	ClassDB::bind_method(D_METHOD("get_dungeon_piece_id", "x", "y"), &DiabloBridge::get_dungeon_piece_id);
	ClassDB::bind_method(D_METHOD("get_dungeon_solidity_grid"), &DiabloBridge::get_dungeon_solidity_grid);
	ClassDB::bind_method(D_METHOD("get_dungeon_piece_data", "piece_id"), &DiabloBridge::get_dungeon_piece_data);
	ClassDB::bind_method(D_METHOD("get_dungeon_piece_texture", "piece_id"), &DiabloBridge::get_dungeon_piece_texture);
	ClassDB::bind_method(D_METHOD("clear_dungeon_piece_cache"), &DiabloBridge::clear_dungeon_piece_cache);
	ClassDB::bind_method(D_METHOD("get_dungeon_special_grid"), &DiabloBridge::get_dungeon_special_grid);
	ClassDB::bind_method(D_METHOD("get_special_cel_data", "special_id"), &DiabloBridge::get_special_cel_data);
	ClassDB::bind_method(D_METHOD("get_special_cel_texture", "special_id"), &DiabloBridge::get_special_cel_texture);
	ClassDB::bind_method(D_METHOD("get_dungeon_light_grid"), &DiabloBridge::get_dungeon_light_grid);
	ClassDB::bind_method(D_METHOD("get_dungeon_flags_grid"), &DiabloBridge::get_dungeon_flags_grid);
	ClassDB::bind_method(D_METHOD("get_dungeon_trans_grid"), &DiabloBridge::get_dungeon_trans_grid);
	ClassDB::bind_method(D_METHOD("get_dungeon_trans_mask"), &DiabloBridge::get_dungeon_trans_mask);
	ClassDB::bind_method(D_METHOD("get_trans_list"), &DiabloBridge::get_trans_list);
	ClassDB::bind_method(D_METHOD("set_zoom_vision_radius", "radius"), &DiabloBridge::set_zoom_vision_radius);

	// Native Godot 2.5D Dungeon Objects (Torches, Barrels, Chests, Shrines)
	ClassDB::bind_method(D_METHOD("get_active_objects"), &DiabloBridge::get_active_objects);
	ClassDB::bind_method(D_METHOD("get_object_sprite_data", "object_id"), &DiabloBridge::get_object_sprite_data);

	// Native Godot 2.5D Ground Items & Loot
	ClassDB::bind_method(D_METHOD("get_active_items"), &DiabloBridge::get_active_items);
	ClassDB::bind_method(D_METHOD("get_ground_item_sprite_data", "item_id"), &DiabloBridge::get_ground_item_sprite_data);
	ClassDB::bind_method(D_METHOD("is_item_label_highlight_enabled"), &DiabloBridge::is_item_label_highlight_enabled);

	// Native Godot 2.5D Corpses & Fallen Monsters
	ClassDB::bind_method(D_METHOD("get_active_corpses"), &DiabloBridge::get_active_corpses);
	ClassDB::bind_method(D_METHOD("get_corpse_sprite_data", "corpse_idx", "dir"), &DiabloBridge::get_corpse_sprite_data);

	// Coordinate Mapping
	ClassDB::bind_method(D_METHOD("map_world_to_screen", "world_pos"), &DiabloBridge::map_world_to_screen);

	// Native Godot 2.5D Missiles & Spell Projectiles
	ClassDB::bind_method(D_METHOD("get_active_missiles"), &DiabloBridge::get_active_missiles);
	ClassDB::bind_method(D_METHOD("get_missile_sprite_data", "missile_id"), &DiabloBridge::get_missile_sprite_data);

	// Native 3D World & Entity Tracking
	ClassDB::bind_method(D_METHOD("get_player_continuous_pos"), &DiabloBridge::get_player_continuous_pos);
	ClassDB::bind_method(D_METHOD("get_active_monsters_data"), &DiabloBridge::get_active_monsters_data);
	ClassDB::bind_method(D_METHOD("get_player_sprite_data"), &DiabloBridge::get_player_sprite_data);
	ClassDB::bind_method(D_METHOD("get_monster_sprite_data", "monster_id"), &DiabloBridge::get_monster_sprite_data);

	// Direct Input
	ClassDB::bind_method(D_METHOD("send_input", "type", "code", "state", "x", "y"), &DiabloBridge::send_input);
	ClassDB::bind_method(D_METHOD("send_key_event", "keycode", "pressed"), &DiabloBridge::send_key_event);
	ClassDB::bind_method(D_METHOD("send_click_to_tile", "tile_x", "tile_y", "button_mask"), &DiabloBridge::send_click_to_tile, DEFVAL(1));

	// Video Frame Blitting
	ClassDB::bind_method(D_METHOD("get_frame_bytes"), &DiabloBridge::get_frame_bytes);
	ClassDB::bind_method(D_METHOD("get_frame_width"), &DiabloBridge::get_frame_width);
	ClassDB::bind_method(D_METHOD("get_frame_height"), &DiabloBridge::get_frame_height);
	ClassDB::bind_method(D_METHOD("get_frame_id"), &DiabloBridge::get_frame_id);
	ClassDB::bind_method(D_METHOD("update_image_texture", "texture"), &DiabloBridge::update_image_texture);

	// Audio & Asset Interception
	ClassDB::bind_method(D_METHOD("poll_audio_events"), &DiabloBridge::poll_audio_events);
	ClassDB::bind_method(D_METHOD("get_asset_bytes", "path"), &DiabloBridge::get_asset_bytes);
	ClassDB::bind_method(D_METHOD("load_wav_stream", "path", "loop"), &DiabloBridge::load_wav_stream, DEFVAL(false));

	// Native Godot 3D Lighting, Shadows & GPUParticles
	ClassDB::bind_method(D_METHOD("get_active_lights"), &DiabloBridge::get_active_lights);
	ClassDB::bind_method(D_METHOD("get_wall_occluders"), &DiabloBridge::get_wall_occluders);
	ClassDB::bind_method(D_METHOD("poll_visual_events"), &DiabloBridge::poll_visual_events);
}

DiabloBridge::DiabloBridge() {
}

DiabloBridge::~DiabloBridge() {
	quit_engine();
}

bool DiabloBridge::init_engine(const String &mpq_dir) {
	if (engine_started) {
		return true;
	}

	UtilityFunctions::print("[DiabloBridge] Starting embedded DevilutionX core with MPQ dir: ", mpq_dir);
	devilution::StartDevilutionXThread(mpq_dir.utf8().get_data());
	engine_started = true;
	return true;
}

void DiabloBridge::step_tick() {
	// Engine tick is driven asynchronously by internal DevilutionX thread,
	// step_tick() can be used to synchronize or signal state updates if needed.
}

bool DiabloBridge::is_engine_ready() const {
	return devilution::g_D1EngineData.frameId > 0 || (devilution::IsDevilutionXRunning() && devilution::GetBridgeMenuMode() != devilution::D1MenuMode::None);
}

bool DiabloBridge::is_engine_running() const {
	return devilution::IsDevilutionXRunning();
}

bool DiabloBridge::is_quit_requested() const {
	return devilution::IsDevilutionXQuitRequested();
}

void DiabloBridge::quit_engine() {
	devilution::RequestDevilutionXQuit();
}

Vector2i DiabloBridge::get_player_tile_pos() const {
	return Vector2i(devilution::g_D1EngineData.playerTileX, devilution::g_D1EngineData.playerTileY);
}

Vector2 DiabloBridge::get_player_norm_pos() const {
	return Vector2(devilution::g_D1EngineData.playerNormX, devilution::g_D1EngineData.playerNormY);
}

int DiabloBridge::get_player_hp() const {
	return devilution::g_D1EngineData.playerHp;
}

int DiabloBridge::get_player_max_hp() const {
	return devilution::g_D1EngineData.playerMaxHp;
}

int DiabloBridge::get_player_mana() const {
	return devilution::g_D1EngineData.playerMana;
}

int DiabloBridge::get_player_max_mana() const {
	return devilution::g_D1EngineData.playerMaxMana;
}

int DiabloBridge::get_player_gold() const {
	return devilution::g_D1EngineData.playerGold;
}

int DiabloBridge::get_player_class() const {
	return devilution::g_D1EngineData.playerClass;
}

int DiabloBridge::get_current_level() const {
	return devilution::g_D1EngineData.currentLevel;
}

int DiabloBridge::get_dungeon_type() const {
	return devilution::g_D1EngineData.dungeonType;
}

bool DiabloBridge::is_left_panel_open() const {
	return devilution::g_D1EngineData.leftPanelOpen;
}

bool DiabloBridge::is_right_panel_open() const {
	return devilution::g_D1EngineData.rightPanelOpen;
}

Rect2 DiabloBridge::get_left_panel_rect() const {
	return Rect2(
		devilution::g_D1EngineData.leftPanelX,
		devilution::g_D1EngineData.leftPanelY,
		devilution::g_D1EngineData.leftPanelW,
		devilution::g_D1EngineData.leftPanelH
	);
}

Rect2 DiabloBridge::get_right_panel_rect() const {
	return Rect2(
		devilution::g_D1EngineData.rightPanelX,
		devilution::g_D1EngineData.rightPanelY,
		devilution::g_D1EngineData.rightPanelW,
		devilution::g_D1EngineData.rightPanelH
	);
}

bool DiabloBridge::is_speedbook_open() const {
	return devilution::g_D1EngineData.isSpeedbookOpen;
}

Rect2 DiabloBridge::get_speedbook_rect() const {
	return Rect2(
		devilution::g_D1EngineData.speedbookX,
		devilution::g_D1EngineData.speedbookY,
		devilution::g_D1EngineData.speedbookW,
		devilution::g_D1EngineData.speedbookH
	);
}

int DiabloBridge::get_player_level() const {
	return devilution::g_D1EngineData.playerLevel;
}

int DiabloBridge::get_player_xp() const {
	return devilution::g_D1EngineData.playerExp;
}

int DiabloBridge::get_player_next_xp() const {
	return devilution::g_D1EngineData.playerNextExp;
}

int DiabloBridge::get_player_spell() const {
	return devilution::g_D1EngineData.playerSpell;
}

int DiabloBridge::get_player_spell_type() const {
	return devilution::g_D1EngineData.playerSpellType;
}

Array DiabloBridge::get_belt_items() const {
	Array items;
	for (int i = 0; i < 8; ++i) {
		Dictionary d;
		d["slot"] = i;
		d["type"] = devilution::g_D1EngineData.beltTypes[i];
		d["count"] = devilution::g_D1EngineData.beltCounts[i];
		d["name"] = String::utf8(devilution::g_D1EngineData.beltNames[i]);
		items.push_back(d);
	}
	return items;
}

void DiabloBridge::use_belt_slot(int slot_index) {
	// Route to engine thread (queued): mutates state, can trigger a render cycle.
	devilution::PushBridgeAction(devilution::D1BridgeActionType::UseBeltSlot, slot_index);
}

void DiabloBridge::click_belt_slot(int slot_index) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ClickBeltSlot, slot_index);
}

void DiabloBridge::set_vanilla_hud_hidden(bool hidden) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetVanillaHUDHidden, hidden ? 1 : 0);
}

bool DiabloBridge::is_vanilla_hud_hidden() const {
	return devilution::gbHideVanillaHUD;
}

bool DiabloBridge::is_game_running() const {
	return devilution::IsGameRunningLive();
}

bool DiabloBridge::is_level_loading() const {
	return devilution::g_D1LevelTransitioning.load() || !devilution::IsBridgeSafeToRead();
}

bool DiabloBridge::is_modal_active() const {
	return devilution::IsModalActiveLive();
}

bool DiabloBridge::is_text_input_active() const {
	return devilution::g_D1EngineData.isTextInputActive || devilution::IsTextInputActiveLive();
}

bool DiabloBridge::is_player_dead() const {
	return devilution::g_D1EngineData.isPlayerDead || devilution::IsPlayerDeadLive();
}

int DiabloBridge::get_modal_type() const {
	return devilution::GetModalType();
}

// Export the active menu items (gamemenu for pause/death OR stext for dialog/store)
// to the Godot native UI overlay. Navigation and buy/select actions remain handled
// by D1's own keyboard handling; Godot just renders + forwards input.
Array DiabloBridge::get_current_menu_items() const {
	if (!devilution::IsModalActiveLive()) return {};
	auto items = devilution::GetCurrentMenuItems();
	Array arr;
	for (const auto &it : items) {
		Dictionary d;
		d["text"] = String::utf8(it.text.c_str());
		d["enabled"] = it.enabled;
		d["selectable"] = it.selectable;
		d["price"] = it.price;
		arr.push_back(d);
	}
	return arr;
}

int DiabloBridge::get_modal_selection_index() const {
	if (!devilution::IsModalActiveLive()) return -1;
	return devilution::GetCurrentModalSelectionIndex();
}

int DiabloBridge::get_store_gold() const {
	return devilution::GetBridgeStoreGold();
}

void DiabloBridge::activate_modal_item(int index) {
	// CRASH FIX: enqueue -> engine thread. Inline call runs on Godot's main thread and races
	// with the engine thread's RenderPresent(), corrupting SDL/heap state (malloc corruption).
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ActivateModal, index);
}

void DiabloBridge::select_modal_item(int index) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SelectModal, index);
}

bool DiabloBridge::is_qtext_active() const {
	return devilution::IsQTextActive();
}

Array DiabloBridge::get_qtext_lines() const {
	Array arr;
	auto lines = devilution::GetQTextLines();
	for (const auto &s : lines) {
		arr.push_back(String::utf8(s.c_str()));
	}
	return arr;
}

String DiabloBridge::get_qtext_title() const {
	return String::utf8(devilution::GetQTextTitle().c_str());
}

void DiabloBridge::dismiss_qtext() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::DismissQText);
}

bool DiabloBridge::is_automap_active() const {
	return devilution::IsAutomapActive();
}

Ref<ImageTexture> DiabloBridge::get_automap_texture() const {
	auto data = devilution::GetAutomapRgba();
	if (data.rgba.empty() || data.width <= 0 || data.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(data.rgba.size());
	std::memcpy(pba.ptrw(), data.rgba.data(), data.rgba.size());

	Ref<Image> img = Image::create_from_data(data.width, data.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null() || img->is_empty())
		return Ref<ImageTexture>();

	return ImageTexture::create_from_image(img);
}

Ref<ImageTexture> DiabloBridge::get_spell_icon_texture(int spell_id, int spell_type) {
	std::vector<uint8_t> rgba = devilution::GetSpellIconRgba(spell_id, spell_type);
	if (rgba.empty())
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(rgba.size());
	std::memcpy(pba.ptrw(), rgba.data(), rgba.size());

	Ref<Image> img = Image::create_from_data(56, 56, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	return ImageTexture::create_from_image(img);
}

Ref<ImageTexture> DiabloBridge::get_belt_item_texture(int slot_index) {
	auto icon = devilution::GetBeltItemIconRgba(slot_index);
	if (icon.rgba.empty() || icon.width <= 0 || icon.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(icon.rgba.size());
	std::memcpy(pba.ptrw(), icon.rgba.data(), icon.rgba.size());

	Ref<Image> img = Image::create_from_data(icon.width, icon.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	return ImageTexture::create_from_image(img);
}

bool DiabloBridge::has_hover_item() const {
	return devilution::g_D1EngineData.hasHoverInfo;
}

Dictionary DiabloBridge::get_hover_item_info() const {
	Dictionary d;
	d["has_hover"] = devilution::g_D1EngineData.hasHoverInfo;
	d["name"] = String::utf8(devilution::g_D1EngineData.hoverItemName);
	d["stats"] = String::utf8(devilution::g_D1EngineData.hoverItemStats);
	d["quality"] = devilution::g_D1EngineData.hoverItemQuality;
	d["is_inventory"] = devilution::g_D1EngineData.isInventoryHover;
	d["is_monster"] = devilution::g_D1EngineData.isMonsterHover;
	d["mouse_pos"] = Vector2i(devilution::g_D1EngineData.hoverMouseX, devilution::g_D1EngineData.hoverMouseY);
	return d;
}

Array DiabloBridge::get_available_spells() const {
	Array arr;
	auto spells = devilution::GetAvailableSpells();
	for (const auto &sp : spells) {
		Dictionary d;
		d["id"] = sp.id;
		d["type"] = sp.type;
		d["name"] = String::utf8(sp.name);
		d["mana_cost"] = sp.manaCost;
		d["hotkey"] = String::utf8(sp.hotkey);
		arr.push_back(d);
	}
	return arr;
}

void DiabloBridge::select_spell(int spell_id, int spell_type) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SelectSpell, spell_id, spell_type);
}

Dictionary DiabloBridge::get_potion_summary() const {
	Dictionary d;
	auto sum = devilution::GetPotionSummary();
	d["hp_count"] = sum.hpCount;
	d["hp_best_type"] = sum.hpBestType;
	d["mana_count"] = sum.manaCount;
	d["mana_best_type"] = sum.manaBestType;
	d["rejuv_count"] = sum.rejuvCount;
	d["rejuv_best_type"] = sum.rejuvBestType;
	return d;
}

void DiabloBridge::use_smart_potion(int category) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::UseSmartPotion, category);
}

Dictionary DiabloBridge::get_town_portal_summary() const {
	Dictionary d;
	auto sum = devilution::GetTownPortalSummary();
	d["has_spell"] = sum.hasSpell;
	d["spell_mana_cost"] = sum.spellManaCost;
	d["can_cast_spell"] = sum.canCastSpell;
	d["scroll_count"] = sum.scrollCount;
	d["charge_count"] = sum.chargeCount;
	d["best_mode"] = sum.bestMode;
	return d;
}

void DiabloBridge::use_smart_town_portal() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::UseSmartTownPortal);
}

Dictionary DiabloBridge::get_target_monster_summary(int target_id) const {
	devilution::D1TargetMonsterSummary s = devilution::GetTargetMonsterSummary(target_id);
	Dictionary d;
	d["has_target"] = s.hasTarget;
	d["is_hovered"] = s.isHovered;
	d["monster_id"] = s.monsterId;
	d["name"] = String::utf8(s.name);
	d["hp"] = s.hp;
	d["max_hp"] = s.maxHp;
	d["hp_percent"] = (s.maxHp > 0) ? (static_cast<float>(s.hp) / static_cast<float>(s.maxHp)) : 0.0f;
	d["mode"] = s.mode;
	d["is_unique"] = s.isUnique;
	d["is_champion"] = s.isChampion;
	d["monster_class"] = s.monsterClass;
	d["class_name"] = String::utf8(s.classText);
	d["resists"] = String::utf8(s.resistText);
	d["immunes"] = String::utf8(s.immuneText);
	d["kill_count"] = s.killCount;
	return d;
}

void DiabloBridge::bind_spell_hotkey(int spell_id, int spell_type, int slot_idx) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::BindSpellHotkey, spell_id, spell_type, slot_idx);
}

void DiabloBridge::quick_cast_hotkey(int slot_idx) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::QuickCastHotkey, slot_idx);
}

int DiabloBridge::get_zoom_mode() const {
	return devilution::g_D1EngineData.zoomMode;
}

// ---------------------------------------------------------------------------
// Native Godot Options menu: Music/Sound volume, Gamma, Speed.
// Getters read plain ints (safe from the main thread). Setters are queued to
// the engine thread via PushBridgeAction — audio/palette/tick-rate state must
// never be mutated from Godot's main thread (see Bridge Thread-Safety docs).
// ---------------------------------------------------------------------------

int DiabloBridge::get_music_volume() const {
	return devilution::sound_get_or_set_music_volume(1); // 1 = read-only
}

int DiabloBridge::get_sound_volume() const {
	return devilution::sound_get_or_set_sound_volume(1); // 1 = read-only
}

int DiabloBridge::get_gamma() const {
	return devilution::UpdateGamma(0); // 0 = no-op, returns current gamma (30..100)
}

int DiabloBridge::get_speed() const {
	return devilution::sgGameInitInfo.nTickRate; // ticks per second (20..50)
}

void DiabloBridge::set_music_volume(int volume) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetMusicVolume, volume);
}

void DiabloBridge::set_sound_volume(int volume) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetSoundVolume, volume);
}

void DiabloBridge::set_gamma(int gamma) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetGamma, gamma);
}

void DiabloBridge::set_speed(int tick_rate) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetSpeed, tick_rate);
}

PackedInt32Array DiabloBridge::get_dungeon_grid() const {
	PackedInt32Array grid;
	grid.resize(112 * 112);
	int32_t *w = grid.ptrw();
	devilution::CopyD1DungeonGrid(w, 112 * 112);
	return grid;
}

int DiabloBridge::get_dungeon_tile(int x, int y) const {
	if (x < 0 || x >= 112 || y < 0 || y >= 112) {
		return 0;
	}
	// Direct access can also be queried from grid
	int32_t temp[112 * 112];
	devilution::CopyD1DungeonGrid(temp, 112 * 112);
	return temp[y * 112 + x];
}

int DiabloBridge::get_dungeon_piece_id(int x, int y) const {
	return get_dungeon_tile(x, y);
}

PackedByteArray DiabloBridge::get_dungeon_solidity_grid() const {
	PackedByteArray arr;
	std::vector<uint8_t> grid = devilution::GetDungeonSolidityGrid();
	arr.resize(grid.size());
	if (!grid.empty()) {
		std::memcpy(arr.ptrw(), grid.data(), grid.size());
	}
	return arr;
}

Dictionary DiabloBridge::get_dungeon_piece_data(int piece_id) const {
	Dictionary d;
	devilution::D1TilePieceRgba p = devilution::GetDungeonPieceRgba(piece_id);
	d["width"] = p.width;
	d["height"] = p.height;
	d["num_rows"] = p.numRows;
	PackedByteArray bytes;
	if (!p.rgba.empty()) {
		bytes.resize(p.rgba.size());
		std::memcpy(bytes.ptrw(), p.rgba.data(), p.rgba.size());
	}
	d["rgba"] = bytes;
	return d;
}

Ref<ImageTexture> DiabloBridge::get_dungeon_piece_texture(int piece_id) {
	if (piece_id < 0)
		return Ref<ImageTexture>();

	auto it = piece_texture_cache.find(piece_id);
	if (it != piece_texture_cache.end() && it->second.is_valid())
		return it->second;

	devilution::D1TilePieceRgba p = devilution::GetDungeonPieceRgba(piece_id);
	if (p.rgba.empty() || p.width <= 0 || p.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(p.rgba.size());
	std::memcpy(pba.ptrw(), p.rgba.data(), p.rgba.size());

	Ref<Image> img = Image::create_from_data(p.width, p.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null() || img->is_empty())
		return Ref<ImageTexture>();

	Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
	piece_texture_cache[piece_id] = tex;
	return tex;
}

void DiabloBridge::clear_dungeon_piece_cache() {
	piece_texture_cache.clear();
	special_texture_cache.clear();
}

PackedInt32Array DiabloBridge::get_dungeon_special_grid() const {
	PackedInt32Array arr;
	arr.resize(112 * 112);
	int32_t *w = arr.ptrw();
	devilution::CopyD1SpecialGrid(w, 112 * 112);
	return arr;
}

Dictionary DiabloBridge::get_special_cel_data(int special_id) const {
	Dictionary d;
	devilution::D1SpecialCelRgba s = devilution::GetSpecialCelRgba(special_id);
	d["width"] = s.width;
	d["height"] = s.height;
	PackedByteArray bytes;
	if (!s.rgba.empty()) {
		bytes.resize(s.rgba.size());
		std::memcpy(bytes.ptrw(), s.rgba.data(), s.rgba.size());
	}
	d["rgba"] = bytes;
	return d;
}

Ref<ImageTexture> DiabloBridge::get_special_cel_texture(int special_id) {
	if (special_id <= 0)
		return Ref<ImageTexture>();

	auto it = special_texture_cache.find(special_id);
	if (it != special_texture_cache.end() && it->second.is_valid())
		return it->second;

	devilution::D1SpecialCelRgba s = devilution::GetSpecialCelRgba(special_id);
	if (s.rgba.empty() || s.width <= 0 || s.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(s.rgba.size());
	std::memcpy(pba.ptrw(), s.rgba.data(), s.rgba.size());

	Ref<Image> img = Image::create_from_data(s.width, s.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null() || img->is_empty())
		return Ref<ImageTexture>();

	Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
	special_texture_cache[special_id] = tex;
	return tex;
}

PackedByteArray DiabloBridge::get_dungeon_light_grid() const {
	PackedByteArray arr;
	arr.resize(112 * 112);
	uint8_t *w = arr.ptrw();
	devilution::CopyD1LightGrid(w, 112 * 112);
	return arr;
}

PackedByteArray DiabloBridge::get_dungeon_flags_grid() const {
	PackedByteArray arr;
	arr.resize(112 * 112);
	uint8_t *w = arr.ptrw();
	devilution::CopyD1FlagsGrid(w, 112 * 112);
	return arr;
}

void DiabloBridge::set_zoom_vision_radius(int radius) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetZoomVisionRadius, radius);
}

PackedByteArray DiabloBridge::get_dungeon_trans_grid() const {
	PackedByteArray arr;
	arr.resize(112 * 112);
	uint8_t *w = arr.ptrw();
	devilution::CopyD1TransGrid(w, 112 * 112);
	return arr;
}

PackedByteArray DiabloBridge::get_dungeon_trans_mask() const {
	PackedByteArray arr;
	arr.resize(112 * 112);
	uint8_t *w = arr.ptrw();
	devilution::CopyD1TransparencyMask(w, 112 * 112);
	return arr;
}

PackedByteArray DiabloBridge::get_trans_list() const {
	PackedByteArray arr;
	std::vector<uint8_t> list = devilution::GetTransList();
	arr.resize(list.size());
	if (!list.empty()) {
		std::memcpy(arr.ptrw(), list.data(), list.size());
	}
	return arr;
}

Dictionary DiabloBridge::get_player_continuous_pos() const {
	Dictionary d;
	devilution::D1PlayerEntityData data = devilution::GetPlayerEntityData();
	d["pos_x"] = data.posX;
	d["pos_y"] = data.posY;
	d["tile_x"] = data.tileX;
	d["tile_y"] = data.tileY;
	d["dir"] = data.dir;
	d["is_walking"] = data.isWalking;
	d["mode"] = data.mode;
	d["anim_frame"] = data.animFrame;
	return d;
}

Array DiabloBridge::get_active_monsters_data() const {
	Array arr;
	std::vector<devilution::D1MonsterEntityData> monsters = devilution::GetActiveMonstersData();
	for (const auto &m : monsters) {
		Dictionary md;
		md["id"] = m.id;
		md["name"] = String(m.name);
		md["type"] = m.type;
		md["pos_x"] = m.posX;
		md["pos_y"] = m.posY;
		md["dir"] = m.dir;
		md["hp"] = m.hp;
		md["max_hp"] = m.maxHp;
		md["is_alive"] = m.isAlive;
		md["is_walking"] = m.isWalking;
		md["mode"] = m.mode;
		md["anim_frame"] = m.animFrame;
		md["is_visible"] = m.isVisible;
		arr.push_back(md);
	}
	return arr;
}

Dictionary DiabloBridge::get_player_sprite_data() const {
	Dictionary d;
	devilution::D1SpriteFrameRgba s = devilution::GetPlayerSpriteRgba();
	d["width"] = s.width;
	d["height"] = s.height;
	d["frame"] = s.frame;
	d["dir"] = s.dir;
	PackedByteArray bytes;
	if (!s.rgba.empty()) {
		bytes.resize(s.rgba.size());
		std::memcpy(bytes.ptrw(), s.rgba.data(), s.rgba.size());
	}
	d["rgba"] = bytes;
	return d;
}

Dictionary DiabloBridge::get_monster_sprite_data(int monster_id) const {
	Dictionary d;
	devilution::D1SpriteFrameRgba s = devilution::GetMonsterSpriteRgba(monster_id);
	d["width"] = s.width;
	d["height"] = s.height;
	d["frame"] = s.frame;
	d["dir"] = s.dir;
	PackedByteArray bytes;
	if (!s.rgba.empty()) {
		bytes.resize(s.rgba.size());
		std::memcpy(bytes.ptrw(), s.rgba.data(), s.rgba.size());
	}
	d["rgba"] = bytes;
	return d;
}

void DiabloBridge::send_input(int type, int code, int state, int x, int y) {
	devilution::PushDevilutionXInput(static_cast<uint32_t>(type),
									 static_cast<uint32_t>(code),
									 static_cast<uint32_t>(state),
									 static_cast<int32_t>(x),
									 static_cast<int32_t>(y));
}

void DiabloBridge::send_key_event(int keycode, bool pressed) {
	int sdl_key = keycode;
	if (keycode == 4194305) sdl_key = 27;       // KEY_ESCAPE
	else if (keycode == 4194309) sdl_key = 13;  // KEY_ENTER
	else if (keycode == 4194306) sdl_key = 9;   // KEY_TAB
	else if (keycode == 32) sdl_key = 32;       // KEY_SPACE
	else if (keycode >= 65 && keycode <= 90) sdl_key = keycode + 32; // 'A'..'Z' -> 'a'..'z'
	else if (keycode >= 48 && keycode <= 57) sdl_key = keycode;      // '0'..'9'

	send_input(3, sdl_key, pressed ? 1 : 0, sdl_key, 0);
}

void DiabloBridge::send_click_to_tile(int tile_x, int tile_y, int button_mask) {
	Vector2 world_pos = Vector2(static_cast<float>(tile_x - tile_y) * 32.0f, static_cast<float>(tile_x + tile_y) * 16.0f);
	Vector2i screen_pos = map_world_to_screen(world_pos);
	int btn = (button_mask == 2) ? 3 : 1;
	send_input(2, btn, 1, screen_pos.x, screen_pos.y);
	send_input(2, btn, 0, screen_pos.x, screen_pos.y);
}

PackedByteArray DiabloBridge::get_frame_bytes() {
	PackedByteArray arr;
	int w = devilution::g_D1EngineData.width;
	int h = devilution::g_D1EngineData.height;
	if (w <= 0 || h <= 0) return arr;

	size_t reqSize = static_cast<size_t>(w) * h * 4;
	arr.resize(reqSize);
	uint8_t *dest = arr.ptrw();

	uint32_t outId = 0;
	int outW = 0, outH = 0;
	if (!devilution::CopyD1FrameBytes(dest, reqSize, &outId, &outW, &outH)) {
		arr.clear();
	}
	return arr;
}

int DiabloBridge::get_frame_width() const {
	return devilution::g_D1EngineData.width;
}

int DiabloBridge::get_frame_height() const {
	return devilution::g_D1EngineData.height;
}

int DiabloBridge::get_frame_id() const {
	return devilution::g_D1EngineData.frameId;
}

bool DiabloBridge::update_image_texture(Ref<ImageTexture> p_texture) {
	if (p_texture.is_null()) {
		return false;
	}

	int w = devilution::g_D1EngineData.width;
	int h = devilution::g_D1EngineData.height;
	if (w <= 0 || h <= 0) {
		return false;
	}

	PackedByteArray buffer;
	size_t reqSize = static_cast<size_t>(w) * h * 4;
	buffer.resize(reqSize);
	uint8_t *dest = buffer.ptrw();

	uint32_t outId = 0;
	int outW = 0, outH = 0;
	if (!devilution::CopyD1FrameBytes(dest, reqSize, &outId, &outW, &outH)) {
		return false;
	}

	Ref<Image> img = Image::create_from_data(outW, outH, false, Image::FORMAT_RGBA8, buffer);
	if (img.is_null() || img->is_empty()) {
		return false;
	}

	p_texture->set_image(img);
	return true;
}

Array DiabloBridge::poll_audio_events() {
	devilution::D1AudioEvent events[64];
	size_t count = devilution::PopDevilutionXAudioEvents(events, 64);
	Array result;
	for (size_t i = 0; i < count; ++i) {
		Dictionary d;
		d["type"] = (int)events[i].type; // 1 = MUSIC_PLAY, 2 = MUSIC_STOP, 3 = SFX_PLAY
		d["path"] = String(events[i].path);
		d["volume"] = events[i].volume;
		d["pan"] = events[i].pan;
		d["tile_x"] = events[i].tileX;
		d["tile_y"] = events[i].tileY;
		d["has_pos"] = events[i].hasPos;
		result.push_back(d);
	}
	return result;
}

PackedByteArray DiabloBridge::get_asset_bytes(const String &path) {
	CharString cs = path.utf8();
	std::vector<uint8_t> bytes = devilution::LoadDevilutionXAsset(cs.get_data());
	PackedByteArray pba;
	if (!bytes.empty()) {
		pba.resize(bytes.size());
		std::memcpy(pba.ptrw(), bytes.data(), bytes.size());
	}
	return pba;
}

Ref<AudioStreamWAV> DiabloBridge::load_wav_stream(const String &path, bool loop) {
	PackedByteArray pba = get_asset_bytes(path);
	if (pba.is_empty()) {
		return Ref<AudioStreamWAV>();
	}

	Ref<AudioStreamWAV> stream = AudioStreamWAV::load_from_buffer(pba);
	if (stream.is_valid() && loop) {
		int bytes_per_sample = (stream->get_format() == AudioStreamWAV::FORMAT_16_BITS) ? 2 : 1;
		int channels = stream->is_stereo() ? 2 : 1;
		int frame_size = bytes_per_sample * channels;
		int total_frames = (frame_size > 0) ? (stream->get_data().size() / frame_size) : 0;
		stream->set_loop_mode(AudioStreamWAV::LOOP_FORWARD);
		stream->set_loop_begin(0);
		stream->set_loop_end(total_frames);
	}
	return stream;
}

Array DiabloBridge::get_active_lights() const {
	Array arr;
	auto lights = devilution::GetActiveEngineLights();
	for (const auto &l : lights) {
		Dictionary d;
		d["norm_pos"] = Vector2(l.normX, l.normY);
		float wx = (l.normX - 0.5f) * 16.0f;
		float wy = (0.5f - l.normY) * 9.0f;
		d["world_pos"] = Vector3(wx, wy, 0.55f);
		d["radius"] = l.radius;
		d["type"] = l.type;
		d["tile_x"] = l.tileX;
		d["tile_y"] = l.tileY;
		arr.append(d);
	}
	return arr;
}

Array DiabloBridge::get_wall_occluders() const {
	Array arr;
	auto occluders = devilution::GetActiveWallOccluders();
	for (const auto &o : occluders) {
		float wx = (o.normX - 0.5f) * 16.0f;
		float wy = (0.5f - o.normY) * 9.0f;
		arr.append(Vector3(wx, wy, 0.35f));
	}
	return arr;
}

Array DiabloBridge::poll_visual_events() {
	Array arr;
	auto events = devilution::DrainVisualEvents();
	for (const auto &ev : events) {
		Dictionary d;
		d["type"] = static_cast<int>(ev.type);
		d["norm_pos"] = Vector2(ev.normX, ev.normY);
		float wx = (ev.normX - 0.5f) * 16.0f;
		float wy = (0.5f - ev.normY) * 9.0f;
		d["world_pos"] = Vector3(wx, wy, 0.50f);
		d["tile"] = Vector2i(ev.tileX, ev.tileY);
		d["dir"] = Vector2(ev.dirX, ev.dirY);
		d["intensity"] = ev.intensity;
		arr.append(d);
	}
	return arr;
}

Dictionary DiabloBridge::get_character_info() const {
	Dictionary d;
	auto info = devilution::GetCharacterInfo();
	d["name"] = String::utf8(info.name);
	d["class"] = info.playerClass;
	d["level"] = info.level;
	d["exp"] = info.exp;
	d["next_exp"] = info.nextExp;
	d["gold"] = info.gold;

	d["str_base"] = info.strBase;
	d["str_now"] = info.strNow;
	d["str_max"] = info.strMax;

	d["mag_base"] = info.magBase;
	d["mag_now"] = info.magNow;
	d["mag_max"] = info.magMax;

	d["dex_base"] = info.dexBase;
	d["dex_now"] = info.dexNow;
	d["dex_max"] = info.dexMax;

	d["vit_base"] = info.vitBase;
	d["vit_now"] = info.vitNow;
	d["vit_max"] = info.vitMax;

	d["stat_pts"] = info.statPts;

	d["hp"] = info.hp;
	d["max_hp"] = info.maxHp;
	d["mana"] = info.mana;
	d["max_mana"] = info.maxMana;

	d["armor"] = info.armor;
	d["to_hit"] = info.toHit;
	d["dmg_min"] = info.dmgMin;
	d["dmg_max"] = info.dmgMax;

	d["res_magic"] = info.resMagic;
	d["res_fire"] = info.resFire;
	d["res_lightning"] = info.resLightning;

	return d;
}

void DiabloBridge::add_attribute_point(int attr_idx) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::AddAttributePoint, attr_idx);
}

bool DiabloBridge::is_character_open() const {
	return devilution::IsCharacterSheetOpen();
}

void DiabloBridge::toggle_character_sheet() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ToggleCharacterSheet);
}

Array DiabloBridge::get_quests_info() const {
	Array arr;
	auto list = devilution::GetQuestsInfo();
	for (const auto &qe : list) {
		Dictionary q;
		q["id"] = qe.idx;
		q["idx"] = qe.idx;
		q["name"] = String::utf8(qe.name);
		q["is_finished"] = qe.isFinished;
		q["isFinished"] = qe.isFinished;
		q["level"] = qe.level;
		q["state"] = qe.isFinished ? 3 : 2;
		arr.push_back(q);
	}
	return arr;
}

void DiabloBridge::select_quest(int quest_idx) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SelectQuest, quest_idx);
}

bool DiabloBridge::is_quest_log_open() const {
	return devilution::IsQuestLogOpen();
}

void DiabloBridge::toggle_quest_log() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ToggleQuestLog);
}

bool DiabloBridge::is_inventory_open() const {
	return devilution::IsInventoryOpen();
}

void DiabloBridge::toggle_inventory() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ToggleInventory);
}

void DiabloBridge::set_active_ui_panel(int panel) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetActiveUiPanel, panel);
}

void DiabloBridge::close_all_ui_panels() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::CloseAllUiPanels);
}

int DiabloBridge::get_active_ui_panel() const {
	return devilution::GetActiveUiPanel();
}


static Dictionary InvDataToDict(const devilution::D1InvItemData &item) {
	Dictionary d;
	d["slot_id"] = item.slotId;
	d["type"] = item.type;
	d["curs"] = item.curs;
	d["curs_id"] = item.cursId;
	d["quality"] = item.quality;
	d["name"] = String::utf8(item.name);
	d["stats"] = String::utf8(item.stats);
	d["cell_x"] = item.cellX;
	d["cell_y"] = item.cellY;
	d["cell_w"] = item.cellW;
	d["cell_h"] = item.cellH;
	d["can_use"] = item.canUse;
	d["is_identified"] = item.isIdentified;
	d["durability"] = item.durability;
	d["max_durability"] = item.maxDurability;
	d["value"] = item.value;
	d["inv_list_index"] = item.invListIndex;
	return d;
}

int DiabloBridge::get_inventory_version() const {
	return static_cast<int>(devilution::GetInventoryVersion());
}

Array DiabloBridge::get_player_equipment() const {
	Array arr;
	auto eq = devilution::GetPlayerEquipmentData();
	for (const auto &item : eq) {
		arr.push_back(InvDataToDict(item));
	}
	return arr;
}

Array DiabloBridge::get_player_backpack() const {
	Array arr;
	auto bp = devilution::GetPlayerBackpackData();
	for (const auto &item : bp) {
		arr.push_back(InvDataToDict(item));
	}
	return arr;
}

Dictionary DiabloBridge::get_player_hold_item() const {
	auto hold = devilution::GetPlayerHoldItemData();
	if (hold.cursId <= 0)
		return Dictionary();
	return InvDataToDict(hold);
}

Ref<ImageTexture> DiabloBridge::get_item_texture(int curs_id) {
	if (curs_id <= 0)
		return Ref<ImageTexture>();

	auto it = item_texture_cache.find(curs_id);
	if (it != item_texture_cache.end() && it->second.is_valid())
		return it->second;

	auto icon = devilution::GetItemSpriteRgba(curs_id);
	if (icon.rgba.empty() || icon.width <= 0 || icon.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(icon.rgba.size());
	std::memcpy(pba.ptrw(), icon.rgba.data(), icon.rgba.size());

	Ref<Image> img = Image::create_from_data(icon.width, icon.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	// Upscale 4X with nearest-neighbor to match 4X HD cell dimensions (28x28 -> 112x112, 28x84 -> 112x336, 56x84 -> 224x336)
	img->resize(icon.width * 4, icon.height * 4, Image::INTERPOLATE_NEAREST);

	Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
	item_texture_cache[curs_id] = tex;
	return tex;
}

void DiabloBridge::click_inventory_slot(int slot_type, int slot_idx, bool is_shift, bool is_ctrl) {
	// bool args encoded as 0/1; drained on the engine thread each frame.
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ClickInventorySlot, slot_type, slot_idx, is_shift ? 1 : 0, is_ctrl ? 1 : 0);
}

void DiabloBridge::use_inventory_slot(int slot_type, int slot_idx) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::UseInventorySlot, slot_type, slot_idx);
}

int DiabloBridge::get_cursor_id() const {
	return devilution::GetCurrentCursorId();
}

void DiabloBridge::cancel_targeting_cursor() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::CancelTargetingCursor);
}

Ref<ImageTexture> DiabloBridge::get_cursor_texture(int curs_id) {
	if (curs_id <= 0)
		return Ref<ImageTexture>();

	auto it = cursor_texture_cache.find(curs_id);
	if (it != cursor_texture_cache.end() && it->second.is_valid())
		return it->second;

	auto icon = devilution::GetItemSpriteRgba(curs_id);
	if (icon.rgba.empty() || icon.width <= 0 || icon.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(icon.rgba.size());
	std::memcpy(pba.ptrw(), icon.rgba.data(), icon.rgba.size());

	Ref<Image> img = Image::create_from_data(icon.width, icon.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	// 2X scale for crisp, appropriately sized custom OS mouse cursor
	img->resize(icon.width * 2, icon.height * 2, Image::INTERPOLATE_NEAREST);

	Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
	cursor_texture_cache[curs_id] = tex;
	return tex;
}

Array DiabloBridge::get_player_durability_warnings() const {
	Array arr;
	auto warnings = devilution::GetPlayerDurabilityWarnings();
	for (const auto &w : warnings) {
		Dictionary d;
		d["slot_id"] = w.slotId;
		d["icon_idx"] = w.iconIdx;
		d["frame_idx"] = w.frameIdx;
		d["durability"] = w.durability;
		d["max_durability"] = w.maxDurability;
		d["status"] = w.status;
		d["name"] = String::utf8(w.name);
		arr.push_back(d);
	}
	return arr;
}

Ref<ImageTexture> DiabloBridge::get_durability_icon(int frame_idx) {
	if (frame_idx < 0 || frame_idx >= 16)
		return Ref<ImageTexture>();

	auto it = durability_texture_cache.find(frame_idx);
	if (it != durability_texture_cache.end() && it->second.is_valid())
		return it->second;

	auto icon = devilution::GetDurabilityIconRgba(frame_idx);
	if (icon.rgba.empty() || icon.width <= 0 || icon.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(icon.rgba.size());
	std::memcpy(pba.ptrw(), icon.rgba.data(), icon.rgba.size());

	Ref<Image> img = Image::create_from_data(icon.width, icon.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
	durability_texture_cache[frame_idx] = tex;
	return tex;
}

Ref<ImageTexture> DiabloBridge::get_durability_icon_composite(int icon_idx, int durability) {
	if (icon_idx < 0 || icon_idx >= 8)
		return Ref<ImageTexture>();

	int clamped_dur = std::clamp(durability, 0, 5);
	int cache_key = 100 + icon_idx * 10 + clamped_dur;

	auto it = durability_texture_cache.find(cache_key);
	if (it != durability_texture_cache.end() && it->second.is_valid())
		return it->second;

	auto icon = devilution::GetDurabilityCompositeIconRgba(icon_idx, clamped_dur);
	if (icon.rgba.empty() || icon.width <= 0 || icon.height <= 0)
		return Ref<ImageTexture>();

	PackedByteArray pba;
	pba.resize(icon.rgba.size());
	std::memcpy(pba.ptrw(), icon.rgba.data(), icon.rgba.size());

	Ref<Image> img = Image::create_from_data(icon.width, icon.height, false, Image::FORMAT_RGBA8, pba);
	if (img.is_null())
		return Ref<ImageTexture>();

	Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
	durability_texture_cache[cache_key] = tex;
	return tex;
}

Array DiabloBridge::get_active_objects() const {
	Array arr;
	auto list = devilution::GetActiveObjectsList();
	for (const auto &obj : list) {
		Dictionary d;
		d["id"] = obj.id;
		d["type"] = obj.type;
		d["tile_x"] = obj.tileX;
		d["tile_y"] = obj.tileY;
		d["anim_frame"] = obj.animFrame;
		d["anim_total"] = obj.animTotal;
		d["pre_flag"] = obj.preFlag;
		d["solid"] = obj.solid;
		d["selectable"] = obj.selectable;
		d["width"] = obj.width;
		d["height"] = obj.height;
		arr.push_back(d);
	}
	return arr;
}

Dictionary DiabloBridge::get_object_sprite_data(int object_id) const {
	Dictionary d;
	auto data = devilution::GetObjectSpriteRgba(object_id);
	d["width"] = data.width;
	d["height"] = data.height;
	PackedByteArray pba;
	pba.resize(data.rgba.size());
	if (!data.rgba.empty()) {
		std::memcpy(pba.ptrw(), data.rgba.data(), data.rgba.size());
	}
	d["rgba"] = pba;
	return d;
}

Array DiabloBridge::get_active_items() const {
	Array arr;
	auto list = devilution::GetActiveItemsList();
	for (const auto &item : list) {
		Dictionary d;
		d["id"] = item.id;
		d["tile_x"] = item.tileX;
		d["tile_y"] = item.tileY;
		d["curs_id"] = item.cursId;
		d["quality"] = item.quality;
		d["identified"] = item.identified;
		d["name"] = String::utf8(item.name);
		d["width"] = item.width;
		d["height"] = item.height;
		d["anim_frame"] = item.animFrame;
		arr.push_back(d);
	}
	return arr;
}

Dictionary DiabloBridge::get_ground_item_sprite_data(int item_id) const {
	Dictionary d;
	auto data = devilution::GetGroundItemSpriteRgba(item_id);
	d["width"] = data.width;
	d["height"] = data.height;
	PackedByteArray pba;
	pba.resize(data.rgba.size());
	if (!data.rgba.empty()) {
		std::memcpy(pba.ptrw(), data.rgba.data(), data.rgba.size());
	}
	d["rgba"] = pba;
	return d;
}

bool DiabloBridge::is_item_label_highlight_enabled() const {
	return devilution::IsItemLabelHighlightEnabled();
}

Array DiabloBridge::get_active_corpses() const {
	Array arr;
	auto list = devilution::GetActiveCorpsesList();
	for (const auto &corpse : list) {
		Dictionary d;
		d["tile_x"] = corpse.tileX;
		d["tile_y"] = corpse.tileY;
		d["corpse_idx"] = corpse.corpseIdx;
		d["dir"] = corpse.dir;
		d["frame"] = corpse.frame;
		d["width"] = corpse.width;
		d["height"] = corpse.height;
		d["monster_name"] = String(corpse.monsterName);
		arr.push_back(d);
	}
	return arr;
}

Dictionary DiabloBridge::get_corpse_sprite_data(int corpse_idx, int dir) const {
	Dictionary d;
	auto data = devilution::GetCorpseSpriteRgba(corpse_idx, dir);
	d["width"] = data.width;
	d["height"] = data.height;
	PackedByteArray pba;
	pba.resize(data.rgba.size());
	if (!data.rgba.empty()) {
		std::memcpy(pba.ptrw(), data.rgba.data(), data.rgba.size());
	}
	d["rgba"] = pba;
	return d;
}

Vector2i DiabloBridge::map_world_to_screen(const Vector2 &world_pos) const {
	devilution::Point p = devilution::MapIsometricToScreenCoords(world_pos.x, world_pos.y);
	return Vector2i(p.x, p.y);
}

Array DiabloBridge::get_active_missiles() const {
	Array arr;
	auto list = devilution::GetActiveMissilesList();
	for (const auto &m : list) {
		Dictionary d;
		d["id"] = m.id;
		d["type"] = m.type;
		d["dir"] = m.dir;
		d["pos_x"] = m.posX;
		d["pos_y"] = m.posY;
		d["tile_x"] = m.tileX;
		d["tile_y"] = m.tileY;
		d["anim_frame"] = m.animFrame;
		d["width"] = m.width;
		d["height"] = m.height;
		d["light_flag"] = m.lightFlag;
		d["pre_flag"] = m.preFlag;
		arr.push_back(d);
	}
	return arr;
}

Dictionary DiabloBridge::get_missile_sprite_data(int missile_id) const {
	Dictionary d;
	auto data = devilution::GetMissileSpriteRgba(missile_id);
	d["width"] = data.width;
	d["height"] = data.height;
	PackedByteArray pba;
	pba.resize(data.rgba.size());
	if (!data.rgba.empty()) {
		std::memcpy(pba.ptrw(), data.rgba.data(), data.rgba.size());
	}
	d["rgba"] = pba;
	return d;
}

// Native Godot Diablo IV Stash
bool DiabloBridge::is_stash_open() const {
	return devilution::IsBridgeStashOpen();
}

void DiabloBridge::close_stash() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::CloseStash);
}

Dictionary DiabloBridge::get_stash_info() const {
	Dictionary d;
	auto info = devilution::GetStashInfo();
	d["page"] = info.page;
	d["total_pages"] = info.totalPages;
	d["gold"] = info.gold;
	return d;
}

Array DiabloBridge::get_stash_items() const {
	Array arr;
	auto items = devilution::GetStashItems();
	for (const auto &item : items) {
		arr.push_back(InvDataToDict(item));
	}
	return arr;
}

void DiabloBridge::stash_change_page(int delta) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::StashChangePage, delta);
}

void DiabloBridge::stash_set_page(int page) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::StashSetPage, page);
}

void DiabloBridge::click_stash_slot(int cell_idx, bool is_shift, bool is_ctrl) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ClickStashSlot, cell_idx, is_shift ? 1 : 0, is_ctrl ? 1 : 0);
}

void DiabloBridge::stash_withdraw_gold(int amount) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::StashWithdrawGold, amount);
}

// Native Godot Diablo IV SpellBook
bool DiabloBridge::is_spell_book_open() const {
	return devilution::IsSpellBookOpen();
}

void DiabloBridge::toggle_spell_book() {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::ToggleSpellBook);
}

int DiabloBridge::get_spell_book_page() const {
	return devilution::GetSpellBookPage();
}

void DiabloBridge::set_spell_book_page(int page) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SetSpellBookPage, page);
}

Array DiabloBridge::get_spell_book_entries() const {
	Array arr;
	auto entries = devilution::GetSpellBookEntries();
	for (const auto &e : entries) {
		Dictionary d;
		d["spell_id"] = e.spellId;
		d["spell_type"] = e.spellType;
		d["name"] = String::utf8(e.name.c_str());
		d["type_text"] = String::utf8(e.typeText.c_str());
		d["level"] = e.level;
		d["mana"] = e.mana;
		d["detail"] = String::utf8(e.detail.c_str());
		d["is_equipped"] = e.isEquipped;
		d["can_cast"] = e.canCast;
		arr.push_back(d);
	}
	return arr;
}

void DiabloBridge::select_spell_book_entry(int spell_id, int spell_type) {
	devilution::PushBridgeAction(devilution::D1BridgeActionType::SelectSpellBookEntry, spell_id, spell_type);
}

// -----------------------------------------------------------------------------
// Native Godot Menu Bridge Implementations
// -----------------------------------------------------------------------------
int DiabloBridge::get_menu_mode() const {
	return static_cast<int>(devilution::GetBridgeMenuMode());
}

bool DiabloBridge::is_hellfire() const {
	return devilution::IsHellfireMode();
}

bool DiabloBridge::is_class_allowed(int hero_class) const {
	return devilution::IsClassAllowed(hero_class);
}

Array DiabloBridge::get_allowed_classes() const {
	Array result;
	for (int c = 0; c < 6; ++c) {
		if (devilution::IsClassAllowed(c)) {
			result.push_back(c);
		}
	}
	return result;
}

String DiabloBridge::get_language_code() const {
	return String::utf8(devilution::GetBridgeLanguageCode().c_str());
}

void DiabloBridge::menu_select_single_player() {
	devilution::BridgeSelectSinglePlayer();
}

void DiabloBridge::menu_select_multiplayer() {
	devilution::BridgeSelectMultiplayer();
}

void DiabloBridge::menu_show_credits() {
	devilution::BridgeShowCredits();
}

void DiabloBridge::menu_exit_game() {
	devilution::BridgeExitGame();
}

Array DiabloBridge::get_hero_list() const {
	Array result;
	auto heroes = devilution::GetBridgeHeroList();
	static const char *const classNames[] = {
		"Warrior", "Rogue", "Sorcerer", "Monk", "Bard", "Barbarian"
	};
	for (const auto &h : heroes) {
		Dictionary d;
		d["save_num"] = static_cast<int>(h.saveNumber);
		d["name"] = String::utf8(h.name);
		d["level"] = static_cast<int>(h.level);
		d["class_id"] = h.heroClass;
		int c = std::max(0, std::min(5, h.heroClass));
		d["class_name"] = String::utf8(classNames[c]);
		d["rank"] = static_cast<int>(h.heroRank);
		d["strength"] = static_cast<int>(h.strength);
		d["magic"] = static_cast<int>(h.magic);
		d["dexterity"] = static_cast<int>(h.dexterity);
		d["vitality"] = static_cast<int>(h.vitality);
		d["has_saved"] = h.hasSaved;
		result.push_back(d);
	}
	return result;
}

Dictionary DiabloBridge::get_class_base_stats(int hero_class) const {
	Dictionary d;
	auto stats = devilution::GetBridgeClassStats(hero_class);
	d["strength"] = static_cast<int>(stats.strength);
	d["magic"] = static_cast<int>(stats.magic);
	d["dexterity"] = static_cast<int>(stats.dexterity);
	d["vitality"] = static_cast<int>(stats.vitality);
	return d;
}

String DiabloBridge::get_random_hero_name(int hero_class) const {
	return String::utf8(devilution::GetBridgeRandomName(hero_class).c_str());
}

bool DiabloBridge::create_hero(const String &name, int hero_class) {
	CharString cs = name.utf8();
	return devilution::BridgeCreateHero(cs.get_data(), hero_class);
}

bool DiabloBridge::delete_hero(int save_num) {
	return devilution::BridgeDeleteHero(static_cast<uint32_t>(save_num));
}

void DiabloBridge::launch_hero_game(int save_num, int difficulty, bool load_saved) {
	devilution::BridgeLaunchHero(static_cast<uint32_t>(save_num), difficulty, load_saved);
}

void DiabloBridge::cancel_hero_select() {
	devilution::BridgeCancelHeroSelect();
}

Array DiabloBridge::get_settings_categories() const {
	Array result;
	auto cats = devilution::GetBridgeSettingsCategories();
	for (const auto &c : cats) {
		Dictionary d;
		d["id"] = c.id;
		d["name"] = String::utf8(c.name.c_str());
		d["description"] = String::utf8(c.description.c_str());
		result.push_back(d);
	}
	return result;
}

Array DiabloBridge::get_settings_entries(int category_id) const {
	Array result;
	auto entries = devilution::GetBridgeSettingsEntries(category_id);
	for (const auto &e : entries) {
		Dictionary d;
		d["id"] = e.id;
		d["category_id"] = e.categoryId;
		d["name"] = String::utf8(e.name.c_str());
		d["description"] = String::utf8(e.description.c_str());
		d["type"] = e.type;
		d["value_str"] = String::utf8(e.valueStr.c_str());
		d["bool_val"] = e.boolValue;
		d["list_index"] = e.listIndex;
		Array opts;
		for (const auto &opt : e.listOptions) {
			opts.push_back(String::utf8(opt.c_str()));
		}
		d["list_options"] = opts;
		result.push_back(d);
	}
	return result;
}

void DiabloBridge::set_setting_bool(int category_id, int entry_id, bool value) {
	devilution::SetBridgeSettingBool(category_id, entry_id, value);
}

void DiabloBridge::set_setting_list(int category_id, int entry_id, int list_index) {
	devilution::SetBridgeSettingList(category_id, entry_id, list_index);
}

void DiabloBridge::save_settings() {
	devilution::SaveBridgeSettings();
}

bool DiabloBridge::get_vsync_enabled() const {
	return devilution::GetVsyncEnabled();
}

bool DiabloBridge::get_show_fps() const {
	return devilution::GetShowFpsEnabled();
}

int DiabloBridge::get_resurrected_display_mode() const {
	return devilution::GetResurrectedDisplayMode();
}

int DiabloBridge::get_mode_switch_key() const {
	return devilution::GetModeSwitchKey();
}

int DiabloBridge::get_mode_switch_mods() const {
	return static_cast<int>(devilution::GetModeSwitchMods());
}

void DiabloBridge::set_mode_switch_binding(int key, int mods) {
	devilution::SetModeSwitchBinding(key, static_cast<uint8_t>(mods));
}

bool DiabloBridge::get_resurrected_torchlight() const {
	return devilution::GetResurrectedTorchlight();
}

int DiabloBridge::get_resurrected_fog_level() const {
	return devilution::GetResurrectedFogLevel();
}

int DiabloBridge::get_resurrected_color_profile() const {
	return devilution::GetResurrectedColorProfile();
}

int DiabloBridge::get_resurrected_hdr_level() const {
	return devilution::GetResurrectedHdrLevel();
}

int DiabloBridge::get_resurrected_upscaler_mode() const {
	return devilution::GetResurrectedUpscalerMode();
}

int DiabloBridge::get_resurrected_relief_mode() const {
	return devilution::GetResurrectedReliefMode();
}

int DiabloBridge::get_d1de_display_mode() const {
	return get_resurrected_display_mode();
}

bool DiabloBridge::get_d1de_torchlight() const {
	return get_resurrected_torchlight();
}

int DiabloBridge::get_d1de_fog_level() const {
	return get_resurrected_fog_level();
}

int DiabloBridge::get_d1de_color_profile() const {
	return get_resurrected_color_profile();
}

int DiabloBridge::get_d1de_hdr_level() const {
	return get_resurrected_hdr_level();
}

int DiabloBridge::get_d1de_upscaler_mode() const {
	return get_resurrected_upscaler_mode();
}

int DiabloBridge::get_d1de_relief_mode() const {
	return get_resurrected_relief_mode();
}

bool DiabloBridge::get_d1de_wet_floor() const {
	return get_resurrected_wet_floor();
}

bool DiabloBridge::get_resurrected_wet_floor() const {
	return devilution::GetResurrectedWetFloor();
}

int DiabloBridge::get_resurrected_tile_model() const {
	return devilution::GetResurrectedTileModel();
}

void DiabloBridge::set_resurrected_tile_model(int model) {
	devilution::SetResurrectedTileModel(model);
}

int DiabloBridge::get_d1de_tile_model() const {
	return get_resurrected_tile_model();
}

void DiabloBridge::set_d1de_tile_model(int model) {
	set_resurrected_tile_model(model);
}

