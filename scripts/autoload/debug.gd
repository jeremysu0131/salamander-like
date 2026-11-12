extends Node
## 開發用的命令列參數。放在 `--` 之後傳入，例如：
##
##   godot --path . -- --skip-title --start=2400 --god --shot=1,3 --shotdir=/tmp/shots --quit=4
##
## --skip-title     直接進入遊戲
## --start=<px>     從關卡的這個捲動距離開始（例如 6300 直接到 Boss）
## --god            玩家無敵（仍會碰撞，只是不會死）
## --powered        開局即滿強化（速度 3 段、飛彈、貫穿光束、4 僚機、護盾）
## --weapon=<w>     搭配 --powered 指定主武器：ring 或 beam
## --autopilot      自動駕駛：自動射擊並閃避地形，用來跑完整關卡
## --shot=<t,...>   在遊戲時間第 t 秒存截圖（需非 headless 執行）
## --shotdir=<dir>  截圖存放目錄，預設 user://shots
## --quit=<t>       遊戲時間第 t 秒結束程式
## --log            每秒印出一行狀態（捲動距離、分數、殘機、Boss HP）
## --touch          一開始就顯示觸控按鈕（在電腦上測試手機操作）

var skip_title := false
var start_x := 0.0
var god := false
var powered := false
var weapon := &"beam"
var autopilot := false
var log_state := false
var touch := false
var shot_times: Array[float] = []
var shot_dir := "user://shots"
var quit_time := -1.0

## 由測試執行器（tests/run_tests.gd）設為 true。
var testing := false

## 遊戲時間（只在 GameWorld 存在且未暫停時累計）。
var game_time := 0.0
var _last_log := 0
var _had_world := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var key := parts[0]
		var value := parts[1] if parts.size() > 1 else ""
		match key:
			"skip-title": skip_title = true
			"start": start_x = value.to_float()
			"god": god = true
			"powered": powered = true
			"weapon": weapon = StringName(value)
			"autopilot": autopilot = true
			"log": log_state = true
			"touch": touch = true
			"shot":
				for t in value.split(","):
					shot_times.append(t.to_float())
			"shotdir": shot_dir = value
			"quit": quit_time = value.to_float()


## 這一輪是否用了開發用參數或在測試中。這種情況下不儲存最高分。
func is_assisted() -> bool:
	return testing or god or powered or autopilot or start_x > 0.0


func _physics_process(delta: float) -> void:
	if Game.world == null:
		# 一輪結束、回到其他畫面後，有指定 --quit 就直接結束，讓自動化執行不會卡在標題畫面。
		if _had_world and quit_time >= 0.0:
			print("[end] game_time=%.1f score=%d" % [game_time, Game.scores[0]])
			get_tree().quit()
		return
	_had_world = true
	if get_tree().paused:
		return
	game_time += delta
	if not shot_times.is_empty() and game_time >= shot_times[0]:
		var t: float = shot_times.pop_front()
		_save_screenshot("t%06.2f" % t)
	if log_state and int(game_time) > _last_log:
		_last_log = int(game_time)
		print("[%3ds] %s" % [_last_log, Game.world.debug_status()])
	if quit_time >= 0.0 and game_time >= quit_time:
		get_tree().quit()


func _save_screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join("%s.png" % label)
	img.save_png(path)
	print("screenshot: ", ProjectSettings.globalize_path(path))
