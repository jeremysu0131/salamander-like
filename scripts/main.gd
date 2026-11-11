extends Node
## 畫面流程：標題 → 遊戲 → Game Over 或過關畫面 → 標題（GDD 9.2）。
##
## UI 場景的介面：
##   title.tscn   根節點發出 start_requested
##   result.tscn  根節點有 setup(result: StringName, score: int, bonus: int)，看完發出 closed

const GAME_SCENE := preload("res://scenes/game/game_world.tscn")
const TITLE_SCENE := "res://scenes/ui/title.tscn"
const RESULT_SCENE := "res://scenes/ui/result.tscn"

var _current: Node = null


func _ready() -> void:
	if Debug.skip_title or not ResourceLoader.exists(TITLE_SCENE):
		start_game()
	else:
		show_title()


func show_title() -> void:
	var title: Node = load(TITLE_SCENE).instantiate()
	title.start_requested.connect(start_game, CONNECT_DEFERRED)
	_switch_to(title)


func start_game() -> void:
	var world: GameWorld = GAME_SCENE.instantiate()
	world.finished.connect(_on_game_finished, CONNECT_DEFERRED)
	_switch_to(world)


func _on_game_finished(result: StringName, bonus: int) -> void:
	var score := Game.scores[0]
	if not ResourceLoader.exists(RESULT_SCENE):
		show_title() if ResourceLoader.exists(TITLE_SCENE) else start_game()
		return
	var screen: Node = load(RESULT_SCENE).instantiate()
	screen.setup(result, score, bonus)
	screen.closed.connect(show_title, CONNECT_DEFERRED)
	_switch_to(screen)


func _switch_to(node: Node) -> void:
	if _current:
		_current.queue_free()
	_current = node
	add_child(node)
