class_name GameManager
extends Node

## Core engine for a vanilla game of Machiavelli (the Italian rummy variant).
##
## Rules implemented:
##  - Every player brings their own deck (a standard 52 cards, plus 2 jokers
##    when jokers are enabled, unless a custom deck is passed to setup) and is
##    dealt a starting hand from it. Players only ever draw from their own deck;
##    the table is shared.
##  - Energy (optional, on when start_energy > 0): each card played from hand
##    costs its Card.cost in energy. A player starts their first turn with
##    start_energy, gains energy_per_turn more each turn up to energy_cap, and
##    unspent energy never carries over. Rearranging the table is always free.
##  - On your turn you either play at least one card from your hand onto the
##    table, or draw from your deck (draw_per_turn cards). While playing you may freely
##    rearrange every meld on the table — the only requirement is that when
##    the turn ends, every meld on the table is valid (Rules.is_valid_meld).
##  - Opening: until a player has laid down at least one valid meld built
##    entirely from their own hand, they may not touch the rest of the table —
##    no adding to other melds and no taking cards from them. Laying a valid
##    own meld unlocks table play immediately (even mid-turn), and once a
##    turn containing such a meld is committed the player stays open for the
##    rest of the game. This applies to every player, human and AI.
##  - Events (optional, see MatchEvent): rule cards in event_deck are revealed
##    one at the start of each round listed in event_rounds and affect every
##    player — once on each player's turn of the reveal round (on reveal) or for
##    the rest of the match (ongoing). A choice an event asks for is a pending
##    choice the current player resolves (resolve_choice) before playing. Each
##    event also puts a random three-card combo of fresh cards (from no one's
##    deck) on the table when it is revealed.
##  - First player to empty their hand wins. A player who cannot draw (their
##    deck is empty or their hand is at the cap) passes; if every player passes
##    in a full round, the game ends and whoever holds the fewest cards wins
##    (ties shared).
##
## The turn is *staged*: moves mutate the board/hand immediately, but the
## whole turn can be rolled back (reset_turn, or draw_and_end_turn when the
## staging isn't a keepable rearrangement) and is only legal-checked at
## commit_turn(). This mirrors how the physical game is played — shuffle the
## table as much as you like, it just has to be clean when you take your hand
## off it. Each staged move is also snapshotted, so
## undo_action() can take back one move at a time, and cards played from the
## hand this turn can be taken back individually (return_cards_to_hand).

signal turn_started(player: PlayerState)
signal board_changed
## Fired once per draw action with every card that player drew this turn (one to
## draw_per_turn cards). Batched so the UI can announce a multi-card draw as a
## single line ("… drew 2 cards, X and Y") instead of one line per card.
signal cards_drawn(player: PlayerState, cards: Array[Card])
signal turn_committed(player: PlayerState, cards_played: int)
signal player_passed(player: PlayerState)
signal game_over(winners: Array)
## An event was turned face up (see MatchEvent).
signal event_revealed(event: MatchEvent)
## Cards left a player's hand for their deck's discard pile because of an event.
signal cards_discarded(player: PlayerState, cards: Array[Card])
## A player handed cards from their hand to another player's hand (the Gift event).
signal cards_given(giver: PlayerState, receiver: PlayerState, cards: Array[Card])
## A player earned coins (the Coin Rush event).
signal coins_gained(player: PlayerState, amount: int)
## Fired when a committed hand charges a player's ultimate meter. `amount` is
## how much the meter actually rose (0 is never emitted), and `now_full` is
## true on the charge that first fills it, so the UI can announce it.
signal meter_charged(player: PlayerState, amount: int, now_full: bool)

const DEFAULT_HAND_SIZE := 13

var players: Array[PlayerState] = []
var board := Board.new()
var turn_index := 0
## The current round of play: every player takes one turn per round, and the
## count ticks up each time play wraps back to the first player (turn_index 0).
## Starts at 1 the moment the game is dealt. This is the table's own round
## counter, distinct from the run's map progress (which enemy you face).
var round_number := 1
var is_game_over := false
## How many cards a player draws when they draw instead of playing (1-3 from
## the settings menu). Drawing stops early when the player's deck runs dry; a
## turn only counts as a pass when zero cards could be drawn.
var draw_per_turn := 1
## Optional hand cap (0 = none, 10-20 from the settings menu). Drawing stops
## at the cap, so a draw attempted with a full hand is a pass; a full round
## of passes still ends the game with fewest cards winning.
var max_hand_size := 0
## Optional cap on cards played per turn (0 = none, 10-20 from the settings
## menu). Only cards leaving the hand count — rearranging the table is always
## free — and returning a played card to the hand gives the play back.
var max_plays_per_turn := 0
## Ultimate-meter tuning (from the settings menu). Every player carries a meter
## that charges when they commit a hand and holds at meter_max once full.
## meter_max 0 disables the meter entirely. Each committed hand adds
## meter_gain points — once per hand, or meter_gain per card played from hand
## when meter_per_card is on.
var meter_max := 20
var meter_gain := 1
var meter_per_card := false
## Energy rules. start_energy 0 turns energy off entirely (cards are free, as in
## vanilla Machiavelli); a roguelike run sets it to 3. A player's ceiling is
## start_energy on their first turn, + energy_per_turn each turn after, capped
## at energy_cap (0 = no cap). Energy refills to the ceiling every turn — unspent
## energy is lost.
var start_energy := 0
var energy_per_turn := 1
var energy_cap := 10
## Events still face down, in reveal order. Set before setup (like the energy
## rules); setup resets every event to face down. Empty = no events (sandbox).
var event_deck: Array[MatchEvent] = []
## The rounds an event is revealed on, one per round in order; the next face-down
## event turns up at the start of each listed round.
var event_rounds: Array[int] = [1, 3, 5]
## Events turned face up this match, in reveal order.
var revealed_events: Array[MatchEvent] = []
# The choice the current player owes an on-reveal event this turn, or {} for
# none: {"event": MatchEvent, "count": int}. Staging, committing and drawing
# wait until resolve_choice settles it.
var _pending_choice := {}

# How many copies of each natural card ("rank,suit") exist across every deck
# and hand at the deal. With per-player decks this depends on what each player
# brought, so the AI's card counting reads it instead of assuming a number.
var _copies := {}

