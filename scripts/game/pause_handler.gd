extends Node
## 暫停鍵處理。這個節點在暫停時仍會執行（PROCESS_MODE_ALWAYS）。


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_parent().toggle_pause()
		get_viewport().set_input_as_handled()
