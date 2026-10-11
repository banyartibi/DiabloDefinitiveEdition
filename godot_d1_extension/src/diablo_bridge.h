#ifndef DIABLO_BRIDGE_H
#define DIABLO_BRIDGE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <unordered_map>

namespace godot {

class DiabloBridge : public Node {
	GDCLASS(DiabloBridge, Node)

private:
	bool engine_started = false;
	mutable std::unordered_map<int, Ref<ImageTexture>> item_texture_cache;
	mutable std::unordered_map<int, Ref<ImageTexture>> piece_texture_cache;
	mutable std::unordered_map<int, Ref<ImageTexture>> special_texture_cache;
	mutable std::unordered_map<int, Ref<ImageTexture>> durability_texture_cache;
	mutable std::unordered_map<int, Ref<ImageTexture>> cursor_texture_cache;

protected:
	static void _bind_methods();

public:
	DiabloBridge();
	~DiabloBridge();

	// Engine Lifecycle
	bool init_engine(const String &mpq_dir);
	void step_tick();
	bool is_engine_ready() const;
	bool is_engine_running() const;
	bool is_quit_requested() const;
	void quit_engine();

	// Real-Time Direct Memory Access (Zero IPC, pure C++ memory pointers!)
	Vector2i get_player_tile_pos() const;
	Vector2 get_player_norm_pos() const;
	int get_player_hp() const;
	int get_player_max_hp() const;
	int get_player_mana() const;
	int get_player_max_mana() const;
	int get_player_gold() const;
	int get_player_class() const;
	int get_current_level() const;
	int get_dungeon_type() const;
	bool is_left_panel_open() const;
	bool is_right_panel_open() const;
	Rect2 get_left_panel_rect() const;
	Rect2 get_right_panel_rect() const;
	bool is_speedbook_open() const;
	Rect2 get_speedbook_rect() const;
	int get_player_level() const;
	int get_player_xp() const;
	int get_player_next_xp() const;
	int get_player_spell() const;
	int get_player_spell_type() const;
	Array get_belt_items() const;
	void use_belt_slot(int slot_index);
	void click_belt_slot(int slot_index);
	void set_vanilla_hud_hidden(bool hidden);
	bool is_vanilla_hud_hidden() const;
	bool is_game_running() const;
	bool is_level_loading() const;
	bool is_modal_active() const;
	bool is_text_input_active() const;
	bool is_player_dead() const;
	int get_modal_type() const;
	// Native modal overlay data for pause/gamemenu and dialog/store menus.
	Array get_current_menu_items() const; // [{"text", "enabled", "selectable", "price"}] for the active menu
	int get_modal_selection_index() const; // visible selected row index (-1 none)
	int get_store_gold() const; // Player's gold amount in store (-1 if not rendering gold)
	void activate_modal_item(int index);
	void select_modal_item(int index);
	bool is_qtext_active() const;
	Array get_qtext_lines() const;
	String get_qtext_title() const;
	void dismiss_qtext();
	bool is_automap_active() const;
	Ref<ImageTexture> get_automap_texture() const;
	Ref<ImageTexture> get_spell_icon_texture(int spell_id, int spell_type);
	Ref<ImageTexture> get_belt_item_texture(int slot_index);
	bool has_hover_item() const;
	Dictionary get_hover_item_info() const;
	Array get_available_spells() const;
	void select_spell(int spell_id, int spell_type);
	Dictionary get_potion_summary() const;
	void use_smart_potion(int category);
	Dictionary get_town_portal_summary() const;
	void use_smart_town_portal();
	Dictionary get_target_monster_summary(int target_id = -1) const;
	void bind_spell_hotkey(int spell_id, int spell_type, int slot_idx);
	void quick_cast_hotkey(int slot_idx);
	int get_zoom_mode() const;

