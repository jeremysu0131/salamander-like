class_name Ring
extends PlayerShot
## 環波砲（GDD 4.4、6.2）：傷害 1、240 px/s，高度從 8 px 擴大到 40 px，命中敵人即消失。
##
## 對地形：沿著環的高度每 8 px 取一個點，全部丟給 Terrain.hit()，
## 所以一發可以削掉增生壁同一直排上它碰到的格子（最多 5 格）。任何一點碰到地形就消失。

const SPEED := 240.0
const MIN_HEIGHT := 8.0
const MAX_HEIGHT := 40.0
## 從最小長到最大需要的時間（約飛行 96 px）。
const GROW_TIME := 0.4
## 對地形的取樣間距，等於增生壁的格子大小。
const SAMPLE_STEP := 8.0
const MAX_CELLS := 5
## 環的寬度（判定與地形取樣的位置）。
const WIDTH := 6.0

var height := MIN_HEIGHT

var _age := 0.0
var _spent := false
var _rect := RectangleShape2D.new()

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	if velocity == Vector2.ZERO:
		velocity = Vector2(SPEED, 0)
	_shape.shape = _rect
	_apply_height()
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_age += delta
	position += velocity * delta
	height = lerpf(MIN_HEIGHT, MAX_HEIGHT, clampf(_age / GROW_TIME, 0.0, 1.0))
	_apply_height()
	if _is_off_screen(MAX_HEIGHT):
		queue_free()
		return
	if _hit_terrain():
		_spent = true
		queue_free()


## 依目前高度取樣，回傳是否碰到地形。可破壞的格子在 Terrain.hit() 裡扣血。
func _hit_terrain() -> bool:
	var t := _terrain()
	if t == null:
		return false
	var front := global_position + Vector2(WIDTH / 2.0, 0)
	var hits := 0
	var y := -height / 2.0
	while y <= height / 2.0 + 0.01 and hits < MAX_CELLS:
		if t.hit(front + Vector2(0, y), damage, player_id):
			hits += 1
		y += SAMPLE_STEP
	return hits > 0


func _apply_height() -> void:
	_rect.size = Vector2(WIDTH, height)
	# ring.png 三幀：小（8）、中（24）、大（40）。
	if height < 16.0:
		_sprite.frame = 0
	elif height < 32.0:
		_sprite.frame = 1
	else:
		_sprite.frame = 2


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	_hit_enemy(area)
	queue_free()
