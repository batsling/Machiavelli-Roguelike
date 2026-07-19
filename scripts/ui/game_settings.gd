class_name GameSettings
extends RefCounted

## The tunable rules for both modes, plus their persistence. Split out of
## main_ui so the Settings dialog edits one model and the controller reads it,
## instead of the two sharing a wall of loose variables. The sandbox block and
## the roguelike block are independent copies of the same rules, so balancing a
## run never disturbs free play.

## Where the Save button persists every setting so a run keeps its rules
## between sessions.
const SETTINGS_PATH := "user://settings.cfg"

# Vanilla sandbox settings (the Settings dialog's first tab) — sandbox games
# only. The AI graph and draw count apply immediately; the rest take effect
# on the next new game.
var ai_strength := 1.0    # 0 = weak, 1 = strong
var ai_style := 0.0       # 0 = quick, 1 = conservative
var ai_attention := 1.0   # 0 = oblivious, 1 = attentive
var ai_planning := 1.0    # 0 = short-sighted, 1 = expert planner
var enemy_count := 2      # 1-3
var draw_per_turn := 1    # 1-3
var start_hand_size := GameManager.DEFAULT_HAND_SIZE  # cards dealt at the start
var max_hand_size := 0    # 0 = no cap, otherwise 10-20
var max_plays_per_turn := 0  # 0 = no cap, otherwise 10-20
var include_jokers := false
var start_combo := false  # deal each player a random opening group on the table
# Ultimate meter (sandbox). Every player charges a meter by playing hands;
# meter_max 0 turns it off. meter_gain is the charge per hand, or per card
# played from hand when meter_per_card is on. Apply from the next game.
var meter_max := 10
var meter_gain := 1
var meter_per_card := false

# Roguelike run settings (the second tab) — the run's own copies of the same
# rules, all applying from the next round so a run in progress keeps the rules
# it started under.
var rogue_draw_per_turn := 2
var rogue_start_hand_size := GameManager.DEFAULT_HAND_SIZE
var rogue_max_hand_size := 0
var rogue_max_plays_per_turn := 13
var rogue_jokers := true
var rogue_start_combo := false
# The run's own copy of the ultimate-meter tuning (see the sandbox block).
var rogue_meter_max := 10
var rogue_meter_gain := 1
var rogue_meter_per_card := false
# Per-enemy AI overrides for roguelike runs, keyed by enemy display_name ->
# {"strength", "style", "attention", "planning"}. Seeded from each designed
# enemy's own dials (see seed_ai_overrides) and editable from the Settings
# dialog's "Roguelike run" tab, so any individual opponent's brain can be
# retuned. The override is stamped onto the enemy the run draws each round.
var rogue_ai_overrides := {}

## A plain-English reading of the four AI dials ("cutthroat, quick, attentive
## and an expert planner"), shared by the settings-tab slider description and
## the enemy info panel so both name a brain the same way.
static func personality_desc(strength: float, style: float, attention: float,
		planning: float) -> String:
	var skill := "capable"
	if strength < 0.35:
		skill = "weak"
	elif strength >= AIProfile.SMART_BRAIN_SKILL:
		skill = "cutthroat"
	elif strength >= 0.7:
		skill = "strong"
	var pace := "quick"
	if style >= 0.75:
		pace = "conservative"
	elif style >= 0.4:
		pace = "balanced"
	var focus := "attentive"
	if attention < 0.4:
		focus = "oblivious"
	elif attention < 0.75:
		focus = "distractible"
	var plan := "an expert planner"
	if planning < 0.34:
		plan = "short-sighted"
	elif planning < 0.67:
		plan = "a measured planner"
	return "%s, %s, %s and %s" % [skill, pace, focus, plan]

## Seed a default AI override for every enemy in the roster from its own
## designed dials, so an untouched enemy plays exactly as designed. Existing
## entries (e.g. just loaded from disk) are left as they are.
func seed_ai_overrides() -> void:
	for enemy in Enemy.roster():
		if not rogue_ai_overrides.has(enemy.display_name):
			rogue_ai_overrides[enemy.display_name] = {
				"strength": enemy.strength,
				"style": enemy.style,
				"attention": enemy.attention,
				"planning": enemy.planning,
			}

## Stamp the AI override for this enemy onto its dials, so the run drives it
## with the brain chosen in the "Roguelike run" tab (its designed dials when
## untouched).
func apply_ai_override(enemy: Enemy) -> void:
	var ov: Dictionary = rogue_ai_overrides.get(enemy.display_name, {})
	if ov.is_empty():
		return
	enemy.strength = ov["strength"]
	enemy.style = ov["style"]
	enemy.attention = ov["attention"]
	enemy.planning = ov.get("planning", enemy.planning)

