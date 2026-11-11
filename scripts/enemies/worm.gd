class_name Worm
extends Enemy
## 游蟲（GDD 5.3）：12×12，HP 1，100 分。沿正弦波路徑由右往左，不開火。
##
## 由 WormFormation 生成，路徑參數由編隊設定。單獨放進場景也能動（用自己的起點當路徑基準）。

## 水平速度（px/s）。
var speed := 80.0
## 正弦波振幅（px）與角頻率（rad/s）。
var amplitude := 24.0
var frequency := 3.0

## 路徑基準點（畫面座標）與經過時間。
var origin := Vector2.ZERO
var t := 0.0


func _init() -> void:
	max_hp = 1
	score = 100
	texture_path = "res://assets/sprites/enemy_worm.png"
	hit_size = Vector2(10, 10)


func _ready() -> void:
	super()
	if origin == Vector2.ZERO:
		origin = global_position
	# 游蟲沒有紅色變體（GDD 5.3）。
	red = false
	set_anim_col(0)


func _behave(delta: float) -> void:
	t += delta
	global_position = path_at(t)


## 路徑：x 等速往左，y 以 origin.y 為中心做正弦擺動。
func path_at(time: float) -> Vector2:
	return Vector2(origin.x - speed * time, origin.y + amplitude * sin(time * frequency))
