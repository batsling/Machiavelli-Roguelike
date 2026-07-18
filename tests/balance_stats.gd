extends SceneTree

## Headless balance-stats runner for the roguelike economy. Run with:
##   godot --headless --path . --import                                (once)
##   godot --headless --path . --script res://tests/balance_stats.gd
## More (or fewer) games per matchup:
##   godot --headless --path . --script res://tests/balance_stats.gd -- --games=100
## With starting combos dealt (every player opens with a random meld):
##   godot --headless --path . --script res://tests/balance_stats.gd -- --combo
##
## Plays seeded 1v1 games — a simulated player against the basic enemy and
## against each designed enemy — and prints the numbers two roguelike systems
## need:
##  - Gold for winning fast: how long games run in *rounds* (turns the player
##    takes), split into wins and losses, with suggested 3-tier cutoffs taken
##    from the terciles of the rounds-to-win distribution.
##  - The ultimate meter: how often the player actually plays a hand (commits
##    cards) instead of drawing, how many hands a game contains, and how many
##    cards each played hand lays down — the raw rates to score meter gain on.
##
## The player seat is driven by the same AI as the enemies, on a fixed strong
## profile, so lengths reflect competent play; enemies use their own designed
## profiles and mechanics (slime, glass), exactly as a rogue round would.

const DEFAULT_GAMES := 30
const MAX_TURNS := 2000

## The simulated player's dials: strongest skill, quick, fully attentive.
const PLAYER_STRENGTH := 1.0
const PLAYER_STYLE := 0.0
const PLAYER_ATTENTION := 1.0

## --combo: deal every player a random starting meld (see
## GameManager.deal_starting_melds) in every game, to measure its effect.
var start_combo := false

func _init() -> void:
	var games := DEFAULT_GAMES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = maxi(1, int(arg.get_slice("=", 1)))
		elif arg == "--combo":
			start_combo = true
	var matchups: Array[Dictionary] = [
		{"label": "Basic enemy (no jokers)",
			"make": func() -> Enemy: return Enemy.new(), "jokers": false},
		{"label": "Basic enemy (jokers)",
			"make": func() -> Enemy: return Enemy.new(), "jokers": true},
		{"label": "The Cute Slime",
			"make": func() -> Enemy: return CuteSlime.new(), "jokers": true},
		{"label": "The Sadistic Billionaire",
			"make": func() -> Enemy: return SadisticBillionaire.new(), "jokers": true},
	]
	print("Balance stats: %d games per matchup, 1v1, player profile " % games
		+ "strength=%.1f style=%.1f attention=%.1f%s" % [PLAYER_STRENGTH, PLAYER_STYLE,
			PLAYER_ATTENTION, ", starting combos dealt" if start_combo else ""])
	var failures := 0
	var all: Array[Dictionary] = []
	var per_matchup: Array[Dictionary] = []
	for m in matchups:
		var results: Array[Dictionary] = []
		for seed_value in games:
			var r := _play_game(m, seed_value)
			if r.is_empty():
				failures += 1
				continue
			results.append(r)
		per_matchup.append({"label": m["label"], "results": results})
		all.append_array(results)
	for pm in per_matchup:
		_report_matchup(pm["label"], pm["results"])
	_report_matchup("ALL MATCHUPS COMBINED", all)
	_report_gold_tiers(per_matchup, all)
	_report_meter(all)
	if failures > 0:
		printerr("balance stats: %d game(s) failed to finish" % failures)
		quit(1)
	else:
		quit(0)

