class_name EnemyBullet
extends Area2D
## 敵彈（GDD 5.1）：4×4 px 圓彈，兩幀交替閃爍。碰到地形或離開畫面就消失。
##
## 由 GameWorld.spawn_enemy_bullet() 生成，velocity 已乘上 Game.difficulty。

const LAYER_ENEMY_BULLET := 1 << 4
## 每幾個物理幀換一幀。
const BLINK_FRAMES := 4
const MARGIN := 8.0

var velocity := Vector2.ZERO

var _sprite: Sprite2D
var _tick := 0


func _ready() -> void:
	collision_layer = LAYER_ENEMY_BULLET
	collision_mask = 0
	monitoring = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4, 4)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	_sprite = Sprite2D.new()
	_sprite.texture = preload("res://assets/sprites/enemy_bullet.png")
	_sprite.hframes = 2
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_tick += 1
	if _tick % BLINK_FRAMES == 0:
		_sprite.frame = 1 - _sprite.frame
	var p := global_position
	if p.x < -MARGIN or p.x > Game.SCREEN_SIZE.x + MARGIN or p.y < -MARGIN or p.y > Game.SCREEN_SIZE.y + MARGIN:
		queue_free()
	elif Game.world and Game.world.terrain() and Game.world.terrain().is_solid_at(p):
		queue_free()
