class_name Bullet
extends PlayerShot
## 基本彈（GDD 4.4）：傷害 1、360 px/s 直線前進，碰到敵人或地形就消失。

const SPEED := 360.0

var _spent := false


func _ready() -> void:
	if velocity == Vector2.ZERO:
		velocity = Vector2(SPEED, 0)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	position += velocity * delta
	if _is_off_screen():
		queue_free()
		return
	var t := _terrain()
	if t and t.hit(global_position + Vector2(3, 0), damage, player_id):
		_spent = true
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	_spent = true
	_hit_enemy(area)
	queue_free()
