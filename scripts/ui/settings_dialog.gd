class_name SettingsDialog
extends AcceptDialog

## The Settings pop-up: two tabs (Vanilla sandbox / Roguelike run) of controls
## bound to a GameSettings model. Split out of main_ui so the control
## construction lives with the dialog, not the table controller. The dialog
## edits the shared settings model directly; for the handful of sandbox rules
## that apply mid-game it calls back through `_apply_live` so the controller
## can push them onto the running GameManager.
##
## Layout: each tab is a ScrollContainer of compact single-line rows — sliders
## sit beside their title with tiny end tags, and the long rule explainers live
## in tooltips — so the dialog always fits fully on screen whatever the tab
## holds (the roguelike tab carries four sliders per enemy in the roster).

## Sensible bounds for the starting hand size setting (both modes).
const HAND_SIZE_MIN := 5
const HAND_SIZE_MAX := 21
## Every tab scrolls inside this viewport, so the dialog's height never grows
## with the number of settings (or enemies) a tab holds.
const TAB_VIEW_SIZE := Vector2(560, 480)

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
	content.add_child(tabs)
	tabs.add_child(_wrap_tab(_build_vanilla_settings(), "Vanilla sandbox"))
	tabs.add_child(_wrap_tab(_build_rogue_settings(), "Roguelike run"))
	_save_note = Label.new()
	_save_note.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	content.add_child(_save_note)

	# A Save button beside "Done" that persists every setting to disk; changes
	# still apply live, but Save is what makes them survive to the next session.
	add_button("Save settings", true, "save_settings")
	custom_action.connect(_on_custom_action)
	about_to_popup.connect(func() -> void: _save_note.text = "")

## Show the dialog clamped inside the window, so every control is reachable
## whatever the screen size — anything past the tab viewport scrolls.
func open() -> void:
	popup_centered_clamped(Vector2i(TAB_VIEW_SIZE) + Vector2i(40, 160), 0.9)

func _on_custom_action(action: StringName) -> void:
	if action == "save_settings":
		_settings.save()
		_save_note.text = "Settings saved."

