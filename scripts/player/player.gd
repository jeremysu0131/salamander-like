class_name Player
extends Node2D
## 玩家機體（GDD 第 4 章）。
##
## - 8 方向移動、無慣性，基礎 90 px/s，每段加速 +25 px/s（最多 5 段）。
## - 一顆射擊鍵同時發射主武器與飛彈，按住自動連射。
## - 判定框 6×4 px（player 層，偵測敵人、敵彈、道具、危險物）；每幀另外查詢地形。
## - 強化狀態存在這個節點上（GDD 12.6），HUD 透過 get_powerup_state() 讀取。
## - 死亡與復活規則見 GDD 4.6。
##
## 碰撞判定一律在 _physics_process 裡用 get_overlapping_areas() 輪詢，
## 這樣無敵結束時已經重疊的東西也會正確判定。

## 殘機用完、不會再復活時發出。
signal out_of_lives
## 強化狀態有變時發出。
signal powerup_changed

enum State { ALIVE, DEAD, GONE }

const BASE_SPEED := 90.0
const SPEED_STEP := 25.0
const MAX_SPEED_LEVEL := 5
const MAX_DRONES := 4
const MAX_SHIELD := 3
## 吃到已達上限的道具時的分數（GDD 8.1）。
const CAPPED_SCORE := 1000
const HITBOX_SIZE := Vector2(6, 4)
## 機體精靈的半寬、半高，用來把整架飛機限制在可活動範圍內。
const HALF_SIZE := Vector2(12, 6)
## 僚機之間在軌跡上相隔的幀數（GDD 4.5）。
const DRONE_SPACING := 16
const MUZZLE := Vector2(12, 0)
const RESPAWN_DELAY := 1.0
const INVULN_TIME := 2.0
## 護盾被敵人本體碰到後，多久之內不再被同一次接觸扣次數。
const SHIELD_CONTACT_IMMUNITY := 0.5
const SHIELD_BLINK_TIME := 0.3
const FLASH_TIME := 0.1

const LAYER_ENEMY := 1 << 3
const LAYER_ENEMY_BULLET := 1 << 4
const LAYER_PICKUP := 1 << 5
const LAYER_HAZARD := 1 << 7

const DRONE_SCENE := preload("res://scenes/player/drone.tscn")
const DRONE_ITEM_SCENE := preload("res://scenes/pickups/drone_item.tscn")
const FLASH_SHADER := preload("res://assets/shaders/flash.gdshader")

var player_id := 0

## 強化狀態。
var speed_level := 0
var missile := false
var weapon: StringName = &"basic"
var shield := 0

var state := State.ALIVE
## 復活後的無敵剩餘時間（秒）。
var invuln_time := 0.0

## 這一幀的輸入。external_input 為 true 時由外部（測試）直接設定，否則每幀從按鍵或自動駕駛讀取。
var input_dir := Vector2.ZERO
var input_shoot := false
var external_input := false

var gun := Gun.new()

## 本機「有移動的幀」的位置佇列，僚機從這裡取位置（GDD 4.5）。
var _trail: Array[Vector2] = []
var _drones: Array[Drone] = []
var _respawn_time := 0.0
var _shield_immunity := 0.0
var _shield_blink := 0.0
var _flash_time := 0.0
var _frames := 0
var _autopilot: Autopilot = null
var _flash_mat := ShaderMaterial.new()

@onready var _sprite: Sprite2D = $Sprite
@onready var _hitbox: Area2D = $Hitbox
@onready var _shield_area: Area2D = $Shield
@onready var _shield_sprite: Sprite2D = $Shield/Sprite
@onready var _drone_root: Node2D = $Drones


func _ready() -> void:
	gun.player_id = player_id
	_flash_mat.shader = FLASH_SHADER
	_sprite.material = _flash_mat
	_trail.append(global_position)
	if Debug.autopilot:
		_autopilot = Autopilot.new()
	if Debug.powered:
		speed_level = 3
		missile = true
		weapon = Debug.weapon if Debug.weapon in [&"ring", &"beam"] else &"beam"
		shield = MAX_SHIELD
		for i in MAX_DRONES:
			_add_drone()
	_update_shield_visual()


func _physics_process(delta: float) -> void:
	_frames += 1
	match state:
		State.ALIVE:
			_process_alive(delta)
		State.DEAD:
			_respawn_time -= delta
			if _respawn_time <= 0.0:
				_respawn()


func is_alive() -> bool:
	return state == State.ALIVE


func is_invulnerable() -> bool:
	return state == State.ALIVE and invuln_time > 0.0


func get_powerup_state() -> Dictionary:
	return {
		speed = speed_level,
		missile = missile,
		weapon = weapon,
		drones = _drones.size(),
		shield = shield,
	}


