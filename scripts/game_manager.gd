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
##  - First player to empty their hand wins. If the stock is empty and every
##    player passes in a full round, the game ends and whoever holds the
##    fewest cards wins (ties shared).
##
## The turn is *staged*: moves mutate the board/hand immediately, but the
## whole turn can be rolled back (reset_turn / draw_and_end_turn) and is only
## legal-checked at commit_turn(). This mirrors how the physical game is
## played — shuffle the table as much as you like, it just has to be clean
## when you take your hand off it.

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
## into a brand-new meld. Legality is only checked at commit_turn().
func move_cards_to_new_meld(cards_to_move: Array[Card]) -> void:
	if cards_to_move.is_empty():
		return
	var meld := CardSet.new()
	board.melds.append(meld)
	_move_cards(cards_to_move, meld)

## Move cards (from hand and/or table) into an existing meld.
func add_cards_to_meld(cards_to_move: Array[Card], meld: CardSet) -> void:
	_move_cards(cards_to_move, meld)

## Undo everything staged this turn: table and hand return to how they were
## at the start of the turn.
func reset_turn() -> void:
	var p := current_player()
	p.hand = _hand_snapshot.duplicate()
	board.restore(_board_snapshot)
	board_changed.emit()

func cards_played_this_turn() -> int:
	return _hand_snapshot.size() - current_player().hand.size()

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
	_consecutive_passes = 0
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

func _begin_turn() -> void:
	var p := current_player()
	_hand_snapshot = p.hand.duplicate()
	_board_snapshot = board.snapshot()
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