	// Native Godot Options menu (Music/Sound/Gamma/Speed).
	// Getters return raw D1 units; setters are queued to the engine thread.
	int get_music_volume() const;  // -1600..0 (-1600 = mute, 0 = max)
	int get_sound_volume() const;  // -1600..0
	int get_gamma() const;         // 30..100 (vanilla slider range)
	int get_speed() const;         // ticks per second: 20..50
	void set_music_volume(int volume);
	void set_sound_volume(int volume);
	void set_gamma(int gamma);
	void set_speed(int tick_rate);

	// Native Godot Diablo IV Character Sheet & Quest Log
	Dictionary get_character_info() const;
	void add_attribute_point(int attr_idx);
	bool is_character_open() const;
	void toggle_character_sheet();

	Array get_quests_info() const;
	void select_quest(int quest_idx);
	bool is_quest_log_open() const;
	void toggle_quest_log();

	bool is_inventory_open() const;
	void toggle_inventory();
	void set_active_ui_panel(int panel);
	void close_all_ui_panels();
	int get_active_ui_panel() const;

	// Native Godot Diablo IV Inventory
	int get_inventory_version() const;
	Array get_player_equipment() const;
	Array get_player_backpack() const;
	Dictionary get_player_hold_item() const;
	Ref<ImageTexture> get_item_texture(int curs_id);
	void click_inventory_slot(int slot_type, int slot_idx, bool is_shift = false, bool is_ctrl = false);
	void use_inventory_slot(int slot_type, int slot_idx);
	int get_cursor_id() const;
	void cancel_targeting_cursor();
	Ref<ImageTexture> get_cursor_texture(int curs_id);
	Array get_player_durability_warnings() const;
	Ref<ImageTexture> get_durability_icon(int frame_idx);
	Ref<ImageTexture> get_durability_icon_composite(int icon_idx, int durability);

	// Native Godot Diablo IV Stash
	bool is_stash_open() const;
	void close_stash();
	Dictionary get_stash_info() const;
	Array get_stash_items() const;
	void stash_change_page(int delta);
	void stash_set_page(int page);
	void click_stash_slot(int cell_idx, bool is_shift = false, bool is_ctrl = false);
	void stash_withdraw_gold(int amount);

	// Native Godot Diablo IV SpellBook
	bool is_spell_book_open() const;
	void toggle_spell_book();
	int get_spell_book_page() const;
	void set_spell_book_page(int page);
	Array get_spell_book_entries() const;
	void select_spell_book_entry(int spell_id, int spell_type);

	// Native Godot Menu Bridge (Main Menu, Character Select, New Hero)
	int get_menu_mode() const; // 0 = None, 1 = MainMenu, 2 = CharacterSelect
	bool is_hellfire() const;
	bool is_class_allowed(int hero_class) const;
	Array get_allowed_classes() const;
	String get_language_code() const;
	void menu_select_single_player();
	void menu_select_multiplayer();
	void menu_show_credits();
	void menu_exit_game();
	Array get_hero_list() const;
	Dictionary get_class_base_stats(int hero_class) const;
	String get_random_hero_name(int hero_class) const;
	bool create_hero(const String &name, int hero_class);
	bool delete_hero(int save_num);
	void launch_hero_game(int save_num, int difficulty, bool load_saved);
	void cancel_hero_select();

	// Native Godot Full DevilutionX Settings Bridge
	Array get_settings_categories() const;
	Array get_settings_entries(int category_id) const;
	void set_setting_bool(int category_id, int entry_id, bool value);
	void set_setting_list(int category_id, int entry_id, int list_index);
	void save_settings();

	// V-Sync & Show FPS state (Graphics category) for the Godot host window.
	bool get_vsync_enabled() const;
	bool get_show_fps() const;

	// Definitive Edition (D1DE) display mode + rebindable mode-switch hotkey binding.
	int get_d1de_display_mode() const;
	int get_resurrected_display_mode() const;
	int get_mode_switch_key() const;
	int get_mode_switch_mods() const;
	void set_mode_switch_binding(int key, int mods);

