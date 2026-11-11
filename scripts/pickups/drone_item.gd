class_name DroneItem
extends Area2D
## 散落的僚機（GDD 4.6）：玩家死亡時每個僚機留在原地變成這個。
##
## 以 20 px/s 往左飄，5 秒後消失，最後 1.5 秒閃爍。玩家碰到就撿回 1 個僚機。

const DRIFT_SPEED := 20.0
const LIFETIME := 5.0
const BLINK_TIME := 1.5
const ANIM_FRAMES := 8

var _age := 0.0
var _frames := 0
var _taken := false

@onready var _sprite: Sprite2D = $Sprite


func _physics_process(delta: float) -> void:
	position.x -= DRIFT_SPEED * delta
	_age += delta
	_frames += 1
	_sprite.frame = 1 if _frames % (ANIM_FRAMES * 2) >= ANIM_FRAMES else 0
	if _age >= LIFETIME - BLINK_TIME:
		_sprite.visible = _frames % 6 < 3
	if _age >= LIFETIME or global_position.x < -16.0:
		queue_free()


## 被玩家撿起。
func collect(player: Player) -> void:
	if _taken:
		return
	_taken = true
	player.recover_drone()
	queue_free()
