extends Sprite2D
## 爆炸動畫：explosion.png 為 5 幀橫排，播完自動刪除。

const FRAME_TIME := 0.06

var _t := 0.0


func _ready() -> void:
	texture = preload("res://assets/sprites/explosion.png")
	hframes = 5


func _physics_process(delta: float) -> void:
	_t += delta
	var f := int(_t / FRAME_TIME)
	if f >= hframes:
		queue_free()
	else:
		frame = f
