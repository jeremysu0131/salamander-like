class_name Boss
extends Node2D
## 第 1 關 Boss「瓣膜母體」（GDD 第 7 章）。
##
## 節點的位置就是核心（插座）中心，畫面座標。本體貼在畫面右緣、垂直置中於 Game.PLAYFIELD。
##
## 流程：
##   ENTER       從右邊滑入（ENTER_TIME 秒，無敵、瓣膜閉合）。時間上限從滑入結束開始算。
##   FIGHT       開合循環。phase 1：張開 2 秒、閉合 2 秒；phase 2：張開 2 秒、閉合 1 秒。
##               張開時：核心可以打，從核心發射扇形彈（5 向／7 向，每秒 1 輪）。
##               閉合時：phase 1 核心完全打不到，上下兩個孔各吐 2 隻孢子；
##                       phase 2 只剩一條水平縫隙（核心中心 ±GAP_HALF px）打得到。
##               phase 2 另外每 STRIKE_INTERVAL 秒從上下緣各伸出 1 條觸手，瞄準玩家當下的 x。
##   TRANSITION  HP 降到 120：前瓣膜碎裂，1.5 秒演出，核心無敵。超過的傷害不帶到第二階段。
##   RETREAT     超過時間上限（180 秒）：縮回肉壁（往右滑出），發出 finished(false)，沒有分數。
##   DYING       擊破：10000 分給擊破者、清掉畫面上的敵彈、核心連續爆炸 2 秒、
##               全畫面白閃一次（全遊戲唯一一次，GDD 9.3）、肉壁停止脈動並褪色，然後 finished(true)。
##
## 瓣膜（boss_valve.png 三幀：上、前、下）：
##   閉合時三幀的中心都疊在核心中心，拼成一個蓋住核心的圓盤；張開時各自沿自己的方向往外移。
##   第二階段碎掉的是「前」瓣膜，剩下的上、下兩片水平翻轉，改成朝左上、左下，
##   像上下顎一樣從正面夾住核心，中間留一條水平縫隙正對玩家。
##   選前瓣膜的理由：玩家的子彈都是水平往右飛，縫隙必須是一條正對左方的水平細縫，
##   「要對準某個 y 才打得到」才看得出來；上下顎夾出的縫正好落在核心中心那一條水平線上。
##   如果留下前瓣膜、碎掉上或下的，缺口會朝右上或右下，水平子彈永遠打不到。
##
## 碰撞：
##   核心與縫隙判定帶是 enemy 層的 BossPart，只在可以打的時候 monitorable。
##   本體與瓣膜是 hazard 層，碰到就死。
##   另外有 enemy 層、不會扣血的「外殼」BossPart（閉合的瓣膜、核心上下與後方的肉），
##   讓子彈打在 Boss 身上會消失，而不是穿過去；外殼的範圍避開張開時的核心正前方，
##   以免高 40 px 的環波先被外殼吃掉。
##
## 開發用參數（放在 `--` 之後）：--boss-hp=<n> 以指定 HP 開場，n ≤ 120 時直接從第二階段開始。

## 結束：defeated 為 true 表示被擊破，false 表示超時撤退。
signal finished(defeated: bool)

enum State { ENTER, FIGHT, TRANSITION, RETREAT, DYING, DONE }

const LAYER_HAZARD := 1 << 7

const MAX_HP := 240
const PHASE2_HP := 120
const TIME_LIMIT := 180.0
const SCORE := 10000

const BODY_TEXTURE := preload("res://assets/sprites/boss_body.png")
const CORE_TEXTURE := preload("res://assets/sprites/boss_core.png")
const VALVE_TEXTURE := preload("res://assets/sprites/boss_valve.png")
const SPORE_SCENE := preload("res://scenes/enemies/spore.tscn")
const TENTACLE_SCENE := preload("res://scenes/terrain/tentacle.tscn")
const FLASH_SHADER := preload("res://assets/shaders/flash.gdshader")

## 本體圖 96×120 中，核心插座中心的像素位置。
const BODY_SOCKET := Vector2(30, 60)
const BODY_SIZE := Vector2(96, 120)
## 孢子孔（相對於核心中心）。
const HOLES: Array[Vector2] = [Vector2(14, -38), Vector2(14, 38)]
## 核心中心的最終畫面位置：本體貼右緣，垂直置中於可活動範圍。
const HOME := Vector2(384.0 - 96.0 + 30.0, 114.0)

