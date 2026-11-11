class_name Enemy
extends Area2D
## 可被打的敵人的共用基底（GDD 5.1、9.3）：HP、受擊白閃、擊破加分與掉落、離開畫面回收。
##
## 子類別在 _init() 設定 max_hp、score、texture_path、hit_size 等欄位，
## 行為寫在 _behave(delta)（每個物理幀由基底呼叫）。
##
## 精靈圖為 2 欄 × 2 列：第 1 列一般、第 2 列紅色變體；第 1、2 欄為動畫幀。
## 碰到玩家的判定由玩家的判定框（mask 第 4 層）發起，這裡不處理。

## 被擊破時發出（在加分、爆炸、掉落之後，queue_free 之前）。編隊與觸手用它追蹤擊破。
signal killed(enemy: Enemy, player_id: int)

const FLASH_SHADER := preload("res://assets/shaders/flash.gdshader")
const LAYER_ENEMY := 1 << 3
## 受擊白閃持續的物理幀數。
const FLASH_FRAMES := 2
## 離開畫面多遠後回收：左側 32 px（GDD 5.1），上下與右側給寬一點。
const OFFSCREEN_LEFT := 32.0
const OFFSCREEN_OTHER := 64.0
## 待機動畫每幾個物理幀換一幀。
const ANIM_FRAMES := 8

var max_hp := 1
var hp := 1
var score := 100
var texture_path := ""
var hframes := 2
var vframes := 2
## 判定框大小（像素）。
var hit_size := Vector2(12, 12)
## 是否自動播放 2 幀待機動畫。壁砲自己控制幀所以關掉。
var animate := true
## 離開畫面時是否自動回收。由其他節點管理生命週期的部位（觸手根部）設為 false。
var auto_free := true

## 生成參數（GDD 5.2）：紅色變體與掉落道具。
var red := false
var drop: StringName = &""

var sprite: Sprite2D
var dead := false

var _flash := 0
var _anim_tick := 0
var _anim_col := 0
var _material: ShaderMaterial


## 生成事件的參數，在加入場景樹前呼叫。通用參數：red、drop。
func setup(params: Dictionary) -> void:
	red = params.get("red", false)
	drop = StringName(params.get("drop", ""))


func _ready() -> void:
	hp = max_hp
	collision_layer = LAYER_ENEMY
	collision_mask = 0
	monitoring = false
	var shape := RectangleShape2D.new()
	shape.size = hit_size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	sprite = Sprite2D.new()
	if texture_path != "":
		sprite.texture = load(texture_path)
	sprite.hframes = hframes
	sprite.vframes = vframes
	_material = ShaderMaterial.new()
	_material.shader = FLASH_SHADER
	sprite.material = _material
	add_child(sprite)
	set_anim_col(0)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_behave(delta)
	if dead or not is_inside_tree():
		return
	if animate:
		_anim_tick += 1
		if _anim_tick >= ANIM_FRAMES:
			_anim_tick = 0
			set_anim_col(1 - _anim_col)
	if _flash > 0:
		_flash -= 1
		if _flash == 0:
			_material.set_shader_parameter(&"flash", 0.0)
	if auto_free and is_offscreen():
		queue_free()


## 子類別的行為，每個物理幀呼叫一次。
func _behave(_delta: float) -> void:
	pass


## 受到玩家攻擊。HP 歸零時擊破，分數記給 player_id。
func take_damage(amount: int, player_id: int) -> void:
	if dead or amount <= 0:
		return
	hp -= amount
	_flash = FLASH_FRAMES
	_material.set_shader_parameter(&"flash", 1.0)
	if hp <= 0:
		die(player_id)


## 擊破：加分、爆炸、掉落道具，然後刪除。
func die(player_id: int) -> void:
	if dead:
		return
	dead = true
	Game.add_score(player_id, score)
	if Game.world:
		Game.world.spawn_explosion(global_position)
		if drop != &"":
			Game.world.spawn_pickup(drop, global_position)
	killed.emit(self, player_id)
	queue_free()


## 設定動畫欄（0 或 1），列由紅色變體決定。
func set_anim_col(col: int) -> void:
	_anim_col = col
	if sprite:
		sprite.frame_coords = Vector2i(mini(col, hframes - 1), 1 if red and vframes > 1 else 0)


func is_offscreen() -> bool:
	var p := global_position
	return p.x < -OFFSCREEN_LEFT or p.x > Game.SCREEN_SIZE.x + OFFSCREEN_OTHER \
			or p.y < -OFFSCREEN_OTHER or p.y > Game.SCREEN_SIZE.y + OFFSCREEN_OTHER


## 朝最近的玩家發射 1 發瞄準彈。沒有目標時不發射，回傳 false。
func fire_aimed(from: Vector2) -> bool:
	if Game.world == null:
		return false
	var target := Game.world.get_target_player(from)
	if target == null:
		return false
	Game.world.spawn_enemy_bullet(from, Game.world.aimed_velocity(from, target.global_position))
	return true