## Play one seeded 1v1 game and return its stats, or {} if it never finished.
func _play_game(matchup: Dictionary, seed_value: int) -> Dictionary:
	var gm := GameManager.new()
	var enemy: Enemy = matchup["make"].call()
	gm.setup(["You", enemy.display_name], 13, seed_value, matchup["jokers"])
	enemy.on_combat_start(gm)
	if start_combo:
		gm.deal_starting_melds()
	var enemy_profile := enemy.make_profile(seed_value)
	var player_profile := AIProfile.new(PLAYER_STRENGTH, PLAYER_STYLE,
		PLAYER_ATTENTION, seed_value)
	# Mutated from the signal lambdas below; a Dictionary so the captures share it.
	var tally := {"player_hands": 0, "enemy_hands": 0, "player_cards": [], "winners": []}
	gm.turn_committed.connect(func(p: PlayerState, cards_played: int) -> void:
		if p.player_id == 0:
			tally["player_hands"] += 1
			tally["player_cards"].append(cards_played)
		else:
			tally["enemy_hands"] += 1)
	gm.game_over.connect(func(winners: Array) -> void:
		tally["winners"] = winners.duplicate())
	var turns := 0
	var rounds := 0
	while not gm.is_game_over and turns < MAX_TURNS:
		if gm.current_player().player_id == 0:
			rounds += 1
			GreedyAI.take_turn(gm, player_profile)
		else:
			GreedyAI.take_turn(gm, enemy_profile, enemy)
		turns += 1
	if not gm.is_game_over:
		printerr("%s seed %d: did not finish within %d turns"
			% [matchup["label"], seed_value, MAX_TURNS])
		gm.free()
		return {}
	var outcome := "loss"
	var went_out := false
	for w: PlayerState in tally["winners"]:
		if w.hand.is_empty():
			went_out = true
		if w.player_id == 0:
			outcome = "win" if tally["winners"].size() == 1 else "tie"
	var result := {
		"rounds": rounds,
		"turns": turns,
		"outcome": outcome,
		"went_out": went_out,
		"player_hands": tally["player_hands"],
		"player_draws": rounds - tally["player_hands"],
		"player_cards": tally["player_cards"],
		"enemy_hands": tally["enemy_hands"],
	}
	gm.free()
	return result

# --- Reporting ---------------------------------------------------------------

func _report_matchup(label: String, results: Array[Dictionary]) -> void:
	if results.is_empty():
		print("\n=== %s — no finished games ===" % label)
		return
	print("\n=== %s — %d games ===" % [label, results.size()])
	var wins := _with_outcome(results, "win")
	var losses := _with_outcome(results, "loss")
	var ties := _with_outcome(results, "tie")
	print("Outcomes: player wins %d (%d%%), losses %d, ties %d"
		% [wins.size(), roundi(100.0 * wins.size() / results.size()),
			losses.size(), ties.size()])
	var stockouts := 0
	for r in results:
		if not r["went_out"]:
			stockouts += 1
	if stockouts > 0:
		print("  (%d game(s) ended by stock-out/passes rather than an emptied hand)"
			% stockouts)
	var all_rounds := _values(results, "rounds")
	print("Game length in player rounds (all games): %s" % _dist_line(all_rounds))
	if not wins.is_empty():
		print("  wins:   %s" % _dist_line(_values(wins, "rounds")))
	if not losses.is_empty():
		print("  losses: %s" % _dist_line(_values(losses, "rounds")))
	var hands := _values(results, "player_hands")
	var total_hands := 0
	var total_rounds := 0
	for r in results:
		total_hands += r["player_hands"]
		total_rounds += r["rounds"]
	print("Hands played by the player per game: %s" % _dist_line(hands))
	if total_rounds > 0:
		print("  the player plays a hand on %d%% of their turns (draws/passes otherwise)"
			% roundi(100.0 * total_hands / total_rounds))
	var cards: Array[int] = []
	var cards_per_game: Array[int] = []
	for r in results:
		var game_total := 0
		for n: int in r["player_cards"]:
			cards.append(n)
			game_total += n
		cards_per_game.append(game_total)
	if not cards.is_empty():
		print("Cards laid per played hand: %s" % _dist_line(cards))
		print("Cards laid per game (total): %s" % _dist_line(cards_per_game))
	_histogram(all_rounds, "Game length histogram (player rounds)")

## The tercile cutoffs of the rounds-to-win distribution: the natural three-way
## gold split ("fast / medium / slow win"), overall and per enemy.
func _report_gold_tiers(per_matchup: Array[Dictionary], all: Array[Dictionary]) -> void:
	print("\n=== Gold tiers — suggested cutoffs from rounds-to-win terciles ===")
	var all_wins := _values(_with_outcome(all, "win"), "rounds")
	if all_wins.is_empty():
		print("No player wins recorded — no tier data.")
		return
	var t1 := roundi(_percentile(all_wins, 33.3))
	var t2 := roundi(_percentile(all_wins, 66.7))
	print("Across all enemies (%d wins): Tier 1 (top gold) win in <= %d rounds, "
		% [all_wins.size(), t1]
		+ "Tier 2 in %d-%d rounds, Tier 3 in > %d rounds" % [t1 + 1, t2, t2])
	print("Per enemy (fastest third | middle | slowest third of wins):")
	for pm in per_matchup:
		var wins := _values(_with_outcome(pm["results"], "win"), "rounds")
		if wins.is_empty():
			print("  %-28s no wins" % pm["label"])
			continue
		print("  %-28s <= %d | %d-%d | > %d   (median win %d rounds, %d wins)"
			% [pm["label"], roundi(_percentile(wins, 33.3)),
				roundi(_percentile(wins, 33.3)) + 1, roundi(_percentile(wins, 66.7)),
				roundi(_percentile(wins, 66.7)), roundi(_percentile(wins, 50.0)),
				wins.size()])