# Staging state for the current turn. _hand_snapshot is the current player's
# hand at the start of the turn; swap_joker() appends to it in place (the
# joker legally becomes "a card you started the turn with"), which is why
# every undo entry carries its own copy.
var _hand_snapshot: Array[Card] = []
# One {hand, board, snapshot} state per staged move, so moves can be undone.
var _undo_stack: Array[Dictionary] = []
var _consecutive_passes := 0
# True once the current player has spent their ultimate this turn (built a
# picture): the meter drained to zero and this turn's plays neither recharge it
# nor fire it again. Cleared at the start of every turn.
var _meter_spent_this_turn := false
# Cards the current player has sealed into a picture this turn. A picture card
# stays movable the turn it is placed (so a just-built shape can still be
# reworked or undone); once the turn ends it is sealed for good. Cleared at the
# start of every turn.
var _shaped_this_turn: Array[Card] = []

## Deal a new game. Every player gets their own deck: `decks[i]` when given (an
## enemy's authored deck, say — its cards are re-tagged to that seat), otherwise
## a standard 52-card deck (+2 jokers when include_jokers). Each deck is shuffled
## with its own seed derived from seed_value, so a seeded game replays exactly.
func setup(player_names: Array, hand_size: int = DEFAULT_HAND_SIZE, seed_value: int = -1,
		include_jokers := false, decks: Array = []) -> void:
	players.clear()
	board = Board.new()
	turn_index = 0
	round_number = 1
	is_game_over = false
	_consecutive_passes = 0
	_pending_choice = {}
	revealed_events.clear()
	for e in event_deck:
		e.revealed_round = 0
		e.combo.clear()
	for i in player_names.size():
		var p := PlayerState.new()
		p.player_id = i
		p.display_name = str(player_names[i])
		p.is_opponent = i != 0
		var given: Deck = decks[i] if i < decks.size() else null
		if given != null:
			p.deck = given
			for c in p.deck.cards:
				c.deck_owner = i
		else:
			p.deck = Deck.new(seed_value + i * 7919 if seed_value >= 0 else -1)
			p.deck.build_standard(i, include_jokers)
		p.deck.shuffle()
		for _j in hand_size:
			var c := p.deck.draw()
			if c == null:
				break
			p.hand.append(c)
		players.append(p)
	_count_copies()
	_begin_turn()

func current_player() -> PlayerState:
	return players[turn_index]

## How many copies of this natural card exist in the game (across every deck,
## hand and the table at the deal). The AI's card counting reads it.
func copies_in_play(rank: int, suit: String) -> int:
	return _copies.get("%d,%s" % [rank, suit], 0)

func _count_copies() -> void:
	_copies.clear()
	for p in players:
		for c in p.deck.cards + p.deck.discards + p.hand:
			if not c.is_joker:
				var key := "%d,%s" % [c.rank, c.suit]
				_copies[key] = _copies.get(key, 0) + 1

## Cards left to draw across every player's deck — the game's "stock", for code
## that cares how close the whole table is to running dry.
func cards_left_in_decks() -> int:
	var n := 0
	for p in players:
		n += p.deck.size()
	return n

## Deal every player a starting combo: a random valid three-card meld (a set
## or a run of naturals) pulled straight from their own deck onto the table,
## which counts as that player's opening meld (has_opened). No one starts stuck
## on a hand that can't lay a group — the whole table is playable from turn one.
## Call after enemy mechanics are planted (on_combat_start), which coat the
## decks and hands, so combo cards keep any effects they picked up there.
func deal_starting_melds() -> void:
	for p in players:
		var pulled := _random_stock_meld(p.deck)
		if pulled.is_empty():
			continue  # this deck is too thin to build one; leave it a normal deal
		var meld := CardSet.new()
		for c in pulled:
			meld.add_card(c)
		board.melds.append(meld)
		p.has_opened = true
	board_changed.emit()

## A random valid three-card meld pulled from `deck`: an even coin flip
## between a set (one rank, three suits) and a run (one suit, three consecutive
## ranks, ace playing low). Uses the deck's RNG so a seeded game stays
## reproducible. Returns [] when the deck can't supply any shape tried.
func _random_stock_meld(deck: Deck) -> Array[Card]:
	for _attempt in 40:
		var want: Array = []  # [rank, suit] pairs
		if deck.rng.randi_range(0, 1) == 0:
			var rank := deck.rng.randi_range(1, 13)
			var suits := Deck.SUITS.duplicate()
			for i in range(suits.size() - 1, 0, -1):
				var j := deck.rng.randi_range(0, i)
				var tmp: String = suits[i]
				suits[i] = suits[j]
				suits[j] = tmp
			for i in 3:
				want.append([rank, suits[i]])
		else:
			var suit: String = Deck.SUITS[deck.rng.randi_range(0, Deck.SUITS.size() - 1)]
			var start := deck.rng.randi_range(1, 11)
			for i in 3:
				want.append([start + i, suit])
		var got: Array[Card] = []
		for w: Array in want:
			var c := deck.take_card(w[0], w[1])
			if c == null:
				break
			got.append(c)
		if got.size() == want.size():
			return got
		# A copy was missing: put the pulls back and try another shape.
		for c in got:
			deck.cards.append(c)
	return []

# --- Staging moves (current player's turn) ---------------------------------

## Move cards (from the current player's hand and/or anywhere on the table)
## into a brand-new meld. Returns "" on success or a human-readable reason the
## move is not allowed (the opening rule is enforced here; meld validity is
## still only checked at commit_turn()).
func move_cards_to_new_meld(cards_to_move: Array[Card]) -> String:
	if cards_to_move.is_empty():
		return ""
	cards_to_move = _expand_sticky(cards_to_move)
	var err := _stage_error(cards_to_move, null)
	if err != "":
		return err
	_push_undo()
	var meld := CardSet.new()
	board.melds.append(meld)
	_move_cards(cards_to_move, meld)
	_lock_table_jokers()
	return ""

## Move cards (from hand and/or table) into an existing meld. Returns "" on
## success or the reason the move is not allowed. Pictures are sealed (their
## edges take Scrabble-style plays instead — play_off_picture), and dropping
## onto an attached extension line reads as extending that line.
func add_cards_to_meld(cards_to_move: Array[Card], meld: CardSet) -> String:
	if meld.is_shape():
		return "Pictures are sealed — play off their edges instead."
	if meld.is_attached():
		return play_off_picture(meld.attach_anchor, meld.attach_step, cards_to_move)
	if cards_to_move.is_empty():
		return ""
	cards_to_move = _expand_sticky(cards_to_move)
	var err := _stage_error(cards_to_move, meld)
	if err != "":
		return err
	_push_undo()
	_move_cards(cards_to_move, meld)
	_lock_table_jokers()
	return ""

# --- Scrabble-style plays off a picture ---------------------------------------

