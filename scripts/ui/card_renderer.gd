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

static func make_card_back(back_size: Vector2) -> Panel:
	var back := Panel.new()
	back.custom_minimum_size = back_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.COL_CARD_BACK
	sb.border_color = UITheme.COL_CARD_BACK_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", sb)
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
