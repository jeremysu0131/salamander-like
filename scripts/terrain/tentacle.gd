class_name Tentacle
extends Node2D
## 伸縮觸手（GDD 6.2；Boss 第二階段的觸手攻擊也重用它，見 GDD 7.1）。
##
## 結構：這個節點的位置是「根部所在的表面點」，節點旋轉成本地 -Y 指向伸出方向。
##   - 根部節點 TentacleRoot：enemy 層（第 4 層），HP 6、500 分。擊破後整條觸手爆炸消失。
##   - 本體每 8 px 一節，最前端是尖端：hazard 層（第 8 層）的 Area2D，碰到玩家即死，子彈穿過。
##     縮在表面內的節是隱藏且沒有判定的。
##
## ── 模式一：關卡用（CYCLE，生成事件 type = tentacle，attached）──
##   生成參數（setup）：
##     ceiling: bool   true 從天花板往下伸，false 從地面往上伸（預設）
##     length: float   最長伸出長度（px，從表面算起）。省略時為該處通道高度的 60%
##     phase: float    週期偏移（秒，0–3）。相鄰觸手錯開時機用
##     red、drop       傳給根部節點（擊破時掉落）
##   加入場景樹時依 x 貼齊地形表面（Terrain.passage_at），生成事件的 y 會被忽略。
##   週期 3 秒：縮著 → 伸出 → 停在最長 → 縮回（時間見 CYCLE_* 常數），永遠循環。
##   離開畫面左側 32 px 後刪除。
##
## ── 模式二：Boss 用（STRIKE）──
##   平時完全隱藏、沒有判定；呼叫 strike() 才出擊一次，結束後回到隱藏，可以再次呼叫。
##   不需要依附地形，可以放在任何容器（例如 Game.world.enemies 或 Boss 底下），用畫面座標。
##   不會自動刪除，由擁有者負責。
##
##     var t: Tentacle = preload("res://scenes/terrain/tentacle.tscn").instantiate()
##     t.setup({mode = &"strike"})
##     Game.world.enemies.add_child(t)
##     t.strike(target_x, true)        # 從上緣瞄準 target_x 伸出
##     t.strike_finished.connect(...)  # 一次出擊結束（已縮回並隱藏）
##     t.destroyed.connect(...)        # 根部被打掉，節點即將刪除；下次要用就重新生成一條
##
##   strike(at_x, from_ceiling, reach := STRIKE_LENGTH)
##     表面位置：有地形時取 Terrain.passage_at(at_x) 的天花板／地面表面，
##     並限制在 Game.PLAYFIELD 之內（上緣不會躲在 HUD 底下）。
##   strike_from(origin, direction, reach)
##     不看地形，直接指定表面點（畫面座標）、伸出方向與長度。
##   時序：預警 STRIKE_WARN（1 秒，表面隆起並閃爍，沒有判定）→ 伸出 STRIKE_EXTEND
##     → 停留 STRIKE_HOLD → 縮回 STRIKE_RETRACT → 隱藏。伸出到縮回期間根部可以被打。
##   出擊中再次呼叫 strike() 會被忽略並回傳 false。
##
##   configure(origin, direction, reach) 也可在 CYCLE 模式下使用，取代地形貼齊。

## 一次出擊結束（已縮回並隱藏）。
signal strike_finished
## 根部被擊破，整條觸手即將刪除。
signal destroyed(player_id: int)

enum Mode { CYCLE, STRIKE }
enum Strike { IDLE, WARN, EXTEND, HOLD, RETRACT }

const SEGMENT := 8.0
const LAYER_HAZARD := 1 << 7
## 根部節點中心離表面的距離（根部 12×12，整顆露在通道內，子彈打得到）。
const ROOT_OFFSET := 6.0
## 省略 length 時，伸出長度佔通道高度的比例。
const AUTO_LENGTH_RATIO := 0.6
const MIN_LENGTH := 16.0
const OFFSCREEN_LEFT := 32.0

## CYCLE 模式：週期 3 秒，依序為縮著、伸出、停在最長、縮回、縮著。
const CYCLE := 3.0
const CYCLE_REST := 0.8
const CYCLE_EXTEND := 0.6
const CYCLE_HOLD := 0.6
const CYCLE_RETRACT := 0.6