const ENTER_TIME := 1.5
const ENTER_DIST := 110.0
const RETREAT_TIME := 2.0
const RETREAT_DIST := 120.0

## 開合週期（秒）：[phase 1, phase 2]。
const OPEN_TIME: Array[float] = [2.0, 2.0]
const CLOSED_TIME: Array[float] = [2.0, 1.0]
## 瓣膜張開／閉合的動畫時間。判定在狀態切換的瞬間就改變，動畫只是視覺。
const VALVE_MOVE_TIME := 0.15
## 張開時瓣膜往外移的距離（px）。
const VALVE_OPEN_DIST := 9.0
## 第二階段上下顎張開的距離。
const JAW_OPEN_DIST := 10.0

## 核心判定（GDD 7：16×16）。
const CORE_SIZE := Vector2(16, 16)
## 第二階段縫隙：核心中心上下各 GAP_HALF px（縫寬 4 px）。
const GAP_HALF := 2.0

## 扇形彈：張開後 FAN_DELAY 秒開第一輪，之後每 FAN_INTERVAL 秒一輪（除以 Game.difficulty）。
## 中心那一發瞄準玩家（限制在正左方 ±FAN_AIM_LIMIT 之內），相鄰兩發夾 FAN_STEP。
const FAN_COUNT: Array[int] = [5, 7]
const FAN_DELAY := 0.3
const FAN_INTERVAL := 1.0
const FAN_STEP := deg_to_rad(15.0)
const FAN_AIM_LIMIT := deg_to_rad(40.0)
const FAN_SPEED := 90.0
## 發射點：核心正前方。
const MUZZLE := Vector2(-8, 0)

## 第一階段閉合時，每個孔吐 SPORES_PER_HOLE 隻孢子，閉合後 SPORE_DELAY 秒開始，間隔 SPORE_INTERVAL。
const SPORES_PER_HOLE := 2
const SPORE_DELAY := 0.3
const SPORE_INTERVAL := 0.8

## 第二階段觸手：進入第二階段後 STRIKE_FIRST 秒第一次，之後每 STRIKE_INTERVAL 秒。
const STRIKE_FIRST := 3.0
const STRIKE_INTERVAL := 6.0
## 上下兩條觸手在通道中央重疊的長度，讓站在正中間也躲不掉，一定要橫移。
const STRIKE_OVERLAP := 6.0
## 觸手瞄準的 x 範圍（不從 Boss 身上長出來）。
const STRIKE_MIN_X := 16.0
const STRIKE_BODY_MARGIN := 20.0

const TRANSITION_TIME := 1.5
## 演出中瓣膜先閉合，這個時間點換成上下顎的配置。
const TRANSITION_SWAP := 0.45
## 演出開頭前瓣膜碎裂的連續爆炸。
const SHATTER_TIME := 0.4
const SHATTER_INTERVAL := 0.1

const DEFEAT_SHOW := 2.0
const DEFEAT_FLASH := 0.4
const DEFEAT_EXPLOSION_INTERVAL := 0.06
const DEFEAT_BIG_INTERVAL := 0.4

const FLASH_FRAMES := 2

var hp: int = MAX_HP
var phase: int = 1
var state: State = State.ENTER
## 戰鬥開始（滑入結束）後經過的時間，到 TIME_LIMIT 就撤退。
var elapsed := 0.0
var valves_open := false
## 開合循環內的時間（秒）。
var cycle_time := 0.0
## 觸手：[0] 從上緣、[1] 從下緣。被打掉時為 null，下次出擊前重新生成。
var tentacles: Array[Tentacle] = [null, null]
## 下次觸手出擊的倒數。
var strike_timer := 0.0
## 最近一次觸手出擊瞄準的 x（測試用）。
var last_strike_x := NAN

var _t := 0.0
var _fan_timer := 0.0
var _spores_left := 0
var _spore_timer := 0.0
var _valve_amount := 0.0
## 瓣膜是否已換成第二階段的上下顎配置（轉換演出中途才換）。
var _jaws := false
var _flash := 0
var _anim_t := 0.0
var _explosion_timer := 0.0
var _big_timer := 0.0
var _rng := RandomNumberGenerator.new()

