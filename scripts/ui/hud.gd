extends Control
## 遊戲中 HUD（GDD 9.1）：畫面最上方 12 px 高的半透明條。
##
##   1P 012300 [殘機]x3     [S3][M][R][B][D2][盾3]     HI 050000
##
## - 左：分數（6 位數補零）、殘機數
## - 中：強化狀態。速度段數、飛彈、主武器（環波／光束）、僚機數、護盾剩餘次數；未持有的顯示為暗色
## - 右：最高分
##
## 分數、殘機、最高分聽 Game 的訊號；強化狀態從玩家節點的 get_powerup_state() 讀取，
## 收到 powerup_changed 時更新。玩家節點可能比 HUD 晚出現，所以沒綁到時每幀找一次。
##
## 為 2P 預留：每個玩家的資訊集中在 _build_player_panel()，以 player_id 區分。
## 2P 時 2P 的面板放在右側、最高分移到中央（GDD 9.1），目前只實作 1P 的排法。

const UiStyle := preload("res://scripts/ui/ui_style.gd")

const BAR_HEIGHT := 12
## 半透明底色的不透明度。
const BAR_ALPHA := 0.8
## 文字頂端與圖示頂端的 y。字高 7、圖示高 8，兩者底部對齊在第 9 列。
const TEXT_Y := 3
const ICON_Y := 2
const MARGIN := 4
## 中央圖示之間的間距。
const ICON_GAP := 5

## 這個 HUD 顯示哪一位玩家。
@export var player_id := 0

var _player: Node = null
var _score_label: Label
var _lives_label: Label
var _hiscore_label: Label
## 中央的強化圖示，key 為 &"speed"、&"missile"、&"ring"、&"beam"、&"drone"、&"shield"。
var _icons := {}
## 圖示旁的數字，key 為 &"speed"、&"drone"、&"shield"。
var _digits := {}


func _ready() -> void:
	theme = UiStyle.THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(Game.SCREEN_SIZE.x, BAR_HEIGHT)
	_build()
	Game.score_changed.connect(_on_score_changed)
	Game.lives_changed.connect(_on_lives_changed)
	Game.hiscore_changed.connect(_on_hiscore_changed)
	if player_id < Game.scores.size():
		_on_score_changed(player_id, Game.scores[player_id])
		_on_lives_changed(player_id, Game.lives[player_id])
	_on_hiscore_changed(Game.hiscore)
	_refresh_powerups()
	_try_bind_player()


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_try_bind_player()


## 綁定要顯示強化狀態的玩家節點。需有 powerup_changed 訊號與 get_powerup_state()。
func bind_player(p: Node) -> void:
	if is_instance_valid(_player) and _player.has_signal(&"powerup_changed") \
			and _player.powerup_changed.is_connected(_refresh_powerups):
		_player.powerup_changed.disconnect(_refresh_powerups)
	_player = p
	if is_instance_valid(p) and p.has_signal(&"powerup_changed"):
		p.powerup_changed.connect(_refresh_powerups)
	_refresh_powerups()


func _try_bind_player() -> void:
	if Game.world == null:
		return
	for p in Game.world.players:
		if is_instance_valid(p) and p.player_id == player_id:
			bind_player(p)
			return


