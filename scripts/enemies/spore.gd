class_name Spore
extends Enemy
## 孢子（GDD 5.3）：12×12，HP 1，100 分，不開火。
##
## 行為分三段：
##   1. 飄入：以 DRIFT_SPEED 往左飄，上下輕微擺動。
##   2. 轉向：與目標玩家的水平距離小於 DASH_RANGE 時停下 TURN_TIME 秒（預備動作）。
##   3. 直衝：鎖定當下玩家的位置，以 DASH_SPEED 直線衝過去，之後不再轉向，飛出畫面後回收。
## 沒有玩家時一直飄，飄出畫面左側回收。

## 飄入速度（px/s）。比捲動略快，玩家看得出它在接近。
const DRIFT_SPEED := 50.0
const BOB_AMPLITUDE := 6.0
const BOB_FREQUENCY := 4.0
## 與玩家水平距離小於這個值時開始轉向（px）。約畫面寬的 1/3，留給玩家反應時間。
const DASH_RANGE := 128.0
## 轉向的停頓（秒）。
const TURN_TIME := 0.3
## 直衝速度（px/s）。
const DASH_SPEED := 150.0

enum State { DRIFT, TURN, DASH }

var state := State.DRIFT
var dash_velocity := Vector2.ZERO

var _t := 0.0
var _base_y := 0.0


func _init() -> void:
	max_hp = 1
	score = 100
	texture_path = "res://assets/sprites/enemy_spore.png"
	hit_size = Vector2(10, 10)


func _ready() -> void:
	super()
	_base_y = global_position.y


func _behave(delta: float) -> void:
	_t += delta
	match state:
		State.DRIFT:
			var p := global_position
			p.x -= DRIFT_SPEED * delta
			p.y = _base_y + BOB_AMPLITUDE * sin(_t * BOB_FREQUENCY)
			global_position = p
			var target := _target()
			if target and absf(target.global_position.x - p.x) < DASH_RANGE:
				state = State.TURN
				_t = 0.0
		State.TURN:
			if _t >= TURN_TIME:
				var target := _target()
				var aim := target.global_position if target else global_position + Vector2.LEFT
				dash_velocity = (aim - global_position).normalized() * DASH_SPEED
				if dash_velocity == Vector2.ZERO:
					dash_velocity = Vector2.LEFT * DASH_SPEED
				state = State.DASH
		State.DASH:
			global_position += dash_velocity * delta


func _target() -> Node2D:
	return Game.world.get_target_player(global_position) if Game.world else null
