class_name WormFormation
extends Node2D
## 游蟲編隊（GDD 5.2、5.3、8.1）：5 隻游蟲排成一列，沿同一條正弦波路徑由右往左。
##
## 生成參數（setup）：
##   drop: StringName   全滅時最後一隻的位置掉落的道具（空字串則不掉）
##   amplitude: float   正弦波振幅，預設 24 px
##   speed: float       水平速度，預設 80 px/s
##
## 每隔 SPAWN_INTERVAL 秒從生成點放出 1 隻，所以 5 隻走的是同一條路徑。
## 5 隻全部被玩家擊破（沒有任何 1 隻逃走）時，最後被擊破的那隻掉落 drop，
## 並額外給擊破者 500 分。編隊在所有游蟲消失後自行刪除。

signal completed(player_id: int)

const WORM_SCENE := preload("res://scenes/enemies/worm.tscn")
const COUNT := 5
const SPAWN_INTERVAL := 0.25
const BONUS := 500

var drop: StringName = &""
var amplitude := 24.0
var speed := 80.0

var _spawned := 0
var _killed := 0
var _escaped := false
var _timer := 0.0
var _worms: Array[Worm] = []


func setup(params: Dictionary) -> void:
	drop = StringName(params.get("drop", ""))
	amplitude = params.get("amplitude", amplitude)
	speed = params.get("speed", speed)


func _physics_process(delta: float) -> void:
	if _spawned < COUNT:
		_timer -= delta
		if _timer <= 0.0:
			_timer += SPAWN_INTERVAL
			_spawn_worm()
	elif get_child_count() == 0:
		queue_free()


## 目前還活著的游蟲。
func worms() -> Array[Worm]:
	var out: Array[Worm] = []
	for w in _worms:
		if is_instance_valid(w) and not w.dead:
			out.append(w)
	return out


func _spawn_worm() -> void:
	var w: Worm = WORM_SCENE.instantiate()
	w.origin = global_position
	w.amplitude = amplitude
	w.speed = speed
	w.position = Vector2.ZERO
	w.killed.connect(_on_worm_killed)
	w.tree_exiting.connect(_on_worm_exiting.bind(w))
	_worms.append(w)
	add_child(w)
	_spawned += 1


func _on_worm_killed(w: Enemy, player_id: int) -> void:
	_killed += 1
	if _killed == COUNT and not _escaped:
		Game.add_score(player_id, BONUS)
		if drop != &"" and Game.world:
			Game.world.spawn_pickup(drop, w.global_position)
		completed.emit(player_id)


func _on_worm_exiting(w: Worm) -> void:
	if not w.dead:
		_escaped = true
