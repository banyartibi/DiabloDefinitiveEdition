#!/usr/bin/env python3
import sys

def build_hud():
    with open("godot_d1_3d/scenes/hud/d1de_hud.tscn", "r") as f:
        content = f.read()

    # 1. Update load_steps and ext_resources
    lines = content.splitlines()
    header_lines = []
    rest_lines = []
    
    in_ext = True
    for i, line in enumerate(lines):
        if line.startswith("[sub_resource"):
            in_ext = False
            rest_lines = lines[i:]
            break
        header_lines.append(line)

    clean_headers = []
    for line in header_lines:
        if line.startswith("[gd_scene load_steps="):
            clean_headers.append('[gd_scene load_steps=20 format=3 uid="uid://d4hudscene001"]')
        elif "12_orb_stone" in line or "13_pillar" in line or "14_slot_gothic" in line or "15_d3_frame" in line or "16_xp_frame" in line or "17_xp_fill" in line:
            continue
        else:
            clean_headers.append(line)

    # Now find where Root/HBox starts and DurabilityContainer starts in rest_lines
    full_rest = "\n".join(rest_lines)
    
    idx_hbox = full_rest.find('[node name="HBox" type="HBoxContainer" parent="Root"]')
    idx_dur = full_rest.find('[node name="DurabilityContainer" type="HBoxContainer" parent="Root"]')

    if idx_hbox == -1 or idx_dur == -1:
        print("Error: Could not find HBox or DurabilityContainer markers in d1de_hud.tscn")
        sys.exit(1)

    before_hbox = full_rest[:idx_hbox]
    after_dur = full_rest[idx_dur:]

    # Build the new HBox snippet
    hbox_snippet = '''[node name="HBox" type="HBoxContainer" parent="Root"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 8
alignment = 1
mouse_filter = 2

[node name="LifeContainer" type="Control" parent="Root/HBox"]
custom_minimum_size = Vector2(136, 136)
layout_mode = 2
size_flags_vertical = 4
mouse_filter = 1

[node name="LifeGlobe" type="ColorRect" parent="Root/HBox/LifeContainer"]
material = SubResource("ShaderMaterial_life")
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -44.0
offset_top = -44.0
offset_right = 44.0
offset_bottom = 44.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="LifeFrame" type="TextureRect" parent="Root/HBox/LifeContainer"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -68.0
offset_top = -68.0
offset_right = 68.0
offset_bottom = 68.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("12_orb_stone")
expand_mode = 1
stretch_mode = 5

[node name="LifeLabel" type="Label" parent="Root/HBox/LifeContainer"]
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -60.0
offset_top = -14.0
offset_right = 60.0
offset_bottom = 10.0
grow_horizontal = 2
theme_override_colors/font_color = Color(1, 0.95, 0.9, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 0.95)
theme_override_constants/shadow_outline_size = 4
theme_override_font_sizes/font_size = 13
text = "HP 100 / 100"
horizontal_alignment = 1
vertical_alignment = 1

[node name="LifeTooltipArea" type="Control" parent="Root/HBox/LifeContainer"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
tooltip_text = "Life: 100 / 100"

[node name="CenterPanel" type="Control" parent="Root/HBox"]
custom_minimum_size = Vector2(580, 150)
layout_mode = 2
size_flags_vertical = 4
mouse_filter = 2

[node name="CenterGothicFrame" type="Control" parent="Root/HBox/CenterPanel"]
clip_contents = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="VoidBackground" type="TextureRect" parent="Root/HBox/CenterPanel/CenterGothicFrame"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 4.0
offset_top = 4.0
offset_right = -4.0
offset_bottom = -4.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("15_d3_frame")
expand_mode = 1
stretch_mode = 1

[node name="FrameNinePatch" type="NinePatchRect" parent="Root/HBox/CenterPanel/CenterGothicFrame"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("10_gothic_bar_frame")
patch_margin_left = 16
patch_margin_top = 16
patch_margin_right = 16
patch_margin_bottom = 16

[node name="XpBar" type="ProgressBar" parent="Root/HBox/CenterPanel"]
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -270.0
offset_top = 8.0
offset_right = 270.0
offset_bottom = 15.0
grow_horizontal = 2
mouse_filter = 2
theme_override_styles/background = SubResource("StyleBoxFlat_xp_bg")
theme_override_styles/fill = SubResource("StyleBoxFlat_xp_fill")
value = 35.0
show_percentage = false

[node name="LevelCrest" type="PanelContainer" parent="Root/HBox/CenterPanel"]
custom_minimum_size = Vector2(46, 16)
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -23.0
offset_top = 2.0
offset_right = 23.0
offset_bottom = 18.0
grow_horizontal = 2
mouse_filter = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_level_crest")

[node name="LevelLabel" type="Label" parent="Root/HBox/CenterPanel/LevelCrest"]
layout_mode = 2
mouse_filter = 2
theme_override_colors/font_color = Color(1, 0.88, 0.45, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 0.95)
theme_override_constants/shadow_outline_size = 2
theme_override_font_sizes/font_size = 9
text = "Lv 1"
horizontal_alignment = 1
vertical_alignment = 1

[node name="ConsoleHBox" type="HBoxContainer" parent="Root/HBox/CenterPanel"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -270.0
offset_top = -52.0
offset_right = 270.0
offset_bottom = 66.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 10
alignment = 1
mouse_filter = 2

[node name="LeftGrid" type="GridContainer" parent="Root/HBox/CenterPanel/ConsoleHBox"]
layout_mode = 2
theme_override_constants/h_separation = 4
theme_override_constants/v_separation = 4
columns = 4
mouse_filter = 2

'''

    # Generate Skill slots 1..4 (Row 1)
    for i in range(1, 5):
        hbox_snippet += f'''[node name="SkillSlot{i}" type="Control" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
tooltip_text = "Quick Spell {i} [{i}]"
mouse_filter = 0

[node name="Frame" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/SkillSlot{i}"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("14_slot_gothic")
expand_mode = 1
stretch_mode = 5

[node name="Icon" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/SkillSlot{i}"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -18.0
offset_top = -18.0
offset_right = 18.0
offset_bottom = 18.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="ActiveBorder" type="Panel" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/SkillSlot{i}"]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -2.0
offset_top = -2.0
offset_right = 2.0
offset_bottom = 2.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_active_skill")

[node name="Badge" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/SkillSlot{i}"]
layout_mode = 0
offset_left = 4.0
offset_top = 2.0
offset_right = 20.0
offset_bottom = 18.0
theme_override_colors/font_color = Color(1, 0.88, 0.45, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 3
theme_override_font_sizes/font_size = 10
text = "{i}"

[node name="RmbBadge" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/SkillSlot{i}"]
visible = false
layout_mode = 1
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -26.0
offset_top = 2.0
offset_right = -3.0
offset_bottom = 16.0
grow_horizontal = 0
theme_override_colors/font_color = Color(1, 0.9, 0.3, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 2
theme_override_font_sizes/font_size = 8
text = "RMB"
horizontal_alignment = 2

[node name="ManaBadge" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/SkillSlot{i}"]
layout_mode = 1
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -26.0
offset_top = -16.0
grow_horizontal = 0
grow_vertical = 0
theme_override_colors/font_color = Color(0.4, 0.8, 1, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 2
theme_override_font_sizes/font_size = 9
horizontal_alignment = 2

'''

    # Utility Potions/TP (Row 2 of LeftGrid: Q, W, E, T)
    utils = [
        ("HealthPotionSlot", "Health Potion [Q]\\n[LMB] Drink best healing potion or scroll", "Q", (1.0, 0.85, 0.4, 1.0)),
        ("ManaPotionSlot", "Mana Potion [W]\\n[LMB] Drink best mana potion", "W", (0.4, 0.85, 1.0, 1.0)),
        ("RejuvPotionSlot", "Rejuvenation Potion [E]\\n[LMB] Drink best rejuvenation potion", "E", (0.9, 0.45, 1.0, 1.0)),
        ("TownPortalSlot", "Town Portal [T]\\n[LMB] Cast Town Portal spell or scroll", "T", (0.4, 0.85, 1.0, 1.0)),
    ]

    for name, tip, badge, col in utils:
        icon_tex = 'texture = ExtResource("9_portal_icon")' if name == "TownPortalSlot" else ""
        hbox_snippet += f'''[node name="{name}" type="Control" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
tooltip_text = "{tip}"
mouse_filter = 0

[node name="Frame" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/{name}"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("14_slot_gothic")
expand_mode = 1
stretch_mode = 5

[node name="ItemIcon" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/{name}"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -18.0
offset_top = -18.0
offset_right = 18.0
offset_bottom = 18.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
{icon_tex}
expand_mode = 1
stretch_mode = 5

[node name="Badge" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/{name}"]
layout_mode = 0
offset_left = 4.0
offset_top = 2.0
offset_right = 20.0
offset_bottom = 18.0
theme_override_colors/font_color = Color({col[0]}, {col[1]}, {col[2]}, {col[3]})
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 3
theme_override_font_sizes/font_size = 10
text = "{badge}"

[node name="CountLabel" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/LeftGrid/{name}"]
layout_mode = 1
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -24.0
offset_top = -16.0
grow_horizontal = 0
grow_vertical = 0
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 2
theme_override_font_sizes/font_size = 9
text = "0"
horizontal_alignment = 2

'''

    # Center Pillar divider
    hbox_snippet += '''[node name="CenterPillar" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox"]
custom_minimum_size = Vector2(24, 116)
layout_mode = 2
size_flags_vertical = 4
mouse_filter = 2
texture = ExtResource("13_pillar")
expand_mode = 1
stretch_mode = 5

[node name="RightGrid" type="GridContainer" parent="Root/HBox/CenterPanel/ConsoleHBox"]
layout_mode = 2
theme_override_constants/h_separation = 4
theme_override_constants/v_separation = 4
columns = 4
mouse_filter = 2

'''

    # Right Grid: Belt slots 0..7
    for i in range(8):
        f_key = f"F{i + 1}"
        hbox_snippet += f'''[node name="BeltSlot{i}" type="Control" parent="Root/HBox/CenterPanel/ConsoleHBox/RightGrid"]
custom_minimum_size = Vector2(56, 56)
layout_mode = 2
tooltip_text = "Belt Slot {i + 1} [{f_key}]"
mouse_filter = 0

[node name="Frame" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox/RightGrid/BeltSlot{i}"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("14_slot_gothic")
expand_mode = 1
stretch_mode = 5

[node name="ItemIcon" type="TextureRect" parent="Root/HBox/CenterPanel/ConsoleHBox/RightGrid/BeltSlot{i}"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -18.0
offset_top = -18.0
offset_right = 18.0
offset_bottom = 18.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
expand_mode = 1
stretch_mode = 5

[node name="Badge" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/RightGrid/BeltSlot{i}"]
layout_mode = 0
offset_left = 4.0
offset_top = 2.0
offset_right = 24.0
offset_bottom = 18.0
theme_override_colors/font_color = Color(1, 0.88, 0.45, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 3
theme_override_font_sizes/font_size = 10
text = "{f_key}"

[node name="CountLabel" type="Label" parent="Root/HBox/CenterPanel/ConsoleHBox/RightGrid/BeltSlot{i}"]
layout_mode = 1
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -24.0
offset_top = -16.0
grow_horizontal = 0
grow_vertical = 0
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 1)
theme_override_constants/shadow_outline_size = 2
theme_override_font_sizes/font_size = 9
text = "0"
horizontal_alignment = 2

'''

    # Mana Container on Right
    hbox_snippet += '''[node name="ManaContainer" type="Control" parent="Root/HBox"]
custom_minimum_size = Vector2(136, 136)
layout_mode = 2
size_flags_vertical = 4
mouse_filter = 1

[node name="ManaGlobe" type="ColorRect" parent="Root/HBox/ManaContainer"]
material = SubResource("ShaderMaterial_mana")
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -44.0
offset_top = -44.0
offset_right = 44.0
offset_bottom = 44.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="ManaFrame" type="TextureRect" parent="Root/HBox/ManaContainer"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -68.0
offset_top = -68.0
offset_right = 68.0
offset_bottom = 68.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
texture = ExtResource("12_orb_stone")
expand_mode = 1
stretch_mode = 5

[node name="ManaLabel" type="Label" parent="Root/HBox/ManaContainer"]
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -60.0
offset_top = -14.0
offset_right = 60.0
offset_bottom = 10.0
grow_horizontal = 2
theme_override_colors/font_color = Color(0.9, 0.95, 1, 1)
theme_override_colors/font_shadow_color = Color(0, 0, 0, 0.95)
theme_override_constants/shadow_outline_size = 4
theme_override_font_sizes/font_size = 13
text = "MANA 50 / 50"
horizontal_alignment = 1
vertical_alignment = 1

[node name="ManaTooltipArea" type="Control" parent="Root/HBox/ManaContainer"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
tooltip_text = "Mana: 50 / 50"

'''

    hbox_snippet = hbox_snippet.replace('ExtResource("12_orb_stone")', 'ExtResource("4_gargoyle")')
    hbox_snippet = hbox_snippet.replace('ExtResource("13_pillar")', 'ExtResource("10_gothic_bar_frame")')
    hbox_snippet = hbox_snippet.replace('ExtResource("14_slot_gothic")', 'ExtResource("6_slot_frame")')
    hbox_snippet = hbox_snippet.replace('ExtResource("15_d3_frame")', 'ExtResource("11_gothic_void_bg")')

    new_full_content = "\n".join(clean_headers) + "\n" + before_hbox + hbox_snippet + after_dur
    with open("godot_d1_3d/scenes/hud/d1de_hud.tscn", "w") as f:
        f.write(new_full_content)
    print("d1de_hud.tscn rebuilt successfully!")

if __name__ == "__main__":
    build_hud()
