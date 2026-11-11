extends Control
## 結果畫面（GDD 9.2）：Game Over 或過關畫面，按射擊鍵發出 closed 回標題。
##
##   Game Over：「GAME OVER」與本次分數
##   過關：     「STAGE CLEAR」、殘機獎勵與總分
##
## Main 在加進場景樹前呼叫 setup()。剛出現的 INPUT_DELAY 秒內不接受輸入，
## 避免一直按著射擊鍵的玩家直接跳過這個畫面。

signal closed

const UiStyle := preload("res://scripts/ui/ui_style.gd")

const INPUT_DELAY := 0.8
const BLINK_PERIOD := 1.0
const BLINK_ON := 0.65

var result: StringName = &"game_over"
## 總分（過關時已包含殘機獎勵）。
var score := 0
var bonus := 0

var _time := 0.0
var _closed := false
var _prompt: Label


## result 為 &"clear" 或 &"game_over"；score 為最終分數；bonus 為殘機獎勵（Game Over 時為 0）。
func setup(p_result: StringName, p_score: int, p_bonus: int) -> void:
	result = p_result
	score = p_score
	bonus = p_bonus


func _ready() -> void:
	theme = UiStyle.THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cx := int(Game.SCREEN_SIZE.x) / 2

	var bg := ColorRect.new()
	bg.color = UiStyle.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	if result == &"clear":
		UiStyle.make_centered_label(self, "STAGE CLEAR", cx, 64, UiStyle.CYAN)
		_add_row("LIFE BONUS", bonus, cx, 96, UiStyle.LGREY)
		_add_row("TOTAL", score, cx, 112, UiStyle.WHITE)
	else:
		UiStyle.make_centered_label(self, "GAME OVER", cx, 72, UiStyle.RED)
		_add_row("SCORE", score, cx, 104, UiStyle.WHITE)

	_prompt = UiStyle.make_centered_label(self, "PRESS SHOOT", cx, 160, UiStyle.GREY)
	_prompt.visible = false


func _process(delta: float) -> void:
	_time += delta
	if _time >= INPUT_DELAY:
		_prompt.visible = fmod(_time - INPUT_DELAY, BLINK_PERIOD) < BLINK_ON


func _unhandled_input(event: InputEvent) -> void:
	if _closed or _time < INPUT_DELAY:
		return
	if event.is_action_pressed(&"p1_shoot") or event.is_action_pressed(&"ui_accept"):
		_closed = true
		get_viewport().set_input_as_handled()
		closed.emit()


## 一列「名稱……數值」，名稱靠左、6 位數數值靠右，整列以 cx 為中心，寬 20 字。
func _add_row(name_text: String, value: int, cx: int, y: int, color: Color) -> void:
	var width := UiStyle.text_width("LIFE BONUS    000000")
	var x := cx - width / 2
	UiStyle.make_label(self, name_text, x, y, color)
	var value_text := UiStyle.format_score(value)
	UiStyle.make_label(self, value_text, x + width - UiStyle.text_width(value_text), y, color)