## Write every sandbox and roguelike setting (including the per-enemy AI
## overrides) to disk, so the Save button makes the current tuning stick
## between sessions.
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sandbox", "ai_strength", ai_strength)
	cfg.set_value("sandbox", "ai_style", ai_style)
	cfg.set_value("sandbox", "ai_attention", ai_attention)
	cfg.set_value("sandbox", "ai_planning", ai_planning)
	cfg.set_value("sandbox", "enemy_count", enemy_count)
	cfg.set_value("sandbox", "draw_per_turn", draw_per_turn)
	cfg.set_value("sandbox", "start_hand_size", start_hand_size)
	cfg.set_value("sandbox", "max_hand_size", max_hand_size)
	cfg.set_value("sandbox", "max_plays_per_turn", max_plays_per_turn)
	cfg.set_value("sandbox", "include_jokers", include_jokers)
	cfg.set_value("sandbox", "start_combo", start_combo)
	cfg.set_value("sandbox", "meter_max", meter_max)
	cfg.set_value("sandbox", "meter_gain", meter_gain)
	cfg.set_value("sandbox", "meter_per_card", meter_per_card)
	cfg.set_value("rogue", "draw_per_turn", rogue_draw_per_turn)
	cfg.set_value("rogue", "start_hand_size", rogue_start_hand_size)
	cfg.set_value("rogue", "max_hand_size", rogue_max_hand_size)
	cfg.set_value("rogue", "max_plays_per_turn", rogue_max_plays_per_turn)
	cfg.set_value("rogue", "jokers", rogue_jokers)
	cfg.set_value("rogue", "start_combo", rogue_start_combo)
	cfg.set_value("rogue", "meter_max", rogue_meter_max)
	cfg.set_value("rogue", "meter_gain", rogue_meter_gain)
	cfg.set_value("rogue", "meter_per_card", rogue_meter_per_card)
	for name: String in rogue_ai_overrides:
		var ov: Dictionary = rogue_ai_overrides[name]
		cfg.set_value("rogue_ai", name,
			[ov["strength"], ov["style"], ov["attention"], ov.get("planning", 1.0)])
	cfg.save(SETTINGS_PATH)

## Load any settings saved by an earlier session, leaving the built-in defaults
## in place when a value (or the file) is missing. Runs before the settings
## dialog is built, so the controls open showing the saved values.
func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	ai_strength = cfg.get_value("sandbox", "ai_strength", ai_strength)
	ai_style = cfg.get_value("sandbox", "ai_style", ai_style)
	ai_attention = cfg.get_value("sandbox", "ai_attention", ai_attention)
	ai_planning = cfg.get_value("sandbox", "ai_planning", ai_planning)
	enemy_count = cfg.get_value("sandbox", "enemy_count", enemy_count)
	draw_per_turn = cfg.get_value("sandbox", "draw_per_turn", draw_per_turn)
	start_hand_size = cfg.get_value("sandbox", "start_hand_size", start_hand_size)
	max_hand_size = cfg.get_value("sandbox", "max_hand_size", max_hand_size)
	max_plays_per_turn = cfg.get_value("sandbox", "max_plays_per_turn", max_plays_per_turn)
	include_jokers = cfg.get_value("sandbox", "include_jokers", include_jokers)
	start_combo = cfg.get_value("sandbox", "start_combo", start_combo)
	meter_max = cfg.get_value("sandbox", "meter_max", meter_max)
	meter_gain = cfg.get_value("sandbox", "meter_gain", meter_gain)
	meter_per_card = cfg.get_value("sandbox", "meter_per_card", meter_per_card)
	rogue_draw_per_turn = cfg.get_value("rogue", "draw_per_turn", rogue_draw_per_turn)
	rogue_start_hand_size = cfg.get_value("rogue", "start_hand_size", rogue_start_hand_size)
	rogue_max_hand_size = cfg.get_value("rogue", "max_hand_size", rogue_max_hand_size)
	rogue_max_plays_per_turn = cfg.get_value("rogue", "max_plays_per_turn", rogue_max_plays_per_turn)
	rogue_jokers = cfg.get_value("rogue", "jokers", rogue_jokers)
	rogue_start_combo = cfg.get_value("rogue", "start_combo", rogue_start_combo)
	rogue_meter_max = cfg.get_value("rogue", "meter_max", rogue_meter_max)
	rogue_meter_gain = cfg.get_value("rogue", "meter_gain", rogue_meter_gain)
	rogue_meter_per_card = cfg.get_value("rogue", "meter_per_card", rogue_meter_per_card)
	for name: String in rogue_ai_overrides:
		var saved: Array = cfg.get_value("rogue_ai", name, [])
		if saved.size() >= 3:
			rogue_ai_overrides[name] = {
				"strength": saved[0], "style": saved[1], "attention": saved[2],
				"planning": saved[3] if saved.size() >= 4 else 1.0}
