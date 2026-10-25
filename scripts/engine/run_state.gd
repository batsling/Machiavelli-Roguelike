class_name RunState
extends RefCounted

## One roguelike run: the lives the player has left and the map of encounters
## they travel. Pure state — no UI — so the headless tests drive it directly.
##
## The map is laid out in rows like Slay the Spire's: you start below row 0,
## pick a node in the next row that your last cleared node links to, fight its
## enemy, and climb. Each node may link to several nodes in the row above, so
## the structure supports branching paths; the current map (linear) is three
## rows of one node each — three enemies in a line.
##
## Lives: losing a match costs one life and the node stays open to retry;
## winning clears it and unlocks the nodes it links to. The run is lost at 0
## lives and won when a node in the last row is cleared.

const DEFAULT_LIVES := 3

## One point on the map: the enemy fought there and the nodes it leads to.
class MapNode:
	extends RefCounted
	var row := 0
	var col := 0
	var enemy: Enemy = null
	## Columns in the next row this node links to.
	var next: Array[int] = []
	var cleared := false

var lives := DEFAULT_LIVES
var start_lives := DEFAULT_LIVES
## rows[r] holds the nodes of row r, left to right.
var rows: Array = []
## The node being fought right now (between begin and record_win/record_loss),
## or null on the map.
var active_node: MapNode = null
# The last node cleared — the player's position on the map (null before the
# first win, i.e. standing below row 0).
var _position: MapNode = null

## A linear map: one row per enemy, each node linking to the next.
static func linear(enemies: Array[Enemy], lives_value := DEFAULT_LIVES) -> RunState:
	var run := RunState.new()
	run.lives = lives_value
	run.start_lives = lives_value
	for i in enemies.size():
		var node := MapNode.new()
		node.row = i
		node.col = 0
		node.enemy = enemies[i]
		if i + 1 < enemies.size():
			node.next.append(0)
		run.rows.append([node])
	return run

func node_at(row: int, col: int) -> MapNode:
	return rows[row][col]

## Nodes the player may travel to now: every node in row 0 before the first
## win, afterwards the uncleared nodes the last cleared node links to. Empty
## once the run is over.
func available_nodes() -> Array[MapNode]:
	var out: Array[MapNode] = []
	if is_over():
		return out
	if _position == null:
		for n: MapNode in rows[0]:
			out.append(n)
		return out
	if _position.row + 1 >= rows.size():
		return out
	for c in _position.next:
		var n: MapNode = rows[_position.row + 1][c]
		if not n.cleared:
			out.append(n)
	return out

func is_available(node: MapNode) -> bool:
	return available_nodes().has(node)

## Start the match at `node`. Returns false (and changes nothing) when the node
## isn't one the player can travel to.
func begin(node: MapNode) -> bool:
	if not is_available(node):
		return false
	active_node = node
	return true

## The active match was won: clear its node and move there.
func record_win() -> void:
	if active_node == null:
		return
	active_node.cleared = true
	_position = active_node
	active_node = null

## The active match was lost: lose a life. The node stays open to retry.
func record_loss() -> void:
	if active_node == null:
		return
	lives = maxi(lives - 1, 0)
	active_node = null

## Nodes cleared so far.
func cleared_count() -> int:
	var n := 0
	for row: Array in rows:
		for node: MapNode in row:
			if node.cleared:
				n += 1
	return n

## True once a node in the last row is cleared.
func is_won() -> bool:
	if rows.is_empty():
		return false
	for node: MapNode in rows[-1]:
		if node.cleared:
			return true
	return false

func is_lost() -> bool:
	return lives <= 0

func is_over() -> bool:
	return is_won() or is_lost()
