class_name CardRenderer
extends RefCounted

## Stateless builders for the game's visual atoms: card and panel styleboxes,
## plain card backs, see-through glass faces, the slime splotch, drag previews
## and the flying-card animation proxy. Split out of main_ui so the seat/board/
## hand views and the enemy-move animator can all render cards the same way
## without depending on the controller. Every method is static and reads only
## its arguments plus UITheme / Card / Rules — no game state, no `self`.

## A card-shaped stylebox: coloured fill, coloured border of the given width,
## rounded corners and a small content margin. Used for hand and table cards.
static func card_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

## A panel stylebox (felt, chips, hand panel): fill and corner radius with a
## roomier margin than a card.
static func panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

## A brighter copy of a stylebox for a control's hover state.
static func hover_variant(sb: StyleBoxFlat) -> StyleBoxFlat:
	var out: StyleBoxFlat = sb.duplicate()
	out.bg_color = Color(out.bg_color.r, out.bg_color.g, out.bg_color.b,
		minf(out.bg_color.a + 0.06, 1.0))
	out.border_color = Color(1, 1, 1, 0.6)
	return out

## A plain face-down card back. A slimed card shows its green splotch even from
## the back (pass the card): the slime is a status the player can read off an
## opponent's hand and the top of the stock, just as glass is — it never reveals
## the card's face, only that it is stuck. `card` may be null for a generic back.
static func make_card_back(back_size: Vector2, card: Card = null) -> Panel:
	var back := Panel.new()
	back.custom_minimum_size = back_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.COL_CARD_BACK
	sb.border_color = UITheme.COL_CARD_BACK_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", sb)
	if card != null and card.is_sticky():
		add_slime_blob(back)
	return back

## A small face-up rendering of a glass card in a card-back footprint: the
## card is transparent, so its face shows even from the back (in an opponent's
## hand, or on top of the stock). Non-interactive.
static func make_glass_face(c: Card, face_size: Vector2) -> Panel:
	var face := Panel.new()
	face.custom_minimum_size = face_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.COL_CARD_BG, UITheme.GLASS_BG_ALPHA)
	sb.border_color = UITheme.COL_GLASS_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	face.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.text = c.label()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	var col := UITheme.COL_CARD_RED if UITheme.RED_SUITS.has(c.suit) else UITheme.COL_CARD_BLACK
	if c.is_joker:
		col = UITheme.COL_JOKER
	lbl.add_theme_color_override("font_color", col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(lbl)
	if c.is_sticky():
		add_slime_blob(face)
	return face

## A little green slime splotch pinned to the top-right corner of a card, the
## visible mark of the Cute Slime's Sticky effect. Non-interactive so it never
## steals the card's clicks or drags.
static func add_slime_blob(parent: Control) -> void:
	const BLOB := 15.0
	const MARGIN := 3.0
	var blob := Panel.new()
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blob.anchor_left = 1.0
	blob.anchor_right = 1.0
	blob.anchor_top = 0.0
	blob.anchor_bottom = 0.0
	blob.offset_left = -(BLOB + MARGIN)
	blob.offset_right = -MARGIN
	blob.offset_top = MARGIN
	blob.offset_bottom = MARGIN + BLOB
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.COL_SLIME
	sb.border_color = UITheme.COL_SLIME_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(BLOB / 2.0))
	blob.add_theme_stylebox_override("panel", sb)
	blob.tooltip_text = "Slimed — sticks to adjacent slimed cards; moving one drags the lump."
	parent.add_child(blob)

## A slim green strip pinned across the top of a hand card, marking a card that
## can be played right now with no rearranging — laid off onto an existing group
## or completing a fresh group with other cards in hand. Same green as the group
## it would drop onto lights up on hover (UITheme.COL_HINT_EDGE), so the card and
## its destination read as a matched pair. Non-interactive so it never steals the
## card's clicks or drags.
static func add_play_marker(parent: Control) -> void:
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left = 4
	bar.offset_right = -4
	bar.offset_top = 2
	bar.offset_bottom = 2 + UITheme.PLAY_MARKER_HEIGHT
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.COL_HINT_EDGE
	sb.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("panel", sb)
	parent.add_child(bar)

## An ultimate-meter bar: a dark track with an amber fill (bright gold once
## full) proportional to value/maximum, and a small "value/max" caption. The
## fill is anchored by ratio, so it fills correctly whatever width the bar is
## laid out at. Non-interactive. Callers gate on maximum > 0 (a disabled meter
## draws no bar).
static func make_meter_bar(value: int, maximum: int) -> Control:
	var ratio := clampf(float(value) / float(maximum), 0.0, 1.0) if maximum > 0 else 0.0
	var track := Panel.new()
	track.custom_minimum_size = UITheme.METER_SIZE
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_sb := StyleBoxFlat.new()
	track_sb.bg_color = UITheme.COL_METER_TRACK
	track_sb.border_color = UITheme.COL_METER_EDGE
	track_sb.set_border_width_all(1)
	track_sb.set_corner_radius_all(4)
	track.add_theme_stylebox_override("panel", track_sb)
	track.tooltip_text = "Ultimate meter: %d / %d" % [value, maximum]
	if ratio > 0.0:
		var full := value >= maximum
		var fill := Panel.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_right = ratio  # width follows the charge, resolution-independent
		fill.anchor_bottom = 1.0
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = UITheme.COL_METER_FULL if full else UITheme.COL_METER_FILL
		fill_sb.set_corner_radius_all(4)
		fill.add_theme_stylebox_override("panel", fill_sb)
		track.add_child(fill)
	var caption := Label.new()
	caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption.text = "%d/%d" % [value, maximum]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UITheme.METER_FONT_SIZE)
	caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(caption)
	return track

## The floating preview shown under the cursor while dragging cards.
static func make_drag_preview(cards: Array[Card]) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for c in Rules.display_order(cards):
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel",
			card_style(UITheme.COL_SELECT_BG, UITheme.COL_SELECT, 2))
		var lbl := Label.new()
		lbl.text = c.label()
		lbl.add_theme_font_size_override("font_size", UITheme.CARD_FONT_SIZE)
		lbl.add_theme_color_override("font_color",
			UITheme.COL_CARD_RED if UITheme.RED_SUITS.has(c.suit) else UITheme.COL_CARD_BLACK)
		chip.add_child(lbl)
		row.add_child(chip)
	row.modulate = Color(1, 1, 1, 0.9)
	return row

## A non-interactive card face used as an enemy-move animation proxy; sized like
## the board card it lands on and styled like the gold highlight it will carry.
static func make_card_face(c: Card) -> Control:
	var face := PanelContainer.new()
	face.custom_minimum_size = UITheme.BOARD_CARD_SIZE
	face.size = UITheme.BOARD_CARD_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel",
		card_style(UITheme.COL_HILITE_BG, UITheme.COL_HILITE, 3))
	var lbl := Label.new()
	lbl.text = c.label()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", UITheme.BOARD_CARD_FONT_SIZE)
	lbl.add_theme_color_override("font_color",
		UITheme.COL_CARD_RED if UITheme.RED_SUITS.has(c.suit) else UITheme.COL_CARD_BLACK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(lbl)
	return face