## Lay cards in a straight line outward from `anchor` — a card of a picture
## group — along `step` (one of the four grid directions). The anchor counts
## in the line's reading: anchor + line must read as a legal set/run on the
## grid (Rules.is_valid_grid_line — spatial order matters for runs), so at
## least three cards counting the anchor; a lone card off a picture is not a
## play. A vertical straight must also keep the lower rank on top
## (Rules.line_direction_ok).
## The anchor stays a picture card; the played cards form (or extend) an
## attached extension line. Outward only: the covered cells must be empty and
## clear of the picture except at the anchor itself, so the picture always
## reads as drawn; a cell brushing another extension line is fine when the
## touching pair could still grow. One line per anchor per axis. A joker plays
## into the line as its own kind of card — standing for the rank its slot needs
## (or a missing suit), exactly as in any set or run (Rules.assign_grid_line),
## and it locks to that. Line cards stay loose afterwards: any of them can be picked back
## up or moved on its own (the rest slide in toward the anchor) — only the
## picture itself is sealed. Returns "" on success or a human-readable reason.
func play_off_picture(anchor: Card, step: Vector2i, cards_to_play: Array[Card]) -> String:
	if cards_to_play.is_empty():
		return ""
	var picture: CardSet = null
	for m in board.melds_of(anchor):
		if m.is_shape():
			picture = m
	if picture == null:
		return "Lines like this start from a card in a picture group."
	if absi(step.x) + absi(step.y) != 1:
		return "Pick one straight direction to play in."
	cards_to_play = _expand_sticky(cards_to_play)
	# One line per anchor and axis; playing at an anchor that already carries
	# a line on this axis extends that line outward.
	var existing: CardSet = null
	for m in board.melds:
		if m.is_attached() and m.attach_anchor == anchor \
				and m.attach_step.abs() == step.abs():
			if m.attach_step != step:
				return "That card already carries its line out the other way."
			existing = m
	# A line off a picture must read as a full group of three counting the
	# anchor, so it takes at least two cards — a single card is not a play.
	var attached_len := existing.cards.size() if existing != null else 0
	if attached_len + cards_to_play.size() < 2:
		return "A line off a picture needs at least two cards — three counting " \
			+ "the picture card it hangs off."
	var err := _stage_error(cards_to_play, existing if existing != null else picture)
	if err != "":
		return err
	var ordered := _ordered_extension(anchor, existing, step, cards_to_play)
	if ordered.is_empty():
		var reason := "Those cards don't read as a straight set or run off %s." \
			% anchor.label()
		if step.x == 0:
			reason += " Vertical straights keep the lower rank on top."
		return reason
	err = _extension_cells_error(anchor, step,
		existing.cards.size() if existing != null else 0, ordered)
	if err != "":
		return err
	_push_undo()
	var line := existing
	if line == null:
		line = CardSet.new()
		line.attach_anchor = anchor
		line.attach_step = step
		line.orientation = CardSet.Orientation.VERTICAL if step.x == 0 \
			else CardSet.Orientation.HORIZONTAL
		board.melds.append(line)
	_move_cards(ordered, line)
	_lock_table_jokers()
	return ""

## The played cards in an order that reads legally at the end of the line
## (anchor + existing line + new cards), or [] when no order does. Tries the
## order given plus rank-ascending and -descending — enough, since a legal
## run line is monotone in rank and a set line is order-free. The reading needs
## at least three cards counting the anchor (Rules.is_valid_grid_line); a
## vertical straight must additionally read with the lower rank on top
## (Rules.line_direction_ok), so only one of the two rank orders can fit.
func _ordered_extension(anchor: Card, existing: CardSet, step: Vector2i,
		cards_to_play: Array[Card]) -> Array[Card]:
	var prefix: Array[Card] = [anchor]
	if existing != null:
		prefix.append_array(existing.cards)
	var asc := cards_to_play.duplicate()
	asc.sort_custom(func(a: Card, b: Card) -> bool: return a.rank < b.rank)
	var desc := asc.duplicate()
	desc.reverse()
	for order: Array[Card] in [cards_to_play, asc, desc]:
		var line := prefix.duplicate()
		line.append_array(order)
		var reads := Rules.is_valid_grid_line(line)
		if reads and Rules.line_direction_ok(line, step):
			return order
	var none: Array[Card] = []
	return none

## Why the cells the new line segment would cover are not playable, or "".
## Each cell must be empty, must not brush the picture anywhere past the
## anchor (outward only — the notch of the heart stays a notch), and may only
## brush another extension line where the touching pair could still grow.
func _extension_cells_error(anchor: Card, step: Vector2i,
		existing_len: int, ordered: Array[Card]) -> String:
	var cluster := BoardGrid.cluster_of(board, anchor)
	if cluster.is_empty():
		return "That card isn't laid out on the felt."
	var cells: Dictionary = cluster["cells"]
	var meld_at: Dictionary = cluster["meld_at"]
	var anchor_cell := Vector2i.ZERO
	var found := false
	for cell: Vector2i in cells:
		if cells[cell] == anchor:
			anchor_cell = cell
			found = true
			break
	if not found:
		return "That card isn't laid out on the felt."
	for i in ordered.size():
		var cell := anchor_cell + step * (existing_len + 1 + i)
		if cells.has(cell):
			return "No room that way — the line runs into other cards."
		for side in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n_cell: Vector2i = cell + side
			if n_cell == cell - step:
				continue  # the line itself: the anchor or the previous card
			var n: Card = cells.get(n_cell)
			if n == null:
				continue
			var n_meld: CardSet = meld_at.get(n_cell)
			if n_meld != null and n_meld.is_shape():
				return "Too snug against the picture — lines only extend " \
					+ "outward, keeping the picture readable."
			if not Rules.could_pair(ordered[i], n):
				return "%s can't sit beside %s — that pair could never grow " \
					% [ordered[i].label(), n.label()] + "into a group."
	return ""

