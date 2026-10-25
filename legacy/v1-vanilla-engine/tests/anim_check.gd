extends SceneTree

## Headless check that enemy turns drive to completion through the extracted
## EnemyMoveAnimator: end the human turn, let the AI play, and confirm the
## coroutine finishes, every flying-card proxy is cleaned up, and play returns
## to the human (or the game ends). Run:
##   godot --headless --path . --script res://tests/anim_check.gd

func _init() -> void:
	var ui: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui._on_play_vanilla_pressed()
	await process_frame
	var ok := true

	# End the human turn without playing; this kicks off _run_ai_turns.
	ui._on_draw_pressed()
	# Wait for the AI coroutine to finish (real timers + tweens), with a cap.
	var frames := 0
	while ui.ai_running and frames < 6000:
		await process_frame
		frames += 1

	if ui.ai_running:
		printerr("AI turns did not finish within the frame budget")
		ok = false
	if ui.anim_layer.get_child_count() != 0:
		printerr("animation proxies leaked on anim_layer: %d left"
			% ui.anim_layer.get_child_count())
		ok = false
	if not ui.gm.is_game_over and ui.gm.current_player() != ui.gm.players[0]:
		printerr("after the AI round it should be the human's turn again")
		ok = false
	# Every card any enemy touched should be registered as highlighted, and each
	# such card must have a live on-screen node (the animation destination).
	for c: Card in ui.highlighted:
		if not ui.card_nodes.has(c):
			printerr("a highlighted enemy card has no on-screen node")
			ok = false
			break

	if ok:
		print("anim_check: PASS")
		quit(0)
	else:
		printerr("anim_check: FAIL")
		quit(1)