## Put a tab's column of rows inside a fixed-size vertical scroller, so a tall
## tab scrolls instead of pushing the dialog off screen.
func _wrap_tab(col: VBoxContainer, tab_title: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title
	scroll.custom_minimum_size = TAB_VIEW_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Breathing room so rows never sit under the scrollbar.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.add_child(col)
	scroll.add_child(pad)
	return scroll

## The "Vanilla sandbox" tab: everything here touches sandbox games only.
func _build_vanilla_settings() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	col.add_child(_make_section("Enemy AI",
		"Four independent dials for the opponents' brains. Applies from their next turn."))
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
	col.add_child(_make_ai_slider_row("Planning", "Short-sighted", "Expert", _settings.ai_planning,
		func(v: float) -> void:
			_settings.ai_planning = v
			_refresh_ai_desc()))

	_ai_desc_label = Label.new()
	_ai_desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_ai_desc_label.add_theme_font_size_override("font_size", 13)
	_ai_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_desc_label.text = _ai_description()
	col.add_child(_ai_desc_label)

	col.add_child(HSeparator.new())
	col.add_child(_make_section("Rules", ""))
	col.add_child(_make_spin_row("Enemies (next game)", 1, 3, _settings.enemy_count,
		func(v: float) -> void: _settings.enemy_count = int(v)))
	col.add_child(_make_spin_row("Cards drawn per turn", 1, 3, _settings.draw_per_turn,
		func(v: float) -> void:
			_settings.draw_per_turn = int(v)
			_apply_live.call()))
	col.add_child(_make_spin_row("Starting hand size (next game)",
		HAND_SIZE_MIN, HAND_SIZE_MAX, _settings.start_hand_size,
		func(v: float) -> void: _settings.start_hand_size = int(v)))
	# Max hand size: with a cap, drawing stops at the cap and a draw attempted
	# on a full hand becomes a pass. Applies immediately — but never to a
	# roguelike run, whose rules are fixed (the controller's _apply_live guards).
	col.add_child(_make_cap_row("Max hand size", _settings.max_hand_size,
		func(v: int) -> void:
			_settings.max_hand_size = v
			_apply_live.call()))
	# Max cards played per turn: only cards leaving the hand count, and the
	# same cap binds the AI. Applies immediately (sandbox only).
	col.add_child(_make_cap_row("Max cards played per turn", _settings.max_plays_per_turn,
		func(v: int) -> void:
			_settings.max_plays_per_turn = v
			_apply_live.call()))

	var joker_check := _make_check_row("Include 4 jokers (next game)",
		"Jokers are wildcards: they count as any card until they lock into a group.",
		_settings.include_jokers,
		func(on: bool) -> void: _settings.include_jokers = on)
	col.add_child(joker_check)

	var combo_check := _make_check_row("Starting combos (next game)",
		"Deal every player a random valid opening group from the stock onto the "
		+ "table, so nobody starts locked out on a hand that can't lay a group.",
		_settings.start_combo,
		func(on: bool) -> void: _settings.start_combo = on)
	col.add_child(combo_check)

	col.add_child(HSeparator.new())
	col.add_child(_make_meter_rows(
		func() -> int: return _settings.meter_max,
		func(v: int) -> void: _settings.meter_max = v,
		func() -> int: return _settings.meter_gain,
		func(v: int) -> void: _settings.meter_gain = v,
		func() -> bool: return _settings.meter_per_card,
		func(on: bool) -> void: _settings.meter_per_card = on))
	return col

## The "Roguelike run" tab: the run's own rules. Everything applies from the
## next round, so a round in progress keeps the rules it started under.
func _build_rogue_settings() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	var intro := Label.new()
	intro.text = "Run rules for balancing the roguelike. Every change applies " \
		+ "from the next round; enemies keep their own designed AI."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 13)
	intro.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	col.add_child(intro)
	col.add_child(HSeparator.new())

	col.add_child(_make_section("Rules", ""))
	col.add_child(_make_spin_row("Cards drawn per turn", 1, 3, _settings.rogue_draw_per_turn,
		func(v: float) -> void: _settings.rogue_draw_per_turn = int(v)))
	col.add_child(_make_spin_row("Starting hand size",
		HAND_SIZE_MIN, HAND_SIZE_MAX, _settings.rogue_start_hand_size,
		func(v: float) -> void: _settings.rogue_start_hand_size = int(v)))
	col.add_child(_make_cap_row("Max hand size", _settings.rogue_max_hand_size,
		func(v: int) -> void: _settings.rogue_max_hand_size = v))
	col.add_child(_make_cap_row("Max cards played per turn", _settings.rogue_max_plays_per_turn,
		func(v: int) -> void: _settings.rogue_max_plays_per_turn = v))

	var joker_check := _make_check_row("Include 4 jokers",
		"Jokers are wildcards: they count as any card until they lock into a group.",
		_settings.rogue_jokers,
		func(on: bool) -> void: _settings.rogue_jokers = on)
	col.add_child(joker_check)

	var combo_check := _make_check_row("Starting combos",
		"Deal every player a random valid opening group from the stock onto the "
		+ "table, so nobody starts locked out on a hand that can't lay a group.",
		_settings.rogue_start_combo,
		func(on: bool) -> void: _settings.rogue_start_combo = on)
	col.add_child(combo_check)

	col.add_child(HSeparator.new())
	col.add_child(_make_meter_rows(
		func() -> int: return _settings.rogue_meter_max,
		func(v: int) -> void: _settings.rogue_meter_max = v,
		func() -> int: return _settings.rogue_meter_gain,
		func(v: int) -> void: _settings.rogue_meter_gain = v,
		func() -> bool: return _settings.rogue_meter_per_card,
		func(on: bool) -> void: _settings.rogue_meter_per_card = on))

	col.add_child(HSeparator.new())
	col.add_child(_make_section("Enemy AI",
		"Retune each opponent's brain individually. Applies from the next round; "
		+ "leave an enemy untouched to keep its designed personality."))
	for enemy in Enemy.roster():
		col.add_child(_build_enemy_ai_rows(enemy.display_name))
	return col