## Move cards (from hand and/or table) into a brand-new SHAPE (picture) group
## laid out on the given grid cells — `cells` maps every moved card to its
## Vector2i cell, exactly one per card. Same staging, undo and legality as
## move_cards_to_new_meld; the picture itself is valid when its cells form one
## connected patch (CardSet). This is what the Cute Slime's ultimate plays
## through. Sealing cards into a picture is a mechanic, not an ordinary play:
## hand cards the picture swallows stop counting as played this turn, so the
## builder still has to play a real card or draw to end the turn. Returns ""
## on success or a human-readable reason.
func move_cards_to_new_shape(cards_to_move: Array[Card], cells: Dictionary) -> String:
	if cards_to_move.is_empty():
		return ""
	# The sticky expansion must not smuggle in cards the picture has no cell
	# for (a mover bound by slime could drag extras along), so settle the real
	# card list first and demand a perfect card<->cell match.
	cards_to_move = _expand_sticky(cards_to_move)
	if cards_to_move.size() != cells.size():
		return "The picture needs exactly one cell per card."
	for c in cards_to_move:
		if not cells.has(c):
			return "The picture needs exactly one cell per card."
	var from_hand: Array[Card] = []
	for c in cards_to_move:
		if current_player().hand.has(c):
			from_hand.append(c)
	var err := move_cards_to_new_meld(cards_to_move)
	if err != "":
		return err
	# move_cards_to_new_meld appends the new group last; shape it in place.
	var meld: CardSet = board.melds[-1]
	meld.set_shape(cells)
	# Drop the swallowed hand cards from the turn-start snapshot so they never
	# count toward cards_played_this_turn (the undo entry pushed above still
	# holds the original snapshot, so undoing the picture restores them). They
	# also stop being returnable to the hand — sealed is sealed.
	for c in from_hand:
		_hand_snapshot.erase(c)
	# Remember the picture's cards as placed this turn: a just-built shape can
	# still be reworked or picked apart until the turn ends, but is sealed from
	# the next turn on (see _stage_error's picture seal).
	for c in cards_to_move:
		if not _shaped_this_turn.has(c):
			_shaped_this_turn.append(c)
	board_changed.emit()
	return ""

## Layout groundwork (no card grants this in normal play yet — a future card
## mechanic will): stage a brand-new group that CROSSES an existing one at
## `pivot`. The pivot card stays in its current group AND becomes a member of
## the new one, which lies perpendicular across it on the felt — one card
## sitting in two combinations at once. Both groups remain ordinary melds:
## each must be valid at commit with the pivot counted in, and each can still
## take further cards (add_cards_to_meld works on either). Taking the pivot
## off the table removes it from both (Board.remove_card). Returns "" on
## success or a human-readable reason the move is not allowed.
func stage_cross_meld(pivot: Card, cards_to_move: Array[Card]) -> String:
	var host := board.meld_of(pivot)
	if host == null:
		return "The crossing card must already be in a group on the table."
	if host.is_shape() or host.is_attached():
		return "Crossings need a plain line group — pictures and their " \
			+ "extension lines follow their own rules."
	if board.melds_of(pivot).size() > 1:
		return "That card is already shared between two groups."
	if cards_to_move.is_empty():
		return ""
	if cards_to_move.has(pivot):
		return "The crossing card stays where it is — bring the other cards to it."
	cards_to_move = _expand_sticky(cards_to_move)
	# Crossing reads and builds on a table group, so the opening rule treats it
	# like adding to that group.
	var err := _stage_error(cards_to_move, host)
	if err != "":
		return err
	_push_undo()
	var meld := CardSet.new()
	meld.orientation = CardSet.Orientation.VERTICAL \
		if host.orientation == CardSet.Orientation.HORIZONTAL \
		else CardSet.Orientation.HORIZONTAL
	meld.add_card(pivot)  # shared: joins the new group without leaving its host
	board.melds.append(meld)
	_move_cards(cards_to_move, meld)
	_lock_table_jokers()
	return ""

## Undo just the last staged move this turn. Returns false if there was
## nothing to undo.
func undo_action() -> bool:
	if _undo_stack.is_empty():
		return false
	var snap: Dictionary = _undo_stack.pop_back()
	current_player().hand.assign(snap["hand"])
	board.restore(snap["board"])
	_hand_snapshot.assign(snap["snapshot"])
	_restore_locks(snap["locks"])
	board_changed.emit()
	return true

func can_undo_action() -> bool:
	return not _undo_stack.is_empty()

## Undo everything staged this turn: table and hand return to how they were
## at the start of the turn (the oldest undo entry holds exactly that state).
func reset_turn() -> void:
	if _undo_stack.is_empty():
		return
	var first: Dictionary = _undo_stack[0]
	current_player().hand.assign(first["hand"])
	board.restore(first["board"])
	_hand_snapshot.assign(first["snapshot"])
	_restore_locks(first["locks"])
	_undo_stack.clear()
	board_changed.emit()

func cards_played_this_turn() -> int:
	return _hand_snapshot.size() - current_player().hand.size()

## The cards the current player has moved from their hand onto the table this
## turn (in the turn-start snapshot but no longer in hand). Energy is the cost
## of these cards (energy_spent).
func cards_placed_this_turn() -> Array[Card]:
	var out: Array[Card] = []
	for c in _hand_snapshot:
		if not current_player().hand.has(c):
			out.append(c)
	return out

## True when every given card is one the current player laid down from hand
## this turn (still in the turn-start snapshot but no longer in the hand) —
## i.e. the whole batch may legally go back into the hand.
func can_return_to_hand(cards_to_return: Array[Card]) -> bool:
	if cards_to_return.is_empty():
		return false
	var p := current_player()
	for c in cards_to_return:
		if p.hand.has(c) or not _hand_snapshot.has(c):
			return false
	return true

## Take cards the current player laid down this turn back into their hand.
## Cards that started the turn on the table stay put. Returns "" on success
## or a human-readable reason the move is not allowed.
func return_cards_to_hand(cards_to_return: Array[Card]) -> String:
	if cards_to_return.is_empty():
		return ""
	if not can_return_to_hand(cards_to_return):
		return "Only cards you played from your hand this turn " \
			+ "can go back to your hand."
	_push_undo()
	var p := current_player()
	for c in cards_to_return:
		board.remove_card(c)
		p.hand.append(c)
		if c.is_joker:
			_free_joker(c)
	board.prune_empty()
	# Removing cards can leave a meld newly valid, so settle its jokers too.
	_lock_table_jokers()
	board_changed.emit()
	return ""

