extends Control
## 暫停畫面（GDD 9.2）：畫面變暗並顯示「PAUSE」，沒有選單。
##
## 由 GameWorld 加進 UI 層並切換 visible；暫停鍵由 PauseHandler 處理。
## 場景樹暫停時仍要繪製，process_mode 設為 ALWAYS。

const UiStyle := preload("res://scripts/ui/ui_style.gd")

## 變暗的程度（黑色遮罩的不透明度）。
const DARKEN := 0.55


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiStyle.THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.BLACK, DARKEN)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var cx := int(Game.SCREEN_SIZE.x) / 2
	var cy := int(Game.SCREEN_SIZE.y) / 2
	UiStyle.make_centered_label(self, "PAUSE", cx, cy - 4, UiStyle.WHITE)
