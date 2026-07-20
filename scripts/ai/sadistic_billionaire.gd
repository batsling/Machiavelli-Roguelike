class_name SadisticBillionaire
extends Enemy

## The second designed enemy. He plays at full strength, conservative (sits on
## his opening meld until it is big enough and holds cards that still pair up)
## and fully attentive (never blunders). His mechanic is glass.
##
## At combat start he turns every card in his own deck — all 52 naturals and both
## his jokers, wherever the deal put them, the stock and every hand — to glass
## (the Clear effect). Because the combined stock holds one copy of each card per
## player, only his copy goes glass: of the two copies of any card exactly one is
## see-through, and only two of the four jokers (his). A glass card is
## see-through from the back: everyone can see it while it sits in any player's
## hand or on top of the stock. The information cuts both ways: the player reads
## his glass cards straight off his card backs, but the smart AI counts every
## glass card too (GreedyAI's glass awareness) — it knows which cards it wants are
## visibly locked in an opponent's hand (not worth waiting for), which lay-offs an
## opponent visibly holds (not worth feeding), which joker stand-ins an opponent
## holds the swap card for (never point a joker there), and what the next draw
## will be whenever the top of the stock is glass.
##
## Glass is pure information — it never restricts how a card moves — so a card
## can be both glass and slimed without conflict.

func _init() -> void:
	display_name = "The Sadistic Billionaire"
	strength = 1.0     # strongest difficulty (for now every enemy is)
	style = 1.0        # conservative
	attention = 1.0    # attentive

func mechanic_intro() -> String:
	return "[b]%s[/b] turns every card in his own deck to glass (transparent) " \
		% display_name \
		+ "— one copy of each, so only his half is see-through. A glass card is " \
		+ "see-through from the back: everyone can see it in any player's hand " \
		+ "and on top of the stock. He reads your glass cards and knows a glass " \
		+ "next draw — but you can read his hand the same way."

## Turn every card from his own deck — all 52 naturals and both his jokers,
## wherever the deal put them, the stock and all hands — to glass. Only his
## copies go glass, so of the two copies of any card exactly one is see-through.
## Deterministic (no RNG), so a seeded game glasses the same cards every replay.
func on_combat_start(gm: GameManager) -> void:
	var own := own_deck_id(gm)
	for c in all_dealt_cards(gm):
		if c.deck_owner == own:
			_glass(c)

func _glass(card: Card) -> void:
	if not card.has_effect(Card.Effect.CLEAR):
		card.effects.append(Card.Effect.CLEAR)