## Swap a natural card from the current player's hand for a joker on the
## table that currently stands for exactly that card (see Rules.assign_jokers).
## The joker comes back to the hand as a free wildcard. The natural card
## genuinely leaves the hand for the table, so the swap counts as playing a
## card — a swap alone is enough to end the turn. Returns "" on success or a
## human-readable reason the swap is not allowed.
func swap_joker(hand_card: Card, joker: Card, meld: CardSet) -> String:
	var p := current_player()
	# Collect the first reason (if any) the swap is illegal, then bail once.
	var err := ""
	if has_pending_choice():
		err = _pending_choice_error()
	elif not joker.is_joker or joker.joker_rank == 0:
		err = "That card is not a joker with a known value."
	elif not meld.cards.has(joker):
		err = "That joker is not in that group."
	elif not p.hand.has(hand_card) or hand_card.is_joker:
		err = "Only a real card from your hand can swap for a joker."
	elif hand_card.rank != joker.joker_rank or hand_card.suit != joker.joker_suit:
		err = "That joker stands for %s — only that exact card can swap for it." \
			% joker.rep_label()
	elif not current_player_is_open() and not is_own_staged_meld(meld):
		err = "You can't touch the table before opening — " \
			+ "lay down a valid group from your own hand first."
	# The swap counts as playing a card, so it needs room under the play cap.
	elif max_plays_per_turn > 0 and cards_played_this_turn() >= max_plays_per_turn:
		err = "You can only play %d cards in a turn." % max_plays_per_turn
	# ...and it costs the real card's energy, like any card played from hand.
	elif energy_on() and hand_card.cost > energy_left():
		err = _energy_error(hand_card.cost)
	if err != "":
		return err
	_push_undo()
	meld.cards[meld.cards.find(joker)] = hand_card
	# Even a picture gives its joker up to the exact card it stands for; the
	# real card takes over the joker's cell so the picture stays well-formed.
	if meld.is_shape():
		meld.shape_cells[hand_card] = meld.shape_cells[joker]
		meld.shape_cells.erase(joker)
	p.hand.erase(hand_card)
	p.hand.append(joker)
	# The joker now counts as a card the player started the turn with. The
	# natural card stays in the snapshot too — it was played from the hand to
	# the table, which is what makes the swap count as one played card.
	if not _hand_snapshot.has(joker):
		_hand_snapshot.append(joker)
	_free_joker(joker)
	board_changed.emit()
	return ""

## A joker back in a hand is a free wildcard again: shed the representation,
## the holder's old choice and the lock it carried on the table.
func _free_joker(joker: Card) -> void:
	joker.joker_rank = 0
	joker.joker_suit = ""
	joker.joker_pref_rank = 0
	joker.joker_pref_suit = ""
	joker.joker_lock_rank = 0
	joker.joker_lock_suit = ""

## True when this card left the current player's hand for the table this turn
## (it is in the turn-start snapshot but no longer in the hand).
func placed_this_turn(c: Card) -> bool:
	return _hand_snapshot.has(c) and not current_player().hand.has(c)

## Re-point a joker the current player placed this turn at another card it
## could stand for in its meld (see Rules.rechoice_alternatives). Jokers lock
## the moment they land in a valid meld, so this is the placer's one way to
## pick a different stand-in before their turn ends. Returns "" on success or
## a human-readable reason the choice is not allowed.
func set_joker_stand_in(joker: Card, meld: CardSet, rank: int, suit: String) -> String:
	if not joker.is_joker or not meld.cards.has(joker):
		return "That card is not a joker in that group."
	if not placed_this_turn(joker):
		return "Only a joker you placed this turn can be re-pointed."
	var fits := false
	for alt in Rules.rechoice_alternatives(meld.cards, joker):
		if alt["rank"] == rank and alt["suit"] == suit:
			fits = true
			break
	if not fits:
		return "The joker can't stand for that card in this group."
	_push_undo()
	joker.joker_pref_rank = rank
	joker.joker_pref_suit = suit
	joker.joker_lock_rank = rank
	joker.joker_lock_suit = suit
	Rules.assign_jokers(meld.cards)
	board_changed.emit()
	return ""

# --- The opening rule --------------------------------------------------------

## True when the current player may rearrange the table: either they opened on
## an earlier turn, or a valid new meld built purely from their own hand is
## staged on the table right now.
func current_player_is_open() -> bool:
	return current_player().has_opened or _staged_open_meld_exists()

## True for a meld made entirely of cards the current player has played from
## hand this turn (board cards can never be in the turn-start hand snapshot).
func is_own_staged_meld(meld: CardSet) -> bool:
	if meld.cards.is_empty():
		return false
	for c in meld.cards:
		if not _hand_snapshot.has(c):
			return false
	return true

func _staged_open_meld_exists() -> bool:
	for m in board.melds:
		if m.is_valid() and is_own_staged_meld(m):
			return true
	return false

## Why moving these cards is blocked right now — an event choice is still owed,
## or they would overrun the turn's play cap or energy (only the cards leaving
## the hand count) — or "" when the move may go ahead.
func _stage_block_error(cards_to_move: Array[Card]) -> String:
	if has_pending_choice():
		return _pending_choice_error()
	var p := current_player()
	var from_hand := 0
	var cost := 0
	for c in cards_to_move:
		if p.hand.has(c):
			from_hand += 1
			cost += c.cost
	if max_plays_per_turn > 0 and from_hand > 0 \
			and cards_played_this_turn() + from_hand > max_plays_per_turn:
		return "You can only play %d cards in a turn." % max_plays_per_turn
	if energy_on() and cost > energy_left():
		return _energy_error(cost)
	return ""

## Why the staged move is illegal under the play cap, energy, the opening rule, or the
## picture seal, or "" if it is fine. Cards in an extension line are NOT
## sealed: they come off one at a time like any table card (the line slides in
## toward its anchor and revalidates at commit), keeping the picture's own
## borders exactly as they were.
func _stage_error(cards_to_move: Array[Card], dest: CardSet) -> String:
	var p := current_player()
	# Picture cards are sealed in place — except the ones sealed in this very
	# turn, which can still be moved back off (or picked apart) until the turn
	# ends, like anything else you played this turn.
	var batch := {}
	for c in cards_to_move:
		batch[c] = true
	for m in board.melds:
		if m.is_shape():
			for c in m.cards:
				if batch.has(c) and not _shaped_this_turn.has(c):
					return "That card is sealed inside a picture."
	var budget_err := _stage_block_error(cards_to_move)
	if budget_err != "":
		return budget_err
	if current_player_is_open():
		return ""
	for c in cards_to_move:
		if not p.hand.has(c):
			return "You can't take cards from the table before opening — " \
				+ "lay down a valid group from your own hand first."
	if dest != null and not is_own_staged_meld(dest):
		return "You can't add to other groups before opening — " \
			+ "lay down a valid group from your own hand first."
	return ""

# --- Energy -----------------------------------------------------------------

## True when cards cost energy this game (start_energy > 0).
func energy_on() -> bool:
	return start_energy > 0

## Energy the current player has spent this turn: the cost of every card they
## have moved from hand to the table. Derived from the staged turn, so undoing a
## move or returning a card to the hand refunds it automatically.
func energy_spent() -> int:
	var spent := 0
	for c in cards_placed_this_turn():
		spent += c.cost
	return spent

## Energy the current player still has to spend this turn (0 when energy is off;
## check energy_on first).
func energy_left() -> int:
	if not energy_on():
		return 0
	return maxi(current_player().max_energy - energy_spent(), 0)

## How many more cards from hand the current player can afford this turn under
## both the play cap and energy, assuming each costs 1 (every card does for
## now); -1 when neither limit applies. The AI plans its moves inside this.
func play_budget() -> int:
	var budget := -1
	if max_plays_per_turn > 0:
		budget = maxi(max_plays_per_turn - cards_played_this_turn(), 0)
	if energy_on():
		budget = energy_left() if budget < 0 else mini(budget, energy_left())
	return budget

