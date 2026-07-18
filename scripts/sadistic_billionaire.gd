class_name SadisticBillionaire
extends Enemy

## The second designed enemy. He plays at full strength, conservative (sits on
## his opening meld until it is big enough and holds cards that still pair up)
## and fully attentive (never blunders). His mechanic is glass.
##
## At combat start he turns a random three quarters of ALL cards — the stock
## and every hand, jokers included — to glass (the Clear effect). A glass card
## is see-through from the back: everyone can see it while it sits in any
## player's hand or on top of the stock. The information cuts both ways: the
## player reads his glass cards straight off his card backs, but the smart AI
## counts every glass card too (GreedyAI's glass awareness) — it knows which
## cards it wants are visibly locked in an opponent's hand (not worth waiting
## for), which lay-offs an opponent visibly holds (not worth feeding), which
## joker stand-ins an opponent holds the swap card for (never point a joker
## there), and what the next draw will be whenever the top of the stock is
## glass.
##
## Glass is pure information — it never restricts how a card moves — so a card
## can be both glass and slimed without conflict.

## The fraction of all cards turned to glass at combat start (3/4).
const GLASS_NUMERATOR := 3
const GLASS_DENOMINATOR := 4

func _init() -> void:
	display_name = "The Sadistic Billionaire"
	strength = 1.0     # strongest difficulty (for now every enemy is)
	style = 1.0        # conservative
	attention = 1.0    # attentive

func mechanic_intro() -> String:
	return "[b]%s[/b] turns three quarters of every card to glass " \
		% display_name \
		+ "(transparent). A glass card is see-through from the back: everyone " \
		+ "can see it in any player's hand and on top of the stock. He reads " \
		+ "your glass cards and knows a glass next draw — but you can read his " \
		+ "hand the same way."

## Turn a random three quarters of every card in the game — the stock and all
## hands, wherever the deal put them — to glass. Rides the deck's own RNG, so a
## seeded game glasses the same cards every replay.
func on_combat_start(gm: GameManager) -> void:
	var pool: Array[Card] = gm.deck.cards.duplicate()
	for p in gm.players:
		pool.append_array(p.hand)
	var rng := gm.deck.rng
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in pool.size() * GLASS_NUMERATOR / GLASS_DENOMINATOR:
		_glass(pool[i])

func _glass(card: Card) -> void:
	if not card.has_effect(Card.Effect.CLEAR):
		card.effects.append(Card.Effect.CLEAR)