var _body: Sprite2D
var _core: Sprite2D
var _core_material: ShaderMaterial
## [上, 前, 下]
var _valves: Array[Sprite2D] = []
var _valve_hazards: Array[Area2D] = []
var _core_part: BossPart
var _gap_part: BossPart
## 外殼：閉合時整個圓盤（phase 1）／上下顎各一塊、中間留縫（phase 2）／身體。
var _shutter_full: BossPart
var _shutter_split: BossPart
var _armor: BossPart
var _body_hazard: Area2D
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect


func _ready() -> void:
	_rng.seed = 7
	global_position = HOME + Vector2(ENTER_DIST, 0)
	_build()
	_apply_debug_hp()
	_update_valves(0.0)
	_update_parts()


func _physics_process(delta: float) -> void:
	step(delta)


## 每個物理幀的邏輯。測試可以停掉 physics_process 直接呼叫它快轉。
func step(delta: float) -> void:
	_t += delta
	match state:
		State.ENTER:
			var k := minf(_t / ENTER_TIME, 1.0)
			global_position = HOME + Vector2(ENTER_DIST * (1.0 - _ease_out(k)), 0)
			if _t >= ENTER_TIME:
				_start_fight()
		State.FIGHT:
			elapsed += delta
			if elapsed >= TIME_LIMIT:
				_start_retreat()
			else:
				_update_cycle(delta)
				if phase == 2:
					_update_strikes(delta)
		State.TRANSITION:
			elapsed += delta
			if elapsed >= TIME_LIMIT:
				_start_retreat()
			else:
				_update_transition(delta)
		State.RETREAT:
			var k := minf(_t / RETREAT_TIME, 1.0)
			global_position = HOME + Vector2(RETREAT_DIST * _ease_in(k), 0)
			if _t >= RETREAT_TIME:
				state = State.DONE
				visible = false
				finished.emit(false)
		State.DYING:
			_update_defeat(delta)
	_animate(delta)
	_update_valves(delta)
	_update_parts()


## 剩餘時間（秒）。
func time_left() -> float:
	return maxf(TIME_LIMIT - elapsed, 0.0)


## 核心目前能不能被打（張開中）。
func is_core_vulnerable() -> bool:
	return state == State.FIGHT and valves_open


## 第二階段閉合時的縫隙目前能不能被打。
func is_gap_vulnerable() -> bool:
	return state == State.FIGHT and phase == 2 and not valves_open


func open_time() -> float:
	return OPEN_TIME[phase - 1]


func closed_time() -> float:
	return CLOSED_TIME[phase - 1]


# ── 建構 ──────────────────────────────────────────────

func _build() -> void:
	_body = Sprite2D.new()
	_body.texture = BODY_TEXTURE
	_body.centered = false
	_body.position = -BODY_SOCKET
	add_child(_body)

	_core = Sprite2D.new()
	_core.texture = CORE_TEXTURE
	_core.hframes = 2
	_core_material = ShaderMaterial.new()
	_core_material.shader = FLASH_SHADER
	_core.material = _core_material
	add_child(_core)

	for i in 3:
		var v := Sprite2D.new()
		v.texture = VALVE_TEXTURE
		v.hframes = 3
		v.frame = i
		add_child(v)
		_valves.append(v)
		var hz := _make_hazard()
		var shape := CircleShape2D.new()
		shape.radius = 6.0
		var cs := CollisionShape2D.new()
		cs.shape = shape
		hz.add_child(cs)
		v.add_child(hz)
		_valve_hazards.append(hz)
	_place_valve_hazards()

	# 本體：圓鼓的肉塊與右側的肉壁。
	_body_hazard = _make_hazard()
	_add_rect(_body_hazard, Rect2(-14, -46, 60, 92))
	_add_rect(_body_hazard, Rect2(46, -60, 20, 120))
	add_child(_body_hazard)

	_core_part = _make_part([Rect2(-CORE_SIZE / 2.0, CORE_SIZE)])
	_gap_part = _make_part([Rect2(-CORE_SIZE.x / 2.0, -GAP_HALF, CORE_SIZE.x, GAP_HALF * 2.0)])
	_shutter_full = _make_part([Rect2(-12, -12, 24, 24)])
	# 上下顎之間留比縫隙稍寬的空間，讓瞄準縫隙的子彈不會先被外殼吃掉。
	var g := GAP_HALF + 1.0
	_shutter_split = _make_part([Rect2(-12, -12, 24, 12 - g), Rect2(-12, g, 24, 12 - g)])
	# 核心上下（避開環波最大高度 ±20）與後方的肉、右側肉壁。
	_armor = _make_part([Rect2(-14, -46, 60, 24), Rect2(-14, 22, 60, 24),
			Rect2(12, -22, 34, 44), Rect2(46, -60, 20, 120)])

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 100
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.size = Game.SCREEN_SIZE
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.add_child(_flash_rect)
	_flash_layer.visible = false
	add_child(_flash_layer)


