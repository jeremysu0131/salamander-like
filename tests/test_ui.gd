extends TestCase
## UI：HUD、標題、結果畫面、暫停畫面（GDD 第 9 章）。

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const TITLE_SCENE := preload("res://scenes/ui/title.tscn")
const RESULT_SCENE := preload("res://scenes/ui/result.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause.tscn")


## 與 Player 相同介面的假玩家，只提供 HUD 需要的部分。
class DummyPlayer extends Node2D:
	signal powerup_changed
	var player_id := 0
	var state := {speed = 0, missile = false, weapon = &"basic", drones = 0, shield = 0}

	func get_powerup_state() -> Dictionary:
		return state.duplicate()


func _shoot_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"p1_shoot"
	ev.pressed = true
	return ev


func test_hud_reacts_to_game_signals() -> void:
	var hud: Control = add(HUD_SCENE.instantiate())
	Game.score_changed.emit(0, 12300)
	check_eq(hud.get_score_text(), "012300", "score")
	Game.score_changed.emit(1, 99999)
	check_eq(hud.get_score_text(), "012300", "other player's score ignored")
	Game.lives_changed.emit(0, 5)
	check_eq(hud.get_lives_text(), "x5", "lives")
	Game.hiscore_changed.emit(50000)
	check_eq(hud.get_hiscore_text(), "050000", "hiscore")
	# 還原成 Game 目前的實際值，避免影響其他測試看到的畫面。
	Game.hiscore_changed.emit(Game.hiscore)


func test_hud_reads_initial_values() -> void:
	Game.reset_run()
	var hud: Control = add(HUD_SCENE.instantiate())
	check_eq(hud.get_score_text(), "000000")
	check_eq(hud.get_lives_text(), "x%d" % Game.START_LIVES)
	check_eq(hud.get_hiscore_text(), "%06d" % Game.hiscore)


func test_hud_powerup_icons() -> void:
	var hud: Control = add(HUD_SCENE.instantiate())
	var p := DummyPlayer.new()
	add(p)
	hud.bind_player(p)
	for key in [&"speed", &"missile", &"ring", &"beam", &"drone", &"shield"]:
		check(not hud.is_lit(key), "%s dim at start" % key)
	check_eq(hud.get_digit(&"speed"), "0")

	p.state = {speed = 3, missile = true, weapon = &"beam", drones = 2, shield = 3}
	p.powerup_changed.emit()
	check(hud.is_lit(&"speed"), "speed lit")
	check_eq(hud.get_digit(&"speed"), "3", "speed level")
	check(hud.is_lit(&"missile"), "missile lit")
	check(hud.is_lit(&"beam"), "beam lit")
	check(not hud.is_lit(&"ring"), "ring dim while beam held")
	check(hud.is_lit(&"drone"), "drone lit")
	check_eq(hud.get_digit(&"drone"), "2", "drone count")
	check_eq(hud.get_digit(&"shield"), "3", "shield count")

	p.state = {speed = 3, missile = true, weapon = &"ring", drones = 0, shield = 0}
	p.powerup_changed.emit()
	check(hud.is_lit(&"ring"), "ring lit")
	check(not hud.is_lit(&"beam"), "beam dim")
	check(not hud.is_lit(&"drone"), "drone dim at 0")
	check(not hud.is_lit(&"shield"), "shield dim at 0")
	check_eq(hud.get_digit(&"shield"), "0")


## 實際的 GameWorld：HUD 會自己找到玩家並跟著強化狀態更新。
func test_hud_binds_world_player() -> void:
	var gw: GDScript = load("res://scripts/game/game_world.gd")
	if not gw.can_instantiate():
		gw.reload()
	var w := await make_world()
	w.stage.set_physics_process(false)
	var hud: Control = null
	for c in w.ui.get_children():
		if c.has_method(&"bind_player"):
			hud = c
	check(hud != null, "HUD added to world UI layer")
	if hud == null:
		return
	var p: Node2D = w.players[0]
	p.apply_powerup(&"missile")
	check(hud.is_lit(&"missile"), "missile lit after pickup")


func test_title_starts_on_shoot() -> void:
	var title: Control = add(TITLE_SCENE.instantiate())
	var started := [0]
	title.start_requested.connect(func(): started[0] += 1)
	await tree.process_frame
	title._unhandled_input(_shoot_event())
	check_eq(started[0], 1, "start_requested on p1_shoot")
	title._unhandled_input(_shoot_event())
	check_eq(started[0], 1, "only once")


func test_title_starts_on_accept() -> void:
	var title: Control = add(TITLE_SCENE.instantiate())
	var started := [0]
	title.start_requested.connect(func(): started[0] += 1)
	var ev := InputEventAction.new()
	ev.action = &"ui_accept"
	ev.pressed = true
	title._unhandled_input(ev)
	check_eq(started[0], 1, "start_requested on ui_accept")


func test_result_ignores_input_during_delay() -> void:
	var screen: Control = RESULT_SCENE.instantiate()
	screen.setup(&"clear", 123400, 15000)
	add(screen)
	var closed := [0]
	screen.closed.connect(func(): closed[0] += 1)
	await tree.process_frame
	screen._unhandled_input(_shoot_event())
	check_eq(closed[0], 0, "ignored right away")
	await tree.create_timer(0.4).timeout
	screen._unhandled_input(_shoot_event())
	check_eq(closed[0], 0, "ignored at 0.4 s")
	await tree.create_timer(0.55).timeout
	screen._unhandled_input(_shoot_event())
	check_eq(closed[0], 1, "closed after delay")
	screen._unhandled_input(_shoot_event())
	check_eq(closed[0], 1, "only once")


func test_result_game_over_shows_score() -> void:
	var screen: Control = RESULT_SCENE.instantiate()
	screen.setup(&"game_over", 8700, 0)
	add(screen)
	var texts: Array[String] = []
	for c in screen.get_children():
		if c is Label:
			var l: Label = c
			texts.append(l.text)
	check(texts.has("GAME OVER"), "title text")
	check(texts.has("008700"), "score text")


func test_pause_runs_while_paused() -> void:
	var pause: Control = add(PAUSE_SCENE.instantiate())
	check_eq(pause.process_mode, Node.PROCESS_MODE_ALWAYS)
	var has_label := false
	for c in pause.get_children():
		if c is Label:
			var l: Label = c
			has_label = has_label or l.text == "PAUSE"
	check(has_label, "PAUSE label")