## How fast the meter would fill at different scoring rules, from the observed
## hand-play rates.
func _report_meter(all: Array[Dictionary]) -> void:
	if all.is_empty():
		return
	print("\n=== Ultimate meter — hand-play rates to score charge on ===")
	var hands := _values(all, "player_hands")
	var total_hands := 0
	var total_rounds := 0
	var total_cards := 0
	for r in all:
		total_hands += r["player_hands"]
		total_rounds += r["rounds"]
		for n: int in r["player_cards"]:
			total_cards += n
	var mean_hands := float(total_hands) / all.size()
	var median_hands := _percentile(hands, 50.0)
	print("The player plays %.1f hands per game on average (median %.0f), on %d%% of turns."
		% [mean_hands, median_hands, roundi(100.0 * total_hands / total_rounds)])
	print("Flat charge per hand played:")
	for ults_per_game: float in [1.0, 1.5, 2.0]:
		print("  ~%.1f ultimate(s) per game -> meter full every %.1f hands "
			% [ults_per_game, mean_hands / ults_per_game]
			+ "(each hand charges %d%%)" % roundi(100.0 * ults_per_game / mean_hands))
	if total_hands > 0:
		var mean_cards := float(total_cards) / total_hands
		print("If charge scales with cards laid instead: %.1f cards per hand, "
			% mean_cards
			+ "%.1f cards per game -> ~%d%% per card for one ultimate per game."
			% [float(total_cards) / all.size(),
				roundi(100.0 * all.size() / total_cards)])

# --- Small stats helpers -----------------------------------------------------

func _with_outcome(results: Array[Dictionary], outcome: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in results:
		if r["outcome"] == outcome:
			out.append(r)
	return out

func _values(results: Array[Dictionary], key: String) -> Array[int]:
	var out: Array[int] = []
	for r in results:
		out.append(r[key])
	return out

## Linear-interpolated percentile of an unsorted int sample.
func _percentile(sample: Array[int], p: float) -> float:
	if sample.is_empty():
		return 0.0
	var sorted := sample.duplicate()
	sorted.sort()
	var idx := p / 100.0 * float(sorted.size() - 1)
	var lo := int(floor(idx))
	var hi := int(ceil(idx))
	return lerpf(float(sorted[lo]), float(sorted[hi]), idx - lo)

func _mean(sample: Array[int]) -> float:
	if sample.is_empty():
		return 0.0
	var total := 0
	for v in sample:
		total += v
	return float(total) / sample.size()

## One line of distribution summary: min, quartiles, p90, max, mean.
func _dist_line(sample: Array[int]) -> String:
	if sample.is_empty():
		return "(no data)"
	var sorted := sample.duplicate()
	sorted.sort()
	return "min %d · p25 %.0f · median %.0f · p75 %.0f · p90 %.0f · max %d · mean %.1f" \
		% [sorted[0], _percentile(sample, 25.0), _percentile(sample, 50.0),
			_percentile(sample, 75.0), _percentile(sample, 90.0), sorted[-1],
			_mean(sample)]

## Compact ASCII histogram (about ten buckets, one line each).
func _histogram(sample: Array[int], title: String) -> void:
	if sample.is_empty():
		return
	var sorted := sample.duplicate()
	sorted.sort()
	var lo: int = sorted[0]
	var hi: int = sorted[-1]
	var width := maxi(1, int(ceil((hi - lo + 1) / 10.0)))
	print(title + ":")
	var start := lo
	while start <= hi:
		var last := start + width - 1
		var count := 0
		for v in sample:
			if v >= start and v <= last:
				count += 1
		var bar := "#".repeat(count)
		if width == 1:
			print("  %3d      | %s (%d)" % [start, bar, count])
		else:
			print("  %3d-%-3d  | %s (%d)" % [start, last, bar, count])
		start += width
