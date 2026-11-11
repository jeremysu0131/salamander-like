class_name Missile
extends PlayerShot
## 飛彈（GDD 4.3、4.4、6.2）：傷害 2、180 px/s，往斜上或斜下飛。
##
## 碰到地形表面後沿著地形往前爬，遇到高低差會順著輪廓上下（最多 CLIMB px 的台階）。
## 正面被擋住（台階太高、增生壁）時對那一格呼叫 Terrain.hit() 後消失，所以每發削 1 格。
## 碰到敵人或離開畫面也消失。
##
## 地形判定用「腳」的位置：飛彈朝地形那一側的邊緣（side = +1 往下飛、貼地面；-1 往上、貼天花板）。

enum State { AIR, CRAWL }

const SPEED := 180.0
## 爬行時一步最多往上（遠離表面）爬幾 px。
const CLIMB := 10
## 爬行時腳下懸空，最多往下（朝表面）找幾 px；找不到就恢復斜飛。
const DROP := 10
const HALF_HEIGHT := 2.0

## +1：往斜下、貼地面爬；-1：往斜上、貼天花板爬。
var side := 1
var state := State.AIR

var _spent := false

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	damage = 2
	velocity = Vector2(1, side).normalized() * SPEED
	_update_sprite()
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var t := _terrain()
	if t == null:
		position += velocity * delta
	elif state == State.AIR:
		_fly(t, delta)
	else:
		_crawl(t, delta)
	if not _spent and _is_off_screen(8.0):
		queue_free()


func _foot() -> Vector2:
	return global_position + Vector2(0, HALF_HEIGHT * side)


func _set_foot(p: Vector2) -> void:
	global_position = p - Vector2(0, HALF_HEIGHT * side)


func _fly(t: Terrain, delta: float) -> void:
	var foot := _foot()
	var next := foot + velocity * delta
	if not t.is_solid_at(next):
		_set_foot(next)
		return
	var forward := foot + Vector2(velocity.x * delta, 0)
	if t.is_solid_at(forward):
		# 正面撞上牆壁。
		_explode_at(t, forward)
		return
	# 落到表面：往表面方向一次 1 px 靠過去，然後開始爬。
	var p := forward
	for i in int(absf(velocity.y * delta)) + 1:
		var q := p + Vector2(0, side)
		if t.is_solid_at(q):
			break
		p = q
	_set_foot(p)
	state = State.CRAWL
	_update_sprite()


func _crawl(t: Terrain, delta: float) -> void:
	var f := _foot() + Vector2(SPEED * delta, 0)
	if t.is_solid_at(f):
		# 前面變高：往遠離表面的方向找可以站的位置。
		var climbed := false
		for i in range(1, CLIMB + 1):
			var c := f - Vector2(0, side * i)
			if not t.is_solid_at(c):
				f = c
				climbed = true
				break
		if not climbed:
			_explode_at(t, f)
			return
	else:
		# 前面變低：往表面方向找地面，貼著走。
		var grounded := false
		for i in range(1, DROP + 1):
			var c := f + Vector2(0, side * i)
			if t.is_solid_at(c):
				grounded = true
				break
			f = c
		if not grounded:
			# 走到地形的盡頭，恢復斜飛。
			state = State.AIR
			_update_sprite()
	_set_foot(f)


func _explode_at(t: Terrain, p: Vector2) -> void:
	t.hit(p, damage, player_id)
	_spent = true
	queue_free()


func _update_sprite() -> void:
	# missile.png 兩幀：飛行、爬行。
	if state == State.AIR:
		_sprite.frame = 0
		_sprite.flip_v = false
		_sprite.rotation = velocity.angle()
	else:
		_sprite.frame = 1
		_sprite.rotation = 0.0
		_sprite.flip_v = side < 0


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	_hit_enemy(area)
	queue_free()