## The energy ceiling `p` will start their next turn with — their current
## ceiling while it is their turn. Lets the UI show an opponent's (or your own)
## energy between turns, including before their first turn.
func upcoming_energy(p: PlayerState) -> int:
	if not energy_on():
		return 0
	if p == current_player() and not is_game_over:
		return p.max_energy
	var ceiling := _energy_ceiling(p.turns_taken + 1) + p.bonus_energy
	# An Overcharge revealed this round still adds its bonus on p's turn if that
	# turn has yet to come this round.
	if p.player_id > turn_index and _revealed_this_round(MatchEvent.Id.OVERCHARGE):
		ceiling += MatchEvent.OVERCHARGE_ENERGY
	return ceiling

func _energy_error(cost: int) -> String:
	return "Not enough energy — that costs %d and you have %d left this turn." \
		% [cost, energy_left()]

## Set the current player's energy ceiling as their turn begins: start_energy on
## their first turn, energy_per_turn more each turn after, capped at energy_cap,
## plus any event bonus (Overcharge's +2 for good, Surge's +3 on its reveal
## turn — bonuses may go past the cap).
func _refill_energy(p: PlayerState) -> void:
	p.turns_taken += 1
	if not energy_on():
		p.max_energy = 0
		return
	p.max_energy = _energy_ceiling(p.turns_taken) + p.bonus_energy
	if _revealed_this_round(MatchEvent.Id.SURGE):
		p.max_energy += MatchEvent.SURGE_ENERGY

## The base energy ceiling on a player's `turn`-th turn (1 = their first).
func _energy_ceiling(turn: int) -> int:
	var ceiling := start_energy + (turn - 1) * energy_per_turn
	return mini(ceiling, energy_cap) if energy_cap > 0 else ceiling

# --- Ending the turn --------------------------------------------------------

## Try to end the turn keeping the staged plays. Returns "" on success, or a
## human-readable reason the turn is illegal (nothing is rolled back on
## failure, so the player can fix the table and try again).
func commit_turn() -> String:
	var p := current_player()
	var err := _commit_error(p)
	if err != "":
		return err
	# Jokers lock as they are placed, but settle the table once more so no
	# free wildcard ever survives a committed turn.
	_lock_table_jokers()
	_consecutive_passes = 0
	p.has_opened = true
	var played := cards_played_this_turn()
	turn_committed.emit(p, played)
	_charge_meter(p, played)
	if played > 0 and _revealed_this_round(MatchEvent.Id.COIN_RUSH):
		p.coins += played
		coins_gained.emit(p, played)
	if p.hand.is_empty():
		_end_game([p])
		return ""
	_advance()
	return ""

## Charge a player's ultimate meter for the hand they just committed:
## meter_gain points, times the cards played when meter_per_card is on, capped
## at meter_max (where it holds). A max of 0 disables the meter. Emits
## meter_charged with how much it actually rose and whether this filled it. A
## turn whose ultimate already fired banks nothing — those plays were spent.
func _charge_meter(p: PlayerState, cards_played: int) -> void:
	if _meter_spent_this_turn:
		return
	var gain := _pending_meter_gain(cards_played)
	if gain <= 0:
		return
	var before := p.meter
	p.meter = mini(meter_max, p.meter + gain)
	if p.meter != before:
		meter_charged.emit(p, p.meter - before, p.meter >= meter_max and before < meter_max)

## The meter charge this turn's plays are worth, matching _charge_meter's rule:
## meter_gain per card played when meter_per_card is on, else a flat meter_gain
## once any card has been played. 0 when the meter is off or nothing was played.
func _pending_meter_gain(cards_played: int) -> int:
	if meter_max <= 0 or cards_played <= 0:
		return 0
	var gain := meter_gain * cards_played if meter_per_card else meter_gain
	return maxi(gain, 0)

## The charge a player's meter shows right now. The current player's bar
## includes the charge their staged-but-uncommitted plays will bank at
## commit, so it fills live as they play and an ultimate can fire the very turn
## the bar completes. Everyone else shows their banked charge. Once the current
## player has spent their ultimate this turn the bar reads empty again — the
## plays that filled it are gone.
func projected_meter(p: PlayerState) -> int:
	if p != current_player() or _meter_spent_this_turn:
		return p.meter
	return mini(meter_max, p.meter + _pending_meter_gain(cards_played_this_turn()))

## Spend the current player's ultimate meter — an ultimate fired this turn.
## Drain it to zero and mark it spent, so this turn's plays neither recharge it
## nor let it fire again; charging resumes fresh next turn.
func spend_meter() -> void:
	current_player().meter = 0
	_meter_spent_this_turn = true

## Why the current turn can't be committed, or "" if it is legal. Split out so
## commit_turn keeps a single success path (the guard clauses live here).
func _commit_error(p: PlayerState) -> String:
	# An owed event choice comes first. Overrunning the cap or energy is normally
	# unreachable (staging enforces both), but the cap can be lowered mid-turn
	# from the settings dialog.
	var blocked := _commit_block_error(p)
	if blocked != "":
		return blocked
	if cards_played_this_turn() <= 0:
		return "You must play at least one card from your hand (or draw instead)."
	for c in p.hand:
		if not _hand_snapshot.has(c):
			return "Cards from the table cannot be taken into your hand."
	for m in board.melds:
		if not m.is_valid():
			return "Invalid group on the table: %s" % _meld_text(m)
	if not p.has_opened and not _staged_open_meld_exists():
		return "To open you must lay down at least one valid group " \
			+ "built only from your own hand."
	return ""

## Why the staged turn can't commit yet — an event choice is still owed, or it
## has played more than the play cap or energy allows — or "".
func _commit_block_error(p: PlayerState) -> String:
	if has_pending_choice():
		return _pending_choice_error()
	if max_plays_per_turn > 0 and cards_played_this_turn() > max_plays_per_turn:
		return "You can only play %d cards in a turn — return some to your hand." \
			% max_plays_per_turn
	if energy_on() and energy_spent() > p.max_energy:
		return "Not enough energy — return some cards to your hand."
	return ""

