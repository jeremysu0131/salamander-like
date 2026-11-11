class_name Pickup
extends Area2D
## 道具（GDD 4.3、5.2）：pickup 層（6）的 Area2D，以 30 px/s 往左飄，離開畫面即消失。
##
## 由玩家的判定框偵測，碰到時玩家呼叫 collect()。

const DRIFT_SPEED := 30.0
## pickup.png 每列一種道具，順序固定。
const ROWS := {&"speed": 0, &"missile": 1, &"ring": 2, &"beam": 3, &"drone": 4, &"shield": 5}
## 閃爍：每幾幀換一次幀。
const BLINK_FRAMES := 8

var type: StringName = &"speed"

var _frames := 0
var _taken := false

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_update_frame()


func _physics_process(delta: float) -> void:
	position.x -= DRIFT_SPEED * delta
	_frames += 1
	_update_frame()
	if global_position.x < -16.0:
		queue_free()


## 被玩家撿起。同一個道具只會生效一次。
func collect(player: Player) -> void:
	if _taken:
		return
	_taken = true
	player.apply_powerup(type)
	queue_free()


func _update_frame() -> void:
	var row: int = ROWS.get(type, 0)
	_sprite.frame_coords = Vector2i(1 if _frames % (BLINK_FRAMES * 2) >= BLINK_FRAMES else 0, row)
