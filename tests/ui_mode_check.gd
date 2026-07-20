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
	if ui.gm.meter_max != 10 or ui.gm.meter_gain != 1 or ui.gm.meter_per_card:
		printerr("rogue meter defaults wrong: max %d gain %d per_card %s"
			% [ui.gm.meter_max, ui.gm.meter_gain, ui.gm.meter_per_card])
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
	if ui.settings_btn.disabled:
		printerr("settings button should stay enabled during a run (roguelike tab)")
		ok = false
	# The round-1 enemy is drawn at random from the roster; whichever it is,
	# its mechanic must be planted across the freshly dealt game.
	var all_cards: Array = ui.gm.deck.cards.duplicate()
	for p in ui.gm.players:
		all_cards.append_array(p.hand)
	if ui.current_enemy is CuteSlime:
		# She marks her own seat immune and slimes the hearts, diamonds and jokers
		# of her own deck only (one copy of each).
		if not ui.gm.players[1].ignores_sticky:
			printerr("the slime's seat should ignore sticky")
			ok = false
		var slimed := 0
		for c in all_cards:
			if c.is_sticky():
				slimed += 1
		if slimed != 28:  # 13 hearts + 13 diamonds + 2 jokers, all from her deck
			printerr("expected 28 slimed cards at combat start, got %d" % slimed)
			ok = false
	elif ui.current_enemy is SadisticBillionaire:
		# He glasses his own deck only: all 52 naturals + his 2 jokers = 54 of 108.
		var glass := 0
		for c in all_cards:
			if c.is_glass():
				glass += 1
		if glass != 54:
			printerr("expected 54 glass cards at combat start, got %d" % glass)
			ok = false
	else:
		printerr("round 1 should face a designed enemy, got %s" % ui.current_enemy)
		ok = false
	# Simulate a won round: Next round advances and picks up any roguelike
	# settings changed in the meantime — they apply from the next round.
	ui.settings.rogue_draw_per_turn = 3
	ui.settings.rogue_start_hand_size = 10
	ui.settings.rogue_start_combo = true
	ui.settings.rogue_meter_max = 7
	ui.settings.rogue_meter_per_card = true
	ui.gm._end_game([ui.gm.players[0]])
	ui._refresh()
	if ui.new_game_btn.text != "Next round":
		printerr("after a win the button should read Next round, got '%s'"
			% ui.new_game_btn.text)
		ok = false
	ui._on_new_game_pressed()
	if ui.rogue_round != 2 or ui.gm.draw_per_turn != 3:
		printerr("Next round should advance to round 2 with the new rules")
		ok = false
	if ui.gm.meter_max != 7 or not ui.gm.meter_per_card:
		printerr("Next round should pick up the new meter settings: max %d per_card %s"
			% [ui.gm.meter_max, ui.gm.meter_per_card])
		ok = false
	if ui.gm.players[0].hand.size() != 10:
		printerr("round 2 should deal the new 10-card hands, got %d"
			% ui.gm.players[0].hand.size())
		ok = false
	if ui.gm.board.melds.size() != 2 or not ui.gm.players[0].has_opened \
			or not ui.gm.players[1].has_opened:
		printerr("starting combos should open every player with a meld on the table")
		ok = false
	for m in ui.gm.board.melds:
		if not m.is_valid():
			printerr("a starting combo left an invalid meld on the table")
			ok = false
	ui.settings.rogue_draw_per_turn = 2
	ui.settings.rogue_start_hand_size = 13
	ui.settings.rogue_start_combo = false
	ui.settings.rogue_meter_max = 10
	ui.settings.rogue_meter_per_card = false
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
	ui.settings.max_plays_per_turn = 12
	ui.settings.enemy_count = 3
	ui.settings.meter_gain = 2
	ui.settings.meter_per_card = true
	ui._on_play_vanilla_pressed()
	if ui.gm.players.size() != 4 or ui.gm.max_plays_per_turn != 12 \
			or ui.gm.draw_per_turn != 1:
		printerr("sandbox game should use sandbox settings")
		ok = false
	if ui.gm.meter_gain != 2 or not ui.gm.meter_per_card or ui.gm.meter_max != 10:
		printerr("sandbox game should use sandbox meter settings: max %d gain %d per_card %s"
			% [ui.gm.meter_max, ui.gm.meter_gain, ui.gm.meter_per_card])
		ok = false
	# Live-apply: editing a sandbox meter dial pushes onto the running game.
	ui.settings.meter_max = 4
	ui._apply_live_settings()
	if ui.gm.meter_max != 4:
		printerr("sandbox meter change should apply live, got %d" % ui.gm.meter_max)
		ok = false
	if ui.settings_btn.disabled:
		printerr("settings button should be enabled in sandbox")
		ok = false
	if ok:
		print("UI MODE CHECK OK")
		quit(0)
	else:
		quit(1)