## Draw draw_per_turn cards from the player's own deck (or pass if it is empty)
## and end the turn.
##
## A staged table rearrangement that plays no card from the hand — the
## signature Machiavelli "shuffle the felt" move, which the Cute Slime uses to
## herd her slime together — is kept when it leaves every group valid, so a
## player can rework the board and still draw. Any other staging (a partial
## play, or a table left invalid mid-edit) is abandoned first, as before.
func draw_and_end_turn() -> void:
	# An event's choice comes first; the driver resolves it (resolve_choice).
	if has_pending_choice():
		return
	if cards_played_this_turn() != 0 or not _kept_rearrangement():
		reset_turn()
	else:
		# The rearrangement stays on the table, so lock its jokers exactly as a
		# committed turn would — the next player inherits a settled board.
		_lock_table_jokers()
		_undo_stack.clear()
	var p := current_player()
	var drawn: Array[Card] = []
	for _i in draw_count():
		if max_hand_size > 0 and p.hand.size() >= max_hand_size:
			break
		var card := p.deck.draw()
		if card == null:
			break
		p.hand.append(card)
		drawn.append(card)
	if not drawn.is_empty():
		cards_drawn.emit(p, drawn)
		_consecutive_passes = 0
	else:
		_consecutive_passes += 1
		player_passed.emit(p)
		if _consecutive_passes >= players.size():
			_end_game(_fewest_cards_winners())
			return
	_advance()

# --- Events -------------------------------------------------------------------
# See MatchEvent. Rule changes are read where they apply (energy refill, draw
# count, commit, the AI's view of deck tops); the turn-start effects and the
# pending choices live here.

## True while an ongoing event of this id is face up.
func is_event_active(id: MatchEvent.Id) -> bool:
	for e in revealed_events:
		if e.id == id and e.is_ongoing():
			return true
	return false

## Events still face down, each paired with the round it turns up on:
## [{"event": MatchEvent, "round": int}], in order. Rounds past the end of
## event_rounds never come, so those events are left out.
func upcoming_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in event_deck.size():
		var slot := revealed_events.size() + i
		if slot < event_rounds.size():
			out.append({"event": event_deck[i], "round": event_rounds[slot]})
	return out

## Cards a player draws when they draw: draw_per_turn, +1 while Extra Draw is in
## force.
func draw_count() -> int:
	return draw_per_turn + (1 if is_event_active(MatchEvent.Id.EXTRA_DRAW) else 0)

## True when `card` — the top of some player's deck — can be seen by everyone:
## a glass card always, any card while Open Decks is in force.
func top_is_public(card: Card) -> bool:
	return card != null and (card.is_glass() or is_event_active(MatchEvent.Id.OPEN_DECKS))

## Turn the next face-down event up right now and apply it to the current player
## as if it had been revealed at the start of their turn (other players get it on
## their turn this round). Returns false when there is nothing left to reveal or
## the current player has already staged moves. Rounds in event_rounds reveal on
## their own; this is for effects (and tests) that reveal one early.
func reveal_next_event() -> bool:
	if event_deck.is_empty() or not _undo_stack.is_empty():
		return false
	var e := _reveal(event_deck.pop_front())
	var p := current_player()
	_apply_reveal(p, e)
	if e.id == MatchEvent.Id.SURGE and energy_on():
		p.max_energy += MatchEvent.SURGE_ENERGY
	elif e.id == MatchEvent.Id.OVERCHARGE and energy_on():
		p.max_energy += MatchEvent.OVERCHARGE_ENERGY
	_hand_snapshot = p.hand.duplicate()
	board_changed.emit()
	return true

func has_pending_choice() -> bool:
	return not _pending_choice.is_empty()

## The choice the current player owes an event before playing, or {} for none:
## {"event": MatchEvent, "count": int} — pick `count` cards from hand.
func pending_choice() -> Dictionary:
	return _pending_choice

## Settle the current player's pending choice with these hand cards (exactly
## the count it asks for). Cycle discards them and draws as many; Gift hands
## them to the next player. Returns "" on success or the reason it is refused.
func resolve_choice(cards: Array[Card]) -> String:
	if not has_pending_choice():
		return "There is no event choice to make."
	var p := current_player()
	var e: MatchEvent = _pending_choice["event"]
	var count: int = _pending_choice["count"]
	var unique := {}
	for c in cards:
		if not p.hand.has(c):
			return "Choose cards from your hand."
		unique[c] = true
	if unique.size() != count:
		return "Choose exactly %d card%s." % [count, "" if count == 1 else "s"]
	_pending_choice = {}
	for c in cards:
		p.hand.erase(c)
	if e.id == MatchEvent.Id.GIFT:
		var receiver := players[(turn_index + 1) % players.size()]
		receiver.hand.append_array(cards)
		cards_given.emit(p, receiver, cards)
	else:
		for c in cards:
			p.deck.discard(c)
		cards_discarded.emit(p, cards)
		var drawn: Array[Card] = []
		for _i in cards.size():
			var c := p.deck.draw()
			if c == null:
				break
			p.hand.append(c)
			drawn.append(c)
		if not drawn.is_empty():
			cards_drawn.emit(p, drawn)
	_hand_snapshot = p.hand.duplicate()
	board_changed.emit()
	return ""

func _pending_choice_error() -> String:
	var e: MatchEvent = _pending_choice["event"]
	return "Resolve the %s event first: %s" % [e.title, e.text]

## Turn `e` face up and put its combo on the table: a random valid group of
## fresh cards from outside every deck (built now, from the first player's deck
## rng so a seeded game replays exactly), counted into copies_in_play.
func _reveal(e: MatchEvent) -> MatchEvent:
	e.revealed_round = round_number
	revealed_events.append(e)
	if e.combo.is_empty():
		e.combo = MatchEvent.random_combo(players[0].deck.rng)
	var meld := CardSet.new()
	for c in e.combo:
		meld.add_card(c)
		var key := "%d,%s" % [c.rank, c.suit]
		_copies[key] = _copies.get(key, 0) + 1
	board.melds.append(meld)
	event_revealed.emit(e)
	board_changed.emit()
	return e

## True when an on-reveal event of this id was revealed this round — its "this
## turn" covers every player's turn in the round.
func _revealed_this_round(id: MatchEvent.Id) -> bool:
	for e in revealed_events:
		if e.id == id and not e.is_ongoing() and e.revealed_round == round_number:
			return true
	return false

## Event effects at the start of `p`'s turn: a new round may turn the next event
## up, Attrition discards a random card, and an event revealed this round asks
## for its choice. A choice never takes a player's last card, so no event can end
## a match on its own (and Attrition leaves a one-card hand alone).
func _start_of_turn_events(p: PlayerState) -> void:
	if turn_index == 0 and not event_deck.is_empty() \
			and revealed_events.size() < event_rounds.size() \
			and event_rounds[revealed_events.size()] <= round_number:
		_reveal(event_deck.pop_front())
	if is_event_active(MatchEvent.Id.ATTRITION) and p.hand.size() > 1:
		var lost := p.hand[p.deck.rng.randi_range(0, p.hand.size() - 1)]
		p.hand.erase(lost)
		p.deck.discard(lost)
		var discarded: Array[Card] = [lost]
		cards_discarded.emit(p, discarded)
	for e in revealed_events:
		if not e.is_ongoing() and e.revealed_round == round_number:
			_apply_reveal(p, e)