func _apply_debug_hp() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boss-hp="):
			hp = clampi(arg.trim_prefix("--boss-hp=").to_int(), 1, MAX_HP)
	if hp <= PHASE2_HP:
		set_phase2()


## 直接進入第二階段的配置（沒有轉換演出）。開發參數與測試用。
func set_phase2() -> void:
	phase = 2
	hp = mini(hp, PHASE2_HP)
	_jaws = true
	_valves[1].visible = false
	_valves[0].flip_h = true
	_valves[2].flip_h = true
	_place_valve_hazards()
	if state == State.FIGHT:
		_restart_cycle()
		strike_timer = STRIKE_FIRST


func _make_hazard() -> Area2D:
	var a := Area2D.new()
	a.collision_layer = LAYER_HAZARD
	a.collision_mask = 0
	a.monitoring = false
	return a


func _make_part(rects: Array[Rect2]) -> BossPart:
	var p := BossPart.new()
	for r in rects:
		p.add_rect(r)
	p.hit.connect(_on_part_hit)
	add_child(p)
	return p


func _add_rect(area: Area2D, rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = rect.get_center()
	area.add_child(cs)


# ── 狀態 ──────────────────────────────────────────────

func _start_fight() -> void:
	state = State.FIGHT
	global_position = HOME
	_t = 0.0
	_restart_cycle()
	if phase == 2:
		strike_timer = STRIKE_FIRST


## 開合循環從「剛張開」開始。
func _restart_cycle() -> void:
	cycle_time = 0.0
	valves_open = true
	_fan_timer = FAN_DELAY
	_spores_left = 0


func _update_cycle(delta: float) -> void:
	var was_open := valves_open
	cycle_time += delta
	var period := open_time() + closed_time()
	if cycle_time >= period:
		cycle_time -= period
	valves_open = cycle_time < open_time()
	if valves_open and not was_open:
		_fan_timer = FAN_DELAY
	elif was_open and not valves_open and phase == 1:
		_spores_left = SPORES_PER_HOLE
		_spore_timer = SPORE_DELAY
	if valves_open:
		_fan_timer -= delta
		if _fan_timer <= 0.0:
			_fan_timer += FAN_INTERVAL / Game.difficulty
			fire_fan()
	elif _spores_left > 0:
		_spore_timer -= delta
		if _spore_timer <= 0.0:
			_spore_timer += SPORE_INTERVAL
			_spores_left -= 1
			spawn_spores()


## 從核心發射一輪扇形彈（phase 1 為 5 向、phase 2 為 7 向）。回傳發射的子彈。
func fire_fan() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if Game.world == null:
		return out
	var from := global_position + MUZZLE
	var center := PI
	var target := Game.world.get_target_player(from)
	if target:
		var d := target.global_position - from
		if d.length_squared() > 1.0:
			# 以正左方為基準，限制在 ±FAN_AIM_LIMIT 之內。
			var off := wrapf(d.angle() - PI, -PI, PI)
			center = PI + clampf(off, -FAN_AIM_LIMIT, FAN_AIM_LIMIT)
	var n: int = FAN_COUNT[phase - 1]
	for i in n:
		var a := center + (i - (n - 1) / 2.0) * FAN_STEP
		var b := Game.world.spawn_enemy_bullet(from, Vector2.from_angle(a) * FAN_SPEED * Game.difficulty)
		if b:
			out.append(b)
	return out


## 上下兩個孔各吐 1 隻孢子。
func spawn_spores() -> void:
	if Game.world == null:
		return
	for h in HOLES:
		var s: Node2D = SPORE_SCENE.instantiate()
		s.position = global_position + h
		Game.world.enemies.add_child(s)


func _update_strikes(delta: float) -> void:
	strike_timer -= delta
	if strike_timer <= 0.0:
		strike_timer += STRIKE_INTERVAL
		strike()


## 上下緣各伸出 1 條觸手，瞄準目標玩家當下的 x。沒有目標時不出擊，回傳 false。
func strike() -> bool:
	if Game.world == null:
		return false
	var target := Game.world.get_target_player(global_position)
	if target == null:
		return false
	var max_x := global_position.x - BODY_SOCKET.x - STRIKE_BODY_MARGIN
	var x := clampf(target.global_position.x, STRIKE_MIN_X, max_x)
	var top := Game.PLAYFIELD.position.y
	var bottom := Game.PLAYFIELD.end.y
	if Game.world.terrain():
		var p := Game.world.terrain().passage_at(x)
		top = maxf(top, p.x)
		bottom = minf(bottom, p.y)
	var length := (bottom - top) / 2.0 + STRIKE_OVERLAP
	for i in 2:
		var t := _tentacle(i)
		t.strike(x, i == 0, length)
	last_strike_x = x
	return true


func _tentacle(i: int) -> Tentacle:
	var t := tentacles[i]
	if t != null and is_instance_valid(t) and not t.is_queued_for_deletion():
		return t
	t = TENTACLE_SCENE.instantiate()
	t.setup({mode = &"strike", ceiling = i == 0})
	# 放在 Boss 底下：Boss 在戰鬥中不會移動，結束時一起清掉。
	add_child(t)
	t.destroyed.connect(_on_tentacle_destroyed.bind(i))
	tentacles[i] = t
	return t


func _on_tentacle_destroyed(_player_id: int, i: int) -> void:
	tentacles[i] = null


func _free_tentacles(explode: bool) -> void:
	for i in tentacles.size():
		var t := tentacles[i]
		if t != null and is_instance_valid(t):
			if explode and Game.world and t.is_striking():
				Game.world.spawn_explosion(t.global_position + t.direction * 6.0)
			t.queue_free()
		tentacles[i] = null


func _on_part_hit(part: BossPart, amount: int, player_id: int) -> void:
	if amount <= 0:
		return
	if (part == _core_part and is_core_vulnerable()) or (part == _gap_part and is_gap_vulnerable()):
		# 判定的開關（monitorable）在下一次 step() 更新：這裡可能是在碰撞訊號裡，不能直接改。
		_damage(amount, player_id)


func _damage(amount: int, player_id: int) -> void:
	hp -= amount
	_flash = FLASH_FRAMES
	_core_material.set_shader_parameter(&"flash", 1.0)
	if phase == 1 and hp <= PHASE2_HP:
		hp = PHASE2_HP
		_start_transition()
	elif phase == 2 and hp <= 0:
		hp = 0
		_start_defeat(player_id)


func _start_transition() -> void:
	state = State.TRANSITION
	phase = 2
	_t = 0.0
	valves_open = false
	_spores_left = 0
	# 前瓣膜碎裂。
	_explode(global_position + Vector2(-10, 0), true)
	_explosion_timer = SHATTER_INTERVAL
	_valves[1].visible = false


func _update_transition(delta: float) -> void:
	if _t < SHATTER_TIME:
		_explosion_timer -= delta
		if _explosion_timer <= 0.0:
			_explosion_timer += SHATTER_INTERVAL
			_explode(global_position + Vector2(_rng.randf_range(-18, -6), _rng.randf_range(-10, 10)), false)
	if not _jaws and _t >= TRANSITION_SWAP:
		# 上下瓣膜翻到正面，變成上下顎（閉合、留縫）。
		_jaws = true
		_valves[0].flip_h = true
		_valves[2].flip_h = true
		_place_valve_hazards()
		_valve_amount = 0.0
	if _t >= TRANSITION_TIME:
		state = State.FIGHT
		_t = 0.0
		_restart_cycle()
		strike_timer = STRIKE_FIRST


func _start_retreat() -> void:
	state = State.RETREAT
	_t = 0.0
	valves_open = false
	_spores_left = 0
	_free_tentacles(false)


func _start_defeat(player_id: int) -> void:
	state = State.DYING
	_t = 0.0
	valves_open = true
	Game.add_score(player_id, SCORE)
	_free_tentacles(true)
	if Game.world:
		for b in Game.world.enemy_bullets.get_children():
			b.queue_free()
		Game.world.spawn_explosion(global_position, true)
	_explosion_timer = DEFEAT_EXPLOSION_INTERVAL
	_big_timer = DEFEAT_BIG_INTERVAL


func _update_defeat(delta: float) -> void:
	if _t < DEFEAT_SHOW:
		_explosion_timer -= delta
		if _explosion_timer <= 0.0:
			_explosion_timer += DEFEAT_EXPLOSION_INTERVAL
			# 爆炸集中在核心附近，偶爾擴散到整個肉塊。
			var spread := Vector2(14, 14) if _rng.randf() < 0.6 else Vector2(36, 44)
			var p := Vector2(_rng.randf_range(-spread.x, spread.x), _rng.randf_range(-spread.y, spread.y))
			if spread.x > 20.0:
				p.x += 14.0
			_explode(global_position + p, false)
		_big_timer -= delta
		if _big_timer <= 0.0:
			_big_timer += DEFEAT_BIG_INTERVAL
			_explode(global_position + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)), true)
		return
	if _core.visible:
		# 最後一爆：核心與瓣膜炸飛、全畫面白閃、肉壁褪色。
		_explode(global_position, true)
		for v in _valves:
			if v.visible:
				_explode(v.global_position, false)
			v.visible = false
		_core.visible = false
		_body.modulate = Color(0.55, 0.5, 0.55)
		_flash_layer.visible = true
	var f := (_t - DEFEAT_SHOW) / DEFEAT_FLASH
	_flash_rect.color.a = clampf(1.0 - f, 0.0, 1.0)
	if f >= 1.0:
		_flash_layer.visible = false
		state = State.DONE
		finished.emit(true)


