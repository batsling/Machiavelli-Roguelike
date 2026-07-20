class_name UITheme
extends RefCounted

## Shared visual constants for the table UI: the felt-and-cards palette, card
## and seat sizes, and the suit→colour mapping. Split out of main_ui so the
## card renderer and the seat/board/hand views all read one source of truth for
## how the game looks. Pure constants — never instantiated; reference members
## directly, e.g. UITheme.COL_FELT or UITheme.CARD_SIZE.

## Suits drawn in red; every other suit is drawn black. Also decides a glass
## card's face colour and the drag-preview text colour.
const RED_SUITS := ["hearts", "diamonds"]

# --- Card and seat sizing -----------------------------------------------------
const CARD_SIZE := Vector2(78, 108)  # hand cards
const CARD_FONT_SIZE := 28
const BOARD_CARD_SIZE := Vector2(62, 86)  # table cards are smaller, so more groups fit
const BOARD_CARD_FONT_SIZE := 22
const NEW_GROUP_SIZE := Vector2(136, 102)
const UI_FONT_SIZE := 17
const BACK_SIZE_TOP := Vector2(46, 64)  # portrait backs for the seat opposite you
const BACK_SIZE_SIDE := Vector2(64, 46)  # landscape backs for the left/right seats
const BACKS_MAX_LEN_TOP := 560.0
const BACKS_MAX_LEN_SIDE := 330.0
const SIDE_SEAT_WIDTH := 130.0

# --- Palette ------------------------------------------------------------------
const COL_FELT := Color(0.09, 0.30, 0.19)
const COL_FELT_DARK := Color(0.07, 0.22, 0.14)
const COL_CARD_BG := Color(0.97, 0.96, 0.91)
const COL_CARD_BORDER := Color(0.60, 0.56, 0.46)
const COL_CARD_RED := Color(0.78, 0.13, 0.16)
const COL_CARD_BLACK := Color(0.10, 0.10, 0.13)
const COL_CARD_BACK := Color(0.17, 0.24, 0.50)
const COL_CARD_BACK_EDGE := Color(0.93, 0.93, 0.97)
const COL_SELECT := Color(0.20, 0.55, 0.95)
const COL_SELECT_BG := Color(0.84, 0.91, 1.0)
const COL_HILITE := Color(0.93, 0.72, 0.13)
const COL_HILITE_BG := Color(1.0, 0.94, 0.75)
const COL_MELD_BORDER := Color(1, 1, 1, 0.16)
const COL_MELD_BAD := Color(0.92, 0.35, 0.30)
const COL_CHIP_BG := Color(0.13, 0.14, 0.17)
const COL_CHIP_ACTIVE := Color(0.93, 0.72, 0.13)
const COL_JOKER := Color(0.48, 0.20, 0.62)
const COL_JOKER_BG := Color(0.96, 0.92, 0.98)
const COL_SLIME := Color(0.44, 0.82, 0.30)      # the slime splotch on a slimed card
const COL_SLIME_EDGE := Color(0.20, 0.52, 0.16)
const COL_GLASS_EDGE := Color(0.62, 0.84, 0.92)  # icy border of a glass card
const GLASS_BG_ALPHA := 0.3   # glass cards let the felt show through
const COL_FILTER_EDGE := Color(0.15, 0.78, 0.80)  # outline on the suit being hovered
const FILTER_DIM_ALPHA := 0.28   # the other suits fade this low while a suit is hovered
const COL_HINT_EDGE := Color(0.34, 0.86, 0.46)    # play-hint spotlight on a group you can play into
const COL_HINT_BG := Color(0.34, 0.86, 0.46, 0.12)  # faint green fill behind a hinted group

# --- Ultimate meter -----------------------------------------------------------
const COL_METER_TRACK := Color(0, 0, 0, 0.38)      # empty channel behind the fill
const COL_METER_EDGE := Color(1, 1, 1, 0.22)       # thin border around the bar
const COL_METER_FILL := Color(0.92, 0.52, 0.16)    # charging amber
const COL_METER_FULL := Color(0.98, 0.80, 0.20)    # bright gold once fully charged
const METER_SIZE := Vector2(118, 13)               # width × height of a seat meter bar
const METER_FONT_SIZE := 10                        # the "value/max" caption inside the bar
