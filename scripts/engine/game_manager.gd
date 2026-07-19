class_name GameManager
extends Node

## Core engine for a vanilla game of Machiavelli (the Italian rummy variant).
##
## Rules implemented:
##  - Two full 52-card decks (plus 4 wildcards when jokers are enabled); each
##    player is dealt a starting hand, the rest forms the stock.
##  - On your turn you either play at least one card from your hand onto the
##    table, or draw from the stock (draw_per_turn cards). While playing you may freely
##    rearrange every meld on the table — the only requirement is that when
##    the turn ends, every meld on the table is valid (Rules.is_valid_meld).
##  - Opening: until a player has laid down at least one valid meld built
##    entirely from their own hand, they may not touch the rest of the table —
##    no adding to other melds and no taking cards from them. Laying a valid
##    own meld unlocks table play immediately (even mid-turn), and once a
##    turn containing such a meld is committed the player stays open for the
##    rest of the game. This applies to every player, human and AI.
##  - First player to empty their hand wins. If the stock is empty and every
##    player passes in a full round, the game ends and whoever holds the
##    fewest cards wins (ties shared).
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
signal card_drawn(player: PlayerState, card: Card)
signal turn_committed(player: PlayerState, cards_played: int)
signal player_passed(player: PlayerState)
signal game_over(winners: Array)

const DEFAULT_HAND_SIZE := 13

var players: Array[PlayerState] = []
var board := Board.new()
var deck: Deck = null
var turn_index := 0
## The current round of play: every player takes one turn per round, and the
## count ticks up each time play wraps back to the first player (turn_index 0).
## Starts at 1 the moment the game is dealt. This is the table's own round
## counter, distinct from the roguelike ladder round (which enemy you face).
var round_number := 1
var is_game_over := false
## How many cards a player draws when they draw instead of playing (1-3 from
## the settings menu). Drawing stops early when the stock runs dry; a turn
## only counts as a pass when zero cards could be drawn.
var draw_per_turn := 1
## Optional hand cap (0 = none, 10-20 from the settings menu). Drawing stops
## at the cap, so a draw attempted with a full hand is a pass; a full round
## of passes still ends the game with fewest cards winning.
var max_hand_size := 0
## Optional cap on cards played per turn (0 = none, 10-20 from the settings
## menu). Only cards leaving the hand count — rearranging the table is always
## free — and returning a played card to the hand gives the play back.
var max_plays_per_turn := 0

# Staging state for the current turn. _hand_snapshot is the current player's
# hand at the start of the turn; swap_joker() appends to it in place (the
# joker legally becomes "a card you started the turn with"), which is why
# every undo entry carries its own copy.
var _hand_snapshot: Array[Card] = []
# One {hand, board, snapshot} state per staged move, so moves can be undone.
var _undo_stack: Array[Dictionary] = []
var _consecutive_passes := 0

func setup(player_names: Array, hand_size: int = DEFAULT_HAND_SIZE, seed_value: int = -1,
		include_jokers := false) -> void:
	players.clear()
	board = Board.new()
	deck = Deck.new(seed_value)
	deck.build_double_deck(include_jokers)
	deck.shuffle()
	turn_index = 0
	round_number = 1
	is_game_over = false
	_consecutive_passes = 0
	for i in player_names.size():
		var p := PlayerState.new()
		p.player_id = i
		p.display_name = str(player_names[i])
		p.is_opponent = i != 0
		for _j in hand_size:
			p.hand.append(deck.draw())
		players.append(p)
	_begin_turn()

func current_player() -> PlayerState:
	return players[turn_index]

## Deal every player a starting combo: a random valid three-card meld (a set
## or a run of naturals) pulled straight from the stock onto the table, which
## counts as that player's opening meld (has_opened). No one starts stuck on a
## hand that can't lay a group — the whole table is playable from turn one.
## Call after enemy mechanics are planted (on_combat_start), which coat the
## stock and hands, so combo cards keep any slime/glass they picked up there.
func deal_starting_melds() -> void:
	for p in players:
		var pulled := _random_stock_meld()
		if pulled.is_empty():
			return  # stock too thin to build one; leave the rest as a normal deal
		var meld := CardSet.new()
		for c in pulled:
			meld.add_card(c)
		board.melds.append(meld)
		p.has_opened = true
	board_changed.emit()

## A random valid three-card meld pulled from the stock: an even coin flip
## between a set (one rank, three suits) and a run (one suit, three consecutive
## ranks, ace playing low). Uses the deck's RNG so a seeded game stays
## reproducible. Returns [] when the stock can't supply any shape tried.
func _random_stock_meld() -> Array[Card]:
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
## success or the reason the move is not allowed.
func add_cards_to_meld(cards_to_move: Array[Card], meld: CardSet) -> String:
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
	if not joker.is_joker or joker.joker_rank == 0:
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
	if err != "":
		return err
	_push_undo()
	meld.cards[meld.cards.find(joker)] = hand_card
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

## Why the staged move is illegal under the play cap or the opening rule, or
## "" if it is fine.
func _stage_error(cards_to_move: Array[Card], dest: CardSet) -> String:
	var p := current_player()
	if max_plays_per_turn > 0:
		var from_hand := 0
		for c in cards_to_move:
			if p.hand.has(c):
				from_hand += 1
		if from_hand > 0 and cards_played_this_turn() + from_hand > max_plays_per_turn:
			return "You can only play %d cards in a turn." % max_plays_per_turn
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
	turn_committed.emit(p, cards_played_this_turn())
	if p.hand.is_empty():
		_end_game([p])
	else:
		_advance()
	return ""

## Why the current turn can't be committed, or "" if it is legal. Split out so
## commit_turn keeps a single success path (the guard clauses live here).
func _commit_error(p: PlayerState) -> String:
	if cards_played_this_turn() <= 0:
		return "You must play at least one card from your hand (or draw instead)."
	# Normally unreachable (staging enforces the cap), but the cap can be
	# lowered mid-turn from the settings dialog.
	if max_plays_per_turn > 0 and cards_played_this_turn() > max_plays_per_turn:
		return "You can only play %d cards in a turn — return some to your hand." \
			% max_plays_per_turn
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

## Draw draw_per_turn cards (or pass if the stock is empty) and end the turn.
##
## A staged table rearrangement that plays no card from the hand — the
## signature Machiavelli "shuffle the felt" move, which the Cute Slime uses to
## herd her slime together — is kept when it leaves every group valid, so a
## player can rework the board and still draw. Any other staging (a partial
## play, or a table left invalid mid-edit) is abandoned first, as before.
func draw_and_end_turn() -> void:
	if cards_played_this_turn() != 0 or not _kept_rearrangement():
		reset_turn()
	else:
		# The rearrangement stays on the table, so lock its jokers exactly as a
		# committed turn would — the next player inherits a settled board.
		_lock_table_jokers()
		_undo_stack.clear()
	var p := current_player()
	var drew := 0
	for _i in draw_per_turn:
		if max_hand_size > 0 and p.hand.size() >= max_hand_size:
			break
		var card := deck.draw()
		if card == null:
			break
		p.hand.append(card)
		drew += 1
		card_drawn.emit(p, card)
	if drew > 0:
		_consecutive_passes = 0
	else:
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
	_hand_snapshot = p.hand.duplicate()
	_undo_stack.clear()
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
