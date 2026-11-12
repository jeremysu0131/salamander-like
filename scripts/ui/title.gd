extends Control
## 標題畫面（GDD 9.2）：Logo、閃爍的「PRESS SHOOT TO START」、最高分、操作說明。
##
## 按射擊鍵（p1_shoot，也接受 ui_accept）發出 start_requested，由 Main 切換到遊戲。

signal start_requested

const UiStyle := preload("res://scripts/ui/ui_style.gd")
const LOGO := preload("res://assets/sprites/logo.png")
const BACKGROUND := preload("res://assets/sprites/bg_rock.png")

## 「PRESS SHOOT TO START」閃爍週期（秒）與其中顯示的比例。
const BLINK_PERIOD := 1.0
const BLINK_ON := 0.65
const CONTROLS := "ARROWS/WASD MOVE  Z/J SHOOT  ESC PAUSE  F11 FULLSCREEN"
const PROMPT := "PRESS SHOOT TO START"
## 觸控模式（TouchControls.active）時改顯示的文字。
const CONTROLS_TOUCH := "HOLD LEFT SIDE: MOVE    HOLD RIGHT SIDE: SHOOT"
const PROMPT_TOUCH := "TAP TO START"

var _prompt: Label
var _controls: Label
var _time := 0.0
var _started := false


func _ready() -> void:
	theme = UiStyle.THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var w := int(Game.SCREEN_SIZE.x)
	var cx := w / 2

	# 背景：岩石區背景壓暗，讓文字清楚。
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.modulate = Color(0.5, 0.5, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.position = Vector2(cx - LOGO.get_width() / 2, 40)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	_prompt = UiStyle.make_centered_label(self, PROMPT, cx, 116, UiStyle.WHITE)

	var hi := "HI " + UiStyle.format_score(Game.hiscore)
	var hi_x := cx - UiStyle.text_width(hi) / 2
	UiStyle.make_label(self, "HI", hi_x, 140, UiStyle.RED)
	UiStyle.make_label(self, UiStyle.format_score(Game.hiscore), hi_x + 3 * UiStyle.GLYPH_W, 140, UiStyle.CREAM)

	_controls = UiStyle.make_centered_label(self, CONTROLS, cx, 196, UiStyle.GREY)
	TouchControls.active_changed.connect(_apply_touch_mode)
	_apply_touch_mode(TouchControls.active)


func _apply_touch_mode(touch: bool) -> void:
	var cx := int(Game.SCREEN_SIZE.x) / 2
	_set_centered(_prompt, PROMPT_TOUCH if touch else PROMPT, cx)
	_set_centered(_controls, CONTROLS_TOUCH if touch else CONTROLS, cx)


func _set_centered(label: Label, text: String, cx: int) -> void:
	label.text = text
	label.position.x = cx - UiStyle.text_width(text) / 2


func _process(delta: float) -> void:
	_time += delta
	_prompt.visible = fmod(_time, BLINK_PERIOD) < BLINK_ON


func _unhandled_input(event: InputEvent) -> void:
	if _started:
		return
	if event.is_action_pressed(&"p1_shoot") or event.is_action_pressed(&"ui_accept"):
		_started = true
		get_viewport().set_input_as_handled()
		start_requested.emit()
