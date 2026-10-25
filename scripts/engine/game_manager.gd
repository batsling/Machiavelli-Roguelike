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
##    costs its energy (card_cost: Card.cost, unless an instance rule sets it). A player starts their first turn with
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
##  - Instances (optional, see MatchInstance): rule cards in instance_deck are revealed
##    one at the start of each round listed in instance_rounds and affect every
##    player — on each player's turn of the reveal round (Reveal) or every turn
##    for the rest of the match (Ongoing), running the commands of its Effect
##    (see InstanceEffect). A choice an instance asks for is a pending
##    choice the current player resolves (resolve_choice) before playing. Each
##    instance also puts a random three-card combo of fresh cards (from no one's
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
## An instance was turned face up (see MatchInstance).
signal instance_revealed(instance: MatchInstance)
## The instances took their turn, which opens every round (before the first
## player): `revealed` is the instance that turned up, or null for none.
signal instance_turn_played(round: int, revealed: MatchInstance)
## Cards left a player's hand for their deck's discard pile because of an instance.
signal cards_discarded(player: PlayerState, cards: Array[Card])
## A player handed cards from their hand to another player's hand (the Gift instance).
signal cards_given(giver: PlayerState, receiver: PlayerState, cards: Array[Card])
## A player earned coins at commit: coins_per_card rules, and cards played into
## a group holding an instance combo card (MatchInstance.COMBO_COINS each).
signal coins_gained(player: PlayerState, amount: int)
## An instance destroyed these cards (a whole group) off the table; each went to
## its deck's discard pile.
signal cards_destroyed(instance: MatchInstance, cards: Array[Card])
## An instance gave these hand cards a random rank and suit (`before` holds their
## old labels, in order).
signal cards_jumbled(player: PlayerState, cards: Array[Card], before: PackedStringArray)
## An instance changed these hand cards' energy cost by `delta` for good.
signal costs_changed(player: PlayerState, cards: Array[Card], delta: int)
## Fired when a committed hand charges a player's ultimate meter. `amount` is
## how much the meter actually rose (0 is never emitted), and `now_full` is
## true on the charge that first fills it, so the UI can announce it.
signal meter_charged(player: PlayerState, amount: int, now_full: bool)

const DEFAULT_HAND_SIZE := 13

var players: Array[PlayerState] = []
var board := Board.new()
var turn_index := 0
## The current round of play. A round is the instances' turn (when the match
## has instances, see _instance_turn), then one turn per player in seat order —
## you, then each enemy clockwise around the table. The count ticks up each time
## play wraps back to the first player (turn_index 0).
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
## The opening rule (classic Machiavelli): until a player has laid a valid group
## built only from their own hand, they may not add to or take from other groups.
## Off by default — anyone may work the whole table from their first turn — and
## kept as a switch so an item or enemy can bring it back.
var opening_rule := false
var energy_per_turn := 1
var energy_cap := 10
## Instances still face down, in reveal order. Set before setup (like the energy
## rules); setup resets every instance to face down. Empty = no instances (sandbox).
var instance_deck: Array[MatchInstance] = []
## The rounds an instance is revealed on, one per round in order; the next face-down
## instance turns up at the start of each listed round.
var instance_rounds: Array[int] = [1, 3, 5, 7, 9]
## Instances turned face up this match, in reveal order.
var revealed_instances: Array[MatchInstance] = []
## Each player's starting combo (deal_starting_melds): player_id -> the cards it
## laid, so the table can name where a group came from. Empty without them.
var starting_combos := {}
# The choice the current player owes an instance this turn, or {} for none (see
# pending_choice; "rest" and "used" carry the instance's remaining commands).
# Staging, committing and drawing wait until resolve_choice settles it.
var _pending_choice := {}
# The instances still to act on the current player's turn, after the one whose
# choice is pending (see _start_of_turn_instances).
var _instance_queue: Array[MatchInstance] = []

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
	revealed_instances.clear()
	starting_combos.clear()
	for e in instance_deck:
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
	_instance_turn()
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
		starting_combos[p.player_id] = pulled
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
	elif energy_on() and card_cost(hand_card) > energy_left():
		err = _energy_error(card_cost(hand_card))
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
## Always true while the opening rule is off.
func current_player_is_open() -> bool:
	if not opening_rule:
		return true
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

## Why moving these cards is blocked right now — an instance choice is still owed,
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
			cost += card_cost(c)
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
		spent += card_cost(c)
	return spent

