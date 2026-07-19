class_name SettingsDialog
extends AcceptDialog

## The Settings pop-up: two tabs (Vanilla sandbox / Roguelike run) of controls
## bound to a GameSettings model. Split out of main_ui so the ~280 lines of
## control construction live with the dialog, not the table controller. The
## dialog edits the shared settings model directly; for the handful of sandbox
## rules that apply mid-game it calls back through `_apply_live` so the
## controller can push them onto the running GameManager.

## Sensible bounds for the starting hand size setting (both modes).
const HAND_SIZE_MIN := 5
const HAND_SIZE_MAX := 21

var _settings: GameSettings
# Called after a live-affecting sandbox rule changes, so the controller can
# sync the running game from the model.
var _apply_live: Callable
var _ai_desc_label: Label
var _save_note: Label

## Build the dialog against a settings model. `apply_live` is invoked whenever a
## setting that takes effect immediately (draw count, hand cap, play cap)
## changes. Call once, after adding the dialog to the tree.
func setup(settings: GameSettings, apply_live: Callable) -> void:
	_settings = settings
	_apply_live = apply_live
	title = "Settings"
	ok_button_text = "Done"

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(420, 0)
	content.add_child(tabs)
	tabs.add_child(_build_vanilla_settings())
	tabs.add_child(_build_rogue_settings())
	_save_note = Label.new()
	_save_note.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	content.add_child(_save_note)

	# A Save button beside "Done" that persists every setting to disk; changes
	# still apply live, but Save is what makes them survive to the next session.
	add_button("Save settings", true, "save_settings")
	custom_action.connect(_on_custom_action)
	about_to_popup.connect(func() -> void: _save_note.text = "")

func _on_custom_action(action: StringName) -> void:
	if action == "save_settings":
		_settings.save()
		_save_note.text = "Settings saved."

## The "Vanilla sandbox" tab: everything here touches sandbox games only.
func _build_vanilla_settings() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Vanilla sandbox"
	col.add_theme_constant_override("separation", 10)

	var ai_label := Label.new()
	ai_label.text = "Enemy AI — three independent dials for the opponents' brains."
	ai_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ai_label)

	col.add_child(_make_ai_slider_row("Skill", "Weak", "Strong", _settings.ai_strength,
		func(v: float) -> void:
			_settings.ai_strength = v
			_refresh_ai_desc()))
	col.add_child(_make_ai_slider_row("Style", "Quick", "Conservative", _settings.ai_style,
		func(v: float) -> void:
			_settings.ai_style = v
			_refresh_ai_desc()))
	col.add_child(_make_ai_slider_row("Attention", "Oblivious", "Attentive", _settings.ai_attention,
		func(v: float) -> void:
			_settings.ai_attention = v
			_refresh_ai_desc()))
	col.add_child(_make_ai_slider_row("Planning", "Short-sighted", "Expert planner", _settings.ai_planning,
		func(v: float) -> void:
			_settings.ai_planning = v
			_refresh_ai_desc()))

	_ai_desc_label = Label.new()
	_ai_desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_ai_desc_label.text = _ai_description()
	col.add_child(_ai_desc_label)

	col.add_child(HSeparator.new())

	col.add_child(_make_spin_row("Enemies (next game):", 1, 3, _settings.enemy_count,
		func(v: float) -> void: _settings.enemy_count = int(v)))
	col.add_child(_make_spin_row("Cards drawn per turn:", 1, 3, _settings.draw_per_turn,
		func(v: float) -> void:
			_settings.draw_per_turn = int(v)
			_apply_live.call()))
	col.add_child(_make_spin_row("Starting hand size (next game):",
		HAND_SIZE_MIN, HAND_SIZE_MAX, _settings.start_hand_size,
		func(v: float) -> void: _settings.start_hand_size = int(v)))
	# Max hand size: with a cap, drawing stops at the cap and a draw attempted
	# on a full hand becomes a pass. Applies immediately — but never to a
	# roguelike run, whose rules are fixed (the controller's _apply_live guards).
	col.add_child(_make_cap_row("Max hand size:", _settings.max_hand_size,
		func(v: int) -> void:
			_settings.max_hand_size = v
			_apply_live.call()))
	# Max cards played per turn: only cards leaving the hand count, and the
	# same cap binds the AI. Applies immediately (sandbox only).
	col.add_child(_make_cap_row("Max cards played per turn:", _settings.max_plays_per_turn,
		func(v: int) -> void:
			_settings.max_plays_per_turn = v
			_apply_live.call()))

	var joker_check := CheckBox.new()
	joker_check.text = "Include 4 jokers — wildcards (next game)"
	joker_check.button_pressed = _settings.include_jokers
	joker_check.toggled.connect(func(on: bool) -> void: _settings.include_jokers = on)
	col.add_child(joker_check)

	var combo_check := CheckBox.new()
	combo_check.text = "Starting combos — deal every player a random opening\n" \
		+ "group from the stock onto the table (next game)"
	combo_check.button_pressed = _settings.start_combo
	combo_check.toggled.connect(func(on: bool) -> void: _settings.start_combo = on)
	col.add_child(combo_check)
	return col

