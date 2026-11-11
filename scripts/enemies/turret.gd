class_name Turret
extends Enemy
## 壁砲（GDD 5.3）：16×16，HP 2，200 分。固定在天花板或地面，每 2 秒朝玩家發射 1 發瞄準彈。
##
## 生成參數（setup）：red、drop，以及
##   ceiling: bool   true 裝在天花板（圖垂直翻轉），false 裝在地面（預設）
##
## 是 Stage.world 的子節點（attached），用世界座標擺放。加入場景樹時依 x 把 y 貼齊
## 該欄的地形表面（Terrain.passage_at），所以生成事件的 y 會被忽略。
## 只有在畫面內才會開火；射擊間隔除以 Game.difficulty。

## 射擊間隔（秒），實際值除以 Game.difficulty。
const FIRE_INTERVAL := 2.0
## 開火幀（第 2 幀）顯示多久。
const FIRE_FRAME_TIME := 0.15
## 砲口離中心多遠（往通道方向）。
const MUZZLE := 6.0

var ceiling := false

var _fire_timer := 0.0
var _fire_frame := 0.0


func _init() -> void:
	max_hp = 2
	score = 200
	texture_path = "res://assets/sprites/enemy_turret.png"
	hit_size = Vector2(14, 14)
	animate = false


func setup(params: Dictionary) -> void:
	super(params)
	ceiling = params.get("ceiling", false)


func _ready() -> void:
	super()
	sprite.flip_v = ceiling
	snap_to_terrain()


## 把 y 貼齊這一欄的地形表面：圖的底邊（天花板時為頂邊）貼著表面。
func snap_to_terrain() -> void:
	if Game.world == null or Game.world.terrain() == null:
		return
	var passage := Game.world.terrain().passage_at(global_position.x)
	var half := 8.0
	if ceiling:
		global_position.y = passage.x + half
	else:
		global_position.y = passage.y - half


## 下一次開火前的間隔（秒）。
func fire_interval() -> float:
	return FIRE_INTERVAL / Game.difficulty


func _behave(delta: float) -> void:
	if _fire_frame > 0.0:
		_fire_frame -= delta
		if _fire_frame <= 0.0:
			set_anim_col(0)
	var x := global_position.x
	if x < 0.0 or x > Game.SCREEN_SIZE.x:
		return
	_fire_timer += delta
	if _fire_timer >= fire_interval():
		_fire_timer = 0.0
		var muzzle := global_position + Vector2(0, MUZZLE if ceiling else -MUZZLE)
		if fire_aimed(muzzle):
			set_anim_col(1)
			_fire_frame = FIRE_FRAME_TIME