## Energy the current player still has to spend this turn (0 when energy is off;
## check energy_on first).
func energy_left() -> int:
	if not energy_on():
		return 0
	return maxi(current_player().max_energy - energy_spent(), 0)

## How many more cards from hand the current player can afford this turn under
## both the play cap and energy — for energy, as many of their cheapest hand
## cards as fit in what is left; -1 when neither limit applies. The AI plans its
## moves inside this (and GreedyAI.plan_move drops a move it can't pay for).
func play_budget() -> int:
	var budget := -1
	if max_plays_per_turn > 0:
		budget = maxi(max_plays_per_turn - cards_played_this_turn(), 0)
	if energy_on():
		var costs: Array[int] = []
		for c in current_player().hand:
			costs.append(card_cost(c))
		costs.sort()
		var left := energy_left()
		var affordable := 0
		for cost in costs:
			if cost > left:
				break
			left -= cost
			affordable += 1
		budget = affordable if budget < 0 else mini(budget, affordable)
	return budget

## The energy the hand cards among `cards` cost to play now.
func cost_of(cards: Array[Card]) -> int:
	var total := 0
	for c in cards:
		if current_player().hand.has(c):
			total += card_cost(c)
	return total

## The energy ceiling `p` will start their next turn with — their current
## ceiling while it is their turn. Lets the UI show an opponent's (or your own)
## energy between turns, including before their first turn.
func upcoming_energy(p: PlayerState) -> int:
	if not energy_on():
		return 0
	if p == current_player() and not is_game_over:
		return p.max_energy
	var ceiling := _energy_ceiling(p.turns_taken + 1) + p.bonus_energy
	# A Reveal instance from this round still acts on p's turn if that turn has
	# yet to come this round; past this round, only Ongoing ones do.
	var later_this_round := p.player_id > turn_index
	for e in revealed_instances:
		if e.is_ongoing() or (later_this_round and e.revealed_round == round_number):
			for eff in e.effects_of(InstanceEffect.Verb.MAX_ENERGY) \
					+ e.effects_of(InstanceEffect.Verb.ENERGY):
				ceiling += eff.count
	return maxi(ceiling, 0)

func _energy_error(cost: int) -> String:
	return "Not enough energy — that costs %d and you have %d left this turn." \
		% [cost, energy_left()]

## Set the current player's energy ceiling as their turn begins: start_energy on
## their first turn, energy_per_turn more each turn after, capped at energy_cap,
## plus any instance bonus (max_energy for good, an energy rule for the turn —
## bonuses may go past the cap).
func _refill_energy(p: PlayerState) -> void:
	p.turns_taken += 1
	_set_max_energy(p)

## The current player's ceiling this turn (see _refill_energy), recomputed when
## an instance changes it mid-turn.
func _set_max_energy(p: PlayerState) -> void:
	if not energy_on():
		p.max_energy = 0
		return
	p.max_energy = maxi(_energy_ceiling(p.turns_taken) + p.bonus_energy
		+ _rule_total(InstanceEffect.Verb.ENERGY), 0)

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
	var coins := pending_coins()
	if coins > 0:
		p.coins += coins
		coins_gained.emit(p, coins)
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
	# An owed instance choice comes first. Overrunning the cap or energy is normally
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
	if opening_rule and not p.has_opened and not _staged_open_meld_exists():
		return "To open you must lay down at least one valid group " \
			+ "built only from your own hand."
	return ""

## Why the staged turn can't commit yet — an instance choice is still owed, or it
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
	# An instance's choice comes first; the driver resolves it (resolve_choice).
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

# --- Instances -------------------------------------------------------------------
# See MatchInstance and InstanceEffect. An instance's Effect is a list of
# commands. Player commands run on a player's turn (each player's turn of the
# reveal round for a Reveal instance, the start of every turn for an Ongoing
# one); rule commands are read where they apply (energy refill, draw count, card
# costs, commit, deck tops) during those same turns; table commands run once at
# a reveal (and each round for an Ongoing instance). A `choose` command pauses
# the list as a pending choice until resolve_choice settles it.

## Every rule command in force on the current player's turn: an Ongoing
## instance's always, a Reveal instance's only in its reveal round.
func _active_rules(verb: InstanceEffect.Verb) -> Array[InstanceEffect]:
	var out: Array[InstanceEffect] = []
	for e in revealed_instances:
		if e.is_ongoing() or e.revealed_round == round_number:
			out.append_array(e.effects_of(verb))
	return out

func _rule_total(verb: InstanceEffect.Verb) -> int:
	var total := 0
	for eff in _active_rules(verb):
		total += eff.count
	return total

