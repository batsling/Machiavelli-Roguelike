class_name EnemyMoveAnimator
extends Node

## Flies enemy cards across the table so their moves are visible: each card's
## face slides from where it was (its old spot on the felt, or the middle of the
## enemy's hidden hand) to where it lands after the refresh. Split out of
## main_ui because it is a self-contained animation concern — it needs only the
## overlay to draw into, the on-screen card registry, and the tree for timing.

const ANIM_TIME := 0.45

var _anim_layer: Control
# The table root, used to centre the fallback origin when an enemy's card backs
# can't be located.
var _ui_root: Control

func setup(anim_layer: Control, ui_root: Control) -> void:
	_anim_layer = anim_layer
	_ui_root = ui_root

## Where each card is on screen right now: face-up cards report their button's
## position, cards still hidden in an enemy hand report the middle of that
## enemy's card backs. Must be called before the move is applied/refreshed.
## `card_nodes` maps Card -> its current on-screen Control; `opponent_backs`
## maps player_id -> that seat's card-back container.
func capture_positions(enemy: PlayerState, cards: Array[Card],
		card_nodes: Dictionary, opponent_backs: Dictionary) -> Dictionary:
	var out := {}
	for c in cards:
		var node: Control = card_nodes.get(c)
		if node != null and is_instance_valid(node):
			out[c] = node.global_position
		else:
			out[c] = _enemy_hand_origin(enemy, opponent_backs)
	return out

func _enemy_hand_origin(enemy: PlayerState, opponent_backs: Dictionary) -> Vector2:
	var backs: Control = opponent_backs.get(enemy.player_id)
	if backs != null and is_instance_valid(backs):
		return backs.get_global_rect().get_center() - UITheme.BOARD_CARD_SIZE / 2.0
	return _ui_root.get_global_rect().get_center() - UITheme.BOARD_CARD_SIZE / 2.0

## Fly card faces from `sources` (Card -> screen position) to wherever the cards
## sit in `card_nodes` after the last refresh. Each destination button is hidden
## while its card is in flight, then revealed when the flight lands.
func animate(cards: Array[Card], sources: Dictionary, card_nodes: Dictionary) -> void:
	# The freshly rebuilt containers need a frame or two to lay out before
	# destination positions are meaningful.
	await get_tree().process_frame
	await get_tree().process_frame
	var last_tween: Tween = null
	for c in cards:
		var dest: Control = card_nodes.get(c)
		if dest == null or not is_instance_valid(dest) or not sources.has(c):
			continue
		var proxy := CardRenderer.make_card_face(c)
		_anim_layer.add_child(proxy)
		proxy.global_position = sources[c]
		dest.modulate.a = 0.0
		var tw := proxy.create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(proxy, "global_position", dest.global_position, ANIM_TIME)
		tw.tween_callback(func() -> void:
			if is_instance_valid(dest):
				dest.modulate.a = 1.0
			proxy.queue_free())
		last_tween = tw
	if last_tween != null:
		await last_tween.finished