func _explode(pos: Vector2, big: bool) -> void:
	if Game.world:
		Game.world.spawn_explosion(pos, big)


# ── 外觀與判定 ────────────────────────────────────────

func _animate(delta: float) -> void:
	if _flash > 0:
		_flash -= 1
		if _flash == 0:
			_core_material.set_shader_parameter(&"flash", 0.0)
	if state == State.DONE or (state == State.DYING and not _core.visible):
		return
	_anim_t += delta
	# 核心脈動；第二階段比較急。
	var period := 0.4 if phase == 1 else 0.25
	_core.frame = int(_anim_t / (period / 2.0)) % 2
	# 本體輕微脈動。
	var b := 0.94 + 0.06 * sin(_anim_t * TAU / (period * 2.0))
	_body.modulate = Color(b, b, b)
	# 無敵演出：核心閃爍。
	if state == State.TRANSITION:
		_core.modulate.a = 1.0 if int(_t * 16.0) % 2 == 0 else 0.35
	else:
		_core.modulate.a = 1.0


func _update_valves(delta: float) -> void:
	var target := 1.0 if valves_open else 0.0
	_valve_amount = move_toward(_valve_amount, target, delta / VALVE_MOVE_TIME)
	var k := _ease_out(_valve_amount)
	if not _jaws:
		var dirs: Array[Vector2] = [Vector2(0.5, -0.866), Vector2(-1, 0), Vector2(0.5, 0.866)]
		for i in 3:
			_valves[i].position = (dirs[i] * VALVE_OPEN_DIST * k).round()
	else:
		var closed: Array[Vector2] = [Vector2(0, -GAP_HALF), Vector2.ZERO, Vector2(0, GAP_HALF)]
		var dirs: Array[Vector2] = [Vector2(-0.5, -0.866), Vector2.ZERO, Vector2(-0.5, 0.866)]
		for i: int in [0, 2]:
			_valves[i].position = closed[i].lerp(dirs[i] * JAW_OPEN_DIST, k).round()


## 瓣膜危險判定放在各瓣膜形狀的中心（沿瓣膜方向 6 px）。
func _place_valve_hazards() -> void:
	var sx := -1.0 if _valves[0].flip_h else 1.0
	_valve_hazards[0].position = Vector2(3.0 * sx, -5.2)
	_valve_hazards[1].position = Vector2(-6, 0)
	_valve_hazards[2].position = Vector2(3.0 * sx, 5.2)


func _update_parts() -> void:
	var alive := state != State.DYING and state != State.DONE
	_core_part.monitorable = is_core_vulnerable()
	_gap_part.monitorable = is_gap_vulnerable()
	var closed_look := alive and not valves_open
	_shutter_full.monitorable = closed_look and not _jaws
	_shutter_split.monitorable = closed_look and _jaws
	_armor.monitorable = alive
	_body_hazard.monitorable = alive
	for i in 3:
		_valve_hazards[i].monitorable = alive and _valves[i].visible


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _ease_in(t: float) -> float:
	return t * t