## Instances still face down, each paired with the round it turns up on:
## [{"instance": MatchInstance, "round": int}], in order. Rounds past the end of
## instance_rounds never come, so those instances are left out.
func upcoming_instances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in instance_deck.size():
		var slot := revealed_instances.size() + i
		if slot < instance_rounds.size():
			out.append({"instance": instance_deck[i], "round": instance_rounds[slot]})
	return out

## Cards a draw takes: draw_per_turn plus any draw_bonus in force.
func draw_count() -> int:
	return maxi(draw_per_turn + _rule_total(InstanceEffect.Verb.DRAW_BONUS), 0)

## True when this deck-top card's face is public: a glass card always is, and
## every top is while an open_decks rule is in force.
func top_is_public(card: Card) -> bool:
	return card != null and (card.is_glass() \
		or not _active_rules(InstanceEffect.Verb.OPEN_DECKS).is_empty())

## The energy a card costs to play right now: its own cost (which `cost random
## N ±D` changes for good), unless a `cost FILTER V` rule in force sets it.
## Never below 0.
func card_cost(c: Card) -> int:
	var cost := c.cost
	for eff in _active_rules(InstanceEffect.Verb.COST_RULE):
		if eff.matches(c):
			cost = eff.amount
	return maxi(cost, 0)

## True when `c` came with an instance's combo and still sits outside every deck.
func is_instance_card(c: Card) -> bool:
	return c.from_instance

## Coins the current player's staged turn will earn at commit: the coins per
## card any coins_per_card rule in force pays, plus MatchInstance.COMBO_COINS
## for each card played from hand into a group holding an instance combo card.
func pending_coins() -> int:
	var placed := cards_placed_this_turn()
	return placed.size() * _rule_total(InstanceEffect.Verb.COINS_PER_CARD) \
		+ pending_combo_coins()

## The combo part of pending_coins: COMBO_COINS per card played from hand that
## sits in a group holding an instance combo card.
func pending_combo_coins() -> int:
	var n := 0
	for c in cards_placed_this_turn():
		var meld := board.meld_of(c)
		if meld != null and meld_has_instance_card(meld):
			n += 1
	return n * MatchInstance.COMBO_COINS

func meld_has_instance_card(meld: CardSet) -> bool:
	for c in meld.cards:
		if is_instance_card(c):
			return true
	return false

## Turn the next face-down instance up right now and apply it to the current
## player straight away, as if it had been revealed at the start of their turn.
## For testing and future card effects; refused when none are left or when the
## current player has already staged moves. Rounds in instance_rounds reveal on
## their own.
func reveal_next_instance() -> bool:
	if instance_deck.is_empty() or not _undo_stack.is_empty():
		return false
	var e := _reveal(instance_deck.pop_front())
	var p := current_player()
	_run_instance(p, e, e.effects)
	_set_max_energy(p)
	_hand_snapshot = p.hand.duplicate()
	board_changed.emit()
	return true

func has_pending_choice() -> bool:
	return not _pending_choice.is_empty()

## The choice the current player owes an instance before playing, or {} for none:
## {"instance": MatchInstance, "effect": InstanceEffect, "count": int} — pick
## `count` cards from hand for that command.
func pending_choice() -> Dictionary:
	return _pending_choice

## What the pending choice will do with the picked cards ("discard", "give", ...).
func pending_choice_verb() -> String:
	if not has_pending_choice():
		return ""
	var eff: InstanceEffect = _pending_choice["effect"]
	return eff.source.split(" ")[0]

## Settle the current player's pending choice with these hand cards (exactly the
## count it asks for): the command acts on them, then the rest of the
## instance's commands run. Returns "" on success or the reason it is refused.
func resolve_choice(cards: Array[Card]) -> String:
	if not has_pending_choice():
		return "There is no instance choice to make."
	var p := current_player()
	var e: MatchInstance = _pending_choice["instance"]
	var eff: InstanceEffect = _pending_choice["effect"]
	var count: int = _pending_choice["count"]
	var unique := {}
	for c in cards:
		if not p.hand.has(c):
			return "Choose cards from your hand."
		if not eff.matches(c):
			return "That card doesn't fit: %s." % eff.source
		unique[c] = true
	if unique.size() != count:
		return "Choose exactly %d card%s." % [count, "" if count == 1 else "s"]
	var rest: Array[InstanceEffect] = _pending_choice["rest"]
	var used: Dictionary = _pending_choice["used"]
	_pending_choice = {}
	_act_on_cards(p, eff, cards)
	for c in cards:
		used[c] = true
	_run_instance(p, e, rest, used)
	if not has_pending_choice():
		_continue_instances(p)
	_set_max_energy(p)
	_hand_snapshot = p.hand.duplicate()
	board_changed.emit()
	return ""

