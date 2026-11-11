class_name Gun
extends RefCounted
## 一個射擊來源（本機或某個僚機）的發射控制。
##
## 每個來源各自計算畫面上限（GDD 4.4）：基本彈 2、環波砲 2、貫穿光束 1、飛彈 1 組。
## 同一種主武器兩發之間至少隔 FIRE_INTERVAL 幀，貼近敵人時基本彈約每秒 6 發（GDD 7.2 的假設）。

const BULLET_SCENE := preload("res://scenes/weapons/bullet.tscn")
const RING_SCENE := preload("res://scenes/weapons/ring.tscn")
const BEAM_SCENE := preload("res://scenes/weapons/beam.tscn")
const MISSILE_SCENE := preload("res://scenes/weapons/missile.tscn")

## 主武器最短發射間隔（物理幀）。
const FIRE_INTERVAL := 10
## 飛彈最短發射間隔（物理幀）。
const MISSILE_INTERVAL := 10
const LIMITS := {&"basic": 2, &"ring": 2, &"beam": 1}

var player_id := 0

var _shots: Array = []
var _missiles: Array = []
var _cooldown := 0
var _missile_cooldown := 0


func _init(id := 0) -> void:
	player_id = id


## 每個物理幀呼叫一次。shooting 為射擊鍵是否按住；muzzle 為砲口的畫面座標。
## 回傳這一幀是否發射了主武器（本機用來播放射擊音效）。
func update(shooting: bool, muzzle: Vector2, weapon: StringName, missile: bool) -> bool:
	_cooldown = maxi(_cooldown - 1, 0)
	_missile_cooldown = maxi(_missile_cooldown - 1, 0)
	_prune(_shots)
	_prune(_missiles)
	if not shooting or Game.world == null:
		return false
	var fired := false
	var limit: int = LIMITS.get(weapon, 2)
	if _cooldown == 0 and _shots.size() < limit:
		_fire_main(weapon, muzzle)
		_cooldown = FIRE_INTERVAL
		fired = true
	if missile and _missile_cooldown == 0 and _missiles.is_empty():
		for side: int in [-1, 1]:
			var m: Missile = MISSILE_SCENE.instantiate()
			m.player_id = player_id
			m.side = side
			m.position = muzzle
			Game.world.player_bullets.add_child(m)
			_missiles.append(m)
		_missile_cooldown = MISSILE_INTERVAL
	return fired


## 畫面上這個來源的主武器數量（測試用）。
func shot_count() -> int:
	_prune(_shots)
	return _shots.size()


func missile_count() -> int:
	_prune(_missiles)
	return _missiles.size()


func _fire_main(weapon: StringName, muzzle: Vector2) -> void:
	var shot: Node2D
	match weapon:
		&"ring":
			shot = RING_SCENE.instantiate()
		&"beam":
			shot = BEAM_SCENE.instantiate()
		_:
			shot = BULLET_SCENE.instantiate()
	shot.set("player_id", player_id)
	shot.position = muzzle
	Game.world.player_bullets.add_child(shot)
	_shots.append(shot)


static func _prune(arr: Array) -> void:
	for i in range(arr.size() - 1, -1, -1):
		var n: Variant = arr[i]
		if not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
			arr.remove_at(i)
