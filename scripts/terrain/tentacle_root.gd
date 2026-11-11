class_name TentacleRoot
extends Enemy
## 伸縮觸手的根部節點（GDD 6.2）：12×12，HP 6，500 分。
##
## 生命週期由 Tentacle 管理：擊破時 Tentacle 收到 killed 訊號，整條觸手一起爆炸消失。


func _init() -> void:
	max_hp = 6
	score = 500
	texture_path = "res://assets/sprites/tentacle_root.png"
	hframes = 1
	vframes = 1
	hit_size = Vector2(12, 12)
	animate = false
	auto_free = false