func _pending_choice_error() -> String:
	var e: MatchInstance = _pending_choice["instance"]
	return "Resolve the %s instance first: %s" % [e.title, e.text]

## Turn `e` face up and put its combo on the table: a random valid group of
## fresh cards from outside every deck (built now, from the first player's deck
## rng so a seeded game replays exactly), counted into copies_in_play. A Reveal
## instance's table commands happen now, once.
func _reveal(e: MatchInstance) -> MatchInstance:
	e.revealed_round = round_number
	revealed_instances.append(e)
	if e.combo.is_empty():
		e.combo = MatchInstance.random_combo(players[0].deck.rng)
	var meld := CardSet.new()
	for c in e.combo:
		meld.add_card(c)
		_count_copy(c, 1)
	board.melds.append(meld)
	instance_revealed.emit(e)
	if not e.is_ongoing():
		_run_table_commands(e)
	board_changed.emit()
	return e

## The instances' turn, which opens every round before the first player's turn:
## every Ongoing instance's table commands run, then the next face-down
## instance turns up if this round is on the schedule (running a Reveal
## instance's table commands). Emits instance_turn_played — even in a round
## where nothing turns up, so the UI can show the turn. A match with no
## instances at all (the sandbox) has no instances' turn.
func _instance_turn() -> void:
	if instance_deck.is_empty() and revealed_instances.is_empty():
		return
	for e in revealed_instances:
		if e.is_ongoing():
			_run_table_commands(e)
	var revealed: MatchInstance = null
	if not instance_deck.is_empty() \
			and revealed_instances.size() < instance_rounds.size() \
			and instance_rounds[revealed_instances.size()] <= round_number:
		revealed = _reveal(instance_deck.pop_front())
	instance_turn_played.emit(round_number, revealed)

## True when this match has instances, so each round opens with their turn.
func has_instance_turn() -> bool:
	return not instance_deck.is_empty() or not revealed_instances.is_empty()

## Instance effects at the start of `p`'s turn (the instances' own turn has
## already opened the round): each Ongoing instance's player commands run, and
## each Reveal instance revealed this round runs its player commands for `p`. A
## `choose` stops the run there as a pending choice; the rest continues once it
## is resolved.
func _start_of_turn_instances(p: PlayerState) -> void:
	_instance_queue.clear()
	for e in revealed_instances:
		if e.is_ongoing() or e.revealed_round == round_number:
			_instance_queue.append(e)
	_continue_instances(p)

## Run the queued instances for `p` in turn, stopping at a pending choice.
func _continue_instances(p: PlayerState) -> void:
	while not _instance_queue.is_empty() and not has_pending_choice():
		var e: MatchInstance = _instance_queue.pop_front()
		_run_instance(p, e, e.effects)

## Run `effects` (player commands only) for `p` in order, stopping at a `choose`
## that has cards to pick, which becomes the pending choice holding the rest.
## `used` holds the cards earlier commands of this instance already picked, so a
## later `random` pick takes "other" cards.
func _run_instance(p: PlayerState, e: MatchInstance, effects: Array[InstanceEffect],
		used := {}) -> void:
	for i in effects.size():
		var eff := effects[i]
		if eff.scope() != InstanceEffect.Scope.PLAYER:
			continue
		match eff.verb:
			InstanceEffect.Verb.DRAW:
				_draw_cards(p, eff.count)
			InstanceEffect.Verb.DRAW_JOKER:
				_draw_jokers(p, eff.count)
			InstanceEffect.Verb.MAX_ENERGY:
				p.bonus_energy += eff.count
			_:
				var pool := _pickable(p, eff, used)
				var n := pool.size() if eff.pick == InstanceEffect.Pick.ALL \
					else mini(eff.count, pool.size())
				if n <= 0:
					continue
				if eff.pick == InstanceEffect.Pick.CHOOSE:
					var rest: Array[InstanceEffect] = []
					rest.assign(effects.slice(i + 1))
					_pending_choice = {"instance": e, "effect": eff, "count": n,
						"rest": rest, "used": used}
					return
				var picked: Array[Card] = []
				for _k in n:
					var c: Card = pool.pop_at(p.deck.rng.randi_range(0, pool.size() - 1))
					picked.append(c)
					used[c] = true
				_act_on_cards(p, eff, picked)

