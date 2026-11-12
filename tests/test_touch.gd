extends TestCase
## 觸控操作（scripts/autoload/touch_controls.gd）：搖桿方向、按住射擊、暫停、標題點一下開始。
##
## 直接呼叫 _on_touch()／_update_stick()，用 384×216 的遊戲座標，不經過視窗座標換算。

const TC := preload("res://scripts/autoload/touch_controls.gd")


func after_each() -> void:
	TouchControls.release_all()
	TouchControls.set_active(false)
	await super()


func test_stick_direction_8_way() -> void:
	check_eq(TC.stick_direction(Vector2(2, 1)), Vector2i.ZERO, "deadzone")
	check_eq(TC.stick_direction(Vector2(20, 0)), Vector2i(1, 0), "right")
	check_eq(TC.stick_direction(Vector2(-20, 3)), Vector2i(-1, 0), "left")
	check_eq(TC.stick_direction(Vector2(0, -20)), Vector2i(0, -1), "up")
	check_eq(TC.stick_direction(Vector2(14, 14)), Vector2i(1, 1), "down-right")
	check_eq(TC.stick_direction(Vector2(-14, -14)), Vector2i(-1, -1), "up-left")


func test_left_side_moves_right_side_shoots() -> void:
	var w := await make_world()
	w.stage.set_physics_process(false)
	var p: Node2D = w.players[0]
	p.global_position = Vector2(100, 110)
	TouchControls.set_active(true)
	# 左手按在 (60, 150) 往上拖 20 px；右手按住右半邊。
	TouchControls._on_touch(0, Vector2(60, 150), true)
	TouchControls._stick_pos = Vector2(60, 130)
	TouchControls._update_stick()
	TouchControls._on_touch(1, Vector2(300, 120), true)
	await tree.process_frame  # 送出的輸入事件下一幀才生效
	check(Input.is_action_pressed(&"p1_up"), "up held")
	check(not Input.is_action_pressed(&"p1_left"), "left not held")
	check(Input.is_action_pressed(&"p1_shoot"), "shoot held")
	await physics_frames(30)
	check(p.global_position.y < 100, "ship moved up, y=%s" % p.global_position.y)
	check(w.player_bullets.get_child_count() > 0, "ship is shooting")
	# 放開後動作要跟著放開。
	TouchControls._on_touch(0, Vector2(60, 130), false)
	TouchControls._on_touch(1, Vector2(300, 120), false)
	await physics_frames(2)
	check(not Input.is_action_pressed(&"p1_up"), "up released")
	check(not Input.is_action_pressed(&"p1_shoot"), "shoot released")


func test_pause_button() -> void:
	var w := await make_world()
	TouchControls.set_active(true)
	TouchControls._on_touch(0, TC.PAUSE_RECT.get_center(), true)
	await tree.process_frame
	check(tree.paused, "paused")
	TouchControls._on_touch(0, TC.PAUSE_RECT.get_center(), false)
	TouchControls._on_touch(0, TC.PAUSE_RECT.get_center(), true)
	await tree.process_frame
	check(not tree.paused, "resumed")
	TouchControls._on_touch(0, TC.PAUSE_RECT.get_center(), false)
	w.queue_free()


func test_tap_on_title_starts() -> void:
	var title: Control = add(load("res://scenes/ui/title.tscn").instantiate())
	TouchControls.set_active(true)
	var started := [false]
	title.start_requested.connect(func(): started[0] = true)
	await tree.process_frame
	check_eq(title._prompt.text, "TAP TO START", "touch prompt")
	TouchControls._on_touch(0, Vector2(200, 100), true)
	await tree.process_frame
	check(started[0], "tap starts the game")
	TouchControls._on_touch(0, Vector2(200, 100), false)


func test_keyboard_hides_touch_controls() -> void:
	TouchControls.set_active(true)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Z
	ev.pressed = true
	TouchControls._input(ev)
	check(not TouchControls.active, "hidden after a key press")
