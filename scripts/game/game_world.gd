class_name GameWorld
extends Node2D
## 一輪遊戲：關卡、玩家、各類物件的容器，以及過關與 Game Over 的判定。
##
## 其他物件透過 Game.world 取得這個節點，用 spawn_* 系列函式生成共用物件。

## 這一輪結束。result 為 &"clear" 或 &"game_over"，bonus 為過關時的殘機獎勵。
signal finished(result: StringName, bonus: int)

const STAGE_DATA := "res://scripts/stage/stage1_data.gd"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSS_SCENE := "res://scenes/boss/boss.tscn"
const PICKUP_SCENE := "res://scenes/pickups/pickup.tscn"
const ENEMY_BULLET_SCENE := "res://scenes/enemies/enemy_bullet.tscn"
const EXPLOSION_SCENE := "res://scenes/effects/explosion.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const PAUSE_SCENE := "res://scenes/ui/pause.tscn"
## 過關時每條剩餘殘機的獎勵（GDD 8.1）。
const LIFE_BONUS := 5000
## Boss 擊破或撤退後，等多久進入過關畫面。
const CLEAR_DELAY := 2.5
const GAME_OVER_DELAY := 1.5

var stage: Stage
var players: Array[Node2D] = []
var boss: Node2D = null
var is_over := false

@onready var pickups: Node2D = $Pickups
@onready var enemies: Node2D = $Enemies
@onready var player_bullets: Node2D = $PlayerBullets
@onready var players_root: Node2D = $Players
@onready var enemy_bullets: Node2D = $EnemyBullets
@onready var effects: Node2D = $Effects
@onready var ui: CanvasLayer = $UI

var _pause_ui: CanvasItem = null
var _scenes := {}


func _ready() -> void:
	Game.world = self
	Game.reset_run()
	Debug.game_time = 0.0
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	move_child(stage, 0)
	stage.setup(load(STAGE_DATA).new(), Debug.start_x)
	stage.end_reached.connect(_on_stage_end_reached)
	_spawn_player(0)
	if ResourceLoader.exists(HUD_SCENE):
		ui.add_child(load(HUD_SCENE).instantiate())
	if ResourceLoader.exists(PAUSE_SCENE):
		_pause_ui = load(PAUSE_SCENE).instantiate()
		_pause_ui.visible = false
		ui.add_child(_pause_ui)
	$PauseHandler.process_mode = Node.PROCESS_MODE_ALWAYS
	$PauseHandler.set_process_unhandled_input(true)
	if stage.scroll_x >= stage.data.length:
		_on_stage_end_reached.call_deferred()


func _exit_tree() -> void:
	if Game.world == self:
		Game.world = null
	get_tree().paused = false


func toggle_pause() -> void:
	if is_over:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	if _pause_ui:
		_pause_ui.visible = p


## 地形；給需要查詢地形的物件使用。
func terrain() -> Terrain:
	return stage.terrain


## 在畫面座標 pos 生成一個道具。type 為 &"speed"、&"missile"、&"ring"、&"beam"、&"drone"、&"shield"。
func spawn_pickup(type: StringName, pos: Vector2) -> Node2D:
	var p: Node2D = _instantiate(PICKUP_SCENE)
	if p == null:
		return null
	p.type = type
	p.position = pos
	pickups.add_child(p)
	return p


## 生成一發敵彈。velocity 應已乘上 Game.difficulty。
func spawn_enemy_bullet(pos: Vector2, velocity: Vector2) -> Node2D:
	var b: Node2D = _instantiate(ENEMY_BULLET_SCENE)
	if b == null:
		return null
	b.position = pos
	b.velocity = velocity
	enemy_bullets.add_child(b)
	return b


## 往 target 方向的敵彈速度，基礎彈速 100 px/s 乘上全域倍率（GDD 5.1）。
func aimed_velocity(from: Vector2, target: Vector2, speed := 100.0) -> Vector2:
	return (target - from).normalized() * speed * Game.difficulty


func spawn_explosion(pos: Vector2, big := false) -> void:
	var e: Node2D = _instantiate(EXPLOSION_SCENE)
	e.position = pos
	if big:
		e.scale = Vector2(2, 2)
	effects.add_child(e)


## 敵人瞄準用：離 from 最近、還活著的玩家。沒有則回傳 null。
## 敵人不要直接引用唯一的玩家節點，一律透過這裡（GDD 12.6）。
func get_target_player(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			var d := from.distance_squared_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best


func debug_status() -> String:
	var parts := ["x=%d" % stage.scroll_x, "score=%d" % Game.scores[0], "lives=%d" % Game.lives[0]]
	if players.size() > 0 and is_instance_valid(players[0]):
		parts.append("pos=(%d,%d)" % [players[0].global_position.x, players[0].global_position.y])
	if is_instance_valid(boss) and "hp" in boss:
		parts.append("boss_hp=%d" % boss.hp)
	return " ".join(parts)


func _spawn_player(id: int) -> void:
	var p: Node2D = _instantiate(PLAYER_SCENE)
	if p == null:
		return
	p.player_id = id
	p.position = Vector2(64, Game.PLAYFIELD.get_center().y)
	players_root.add_child(p)
	players.append(p)
	p.out_of_lives.connect(_on_player_out_of_lives)


func _on_player_out_of_lives() -> void:
	for p in players:
		if is_instance_valid(p) and Game.lives[p.player_id] > 0:
			return
	_end(&"game_over", 0, GAME_OVER_DELAY)


func _on_stage_end_reached() -> void:
	if not ResourceLoader.exists(BOSS_SCENE):
		_on_boss_finished(false)
		return
	boss = load(BOSS_SCENE).instantiate()
	enemies.add_child(boss)
	boss.finished.connect(_on_boss_finished)


func _on_boss_finished(_defeated: bool) -> void:
	if is_over:
		return
	var bonus := 0
	for p in players:
		bonus += Game.lives[p.player_id] * LIFE_BONUS
		Game.add_score(p.player_id, Game.lives[p.player_id] * LIFE_BONUS)
	_end(&"clear", bonus, CLEAR_DELAY)


func _end(result: StringName, bonus: int, delay: float) -> void:
	if is_over:
		return
	is_over = true
	Game.save_hiscore()
	await get_tree().create_timer(delay, false).timeout
	finished.emit(result, bonus)


func _instantiate(path: String) -> Node:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	if _scenes[path] == null:
		return null
	return _scenes[path].instantiate()