## The hand cards a pick command may take: those passing its filter and not
## already picked by this instance. Discarding and giving never take a player's
## last card, so no instance can end a match on its own.
func _pickable(p: PlayerState, eff: InstanceEffect, used: Dictionary) -> Array[Card]:
	var out: Array[Card] = []
	for c in p.hand:
		if eff.matches(c) and not used.has(c):
			out.append(c)
	if eff.verb in [InstanceEffect.Verb.DISCARD, InstanceEffect.Verb.GIVE]:
		while not out.is_empty() and p.hand.size() - out.size() < 1:
			out.pop_back()
	return out

## Apply a pick command to the cards picked for it.
func _act_on_cards(p: PlayerState, eff: InstanceEffect, cards: Array[Card]) -> void:
	match eff.verb:
		InstanceEffect.Verb.DISCARD:
			for c in cards:
				p.hand.erase(c)
				p.deck.discard(c)
			cards_discarded.emit(p, cards)
		InstanceEffect.Verb.GIVE:
			var receiver := players[(players.find(p) + 1) % players.size()]
			for c in cards:
				p.hand.erase(c)
			receiver.hand.append_array(cards)
			cards_given.emit(p, receiver, cards)
		InstanceEffect.Verb.JUMBLE:
			var before := PackedStringArray()
			for c in cards:
				before.append(c.label())
				_count_copy(c, -1)
				c.is_joker = false
				c.rank = p.deck.rng.randi_range(1, 13)
				c.suit = Deck.SUITS[p.deck.rng.randi_range(0, Deck.SUITS.size() - 1)]
				c.joker_rank = 0
				c.joker_suit = ""
				_count_copy(c, 1)
			cards_jumbled.emit(p, cards, before)
		InstanceEffect.Verb.COST_CHANGE:
			for c in cards:
				c.cost = maxi(c.cost + eff.amount, 0)
			costs_changed.emit(p, cards, eff.amount)

## Draw up to `n` cards from `p`'s own deck (a location draw, outside the turn's
## draw), stopping at the hand cap or an empty deck.
func _draw_cards(p: PlayerState, n: int) -> void:
	var drawn: Array[Card] = []
	for _i in n:
		if max_hand_size > 0 and p.hand.size() >= max_hand_size:
			break
		var c := p.deck.draw()
		if c == null:
			break
		p.hand.append(c)
		drawn.append(c)
	if not drawn.is_empty():
		cards_drawn.emit(p, drawn)

## Take up to `n` jokers from `p`'s deck — or its discard pile — into their hand.
func _draw_jokers(p: PlayerState, n: int) -> void:
	var drawn: Array[Card] = []
	for pile: Array[Card] in [p.deck.cards, p.deck.discards]:
		for c in pile.duplicate():
			if drawn.size() >= n:
				break
			if c.is_joker:
				pile.erase(c)
				p.hand.append(c)
				drawn.append(c)
	if not drawn.is_empty():
		cards_drawn.emit(p, drawn)

## An instance's table commands (destroy), run on the instances' turn.
## Destroyed cards go to their deck's discard pile; a combo card (from no one's
## deck) goes to the discard pile of the player who acts first in the round,
## and is theirs from then on.
func _run_table_commands(e: MatchInstance) -> void:
	for eff in e.effects:
		if eff.verb != InstanceEffect.Verb.DESTROY_COMBO or board.melds.is_empty():
			continue
		var rng := players[0].deck.rng
		var meld: CardSet = board.melds[rng.randi_range(0, board.melds.size() - 1)]
		var gone: Array[Card] = meld.cards.duplicate()
		board.melds.erase(meld)
		for c in gone:
			if c.is_joker:
				c.joker_lock_rank = 0
				c.joker_lock_suit = ""
			if is_instance_card(c):
				c.deck_owner = current_player().player_id
				c.from_instance = false
			players[c.deck_owner].deck.discard(c)
		cards_destroyed.emit(e, gone)

func _count_copy(c: Card, delta: int) -> void:
	if c.is_joker:
		return
	var key := "%d,%s" % [c.rank, c.suit]
	_copies[key] = _copies.get(key, 0) + delta

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
	_instance_queue.clear()
	_start_of_turn_instances(p)
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
	# Wrapping back to the first player opens a fresh round of play, which
	# starts with the instances' turn.
	if turn_index == 0:
		round_number += 1
		_instance_turn()
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