## STRIKE 模式的時序（秒）與預設長度（px）。
const STRIKE_WARN := 1.0
const STRIKE_EXTEND := 0.35
const STRIKE_HOLD := 0.4
const STRIKE_RETRACT := 0.5
const STRIKE_LENGTH := 88.0

var mode := Mode.CYCLE
var ceiling := false
## 最長伸出長度（px）。0 表示依通道高度自動決定。
var reach := 0.0
var phase := 0.0
## 伸出方向（單位向量，畫面座標）。
var direction := Vector2.UP
## 目前伸出的長度（px，從表面算起）。
var extension := 0.0
var strike_state := Strike.IDLE

var root: TentacleRoot
var segments: Array[Area2D] = []

var _root_params := {}
var _configured := false
var _origin := Vector2.ZERO
var _time := 0.0
var _strike_t := 0.0


func setup(params: Dictionary) -> void:
	ceiling = params.get("ceiling", false)
	reach = params.get("length", 0.0)
	phase = params.get("phase", 0.0)
	if StringName(params.get("mode", "cycle")) == &"strike":
		mode = Mode.STRIKE
	_root_params = {red = params.get("red", false), drop = params.get("drop", "")}


## 不貼齊地形，直接指定表面點（畫面座標）、伸出方向與最長長度。可在加入場景樹前後呼叫。
func configure(origin: Vector2, dir: Vector2, length: float) -> void:
	_configured = true
	_origin = origin
	direction = dir.normalized()
	reach = maxf(length, MIN_LENGTH)
	if is_inside_tree():
		_apply_placement()


func _ready() -> void:
	root = TentacleRoot.new()
	root.setup(_root_params)
	if not _configured:
		_snap_to_terrain()
	_apply_placement()
	root.position = Vector2(0, -ROOT_OFFSET)
	root.killed.connect(_on_root_killed)
	add_child(root)
	_apply_extension(0.0)


func _snap_to_terrain() -> void:
	var x := global_position.x
	var passage := Vector2(Game.PLAYFIELD.position.y, Game.PLAYFIELD.end.y)
	if Game.world and Game.world.terrain():
		passage = Game.world.terrain().passage_at(x)
	_origin = Vector2(x, passage.x if ceiling else passage.y)
	direction = Vector2.DOWN if ceiling else Vector2.UP
	if reach <= 0.0:
		reach = (passage.y - passage.x) * AUTO_LENGTH_RATIO
	reach = maxf(reach, MIN_LENGTH)


## 依 _origin、direction、reach 擺放節點並（重新）建立足夠的節。
func _apply_placement() -> void:
	global_position = _origin
	rotation = direction.angle() + PI / 2.0
	var need := ceili(reach / SEGMENT)
	while segments.size() < need:
		segments.append(_make_segment())
	_apply_extension(extension)


func _make_segment() -> Area2D:
	var a := Area2D.new()
	a.collision_layer = LAYER_HAZARD
	a.collision_mask = 0
	a.monitoring = false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(6, 6)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	a.add_child(cs)
	var s := Sprite2D.new()
	s.texture = preload("res://assets/sprites/tentacle.png")
	s.hframes = 2
	a.add_child(s)
	add_child(a)
	if root and root.get_parent() == self:
		move_child(root, -1)  # 根部畫在最上層
	return a


func _physics_process(delta: float) -> void:
	if mode == Mode.CYCLE:
		_time += delta
		_apply_extension(cycle_extension(fposmod(_time + phase, CYCLE)))
		if global_position.x < -OFFSCREEN_LEFT:
			queue_free()
	else:
		_update_strike(delta)


## CYCLE 模式下，週期內時間 t（0–3 秒）對應的伸出長度。
func cycle_extension(t: float) -> float:
	var a := CYCLE_REST
	if t < a:
		return 0.0
	if t < a + CYCLE_EXTEND:
		return reach * _ease_out((t - a) / CYCLE_EXTEND)
	a += CYCLE_EXTEND
	if t < a + CYCLE_HOLD:
		return reach
	a += CYCLE_HOLD
	if t < a + CYCLE_RETRACT:
		return reach * (1.0 - _ease_in((t - a) / CYCLE_RETRACT))
	return 0.0


