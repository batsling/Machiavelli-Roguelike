extends SceneTree

## Headless check for the Tiling solver (the Riichi go-out / wait engine). Run:
##   godot --headless --path . --script res://tests/tiling_check.gd

var ok := true

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _joker() -> Card:
	var j := Card.new()
	j.suit = "joker"
	j.rank = 0
	j.is_joker = true
	return j

## Parse a compact spec like "5h 6h 7h" or "Ah 2h 3h *" (* = free joker) into a
## card list. Ranks: A,2..9,T,J,Q,K. Suits: h,d,c,s.
func _hand(spec: String) -> Array[Card]:
	const RANKS := {"A": 1, "T": 10, "J": 11, "Q": 12, "K": 13}
	const SUITS := {"h": "hearts", "d": "diamonds", "c": "clubs", "s": "spades"}
	var out: Array[Card] = []
	for tok in spec.split(" ", false):
		if tok == "*":
			out.append(_joker())
			continue
		var rs := tok.substr(0, tok.length() - 1)
		var su := tok.substr(tok.length() - 1)
		var rank: int = RANKS.get(rs, rs.to_int())
		out.append(_card(rank, SUITS[su]))
	return out

func _fail(msg: String) -> void:
	printerr(msg)
	ok = false

func _expect(spec: String, want: bool) -> void:
	var got := Tiling.can_partition(_hand(spec))
	if got != want:
		_fail("can_partition(%s) = %s, expected %s" % [spec, got, want])

func _expect_wait(spec: String, want_tokens: Array) -> void:
	const SUITS := {"hearts": "h", "diamonds": "d", "clubs": "c", "spades": "s"}
	const NAMES := {1: "A", 10: "T", 11: "J", 12: "Q", 13: "K"}
	var got := Tiling.wait_cards(_hand(spec))
	var got_set := {}
	for w: Dictionary in got:
		var rn: String = NAMES.get(w["rank"], str(w["rank"]))
		got_set["%s%s" % [rn, SUITS[w["suit"]]]] = true
	var want_set := {}
	for t: String in want_tokens:
		want_set[t] = true
	if got_set.keys().size() != want_set.keys().size() or not _same_keys(got_set, want_set):
		_fail("wait(%s) = %s, expected %s" % [spec, got_set.keys(), want_tokens])

func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if not b.has(k):
			return false
	for k in b:
		if not a.has(k):
			return false
	return true

func _init() -> void:
	# --- can_partition ---
	_expect("5h 5d 5c", true)                 # set of three
	_expect("5h 5d 5c 5s", true)              # set of four
	_expect("5h 5d 5c 5s 5h", false)          # five of a rank cannot tile
	_expect("5h 6h 7h", true)                 # run
	_expect("5h 6h", false)                   # too short
	_expect("5h 6h 7h 8h 9h", true)           # long run
	_expect("Ah 2h 3h", true)                 # ace low
	_expect("Qh Kh Ah", true)                 # ace high
	_expect("Kh Ah 2h", false)                # no wrap
	_expect("Jh Qh Kh Ah", true)              # ace-high length 4
	_expect("5h 5d 5c 8s 9s Ts", true)        # set + run
	_expect("5h 5d 5c 8s", false)             # leftover single
	_expect("5h 5d *", true)                  # joker completes a set
	_expect("5h 6h *", true)                  # joker completes a run (inner/outer)
	_expect("* * *", false)                   # jokers cannot stand alone
	_expect("5h 5d *  8s 9s *", true)         # two joker-completed melds
	_expect("", true)                         # empty tiles vacuously
	# Two full 5-of-a-rank across suits should split as run+set only if possible:
	_expect("Ah Ad Ac 2h 3h", false)          # A(set)+2h3h leftover (2 cards)
	_expect("Ah Ad Ac 2h 3h 4h", true)        # set of aces + run 2-3-4 hearts... uses Ah twice? no
	# Note: the line above reuses no card twice — Ah is one physical card. The set
	# {Ah,Ad,Ac} and run {2h,3h,4h} share nothing, so it tiles.

	# --- wait_cards ---
	_expect_wait("5h 5d", ["5c", "5s"])       # needs the last two suits (either)
	_expect_wait("4h 5h", ["3h", "6h"])       # open-ended run wait
	_expect_wait("5h 6h", ["4h", "7h"])       # both ends
	_expect_wait("Qh Kh", ["Jh", "Ah"])       # ace-high edge wait
	_expect_wait("5h 5d 5c 8s 9s", ["Ts", "7s"]) # completed set + run wait

	if ok:
		print("tiling_check: PASS")
		quit(0)
	else:
		printerr("tiling_check: FAIL")
		quit(1)
