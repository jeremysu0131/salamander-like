class_name Charger
extends Enemy
## 衝鋒體（GDD 5.3）：16×12，HP 2，200 分。
##
## 生成後先在畫面右緣、自己的 y 位置閃光預警 WARNING_TIME 秒（期間不可見、沒有判定），
## 然後從畫面右緣外以 SPEED 直線往左衝。

const WARNING_TIME := 0.5
const SPEED := 200.0
## 預警閃光每幾個物理幀切換一次。
const BLINK_FRAMES := 3
## 預警閃光的大小與位置（貼著畫面右緣）。
const WARNING_SIZE := Vector2(4, 12)

var warning := true

var _t := 0.0
var _tick := 0
var _warning_rect: ColorRect


func _init() -> void:
	max_hp = 2
	score = 200
	texture_path = "res://assets/sprites/enemy_charger.png"
	hit_size = Vector2(14, 10)


func _ready() -> void:
	super()
	sprite.visible = false
	monitorable = false
	_warning_rect = ColorRect.new()
	_warning_rect.color = Color(1, 1, 1, 0.9)
	_warning_rect.size = WARNING_SIZE
	_warning_rect.top_level = true
	add_child(_warning_rect)
	_warning_rect.global_position = Vector2(Game.SCREEN_SIZE.x - WARNING_SIZE.x, global_position.y - WARNING_SIZE.y / 2)


func _behave(delta: float) -> void:
	if warning:
		_t += delta
		_tick += 1
		_warning_rect.visible = _tick % (BLINK_FRAMES * 2) < BLINK_FRAMES
		if _t >= WARNING_TIME:
			warning = false
			_warning_rect.queue_free()
			sprite.visible = true
			monitorable = true
			global_position.x = Game.SCREEN_SIZE.x + 8.0
		return
	global_position.x -= SPEED * delta