## 從上緣（from_ceiling）或下緣朝 at_x 出擊一次。出擊中呼叫會被忽略並回傳 false。
func strike(at_x: float, from_ceiling: bool, length := STRIKE_LENGTH) -> bool:
	var top := Game.PLAYFIELD.position.y
	var bottom := Game.PLAYFIELD.end.y
	if Game.world and Game.world.terrain():
		var passage := Game.world.terrain().passage_at(at_x)
		top = maxf(top, passage.x)
		bottom = minf(bottom, passage.y)
	var origin := Vector2(at_x, top if from_ceiling else bottom)
	return strike_from(origin, Vector2.DOWN if from_ceiling else Vector2.UP, length)


## 不看地形，從表面點 origin（畫面座標）往 dir 出擊一次。
func strike_from(origin: Vector2, dir: Vector2, length := STRIKE_LENGTH) -> bool:
	if strike_state != Strike.IDLE:
		return false
	mode = Mode.STRIKE
	ceiling = dir.y > 0.0
	configure(origin, dir, length)
	strike_state = Strike.WARN
	_strike_t = 0.0
	_apply_extension(0.0)
	return true


func is_striking() -> bool:
	return strike_state != Strike.IDLE


func _update_strike(delta: float) -> void:
	if strike_state == Strike.IDLE:
		_apply_extension(0.0)
		return
	_strike_t += delta
	match strike_state:
		Strike.WARN:
			_apply_extension(0.0)
			if _strike_t >= STRIKE_WARN:
				_next_strike_state(Strike.EXTEND, STRIKE_WARN)
		Strike.EXTEND:
			_apply_extension(reach * _ease_out(minf(_strike_t / STRIKE_EXTEND, 1.0)))
			if _strike_t >= STRIKE_EXTEND:
				_next_strike_state(Strike.HOLD, STRIKE_EXTEND)
				_apply_extension(reach)
		Strike.HOLD:
			_apply_extension(reach)
			if _strike_t >= STRIKE_HOLD:
				_next_strike_state(Strike.RETRACT, STRIKE_HOLD)
		Strike.RETRACT:
			_apply_extension(reach * (1.0 - _ease_in(minf(_strike_t / STRIKE_RETRACT, 1.0))))
			if _strike_t >= STRIKE_RETRACT:
				strike_state = Strike.IDLE
				_apply_extension(0.0)
				strike_finished.emit()


func _next_strike_state(s: Strike, duration: float) -> void:
	strike_state = s
	_strike_t -= duration


## 依伸出長度 e 擺放各節，並更新根部的顯示與判定。
func _apply_extension(e: float) -> void:
	extension = clampf(e, 0.0, reach)
	var n := segments.size()
	for k in n:
		var seg := segments[k]
		# 第 k 節（0 = 尖端）的中心離表面的距離。
		var d := extension - SEGMENT / 2.0 - SEGMENT * k
		var shown := d >= SEGMENT / 2.0 - 0.001
		seg.visible = shown
		seg.monitorable = shown
		seg.position = Vector2(0, -d)
		var s: Sprite2D = seg.get_child(1)
		s.frame = 1 if k == 0 else 0
	if root == null:
		return
	var hidden := mode == Mode.STRIKE and strike_state == Strike.IDLE
	var warning := mode == Mode.STRIKE and strike_state == Strike.WARN
	root.visible = not hidden
	root.monitorable = not hidden and not warning
	if root.sprite:
		if warning:
			# 預警：表面隆起並閃爍。
			var k := _strike_t / STRIKE_WARN
			root.sprite.scale = Vector2.ONE * lerpf(0.4, 1.0, k)
			root.sprite.modulate.a = 1.0 if int(_strike_t * 12.0) % 2 == 0 else 0.4
		else:
			root.sprite.scale = Vector2.ONE
			root.sprite.modulate.a = 1.0


func _on_root_killed(_enemy: Enemy, player_id: int) -> void:
	if Game.world:
		Game.world.spawn_explosion(global_position + direction * ROOT_OFFSET, true)
		for seg in segments:
			if seg.visible:
				Game.world.spawn_explosion(seg.global_position)
	destroyed.emit(player_id)
	queue_free()


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


static func _ease_in(t: float) -> float:
	return t * t
