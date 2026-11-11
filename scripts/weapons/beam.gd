class_name Beam
extends Area2D
## 貫穿光束（GDD 4.4、6.2）：一道水平線段，前端以 600 px/s 前進，長度最多 96 px。
##
## - 剛射出時尾端停在砲口，前端往前伸；長到 96 px 後整道往前飛。
## - 貫穿敵人：對每個重疊的敵人立刻造成 1 點傷害，之後每 0.2 秒再 1 點。
## - 被地形擋住：前端停在地形邊緣，尾端繼續前進，光束越來越短直到消失。
##   前端抵著地形時每 0.2 秒對前端那一格呼叫一次 Terrain.hit()，用來鑽穿增生壁。
##
## 節點的 position 是尾端（左端）的中心，線段往 +x 延伸 length。

const SPEED := 600.0
const MAX_LENGTH := 96.0
const THICKNESS := 4.0
## 傷害間隔（物理幀）。0.2 秒 × 60 Hz。
const TICK_FRAMES := 12
## 檢查地形的取樣間距，小於格子大小。
const SCAN_STEP := 4.0

var player_id := 0
var damage := 1
## 前端的速度。測試可以設成 0 讓光束停住。
var speed := SPEED
## 目前長度。
var length := 0.0
## 尾端是否已經離開砲口（長到最大長度之後）。
var detached := false
## 前端是否被地形擋住。
var blocked := false
## 擋住前端的地形 x 座標。
var _block_x := INF

## 每個敵人（instance id）距離下次受傷還有幾幀。
var _cooldowns := {}
var _tip_cooldown := 0
var _rect := RectangleShape2D.new()

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	_shape.shape = _rect
	_apply_length()


func _physics_process(delta: float) -> void:
	var tail := global_position.x
	var step := speed * delta
	var head := tail + length + step
	_update_terrain(tail, head)
	if blocked:
		# 前端停在地形邊緣，後面的部分繼續往前「流進」地形。
		head = _block_x
		tail += step
	elif head - tail > MAX_LENGTH:
		detached = true
		tail = head - MAX_LENGTH
	if head - tail <= 0.5 or tail > Game.SCREEN_SIZE.x + 8.0:
		queue_free()
		return
	global_position.x = tail
	length = head - tail
	_apply_length()
	_damage_enemies()


## 從尾端往前掃描，找出第一個實心點；找到就截斷光束。前端抵住地形時定期對那一格造成傷害。
func _update_terrain(tail: float, head: float) -> void:
	if Game.world == null or Game.world.stage == null:
		return
	var t := Game.world.terrain()
	var y := global_position.y
	var x := tail
	var found := false
	while x <= head:
		if t.is_solid_at(Vector2(x, y)):
			found = true
			break
		x += SCAN_STEP
	if found:
		# 取樣間距是 4 px，往回逐 px 找到地形真正的邊緣。
		while x - 1.0 > tail and t.is_solid_at(Vector2(x - 1.0, y)):
			x -= 1.0
		blocked = true
		_block_x = x
		_tip_cooldown -= 1
		if _tip_cooldown <= 0:
			_tip_cooldown = TICK_FRAMES
			t.hit(Vector2(x + 1.0, y), damage, player_id)
	else:
		# 擋住它的格子被削掉（或捲走）了，繼續前進。
		blocked = false
		_block_x = INF


func _damage_enemies() -> void:
	var touching := {}
	for area in get_overlapping_areas():
		if area.is_queued_for_deletion() or not area.has_method("take_damage"):
			continue
		var id := area.get_instance_id()
		touching[id] = true
		var left: int = _cooldowns.get(id, 0)
		if left <= 0:
			area.take_damage(damage, player_id)
			_cooldowns[id] = TICK_FRAMES
	for id: int in _cooldowns.keys():
		var left: int = _cooldowns[id]
		left -= 1
		if left <= 0 and not touching.has(id):
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left


func _apply_length() -> void:
	_rect.size = Vector2(maxf(length, 1.0), THICKNESS)
	_shape.position = Vector2(length / 2.0, 0)
	_sprite.region_rect = Rect2(0, 0, maxf(length, 1.0), THICKNESS)
