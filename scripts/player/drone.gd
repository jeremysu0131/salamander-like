class_name Drone
extends Node2D
## 僚機（GDD 4.3、4.5）：跟著本機的軌跡走，發射與本機相同的主武器與飛彈。
##
## 無敵、不擋子彈，所以沒有任何碰撞。位置由 Player 每幀設定（top_level，座標即畫面座標）。
## 自己有一個 Gun，畫面上限與本機分開計算。

const ANIM_FRAMES := 8

var gun := Gun.new()

var _frames := 0

@onready var _sprite: Sprite2D = $Sprite


func _physics_process(_delta: float) -> void:
	_frames += 1
	_sprite.frame = 1 if _frames % (ANIM_FRAMES * 2) >= ANIM_FRAMES else 0


## 由 Player 每幀呼叫。
func shoot(shooting: bool, weapon: StringName, missile: bool) -> void:
	gun.update(shooting, global_position + Vector2(5, 0), weapon, missile)
