extends SceneTree

## Headless check for the menu modes (sandbox vs roguelike run). Run with:
##   godot --headless --path . --script res://tests/ui_mode_check.gd

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	var ok := true
	if not ui.menu_layer.visible:
		printerr("menu should be visible on boot")
		ok = false
	ui._on_play_rogue_pressed()
	if ui.gm.players.size() != 2:
		printerr("rogue run should be 1v1, got %d players" % ui.gm.players.size())
		ok = false
	if ui.gm.draw_per_turn != 2 or ui.gm.max_plays_per_turn != 13 \
			or ui.gm.max_hand_size != 0:
		printerr("rogue rules wrong: draw %d, plays %d, hand cap %d"
			% [ui.gm.draw_per_turn, ui.gm.max_plays_per_turn, ui.gm.max_hand_size])
		ok = false
	var jokers := 0
	for c in ui.gm.deck.cards:
		if c.is_joker:
			jokers += 1
	for p in ui.gm.players:
		for c in p.hand:
			if c.is_joker:
				jokers += 1
	if jokers != 4:
		printerr("rogue deck should hold 4 jokers, found %d" % jokers)
		ok = false
	if ui.settings_btn.disabled != true:
		printerr("settings button should be disabled during a run")
		ok = false
	# The round-1 enemy is drawn at random from the roster; whichever it is,
	# its mechanic must be planted across the freshly dealt game.
	var all_cards: Array = ui.gm.deck.cards.duplicate()
	for p in ui.gm.players:
		all_cards.append_array(p.hand)
	if ui.current_enemy is CuteSlime:
		# She marks her own seat immune and slimes hearts, diamonds and jokers.
		if not ui.gm.players[1].ignores_sticky:
			printerr("the slime's seat should ignore sticky")
			ok = false
		var slimed := 0
		for c in all_cards:
			if c.is_sticky():
				slimed += 1
		if slimed != 30:  # 13 hearts + 13 diamonds + 4 jokers
			printerr("expected 30 slimed cards at combat start, got %d" % slimed)
			ok = false
	elif ui.current_enemy is SadisticBillionaire:
		# He turns three quarters of all 108 cards to glass.
		var glass := 0
		for c in all_cards:
			if c.is_glass():
				glass += 1
		if glass != 81:
			printerr("expected 81 glass cards at combat start, got %d" % glass)
			ok = false
	else:
		printerr("round 1 should face a designed enemy, got %s" % ui.current_enemy)
		ok = false
	# Simulate a won round: Next round advances, rules stay fixed.
	ui.gm._end_game([ui.gm.players[0]])
	ui._refresh()
	if ui.new_game_btn.text != "Next round":
		printerr("after a win the button should read Next round, got '%s'"
			% ui.new_game_btn.text)
		ok = false
	ui._on_new_game_pressed()
	if ui.rogue_round != 2 or ui.gm.draw_per_turn != 2:
		printerr("Next round should advance to round 2 with rules intact")
		ok = false
	# Simulate a lost round: the button offers a fresh run from round 1.
	ui.gm._end_game([ui.gm.players[1]])
	ui._refresh()
	if ui.new_game_btn.text != "New run":
		printerr("after a loss the button should read New run, got '%s'"
			% ui.new_game_btn.text)
		ok = false
	ui._on_new_game_pressed()
	if ui.rogue_round != 1:
		printerr("New run should reset to round 1, got %d" % ui.rogue_round)
		ok = false
	# Back to sandbox: player settings apply again.
	ui.max_plays_per_turn = 12
	ui.enemy_count = 3
	ui._on_play_vanilla_pressed()
	if ui.gm.players.size() != 4 or ui.gm.max_plays_per_turn != 12 \
			or ui.gm.draw_per_turn != 1:
		printerr("sandbox game should use sandbox settings")
		ok = false
	if ui.settings_btn.disabled:
		printerr("settings button should be enabled in sandbox")
		ok = false
	if ok:
		print("UI MODE CHECK OK")
		quit(0)
	else:
		quit(1)
