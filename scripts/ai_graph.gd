class_name AIGraph
extends Control

## A small 2D picker for the enemy-AI settings: click or drag anywhere on the
## graph to place the marker. Vertical axis is skill (top = strong, bottom =
## weak), horizontal axis is style (left = quick, right = conservative).

signal value_changed(style: float, strength: float)

const COL_BG := Color(0.10, 0.11, 0.14)
const COL_GRID := Color(1, 1, 1, 0.12)
const COL_MARKER := Color(0.93, 0.72, 0.13)
const COL_TEXT := Color(1, 1, 1, 0.55)
const LABEL_FONT_SIZE := 13
const MARKER_RADIUS := 8.0

var style := 0.0     # 0 = quick, 1 = conservative
var strength := 1.0  # 0 = weak,  1 = strong

func _init() -> void:
	custom_minimum_size = Vector2(340, 220)
	mouse_default_cursor_shape = Control.CURSOR_CROSS

func set_values(style_value: float, strength_value: float) -> void:
	style = clampf(style_value, 0.0, 1.0)
	strength = clampf(strength_value, 0.0, 1.0)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_pick(mb.position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pick(mm.position)
		accept_event()

func _pick(pos: Vector2) -> void:
	style = clampf(pos.x / size.x, 0.0, 1.0)
	strength = clampf(1.0 - pos.y / size.y, 0.0, 1.0)
	value_changed.emit(style, strength)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COL_BG)
	for f: float in [0.25, 0.5, 0.75]:
		draw_line(Vector2(size.x * f, 0), Vector2(size.x * f, size.y), COL_GRID)
		draw_line(Vector2(0, size.y * f), Vector2(size.x, size.y * f), COL_GRID)
	draw_rect(rect, COL_GRID, false, 1.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 17), "Strong",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, LABEL_FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(0, size.y - 7), "Weak",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, LABEL_FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(6, size.y / 2.0 + 5), "Quick",
		HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, COL_TEXT)
	draw_string(font, Vector2(0, size.y / 2.0 + 5), "Conservative ",
		HORIZONTAL_ALIGNMENT_RIGHT, size.x, LABEL_FONT_SIZE, COL_TEXT)
	var marker := Vector2(style * size.x, (1.0 - strength) * size.y)
	draw_circle(marker, MARKER_RADIUS, COL_MARKER)
	draw_arc(marker, MARKER_RADIUS + 2.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.5)
