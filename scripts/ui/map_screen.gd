class_name MapScreen
extends PanelContainer

## The run map, Slay the Spire style: the run's nodes laid out in rows from the
## bottom (where you start) to the top (the last enemy), joined by the paths
## between them. Nodes you can travel to now are lit and clickable; cleared
## nodes are checked off; the rest are locked. Your lives sit in the header.
##
## Built entirely in code. Like MenuScreen it owns no game state: it renders a
## RunState and emits intent signals; the controller (MainUI) starts the match
## and toggles visibility.

signal node_chosen(node: RunState.MapNode)
signal menu_requested

const NODE_SIZE := Vector2(190, 64)
## Vertical distance between rows on the map.
const ROW_GAP := 150.0
## Horizontal room each column of nodes gets.
const COL_WIDTH := 240.0

var _lives_label: Label
var _status_label: Label
var _canvas: MapCanvas

## The drawing surface: node buttons are its children, positioned absolutely,
## and it paints the paths between them underneath.
class MapCanvas:
	extends Control
	## Each entry: [from: Vector2, to: Vector2, walked: bool].
	var paths: Array = []

	func _draw() -> void:
		for p: Array in paths:
			var col := UITheme.COL_CHIP_ACTIVE if p[2] else Color(1, 1, 1, 0.22)
			draw_line(p[0], p[1], col, 4.0 if p[2] else 3.0, true)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", CardRenderer.panel_style(UITheme.COL_FELT_DARK, 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(12, 0)
	header.add_child(pad)
	var title := Label.new()
	title.text = "Star chart"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UITheme.COL_CHIP_ACTIVE)
	header.add_child(title)
	_lives_label = Label.new()
	_lives_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lives_label.add_theme_font_size_override("font_size", 20)
	header.add_child(_lives_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.tooltip_text = "Back to the main menu — the run is kept"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	header.add_child(menu_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	col.add_child(_status_label)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(center)
	_canvas = MapCanvas.new()
	center.add_child(_canvas)

## Draw `run` and show the map.
func show_run(run: RunState) -> void:
	_lives_label.text = "Lives  %s" % _hearts(run.lives, run.start_lives)
	_lives_label.tooltip_text = "Losing a match costs a life; at 0 the run is over."
	if run.is_won():
		_status_label.text = "Run complete — every enemy on the chart is beaten."
	elif run.is_lost():
		_status_label.text = "Out of lives — the run is over."
	else:
		_status_label.text = "Pick a lit node to fight its enemy. Win to move on; " \
			+ "lose and you can try again for a life."
	_build_nodes(run)
	visible = true

func _build_nodes(run: RunState) -> void:
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	var widest := 1
	for row: Array in run.rows:
		widest = maxi(widest, row.size())
	var area := Vector2(widest * COL_WIDTH, run.rows.size() * ROW_GAP)
	_canvas.custom_minimum_size = area
	var available := run.available_nodes()
	var centers := {}
	for row: Array in run.rows:
		for node: RunState.MapNode in row:
			var c := _node_center(node, row.size(), area)
			centers[node] = c
			var b := _make_node_button(node, available.has(node), run)
			b.position = c - NODE_SIZE / 2.0
			_canvas.add_child(b)
	var paths: Array = []
	for row: Array in run.rows:
		for node: RunState.MapNode in row:
			for next_col in node.next:
				var nxt: RunState.MapNode = run.node_at(node.row + 1, next_col)
				var from: Vector2 = centers[node] - Vector2(0, NODE_SIZE.y / 2.0)
				var to: Vector2 = centers[nxt] + Vector2(0, NODE_SIZE.y / 2.0)
				paths.append([from, to, node.cleared and nxt.cleared])
	_canvas.paths = paths
	_canvas.queue_redraw()

## Where a node sits: row 0 at the bottom, its columns spread evenly across.
func _node_center(node: RunState.MapNode, row_count: int, area: Vector2) -> Vector2:
	var x := area.x * (node.col + 0.5) / row_count
	var y := area.y - (node.row + 0.5) * ROW_GAP
	return Vector2(x, y)

func _make_node_button(node: RunState.MapNode, available: bool, run: RunState) -> Button:
	var b := Button.new()
	b.custom_minimum_size = NODE_SIZE
	b.size = NODE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	var label := "%d · %s" % [node.row + 1, node.enemy.display_name]
	if node.row == run.rows.size() - 1:
		label += "  (boss)"
	var state := "Locked"
	var bg := Color(0.16, 0.18, 0.2)
	var edge := Color(1, 1, 1, 0.15)
	if node.cleared:
		state = "✓ Cleared"
		bg = Color(0.12, 0.3, 0.18)
		edge = Color(0.45, 0.8, 0.5)
	elif available:
		state = "Fight"
		bg = Color(0.32, 0.24, 0.08)
		edge = UITheme.COL_CHIP_ACTIVE
	b.text = "%s\n%s" % [label, state]
	b.disabled = not available
	b.tooltip_text = "%s\n\n%s\n\nAI: plays %s." % [node.enemy.display_name,
		node.enemy.description, GameSettings.personality_desc(node.enemy.strength,
			node.enemy.style, node.enemy.attention, node.enemy.planning)]
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := CardRenderer.panel_style(bg.lightened(0.12) if style_name == "hover" else bg, 12)
		sb.border_color = edge
		sb.set_border_width_all(3 if available else 2)
		b.add_theme_stylebox_override(style_name, sb)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_disabled_color"]:
		b.add_theme_color_override(font_state,
			Color(1, 1, 1, 0.95) if available or node.cleared else Color(1, 1, 1, 0.45))
	b.pressed.connect(func() -> void: node_chosen.emit(node))
	return b

## "♥ ♥ ♡" — full hearts for lives left, hollow for lives lost.
func _hearts(lives: int, total: int) -> String:
	var parts := PackedStringArray()
	for i in maxi(total, lives):
		parts.append("♥" if i < lives else "♡")
	return " ".join(parts)