## The "Roguelike run" tab: the run's own rules. Everything applies from the
## next round, so a round in progress keeps the rules it started under.
func _build_rogue_settings() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Roguelike run"
	col.add_theme_constant_override("separation", 10)

	var intro := Label.new()
	intro.text = "Run rules for balancing the roguelike. Every change applies " \
		+ "from the next round; enemies keep their own designed AI."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	col.add_child(HSeparator.new())

	col.add_child(_make_spin_row("Cards drawn per turn:", 1, 3, _settings.rogue_draw_per_turn,
		func(v: float) -> void: _settings.rogue_draw_per_turn = int(v)))
	col.add_child(_make_spin_row("Starting hand size:",
		HAND_SIZE_MIN, HAND_SIZE_MAX, _settings.rogue_start_hand_size,
		func(v: float) -> void: _settings.rogue_start_hand_size = int(v)))
	col.add_child(_make_cap_row("Max hand size:", _settings.rogue_max_hand_size,
		func(v: int) -> void: _settings.rogue_max_hand_size = v))
	col.add_child(_make_cap_row("Max cards played per turn:", _settings.rogue_max_plays_per_turn,
		func(v: int) -> void: _settings.rogue_max_plays_per_turn = v))

	var joker_check := CheckBox.new()
	joker_check.text = "Include 4 jokers — wildcards"
	joker_check.button_pressed = _settings.rogue_jokers
	joker_check.toggled.connect(func(on: bool) -> void: _settings.rogue_jokers = on)
	col.add_child(joker_check)

	var combo_check := CheckBox.new()
	combo_check.text = "Starting combos — deal every player a random opening\n" \
		+ "group from the stock onto the table"
	combo_check.button_pressed = _settings.rogue_start_combo
	combo_check.toggled.connect(func(on: bool) -> void: _settings.rogue_start_combo = on)
	col.add_child(combo_check)

	col.add_child(HSeparator.new())
	var ai_header := Label.new()
	ai_header.text = "Enemy AI — retune each opponent's brain individually. " \
		+ "Applies from the next round; leave an enemy untouched to keep its " \
		+ "designed personality."
	ai_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ai_header)
	for enemy in Enemy.roster():
		col.add_child(_build_enemy_ai_rows(enemy.display_name))
	return col

## A per-enemy AI block for the roguelike tab: the enemy's name over four
## sliders bound to its entry in settings.rogue_ai_overrides (which is passed by
## reference, so editing the sliders retunes the run's copy of that enemy).
func _build_enemy_ai_rows(enemy_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = enemy_name
	title.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	box.add_child(title)
	var ov: Dictionary = _settings.rogue_ai_overrides[enemy_name]
	box.add_child(_make_ai_slider_row("Skill", "Weak", "Strong", ov["strength"],
		func(v: float) -> void: ov["strength"] = v))
	box.add_child(_make_ai_slider_row("Style", "Quick", "Conservative", ov["style"],
		func(v: float) -> void: ov["style"] = v))
	box.add_child(_make_ai_slider_row("Attention", "Oblivious", "Attentive", ov["attention"],
		func(v: float) -> void: ov["attention"] = v))
	box.add_child(_make_ai_slider_row("Planning", "Short-sighted", "Expert planner",
		ov.get("planning", 1.0),
		func(v: float) -> void: ov["planning"] = v))
	return box

func _make_spin_row(text: String, minimum: int, maximum: int, value: int,
		on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.value_changed.connect(on_changed)
	row.add_child(spin)
	return row

## A "None or 10-20" dropdown row; `on_changed` gets the chosen value (0 for
## "None"). Used for the hand cap and the play cap.
func _make_cap_row(text: String, value: int, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.add_item("None", 0)
	for v in range(10, 21):
		opt.add_item(str(v), v)
	opt.select(0 if value == 0 else value - 9)
	opt.item_selected.connect(func(idx: int) -> void:
		on_changed.call(opt.get_item_id(idx)))
	row.add_child(opt)
	return row

## A titled 0..1 slider with its two end labels underneath. `on_changed` gets
## the new value. Used for the enemy-AI dials.
func _make_ai_slider_row(title: String, left: String, right: String,
		value: float, on_changed: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.text = title
	box.add_child(head)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_changed)
	box.add_child(slider)
	var ends := HBoxContainer.new()
	var l := Label.new()
	l.text = left
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	l.add_theme_font_size_override("font_size", 12)
	var r := Label.new()
	r.text = right
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	r.add_theme_font_size_override("font_size", 12)
	ends.add_child(l)
	ends.add_child(r)
	box.add_child(ends)
	return box

func _refresh_ai_desc() -> void:
	_ai_desc_label.text = _ai_description()

func _ai_description() -> String:
	return "Enemies play %s. Applies from their next turn." \
		% GameSettings.personality_desc(_settings.ai_strength, _settings.ai_style,
			_settings.ai_attention, _settings.ai_planning)