## The once-per-player part of an on-reveal event: Overcharge raises the
## player's max energy for good, Cycle and Gift queue a choice (Surge and Coin
## Rush are read where they apply).
func _apply_reveal(p: PlayerState, e: MatchEvent) -> void:
	if e.id == MatchEvent.Id.OVERCHARGE:
		p.bonus_energy += MatchEvent.OVERCHARGE_ENERGY
	var count := 0
	if e.id == MatchEvent.Id.CYCLE:
		count = mini(MatchEvent.CHOICE_COUNT, p.hand.size())
	elif e.id == MatchEvent.Id.GIFT:
		count = mini(MatchEvent.CHOICE_COUNT, p.hand.size() - 1)
	if count > 0:
		_pending_choice = {"event": e, "count": count}

# --- Mechanic-driven turns ---------------------------------------------------
# Primitives a designed enemy uses to drive a turn that isn't an ordinary
# play-or-draw (see Enemy.wants_control). Centralized here so pass/advance/round
# bookkeeping stays in one place.

## End the game with these winners — the win path for mechanics that go out
## outside the ordinary empty-hand check.
func win_now(winners: Array) -> void:
	_end_game(winners)

## Advance to the next player after a mechanic resolved the turn without a
## commit or a pass (a card left the stock, so this is not a pass).
func advance_after_action() -> void:
	_consecutive_passes = 0
	_advance()

## Register a pass for the current player (nothing they can draw), ending the
## game if this completes a full round of passes.
func pass_turn() -> void:
	var p := current_player()
	_consecutive_passes += 1
	player_passed.emit(p)
	if _consecutive_passes >= players.size():
		_end_game(_fewest_cards_winners())
		return
	_advance()

# --- Internals ---------------------------------------------------------------

## True when this turn has staged at least one move and left the whole table
## valid — a pure table rearrangement worth keeping when the player draws
## instead of committing a hand play. The caller checks cards_played first, so
## reaching here already means no card left the hand.
func _kept_rearrangement() -> bool:
	return not _undo_stack.is_empty() and board.all_valid()

## Lock every joker sitting in a valid meld to the card it currently stands
## for: from then on every rule treats it as exactly that card (no longer a
## wildcard) until it returns to a hand. Runs after every staged move — a
## joker is only wild while it is in someone's hand — plus at commit and when
## a drawn turn keeps a rearrangement, as a final settle. Jokers in a meld
## that is still invalid mid-edit have no representation yet, so they stay
## free until the meld first turns valid. The placer can still re-point a
## joker this turn via set_joker_stand_in.
func _lock_table_jokers() -> void:
	for m in board.melds:
		# A picture line reads by spatial position, so its jokers are assigned
		# from their slot (anchor prepended); every other group is order-free.
		if m.is_attached():
			var line: Array[Card] = [m.attach_anchor]
			line.append_array(m.cards)
			Rules.assign_grid_line(line, m.attach_step)
		else:
			Rules.assign_jokers(m.cards)
		for c in m.cards:
			if c.is_joker and c.joker_lock_rank == 0 and c.joker_rank > 0:
				c.joker_lock_rank = c.joker_rank
				c.joker_lock_suit = c.joker_suit

## Grow a move so it drags whole slime clusters: any card in cards_to_move that
## sits on the table pulls its full sticky_cluster along (see CardSet). Cluster
## members are emitted contiguously in board order so the cluster keeps its
## arrangement wherever it lands, which keeps the bonds intact for next time.
## Hand cards (not on any meld) pass through untouched, so a hand-only play is
## never affected. The Cute Slime slips her own slime freely, so a player that
## ignores_sticky is never expanded. Idempotent: expanding an already-whole
## cluster changes nothing, so it is safe to call over UI moves that expanded.
func _expand_sticky(cards_to_move: Array[Card]) -> Array[Card]:
	if current_player().ignores_sticky:
		return cards_to_move
	var out: Array[Card] = []
	for c in cards_to_move:
		if out.has(c):
			continue
		var meld := board.meld_of(c)
		if meld == null:
			out.append(c)
			continue
		for m in meld.sticky_cluster(c):
			if not out.has(m):
				out.append(m)
	return out

func _move_cards(cards_to_move: Array[Card], dest: CardSet) -> void:
	var p := current_player()
	for c in cards_to_move:
		if p.hand.has(c):
			p.hand.erase(c)
		else:
			board.remove_card(c)
		if not dest.cards.has(c):
			dest.add_card(c)
	board.prune_empty()
	board_changed.emit()

func _push_undo() -> void:
	_undo_stack.append({
		"hand": current_player().hand.duplicate(),
		"board": board.snapshot(),
		"snapshot": _hand_snapshot.duplicate(),
		"locks": _joker_locks(),
	})

## Joker locks live on the cards, not in the board's card lists, so undoing a
## move must put the lock back explicitly: a swap cleared it, a staged play
## set it. The current player's hand is included so undoing the play of a
## joker also undoes the lock it picked up on the table.
func _joker_locks() -> Dictionary:
	var out := {}
	for c in board.all_cards() + current_player().hand:
		if c.is_joker:
			out[c] = [c.joker_lock_rank, c.joker_lock_suit]
	return out

func _restore_locks(locks: Dictionary) -> void:
	for c: Card in locks:
		c.joker_lock_rank = locks[c][0]
		c.joker_lock_suit = locks[c][1]

func _begin_turn() -> void:
	var p := current_player()
	_pending_choice = {}
	_start_of_turn_events(p)
	_refill_energy(p)
	_hand_snapshot = p.hand.duplicate()
	_undo_stack.clear()
	_meter_spent_this_turn = false
	_shaped_this_turn.clear()
	turn_started.emit(p)

func _advance() -> void:
	if is_game_over:
		return
	turn_index = (turn_index + 1) % players.size()
	# Wrapping back to the first player opens a fresh round of play.
	if turn_index == 0:
		round_number += 1
	_begin_turn()

func _end_game(winners: Array) -> void:
	is_game_over = true
	game_over.emit(winners)

func _fewest_cards_winners() -> Array:
	var best := players[0].hand.size()
	for p in players:
		best = mini(best, p.hand.size())
	var winners: Array = []
	for p in players:
		if p.hand.size() == best:
			winners.append(p)
	return winners

func _meld_text(m: CardSet) -> String:
	var parts := PackedStringArray()
	for c in m.cards:
		parts.append(c.label())
	return " ".join(parts)
