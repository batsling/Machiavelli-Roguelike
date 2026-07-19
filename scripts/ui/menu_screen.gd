class_name MenuScreen
extends PanelContainer

## The main menu that fronts the table: title, subtitle and the five buttons.
## Built entirely in code (its .tscn is just this script on a root
## PanelContainer). Each button emits an intent signal; the controller
## (main_ui) decides what each does and toggles this menu's visibility. The
## menu owns no game state, so it stays a self-contained scene.

signal play_vanilla_requested
signal play_rogue_requested
signal resume_requested
signal settings_requested
signal quit_requested

var _resume_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", CardRenderer.panel_style(UITheme.COL_FELT_DARK, 0))
	var center := CenterContainer.new()
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var title := Label.new()
	title.text = "Machiavelli"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	col.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "the Italian rummy of rearranging the whole table"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	col.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)

	_resume_btn = _make_button("Resume game", func() -> void: resume_requested.emit())
	col.add_child(_resume_btn)
	col.add_child(_make_button("Roguelike run", func() -> void: play_rogue_requested.emit()))
	col.add_child(_make_button("Vanilla sandbox", func() -> void: play_vanilla_requested.emit()))
	col.add_child(_make_button("Settings", func() -> void: settings_requested.emit()))
	col.add_child(_make_button("Quit", func() -> void: quit_requested.emit()))

## Show the menu; `can_resume` decides whether the Resume button is offered
## (there is nothing to resume before the first game is dealt).
func show_menu(can_resume: bool) -> void:
	_resume_btn.visible = can_resume
	visible = true

func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 54)
	b.add_theme_font_size_override("font_size", 21)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b