## A per-enemy AI block for the roguelike tab: the enemy's name over four
## sliders bound to its entry in settings.rogue_ai_overrides (which is passed by
## reference, so editing the sliders retunes the run's copy of that enemy).
func _build_enemy_ai_rows(enemy_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.text = enemy_name
	name_label.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	box.add_child(name_label)
	var ov: Dictionary = _settings.rogue_ai_overrides[enemy_name]
	box.add_child(_make_ai_slider_row("Skill", "Weak", "Strong", ov["strength"],
		func(v: float) -> void: ov["strength"] = v))
	box.add_child(_make_ai_slider_row("Style", "Quick", "Conservative", ov["style"],
		func(v: float) -> void: ov["style"] = v))
	box.add_child(_make_ai_slider_row("Attention", "Oblivious", "Attentive", ov["attention"],
		func(v: float) -> void: ov["attention"] = v))
	box.add_child(_make_ai_slider_row("Planning", "Short-sighted", "Expert",
		ov.get("planning", 1.0),
		func(v: float) -> void: ov["planning"] = v))
	return box

## The ultimate-meter block shared by both tabs: a section header (explainer in
## its tooltip), the meter max (0 = off), the charge per play, and the per-card
## toggle. Values are read and written through the getter/setter pairs so one
## builder serves the sandbox and rogue copies. Same-tab live-apply is left to
## the caller's _apply_live (only sandbox pushes onto a running game); both
## take effect next game/round.
func _make_meter_rows(get_max: Callable, set_max: Callable,
		get_gain: Callable, set_gain: Callable,
		get_per_card: Callable, set_per_card: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_make_section("Ultimate meter",
		"Every player charges a meter by playing hands; it holds once full."))
	box.add_child(_make_spin_row("Meter max (0 = off)", 0, 50, get_max.call(),
		func(v: float) -> void:
			set_max.call(int(v))
			_apply_live.call()))
	box.add_child(_make_spin_row("Charge per play", 0, 20, get_gain.call(),
		func(v: float) -> void:
			set_gain.call(int(v))
			_apply_live.call()))
	var per_card := _make_check_row("Charge per card played from hand",
		"Charge once per card leaving the hand that turn, instead of once per hand.",
		get_per_card.call(),
		func(on: bool) -> void:
			set_per_card.call(on)
			_apply_live.call())
	box.add_child(per_card)
	return box

## A bold-ish section header; the explainer (when given) lives in its tooltip
## so the row costs one line.
func _make_section(text: String, tip: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	if tip != "":
		lbl.tooltip_text = tip
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	return lbl

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

## A single-line checkbox row; the rule explainer lives in the tooltip.
func _make_check_row(text: String, tip: String, value: bool,
		on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.tooltip_text = tip
	check.button_pressed = value
	check.toggled.connect(on_toggled)
	return check

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

## A 0..1 slider on a single line: the dial's name, its low end tag, the
## slider, its high end tag. `on_changed` gets the new value. Used for the
## enemy-AI dials.
func _make_ai_slider_row(dial: String, left: String, right: String,
		value: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = dial
	head.custom_minimum_size = Vector2(82, 0)
	row.add_child(head)
	var l := _make_end_tag(left, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = "%s: %s → %s" % [dial, left, right]
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	row.add_child(_make_end_tag(right, HORIZONTAL_ALIGNMENT_LEFT))
	return row

## A tiny, dim end-of-scale tag beside a slider, fixed-width so the sliders in
## a column line up.
func _make_end_tag(text: String, align: HorizontalAlignment) -> Label:
	var tag := Label.new()
	tag.text = text
	tag.custom_minimum_size = Vector2(88, 0)
	tag.horizontal_alignment = align
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	tag.add_theme_font_size_override("font_size", 12)
	return tag

func _refresh_ai_desc() -> void:
	_ai_desc_label.text = _ai_description()

func _ai_description() -> String:
	return "Enemies play %s. Applies from their next turn." \
		% GameSettings.personality_desc(_settings.ai_strength, _settings.ai_style,
			_settings.ai_attention, _settings.ai_planning)
