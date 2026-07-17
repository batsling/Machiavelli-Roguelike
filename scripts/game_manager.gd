class_name GameManager
extends Node

## Core engine for a vanilla game of Machiavelli (the Italian rummy variant).
##
## Rules implemented:
##  - Two full 52-card decks, no jokers; each player is dealt a starting hand,
##    the rest forms the stock.
##  - On your turn you either play at least one card from your hand onto the
##    table, or draw one card from the stock. While playing you may freely
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
## whole turn can be rolled back (reset_turn / draw_and_end_turn) and is only
## legal-checked at commit_turn(). This mirrors how the physical game is
## played — shuffle the table as much as you like, it just has to be clean
## when you take your hand off it. Each staged move is also snapshotted, so
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
var is_game_over := false

# Staging state for the current turn.
var _hand_snapshot: Array[Card] = []
var _board_snapshot: Array = []
# One {hand, board} snapshot per staged move, so single moves can be undone.
var _undo_stack: Array[Dictionary] = []
var _consecutive_passes := 0

func setup(player_names: Array, hand_size: int = DEFAULT_HAND_SIZE, seed_value: int = -1) -> void:
	players.clear()
	board = Board.new()
	deck = Deck.new(seed_value)
	deck.build_double_deck()
	deck.shuffle()
	turn_index = 0
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

# --- Staging moves (current player's turn) ---------------------------------

## Move cards (from the current player's hand and/or anywhere on the table)
## into a brand-new meld. Returns "" on success or a human-readable reason the
## move is not allowed (the opening rule is enforced here; meld validity is
## still only checked at commit_turn()).
func move_cards_to_new_meld(cards_to_move: Array[Card]) -> String:
	if cards_to_move.is_empty():
		return ""
	var err := _stage_error(cards_to_move, null)
	if err != "":
		return err
	_push_undo()
	var meld := CardSet.new()
	board.melds.append(meld)
	_move_cards(cards_to_move, meld)
	return ""

## Move cards (from hand and/or table) into an existing meld. Returns "" on
## success or the reason the move is not allowed.
func add_cards_to_meld(cards_to_move: Array[Card], meld: CardSet) -> String:
	if cards_to_move.is_empty():
		return ""
	var err := _stage_error(cards_to_move, meld)
	if err != "":
		return err
	_push_undo()
	_move_cards(cards_to_move, meld)
	return ""

## Undo just the last staged move this turn. Returns false if there was
## nothing to undo.
func undo_action() -> bool:
	if _undo_stack.is_empty():
		return false
	var snap: Dictionary = _undo_stack.pop_back()
	current_player().hand.assign(snap["hand"])
	board.restore(snap["board"])
	board_changed.emit()
	return true

func can_undo_action() -> bool:
	return not _undo_stack.is_empty()

## Undo everything staged this turn: table and hand return to how they were
## at the start of the turn.
func reset_turn() -> void:
	var p := current_player()
	p.hand = _hand_snapshot.duplicate()
	board.restore(_board_snapshot)
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
	board.prune_empty()
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

## Why the staged move is illegal under the opening rule, or "" if it is fine.
func _stage_error(cards_to_move: Array[Card], dest: CardSet) -> String:
	if current_player_is_open():
		return ""
	var p := current_player()
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
	_consecutive_passes = 0
	p.has_opened = true
	turn_committed.emit(p, cards_played_this_turn())
	if p.hand.is_empty():
		_end_game([p])
		return ""
	_advance()
	return ""

## Abandon any staged plays, draw one card (or pass if the stock is empty)
## and end the turn.
func draw_and_end_turn() -> void:
	reset_turn()
	var p := current_player()
	var card := deck.draw()
	if card != null:
		p.hand.append(card)
		_consecutive_passes = 0
		card_drawn.emit(p, card)
	else:
		_consecutive_passes += 1
		player_passed.emit(p)
		if _consecutive_passes >= players.size():
			_end_game(_fewest_cards_winners())
			return
	_advance()

# --- Internals ---------------------------------------------------------------

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
	})

func _begin_turn() -> void:
	var p := current_player()
	_hand_snapshot = p.hand.duplicate()
	_board_snapshot = board.snapshot()
	_undo_stack.clear()
	turn_started.emit(p)

func _advance() -> void:
	if is_game_over:
		return
	turn_index = (turn_index + 1) % players.size()
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