## 目前的移動速度（px/s）。
func move_speed() -> float:
	return BASE_SPEED + SPEED_STEP * speed_level


## 判定框的畫面座標矩形。
func hitbox_rect() -> Rect2:
	return Rect2(global_position - HITBOX_SIZE / 2.0, HITBOX_SIZE)


func drones() -> Array[Drone]:
	return _drones


## 吃到道具（GDD 4.3）。已達上限時改為加 1000 分。
func apply_powerup(type: StringName) -> void:
	var capped := false
	match type:
		&"speed":
			if speed_level >= MAX_SPEED_LEVEL:
				capped = true
			else:
				speed_level += 1
		&"missile":
			if missile:
				capped = true
			else:
				missile = true
		&"ring", &"beam":
			# 主武器互斥，後吃的覆蓋前者。
			if weapon == type:
				capped = true
			else:
				weapon = type
		&"drone":
			if _drones.size() >= MAX_DRONES:
				capped = true
			else:
				_add_drone()
		&"shield":
			# 不疊加，再吃則補滿；已經是滿的才算達到上限。
			if shield >= MAX_SHIELD:
				capped = true
			else:
				shield = MAX_SHIELD
				_update_shield_visual()
		_:
			push_warning("Unknown pickup type: %s" % type)
			return
	if capped:
		Game.add_score(player_id, CAPPED_SCORE)
	_on_collected()


## 撿回散落的僚機（GDD 4.6）。已經有 4 個時改為加分。
func recover_drone() -> void:
	if _drones.size() >= MAX_DRONES:
		Game.add_score(player_id, CAPPED_SCORE)
	else:
		_add_drone()
	_on_collected()


## 死亡（GDD 4.6）。無敵中或 Debug.god 時不會死。
func die() -> void:
	if state != State.ALIVE or is_invulnerable() or Debug.god:
		return
	_kill()


func _process_alive(delta: float) -> void:
	_read_input()
	_move(delta)
	_update_drones()
	_shoot()
	_update_shield(delta)
	_check_hits()
	if state != State.ALIVE:
		return
	if invuln_time > 0.0:
		invuln_time -= delta
		if invuln_time <= 0.0:
			invuln_time = 0.0
			# 無敵結束的瞬間仍在地形內則死亡。
			if _in_terrain():
				die()
				return
	elif _in_terrain():
		die()
		return
	_update_visual(delta)


func _read_input() -> void:
	if external_input:
		return
	if _autopilot:
		input_dir = _autopilot.steer(self)
		input_shoot = true
		return
	var prefix := "p%d_" % (player_id + 1)
	var x := int(Input.is_action_pressed(prefix + "right")) - int(Input.is_action_pressed(prefix + "left"))
	var y := int(Input.is_action_pressed(prefix + "down")) - int(Input.is_action_pressed(prefix + "up"))
	input_dir = Vector2(x, y)
	input_shoot = Input.is_action_pressed(prefix + "shoot")


func _move(delta: float) -> void:
	var dir := input_dir
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var before := global_position
	var p := before + dir * move_speed() * delta
	p.x = clampf(p.x, Game.PLAYFIELD.position.x + HALF_SIZE.x, Game.PLAYFIELD.end.x - HALF_SIZE.x)
	p.y = clampf(p.y, Game.PLAYFIELD.position.y + HALF_SIZE.y, Game.PLAYFIELD.end.y - HALF_SIZE.y)
	global_position = p
	if p != before:
		_trail.append(p)
		var keep := DRONE_SPACING * MAX_DRONES + 1
		while _trail.size() > keep:
			_trail.remove_at(0)
	# player.png：平飛、上傾、下傾。
	if input_dir.y < 0.0:
		_sprite.frame = 1
	elif input_dir.y > 0.0:
		_sprite.frame = 2
	else:
		_sprite.frame = 0


func _update_drones() -> void:
	for i in _drones.size():
		_drones[i].global_position = _trail_position(i)


## 第 i 個僚機在軌跡上的位置：落後 16 × (i + 1) 個記錄點。軌跡不夠長時取最舊的點。
func _trail_position(i: int) -> Vector2:
	var idx := maxi(_trail.size() - 1 - DRONE_SPACING * (i + 1), 0)
	return _trail[idx]


func _shoot() -> void:
	if gun.update(input_shoot, global_position + MUZZLE, weapon, missile):
		Sfx.play(&"shoot")
	for d in _drones:
		d.shoot(input_shoot, weapon, missile)