	// Definitive Edition (D1DE) display effect states (Mode 0), polled by the Godot side.
	bool get_d1de_torchlight() const;
	int get_d1de_fog_level() const;
	int get_d1de_color_profile() const;
	int get_d1de_hdr_level() const;
	int get_d1de_upscaler_mode() const;
	int get_d1de_relief_mode() const;
	bool get_d1de_wet_floor() const;
	int get_d1de_tile_model() const;
	void set_d1de_tile_model(int model);

	// Backward-compatibility aliases
	bool get_resurrected_torchlight() const;
	int get_resurrected_fog_level() const;
	int get_resurrected_color_profile() const;
	int get_resurrected_hdr_level() const;
	int get_resurrected_upscaler_mode() const;
	int get_resurrected_relief_mode() const;
	bool get_resurrected_wet_floor() const;
	int get_resurrected_tile_model() const;
	void set_resurrected_tile_model(int model);

	// Direct 112x112 Dungeon Grid Access for Godot TileMap / GridMap
	PackedInt32Array get_dungeon_grid() const;
	int get_dungeon_tile(int x, int y) const;
	int get_dungeon_piece_id(int x, int y) const;
	PackedByteArray get_dungeon_solidity_grid() const;

	// Native Godot 2.5D Tile Piece Extraction & Caching
	Dictionary get_dungeon_piece_data(int piece_id) const;
	Ref<ImageTexture> get_dungeon_piece_texture(int piece_id);
	void clear_dungeon_piece_cache();

	// Special CELs (Archways, Column Tops, Doorways)
	PackedInt32Array get_dungeon_special_grid() const;
	Dictionary get_special_cel_data(int special_id) const;
	Ref<ImageTexture> get_special_cel_texture(int special_id);

	// Per-Tile Lighting & Transparency (Fog of War & Room Transparency)
	PackedByteArray get_dungeon_light_grid() const;
	PackedByteArray get_dungeon_flags_grid() const;
	PackedByteArray get_dungeon_trans_grid() const;
	PackedByteArray get_dungeon_trans_mask() const;
	PackedByteArray get_trans_list() const;
	void set_zoom_vision_radius(int radius);

	// Native Godot 2.5D Dungeon Objects (Torches, Barrels, Chests, Shrines)
	Array get_active_objects() const;
	Dictionary get_object_sprite_data(int object_id) const;

	// Native Godot 2.5D Ground Items & Loot
	Array get_active_items() const;
	Dictionary get_ground_item_sprite_data(int item_id) const;
	bool is_item_label_highlight_enabled() const;

	// Native Godot 2.5D Corpses & Fallen Monsters
	Array get_active_corpses() const;
	Dictionary get_corpse_sprite_data(int corpse_idx, int dir) const;

	// Coordinate Mapping
	Vector2i map_world_to_screen(const Vector2 &world_pos) const;

	// Native Godot 2.5D Missiles & Spell Projectiles
	Array get_active_missiles() const;
	Dictionary get_missile_sprite_data(int missile_id) const;

	// Native 3D World & Entity Tracking
	Dictionary get_player_continuous_pos() const;
	Array get_active_monsters_data() const;
	Dictionary get_player_sprite_data() const;
	Dictionary get_monster_sprite_data(int monster_id) const;

	// Direct Input Routing (In-memory C++ event dispatch, no SHM!)
	void send_input(int type, int code, int state, int x, int y);
	void send_key_event(int keycode, bool pressed);
	void send_click_to_tile(int tile_x, int tile_y, int button_mask = 1);

	// Direct Video Frame Access (In-memory blit directly to Godot Image)
	PackedByteArray get_frame_bytes();
	int get_frame_width() const;
	int get_frame_height() const;
	int get_frame_id() const;
	bool update_image_texture(Ref<ImageTexture> p_texture);

	// Audio & Asset Interception
	Array poll_audio_events();
	PackedByteArray get_asset_bytes(const String &path);
	Ref<AudioStreamWAV> load_wav_stream(const String &path, bool loop = false);

	// Native Godot 3D Lighting, Shadows & GPUParticles
	Array get_active_lights() const;
	Array get_wall_occluders() const;
	Array poll_visual_events();
};

} // namespace godot

#endif // DIABLO_BRIDGE_H
