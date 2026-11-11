extends Node
## 全域狀態：分數、殘機、最高分、輸入動作，以及目前這一輪遊戲的世界。
##
## 分數與殘機以玩家為單位存放（GDD 12.6），MVP 只有 player_id 0。

signal score_changed(player_id: int, score: int)
signal lives_changed(player_id: int, lives: int)
signal hiscore_changed(hiscore: int)

const SCREEN_SIZE := Vector2(384, 216)
const HUD_HEIGHT := 12
## 玩家可以活動的範圍。HUD 疊在最上方 12 px，不能進入。
const PLAYFIELD := Rect2(0, 12, 384, 204)
const SCROLL_SPEED := 30.0
const START_LIVES := 3
const MAX_LIVES := 9
const EXTEND_FIRST := 30000
const EXTEND_EVERY := 70000
const SAVE_PATH := "user://save.cfg"

## 敵彈速度與射擊頻率的全域倍率（GDD 8.3，預留給日後的動態難度）。
## 敵人計算彈速時乘上它，計算射擊間隔時除以它。
var difficulty := 1.0

var scores: Array[int] = [0]
var lives: Array[int] = [START_LIVES]
var hiscore := 0

## 目前這一輪遊戲的 GameWorld（scripts/game/game_world.gd），不在遊戲中時為 null。
var world: GameWorld = null

var _next_extend: Array[int] = [EXTEND_FIRST]


func _ready() -> void:
	_setup_input()
	_load_hiscore()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## 開始新的一輪：分數、殘機、加命門檻歸零。
func reset_run(player_count := 1) -> void:
	scores.clear()
	lives.clear()
	_next_extend.clear()
	for i in player_count:
		scores.append(0)
		lives.append(START_LIVES)
		_next_extend.append(EXTEND_FIRST)
		score_changed.emit(i, 0)
		lives_changed.emit(i, START_LIVES)


func add_score(player_id: int, points: int) -> void:
	if player_id < 0 or player_id >= scores.size():
		return
	scores[player_id] += points
	score_changed.emit(player_id, scores[player_id])
	while scores[player_id] >= _next_extend[player_id]:
		_next_extend[player_id] += EXTEND_EVERY
		add_life(player_id)
	if scores[player_id] > hiscore:
		hiscore = scores[player_id]
		hiscore_changed.emit(hiscore)


func add_life(player_id: int) -> void:
	lives[player_id] = mini(lives[player_id] + 1, MAX_LIVES)
	lives_changed.emit(player_id, lives[player_id])


## 扣 1 條命，回傳扣完後是否還有殘機。
func lose_life(player_id: int) -> bool:
	lives[player_id] = maxi(lives[player_id] - 1, 0)
	lives_changed.emit(player_id, lives[player_id])
	return lives[player_id] > 0


## 用了開發用參數或在測試中時不儲存，以免汙染正式紀錄。
func save_hiscore() -> void:
	if Debug.is_assisted():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("score", "hiscore", hiscore)
	cfg.save(SAVE_PATH)


func _load_hiscore() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		hiscore = cfg.get_value("score", "hiscore", 0)


## 輸入動作在程式中建立，動作名稱一律帶玩家前綴（GDD 12.6）。
func _setup_input() -> void:
	_add_action(&"p1_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add_action(&"p1_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add_action(&"p1_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add_action(&"p1_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add_action(&"p1_shoot", [KEY_Z, KEY_J], [JOY_BUTTON_A])
	_add_action(&"pause", [KEY_ESCAPE, KEY_ENTER], [JOY_BUTTON_START])
	_add_action(&"toggle_fullscreen", [KEY_F11], [])


func _add_action(action: StringName, keys: Array, buttons: Array,
		axis := JOY_AXIS_INVALID, axis_dir := 0.0) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.4)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)
	if axis != JOY_AXIS_INVALID:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = axis_dir
		InputMap.action_add_event(action, ev)