func _update_shield(delta: float) -> void:
	_shield_immunity = maxf(_shield_immunity - delta, 0.0)
	_shield_blink = maxf(_shield_blink - delta, 0.0)
	if shield <= 0:
		return
	for area in _shield_area.get_overlapping_areas():
		if area.is_queued_for_deletion():
			continue
		if area.collision_layer & LAYER_ENEMY_BULLET:
			area.queue_free()
			_shield_hit()
		elif area.collision_layer & LAYER_ENEMY and _shield_immunity <= 0.0:
			_shield_immunity = SHIELD_CONTACT_IMMUNITY
			_shield_hit()
			# 一般雜兵撞上護盾直接擊毀，否則會繼續衝進判定框。
			# Boss 的部位與觸手根部不受影響（它們不會移動到機體上）。
			if area is Enemy and not area is TentacleRoot:
				var e: Enemy = area
				e.die(player_id)
		if shield <= 0:
			break


func _shield_hit() -> void:
	shield = maxi(shield - 1, 0)
	_shield_blink = SHIELD_BLINK_TIME
	_update_shield_visual()
	powerup_changed.emit()


func _check_hits() -> void:
	for area in _hitbox.get_overlapping_areas():
		if state != State.ALIVE:
			return
		if area.is_queued_for_deletion():
			continue
		var layer := area.collision_layer
		if layer & LAYER_PICKUP:
			if area.has_method("collect"):
				area.collect(self)
		elif layer & (LAYER_ENEMY | LAYER_ENEMY_BULLET | LAYER_HAZARD):
			if is_invulnerable() or Debug.god:
				continue
			if layer & LAYER_ENEMY_BULLET:
				area.queue_free()
			_kill()


func _in_terrain() -> bool:
	if Game.world == null or Game.world.stage == null:
		return false
	return Game.world.terrain().is_solid_rect(hitbox_rect())


func _kill() -> void:
	state = State.DEAD
	invuln_time = 0.0
	if Game.world:
		Game.world.spawn_explosion(global_position)
	# 僚機留在原地，變成可撿回的道具。
	for d in _drones:
		var item: Node2D = DRONE_ITEM_SCENE.instantiate()
		item.position = d.global_position
		if Game.world:
			Game.world.pickups.add_child(item)
		else:
			item.free()
		d.queue_free()
	_drones.clear()
	speed_level = 0
	missile = false
	weapon = &"basic"
	shield = 0
	_update_shield_visual()
	_sprite.visible = false
	powerup_changed.emit()
	if Game.lose_life(player_id):
		_respawn_time = RESPAWN_DELAY
	else:
		state = State.GONE
		out_of_lives.emit()


func _respawn() -> void:
	global_position = _find_safe_position(global_position)
	_trail.clear()
	_trail.append(global_position)
	state = State.ALIVE
	invuln_time = INVULN_TIME
	_sprite.visible = true


## 復活位置（GDD 4.6）：原地若碰到地形、觸手、Boss 或敵人，就從原地往上下左右同時擴大搜尋，
## 取最近的空位（同距離時依序：上、下、右、左）。
## 「空位」是指機體周圍 12×8 的範圍沒有地形、hazard 層與 enemy 層的東西。
## 都找不到就留在原地（反正有 2 秒無敵）。
func _find_safe_position(p: Vector2) -> Vector2:
	if _is_safe(p):
		return p
	var area := Rect2(Game.PLAYFIELD.position + HALF_SIZE, Game.PLAYFIELD.size - HALF_SIZE * 2.0)
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT]
	for d in range(4, int(Game.PLAYFIELD.size.x), 4):
		for dir in dirs:
			var q := p + dir * d
			if area.has_point(q) and _is_safe(q):
				return q
	return p


func _is_safe(p: Vector2) -> bool:
	if Game.world == null or Game.world.stage == null:
		return true
	if Game.world.terrain().is_solid_rect(Rect2(p - Vector2(6, 4), Vector2(12, 8))):
		return false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 8)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, p)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = LAYER_ENEMY | LAYER_HAZARD
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _add_drone() -> void:
	var d: Drone = DRONE_SCENE.instantiate()
	d.gun.player_id = player_id
	_drone_root.add_child(d)
	_drones.append(d)
	d.global_position = _trail_position(_drones.size() - 1)


func _on_collected() -> void:
	Sfx.play(&"pickup")
	_flash_time = FLASH_TIME
	powerup_changed.emit()


func _update_shield_visual() -> void:
	_shield_area.visible = shield > 0
	_shield_area.set_deferred(&"monitoring", shield > 0)


func _update_visual(delta: float) -> void:
	# 復活無敵中閃爍。
	_sprite.visible = invuln_time <= 0.0 or _frames % 8 < 4
	_flash_time = maxf(_flash_time - delta, 0.0)
	_flash_mat.set_shader_parameter(&"flash", 1.0 if _flash_time > 0.0 else 0.0)
	if shield > 0:
		_shield_sprite.visible = _shield_blink <= 0.0 or _frames % 4 < 2