func _build() -> void:
	var bar := ColorRect.new()
	bar.color = Color(UiStyle.BLACK, BAR_ALPHA)
	bar.size = Vector2(Game.SCREEN_SIZE.x, BAR_HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_build_player_panel(MARGIN)
	_build_powerups(int(Game.SCREEN_SIZE.x) / 2)
	# 右：HI 與 6 位數最高分，右緣貼齊邊界。
	var hi_x := int(Game.SCREEN_SIZE.x) - MARGIN - UiStyle.text_width("HI 000000")
	UiStyle.make_label(self, "HI", hi_x, TEXT_Y, UiStyle.RED)
	_hiscore_label = UiStyle.make_label(self, "", hi_x + 3 * UiStyle.GLYPH_W, TEXT_Y, UiStyle.CREAM)


## 一位玩家的分數與殘機，從 x 開始往右排。
func _build_player_panel(x: int) -> void:
	UiStyle.make_label(self, "%dP" % (player_id + 1), x, TEXT_Y, UiStyle.CYAN)
	x += 3 * UiStyle.GLYPH_W
	_score_label = UiStyle.make_label(self, "", x, TEXT_Y, UiStyle.WHITE)
	x += 6 * UiStyle.GLYPH_W + 5
	UiStyle.make_icon(self, UiStyle.Icon.LIFE, x, ICON_Y)
	x += 9
	_lives_label = UiStyle.make_label(self, "", x, TEXT_Y, UiStyle.WHITE)


## 中央的強化圖示，整組以 cx 為中心。
func _build_powerups(cx: int) -> void:
	# [key, 圖示, 是否附數字]
	var items := [
		[&"speed", UiStyle.Icon.SPEED, true],
		[&"missile", UiStyle.Icon.MISSILE, false],
		[&"ring", UiStyle.Icon.RING, false],
		[&"beam", UiStyle.Icon.BEAM, false],
		[&"drone", UiStyle.Icon.DRONE, true],
		[&"shield", UiStyle.Icon.SHIELD, true],
	]
	var widths: Array[int] = []
	var total := 0
	for it in items:
		var with_digit: bool = it[2]
		var w := 8 + (1 + UiStyle.GLYPH_W - 1 if with_digit else 0)
		widths.append(w)
		total += w
	total += ICON_GAP * (items.size() - 1)
	var x := cx - total / 2
	for i in items.size():
		var key: StringName = items[i][0]
		var icon: UiStyle.Icon = items[i][1]
		var with_digit: bool = items[i][2]
		_icons[key] = UiStyle.make_icon(self, icon, x, ICON_Y)
		if with_digit:
			_digits[key] = UiStyle.make_label(self, "0", x + 9, TEXT_Y, UiStyle.WHITE)
		x += widths[i] + ICON_GAP


func _on_score_changed(id: int, score: int) -> void:
	if id == player_id:
		_score_label.text = UiStyle.format_score(score)


func _on_lives_changed(id: int, lives: int) -> void:
	if id == player_id:
		_lives_label.text = "x%d" % lives


func _on_hiscore_changed(hiscore: int) -> void:
	_hiscore_label.text = UiStyle.format_score(hiscore)


func _refresh_powerups() -> void:
	var state := {}
	if is_instance_valid(_player) and _player.has_method(&"get_powerup_state"):
		state = _player.get_powerup_state()
	var speed := _state_int(state, "speed")
	var drones := _state_int(state, "drones")
	var shield := _state_int(state, "shield")
	var missile := _state_int(state, "missile") > 0
	var weapon := StringName(str(_state_value(state, "weapon", &"basic")))
	_set_lit(&"speed", speed > 0, speed)
	_set_lit(&"missile", missile)
	_set_lit(&"ring", weapon == &"ring")
	_set_lit(&"beam", weapon == &"beam")
	_set_lit(&"drone", drones > 0, drones)
	_set_lit(&"shield", shield > 0, shield)


func _set_lit(key: StringName, lit: bool, value := -1) -> void:
	var c := Color.WHITE if lit else UiStyle.DIM
	var icon: TextureRect = _icons[key]
	icon.modulate = c
	if _digits.has(key):
		var label: Label = _digits[key]
		label.text = str(maxi(value, 0))
		label.modulate = c


## get_powerup_state() 的鍵可能是 String 或 StringName，兩種都試。
func _state_value(state: Dictionary, key: String, default: Variant) -> Variant:
	if state.has(key):
		return state[key]
	if state.has(StringName(key)):
		return state[StringName(key)]
	return default


func _state_int(state: Dictionary, key: String) -> int:
	var v: Variant = _state_value(state, key, 0)
	return int(v)


## 測試用：目前顯示的文字。
func get_score_text() -> String:
	return _score_label.text


func get_lives_text() -> String:
	return _lives_label.text


func get_hiscore_text() -> String:
	return _hiscore_label.text


## 測試用：該圖示是否為亮色（已持有）。
func is_lit(key: StringName) -> bool:
	var icon: TextureRect = _icons[key]
	return icon.modulate == Color.WHITE


## 測試用：圖示旁的數字。
func get_digit(key: StringName) -> String:
	var label: Label = _digits[key]
	return label.text
