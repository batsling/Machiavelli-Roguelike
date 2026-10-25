extends SceneTree

## Headless check for the menu modes: the roguelike run (map, lives, energy,
## own decks) and the vanilla sandbox. Run with:
##   godot --headless --path . --script res://tests/ui_mode_check.gd

func _card(rank: int, suit: String) -> Card:
	var c := Card.new()
	c.suit = suit
	c.rank = rank
	return c

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(ui)
	await process_frame
	await process_frame
	var ok := true
	if not ui.menu_layer.visible:
		printerr("menu should be visible on boot")
		ok = false

	# --- A new run opens on the map ---------------------------------------------
	ui._on_play_rogue_pressed()
	var run: RunState = ui.run
	if not ui.map_layer.visible or ui.game_root.visible or ui.menu_layer.visible:
		printerr("a new run should open on the map")
		ok = false
	if run.lives != 3 or run.rows.size() != 3:
		printerr("a run should start with 3 lives and 3 nodes, got %d / %d"
			% [run.lives, run.rows.size()])
		ok = false
	# Only the first node can be picked.
	ui._on_map_node_chosen(run.node_at(1, 0))
	if ui.game_root.visible:
		printerr("a locked node must not start a match")
		ok = false

	# --- The first match ---------------------------------------------------------
	ui._on_map_node_chosen(run.node_at(0, 0))
	var gm: GameManager = ui.gm
	if not ui.game_root.visible or ui.map_layer.visible:
		printerr("picking the open node should start its match")
		ok = false
	if gm.players.size() != 2 or gm.players[1].display_name != "Scrap Drone":
		printerr("node 1 should be a 1v1 against the Scrap Drone")
		ok = false
	if gm.draw_per_turn != 2 or gm.max_plays_per_turn != 0 or gm.max_hand_size != 0 \
			or gm.meter_max != 0:
		printerr("run rules wrong: draw %d, plays %d, hand cap %d, meter %d"
			% [gm.draw_per_turn, gm.max_plays_per_turn, gm.max_hand_size, gm.meter_max])
		ok = false
	# 3 energy on the first turn, plus whatever the round-1 event adds.
	var first_energy := 3
	if gm.is_event_active(MatchEvent.Id.OVERCHARGE):
		first_energy += 1
	if gm.revealed_events[0].id == MatchEvent.Id.SURGE:
		first_energy += MatchEvent.SURGE_ENERGY
	if not gm.energy_on() or gm.players[0].max_energy != first_energy \
			or gm.energy_left() != first_energy:
		printerr("the first turn should start with %d energy" % first_energy)
		ok = false
	# Every player brings their own deck: 2 jokers each, every card tagged to its owner.
	for p in gm.players:
		var jokers := 0
		for c in p.deck.cards + p.hand:
			if c.deck_owner != p.player_id:
				printerr("%s holds a card from another deck" % p.display_name)
				ok = false
				break
			if c.is_joker:
				jokers += 1
		for m in gm.board.melds:
			for c in m.cards:
				if c.deck_owner == p.player_id and c.is_joker:
					jokers += 1
		if jokers != 2:
			printerr("%s's deck should hold 2 jokers, found %d" % [p.display_name, jokers])
			ok = false
	if gm.board.melds.size() != 2 or not gm.players[0].has_opened:
		printerr("starting combos should open both players with a meld each")
		ok = false
	if ui.energy_slot.get_child_count() != 1 + first_energy:
		printerr("the hand header should show the energy label and %d pips" % first_energy)
		ok = false
	elif (ui.energy_slot.get_child(0) as Label).text \
			!= "Energy %d/%d" % [first_energy, first_energy]:
		printerr("energy label should read 'Energy %d/%d', got '%s'"
			% [first_energy, first_energy, (ui.energy_slot.get_child(0) as Label).text])
		ok = false
	if not ui.lives_label.visible or ui.lives_label.text.find("Node 1/3") == -1:
		printerr("the top bar should show lives and 'Node 1/3', got '%s'" % ui.lives_label.text)
		ok = false
	if ui.settings_btn.disabled:
		printerr("settings button should stay enabled during a run (roguelike tab)")
		ok = false
	if ui.new_game_btn.text != "Restart run":
		printerr("mid-match the button should read Restart run, got '%s'" % ui.new_game_btn.text)
		ok = false

	# --- Events: three per match, one face up at the deal ------------------------
	if gm.revealed_events.size() != 1 or gm.upcoming_events().size() != 2 \
			or ui.events_row.get_child_count() != 3 or not ui.events_row.visible:
		printerr("a match should show 3 events, 1 revealed at the deal")
		ok = false
	# Settle any choice the random deal asked for, then reveal a Cycle early and
	# work its choice through the Confirm button.
	if gm.has_pending_choice():
		GreedyAI.resolve_event_choice(gm)
	gm.event_deck = [MatchEvent.new(MatchEvent.Id.CYCLE)] as Array[MatchEvent]
	gm.reveal_next_event()
	ui._refresh()
	if not ui.choice_btn.visible or not ui.choice_btn.disabled or not ui.end_turn_btn.disabled \
			or not ui.draw_btn.disabled:
		printerr("an event choice should show a disabled Confirm and block ending the turn")
		ok = false
	var hand_before: int = gm.players[0].hand.size()
	ui.selected.assign([gm.players[0].hand[0], gm.players[0].hand[1]])
	ui._refresh()
	if ui.choice_btn.disabled or ui.choice_btn.text.find("2/2") == -1:
		printerr("Confirm should enable at 2/2, reads '%s'" % ui.choice_btn.text)
		ok = false
	ui._on_choice_confirm_pressed()
	if gm.has_pending_choice() or ui.choice_btn.visible or ui.end_turn_btn.disabled \
			or gm.players[0].hand.size() != hand_before:
		printerr("Confirm should discard 2, draw 2 and hand the turn back")
		ok = false

	# --- Energy gates the green playable cap -------------------------------------
	var run_meld := CardSet.new()
	run_meld.cards.assign([_card(5, "hearts"), _card(6, "hearts"), _card(7, "hearts")])
	gm.board.melds.append(run_meld)
	var eight := _card(8, "hearts")
	gm.players[0].hand.append(eight)
	gm._hand_snapshot = gm.players[0].hand.duplicate()
	if not ui._card_is_playable_now(eight):
		printerr("8♥ should be playable with energy to spare")
		ok = false
	gm.players[0].max_energy = 0
	if ui._card_is_playable_now(eight):
		printerr("with no energy left nothing should read as playable")
		ok = false
	gm.players[0].max_energy = first_energy

	# --- Win: back to the map, next node open, new rules apply -------------------
	ui.settings.rogue_draw_per_turn = 3
	ui.settings.rogue_start_hand_size = 10
	ui.settings.rogue_start_energy = 4
	ui.settings.rogue_events = 0  # no events next match, so its energy is exactly 4
	gm.players[0].coins = 4
	gm._end_game([gm.players[0]])
	ui._refresh()
	if run.coins != 4:
		printerr("the match's coins should bank into the run, got %d" % run.coins)
		ok = false
	if run.cleared_count() != 1 or ui.new_game_btn.text != "Back to map":
		printerr("a win should clear node 1 and offer Back to map, got '%s'"
			% ui.new_game_btn.text)
		ok = false
	ui._on_new_game_pressed()
	if not ui.map_layer.visible or run.available_nodes() != [run.node_at(1, 0)]:
		printerr("after a win the map should open node 2")
		ok = false
	ui._on_map_node_chosen(run.node_at(1, 0))
	gm = ui.gm
	if gm.players[1].display_name != "Rust Raider" or gm.draw_per_turn != 3 \
			or gm.players[0].hand.size() != 10 or gm.players[0].max_energy != 4:
		printerr("node 2 should face the Rust Raider under the changed run rules")
		ok = false
	ui.settings.rogue_draw_per_turn = 2
	ui.settings.rogue_start_hand_size = 13
	ui.settings.rogue_start_energy = 3
	if ui.events_row.visible:
		printerr("a match with 0 events should hide the events row")
		ok = false
	ui.settings.rogue_events = 3

	# --- Loss: a life lost, the node stays open ----------------------------------
	gm._end_game([gm.players[1]])
	ui._refresh()
	if run.lives != 2 or ui.new_game_btn.text != "Back to map":
		printerr("a loss should cost a life and offer Back to map")
		ok = false
	ui._on_new_game_pressed()
	if run.available_nodes() != [run.node_at(1, 0)]:
		printerr("a lost node should stay open to retry")
		ok = false
	# Menu → Resume between matches returns to the map.
	ui._show_menu()
	ui._on_resume_pressed()
	if not ui.map_layer.visible:
		printerr("Resume between matches should return to the map")
		ok = false

	# --- Out of lives: the run is over -------------------------------------------
	for _i in 2:
		ui._on_map_node_chosen(run.node_at(1, 0))
		ui.gm._end_game([ui.gm.players[1]])
	ui._refresh()
	if not run.is_lost() or ui.new_game_btn.text != "New run":
		printerr("at 0 lives the run should be over and offer New run")
		ok = false
	ui._on_new_game_pressed()
	if ui.run == run or ui.run.lives != 3 or not ui.map_layer.visible:
		printerr("New run should start a fresh run on the map")
		ok = false

	# --- Beat every node: the run is won -----------------------------------------
	run = ui.run
	for r in 3:
		ui._on_map_node_chosen(run.node_at(r, 0))
		ui.gm._end_game([ui.gm.players[0]])
	ui._refresh()
	if not run.is_won() or ui.new_game_btn.text != "New run":
		printerr("clearing the last node should win the run")
		ok = false

	# --- Back to sandbox: sandbox settings apply, no energy ----------------------
	ui.settings.max_plays_per_turn = 12
	ui.settings.enemy_count = 3
	ui.settings.meter_gain = 2
	ui.settings.meter_per_card = true
	ui._on_play_vanilla_pressed()
	gm = ui.gm
	if gm.players.size() != 4 or gm.max_plays_per_turn != 12 or gm.draw_per_turn != 1:
		printerr("sandbox game should use sandbox settings")
		ok = false
	if gm.energy_on() or ui.lives_label.visible or ui.events_row.visible:
		printerr("sandbox games have no energy, lives or events")
		ok = false
	if gm.meter_gain != 2 or not gm.meter_per_card or gm.meter_max != 20:
		printerr("sandbox game should use sandbox meter settings: max %d gain %d per_card %s"
			% [gm.meter_max, gm.meter_gain, gm.meter_per_card])
		ok = false
	# Live-apply: editing a sandbox meter dial pushes onto the running game.
	ui.settings.meter_max = 4
	ui._apply_live_settings()
	if gm.meter_max != 4:
		printerr("sandbox meter change should apply live, got %d" % gm.meter_max)
		ok = false
	if ok:
		print("UI MODE CHECK OK")
		quit(0)
	else:
		quit(1)
