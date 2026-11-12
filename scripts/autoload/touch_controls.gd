extends CanvasLayer
## 觸控操作（手機）：左半邊虛擬搖桿移動、右半邊按住射擊、右上角暫停。
##
## 觸控會被轉成既有的輸入動作（p1_up 等、p1_shoot、pause）送進引擎，
## 所以機體、標題、結果畫面都不需要知道觸控的存在。
##
## 顯示時機：手機瀏覽器（web_android、web_ios）與原生手機一開始就顯示；
## 其他裝置在第一次觸控時顯示，按鍵盤或手把時隱藏。
## 不在遊戲中（標題、結果畫面）時不畫按鈕，點一下螢幕等於按射擊鍵。

signal active_changed(active: bool)

## 搖桿底座半徑與搖桿頭半徑（像素，384×216 座標）。
const STICK_RADIUS := 20.0
const KNOB_RADIUS := 8.0
## 拖曳距離小於這個值不算移動。
const DEADZONE := 5.0
## 沒有按著時，搖桿提示畫在這裡。
const STICK_HOME := Vector2(48, 168)
const SHOOT_CENTER := Vector2(336, 168)
const SHOOT_RADIUS := 22.0
## 暫停按鈕（在 HUD 下方的右上角）。判定範圍比畫出來的大一點，手指比較好按。
const PAUSE_RECT := Rect2(362, 15, 18, 14)
const PAUSE_HIT_MARGIN := 6.0
## 畫面左右分界：左邊是搖桿，右邊是射擊。
const SPLIT_X := 192.0
const ALPHA := 0.35
const ALPHA_PRESSED := 0.6
const MOVE_ACTIONS: Array[StringName] = [&"p1_left", &"p1_right", &"p1_up", &"p1_down"]

var active := false

var _stick_index := -1
var _stick_origin := STICK_HOME
var _stick_pos := STICK_HOME
var _shoot_index := -1
var _tap_index := -1
var _held := {}
var _drawer: Node2D
var _rotate_hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_drawer = Node2D.new()
	_drawer.draw.connect(_draw_controls)
	add_child(_drawer)
	_rotate_hint = _make_rotate_hint()
	add_child(_rotate_hint)
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile") \
			or Debug.touch:
		set_active(true)


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active:
		release_all()
	_drawer.queue_redraw()
	active_changed.emit(active)


## 放開所有由觸控按下的動作。
func release_all() -> void:
	_stick_index = -1
	_shoot_index = -1
	_tap_index = -1
	for action: StringName in _held.keys():
		_set_action(action, false)


func _process(_delta: float) -> void:
	var size := DisplayServer.window_get_size()
	_rotate_hint.visible = active and size.y > size.x
	_drawer.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		set_active(true)
		_on_touch(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _stick_index:
			_stick_pos = drag.position
			_update_stick()
	elif active and (event is InputEventKey or event is InputEventJoypadButton):
		# 改用鍵盤或手把：收起觸控按鈕。
		if event.is_pressed():
			set_active(false)


func _on_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if index == _stick_index:
			_stick_index = -1
			for a in MOVE_ACTIONS:
				_set_action(a, false)
		if index == _shoot_index:
			_shoot_index = -1
			_set_action(&"p1_shoot", false)
		if index == _tap_index:
			_tap_index = -1
			_set_action(&"p1_shoot", false)
		return
	if _in_game() and PAUSE_RECT.grow(PAUSE_HIT_MARGIN).has_point(pos):
		_set_action(&"pause", true)
		_set_action(&"pause", false)
		return
	if get_tree().paused:
		return
	if not _in_game():
		# 標題與結果畫面：點一下等於按射擊鍵。
		_tap_index = index
		_set_action(&"p1_shoot", true)
		return
	if pos.x < SPLIT_X:
		if _stick_index < 0:
			_stick_index = index
			_stick_origin = pos
			_stick_pos = pos
			_update_stick()
	elif _shoot_index < 0:
		_shoot_index = index
		_set_action(&"p1_shoot", true)


## 依搖桿位移決定 8 方向。拖超過底座半徑時底座跟著手指走，反方向拖動時反應比較快。
func _update_stick() -> void:
	var v := _stick_pos - _stick_origin
	if v.length() > STICK_RADIUS:
		_stick_origin = _stick_pos - v.normalized() * STICK_RADIUS
		v = _stick_pos - _stick_origin
	var dir := stick_direction(v)
	_set_action(&"p1_left", dir.x < 0)
	_set_action(&"p1_right", dir.x > 0)
	_set_action(&"p1_up", dir.y < 0)
	_set_action(&"p1_down", dir.y > 0)


## 搖桿位移轉成 8 方向（每個分量為 -1、0 或 1）。
static func stick_direction(v: Vector2) -> Vector2i:
	if v.length() < DEADZONE:
		return Vector2i.ZERO
	var sector := posmod(roundi(v.angle() / (PI / 4.0)), 8)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	]
	return dirs[sector]


func _set_action(action: StringName, pressed: bool) -> void:
	if _held.get(action, false) == pressed:
		return
	if pressed:
		_held[action] = true
	else:
		_held.erase(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _in_game() -> bool:
	return Game.world != null and not Game.world.is_over


func _draw_controls() -> void:
	if not active or not _in_game():
		return
	var white := Color(1, 1, 1)
	# 搖桿
	var held := _stick_index >= 0
	var origin := _stick_origin if held else STICK_HOME
	var knob := origin + (_stick_pos - _stick_origin) if held else STICK_HOME
	var a := ALPHA_PRESSED if held else ALPHA
	_drawer.draw_circle(origin, STICK_RADIUS, Color(0, 0, 0, a * 0.5), true, -1.0, false)
	_drawer.draw_arc(origin, STICK_RADIUS, 0, TAU, 32, Color(white, a), 1.0, false)
	_drawer.draw_circle(knob, KNOB_RADIUS, Color(white, a), true, -1.0, false)
	# 射擊鈕
	a = ALPHA_PRESSED if _shoot_index >= 0 else ALPHA
	_drawer.draw_circle(SHOOT_CENTER, SHOOT_RADIUS, Color(0.17, 0.91, 0.96, a * 0.6), true, -1.0, false)
	_drawer.draw_arc(SHOOT_CENTER, SHOOT_RADIUS, 0, TAU, 32, Color(white, a), 1.0, false)
	# 射擊鈕中央畫一個朝右的小三角，提示「發射」。
	var c := SHOOT_CENTER
	_drawer.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-5, -7), c + Vector2(8, 0), c + Vector2(-5, 7)]), Color(white, a + 0.2))
	# 暫停鈕
	var r := PAUSE_RECT
	_drawer.draw_rect(r, Color(0, 0, 0, 0.5))
	_drawer.draw_rect(r, Color(white, 0.6), false, 1.0)
	_drawer.draw_rect(Rect2(r.position + Vector2(6, 3), Vector2(2, r.size.y - 6)), Color(white, 0.8))
	_drawer.draw_rect(Rect2(r.position + Vector2(r.size.x - 8, 3), Vector2(2, r.size.y - 6)), Color(white, 0.8))


func _make_rotate_hint() -> Label:
	var l := Label.new()
	l.theme = preload("res://assets/ui/theme.tres")
	l.text = "ROTATE YOUR DEVICE\nTO LANDSCAPE"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Game.SCREEN_SIZE
	l.add_theme_color_override(&"font_color", Color.WHITE)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.08, 0.15, 0.92)
	l.add_theme_stylebox_override(&"normal", bg)
	l.visible = false
	return l
