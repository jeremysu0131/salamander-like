extends TestCase
## 第 1 關的排關資料（GDD 第 6 章、scripts/stage/stage1_data.gd）。
##
## 只檢查資料，不跑遊戲：地形用 Terrain.build() 產生格子後直接讀 ceil_rows／floor_rows。
## 世界座標 x 的換算見 stage1_data.gd 開頭。

const DATA_PATH := "res://scripts/stage/stage1_data.gd"
const CELL := 8
const ROWS := 27
const SCREEN_W := 384.0
const SCREEN_H := 216.0
## 自由飛行的敵人在捲動到 x − SPAWN_AHEAD 時生成（畫面右緣外 16 px）。
const SPAWN_AHEAD := 400.0
const FREE_TYPES := [&"worm_formation", &"spore", &"charger"]
const ATTACHED_TYPES := [&"turret", &"growth_wall", &"tentacle"]

## 觸手根部節點寬 12 px（本體每節 8 px），間距扣掉這個寬度。
const TENTACLE_WIDTH := 12.0
## 固定地形的通道最低高度（增生壁另計）。
const MIN_PASSAGE := 64.0
## 復活：無敵 2 秒內地形最多往左移 60 px（GDD 6.4 #5）。
const RESPAWN_SCROLL := 60.0
const RESPAWN_HALF_W := 6.0
## 復活後可以停留的空間至少要這麼高（機體 12 px 加上一點餘裕）。
const RESPAWN_TUBE := 16.0
## 2 秒內以 90 px/s 能垂直移動 180 px，留一點餘裕。
const RESPAWN_REACH := 150.0

var data: StageData
var segments: Dictionary
var lead: float
var ceil_rows := PackedInt32Array()
var floor_rows := PackedInt32Array()
var flesh := PackedByteArray()


func before_each() -> void:
	var script: GDScript = load(DATA_PATH)
	data = script.new()
	var consts := script.get_script_constant_map()
	segments = consts.get("SEGMENTS", {})
	lead = consts.get("FREE_SPAWN_LEAD", 300.0)
	var t := Terrain.new()
	t.build(data.terrain_profile, data.length)
	ceil_rows = t.ceil_rows
	floor_rows = t.floor_rows
	flesh = t.flesh
	t.free()


# ── 工具 ──

func _top(x: float) -> float:
	var col := clampi(floori(x / CELL), 0, ceil_rows.size() - 1)
	return ceil_rows[col] * CELL


func _bottom(x: float) -> float:
	var col := clampi(floori(x / CELL), 0, floor_rows.size() - 1)
	return (ROWS - floor_rows[col]) * CELL


## 世界 x 範圍 [x0, x1] 內所有欄共同的通道：Vector2(最低的天花板底, 最高的地面頂)。
func _common_passage(x0: float, x1: float) -> Vector2:
	var top := 0.0
	var bottom := SCREEN_H
	var col := floori(x0 / CELL)
	while col * CELL <= x1:
		var x := col * CELL + 0.5
		top = maxf(top, _top(x))
		bottom = minf(bottom, _bottom(x))
		col += 1
	return Vector2(top, bottom)


func _type(ev: Dictionary) -> StringName:
	return StringName(ev.type)


func _x(ev: Dictionary) -> float:
	return float(ev.x)


func _of_type(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev in data.spawns:
		if _type(ev) == type:
			out.append(ev)
	return out


## 事件屬於哪一段：固定在地形上的用 x，自由飛行的用生成時玩家所在的 x − lead。
func _segment_of(ev: Dictionary) -> String:
	var x := _x(ev)
	if _type(ev) in FREE_TYPES:
		x -= lead
	for key: String in segments:
		var r: Vector2 = segments[key]
		if x >= r.x and x < r.y:
			return key
	return "?"


func _in_segment(seg: String, type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev in _of_type(type):
		if _segment_of(ev) == seg:
			out.append(ev)
	return out


func _drop(ev: Dictionary) -> StringName:
	return StringName(ev.get("drop", ""))


## 某段的所有掉落，依字母排序（StringName 的 sort() 不是依字母，所以轉成 String）。
func _drops_in(seg: String) -> Array[String]:
	var out: Array[String] = []
	for ev in data.spawns:
		if _segment_of(ev) == seg and _drop(ev) != &"":
			out.append(String(_drop(ev)))
	out.sort()
	return out


func _wall_right(ev: Dictionary) -> float:
	return _x(ev) + int(ev.get("thickness", 6)) * CELL


## 自由飛行的敵人在畫面內時經過的世界 x 範圍（依各敵人的速度推算）。
##   游蟲：畫面速度 80 px/s 對地 50 px/s，5 隻相隔 0.25 秒，飛到畫面左緣約 6.1 秒 → x − 310
##   衝鋒體：預警 0.5 秒後以 200 px/s（對地 170 px/s）飛過畫面約 2 秒 → x − 330
##   孢子：對地 20 px/s 飄入，轉向直衝前約 6 秒以內 → x − 150（直衝方向看玩家，不檢查）
func _free_path(ev: Dictionary) -> Vector2:
	var x := _x(ev)
	match _type(ev):
		&"worm_formation": return Vector2(x - 310.0, x)
		&"charger": return Vector2(x - 330.0, x + 10.0)
		_: return Vector2(x - 150.0, x)


## 自由飛行的敵人佔的垂直範圍（半高）。
func _free_half_height(ev: Dictionary) -> float:
	match _type(ev):
		&"worm_formation": return float(ev.get("amplitude", 24.0)) + 6.0
		&"charger": return 6.0
		_: return 12.0  # 孢子：半高 6 加上下擺動 6


# ── 測試 ──

func test_events_sorted_by_x() -> void:
	check(not data.spawns.is_empty(), "has spawns")
	for i in range(1, data.spawns.size()):
		check(_x(data.spawns[i]) >= _x(data.spawns[i - 1]),
				"spawn %d (x=%s) before previous (x=%s)" % [i, data.spawns[i].x, data.spawns[i - 1].x])


func test_types_registered() -> void:
	for ev in data.spawns:
		check(SpawnRegistry.ENTRIES.has(_type(ev)), "unknown type %s at x=%s" % [ev.type, ev.x])
		check(ev.has("y"), "event at x=%s has y" % ev.x)


func test_terrain_profile_sorted_and_long_enough() -> void:
	var prev := -1.0
	for k in data.terrain_profile:
		check(float(k.x) > prev, "profile sorted at x=%s" % k.x)
		prev = float(k.x)
	check(prev >= data.length + SCREEN_W, "profile covers the boss screen")
	check_eq(data.length, 6300.0, "length")


## GDD 6.5：加速 ×4、飛彈 ×2、環波砲 ×1、貫穿光束 ×1、僚機 ×4、護盾 ×2。
## 紅色變體必定掉落（5.2），所以掉道具的非游蟲都必須是紅色，紅色的也都必須有掉落。
func test_pickup_totals() -> void:
	var counts := {}
	for ev in data.spawns:
		var d := _drop(ev)
		var red: bool = ev.get("red", false)
		if _type(ev) == &"worm_formation":
			check(not red, "worms have no red variant")
		elif d != &"" or red:
			check(red and d != &"", "red <=> drop at x=%s" % ev.x)
		if d != &"":
			check(Pickup.ROWS.has(d), "valid pickup type %s" % d)
			counts[d] = int(counts.get(d, 0)) + 1
	var expected := {&"speed": 4, &"missile": 2, &"ring": 1, &"beam": 1, &"drone": 4, &"shield": 2}
	for k: StringName in expected:
		check_eq(int(counts.get(k, 0)), int(expected[k]), "%s count" % k)
	check_eq(counts.size(), expected.size(), "no extra pickup types")


## 每個事件都落在某一段裡，各段的掉落符合 GDD 6.3。
func test_segment_drops() -> void:
	for ev in data.spawns:
		check(_segment_of(ev) != "?", "event x=%s outside every segment" % ev.x)
	check_eq(_drops_in("A"), ["drone", "speed", "speed"] as Array[String], "A drops")
	check_eq(_drops_in("B"), ["drone", "missile"] as Array[String], "B drops")
	check_eq(_drops_in("C"), ["beam", "ring"] as Array[String], "C drops")
	check_eq(_drops_in("D"), ["drone", "shield"] as Array[String], "D drops")
	check_eq(_drops_in("E"), ["missile", "shield", "speed"] as Array[String], "E drops")
	check_eq(_drops_in("F"), ["drone", "speed"] as Array[String], "F drops")
	# A：3 波游蟲分別掉加速、加速、僚機。
	var a_worms := _in_segment("A", &"worm_formation")
	check_eq(a_worms.size(), 3, "A worm formations")
	if a_worms.size() == 3:
		check_eq([_drop(a_worms[0]), _drop(a_worms[1]), _drop(a_worms[2])], [&"speed", &"speed", &"drone"], "A order")
	# B：紅色壁砲掉飛彈、紅色孢子掉僚機。
	for ev in data.spawns:
		if _segment_of(ev) != "B" or _drop(ev) == &"":
			continue
		match _drop(ev):
			&"missile": check_eq(_type(ev), &"turret", "B missile from turret")
			&"drone": check_eq(_type(ev), &"spore", "B drone from spore")
	# C：環波砲與貫穿光束一上一下。
	var ring_ceiling := false
	var beam_ceiling := true
	var ring_x := 0.0
	var beam_x := 1e9
	for ev in data.spawns:
		if _drop(ev) == &"ring":
			ring_ceiling = ev.get("ceiling", false)
			ring_x = _x(ev)
			check_eq(_type(ev), &"turret", "ring from turret")
		elif _drop(ev) == &"beam":
			beam_ceiling = ev.get("ceiling", false)
			beam_x = _x(ev)
			check_eq(_type(ev), &"turret", "beam from turret")
	check(ring_ceiling != beam_ceiling, "ring and beam one high, one low")
	check(absf(ring_x - beam_x) <= 16.0, "ring and beam side by side")
	# D：游蟲掉僚機，紅色衝鋒體掉護盾。E：2 座紅色壁砲（加速、飛彈），紅色衝鋒體掉護盾。
	for seg: String in ["D", "E"]:
		var chargers := _in_segment(seg, &"charger")
		check_eq(chargers.size(), 1, "%s chargers" % seg)
		if chargers.size() == 1:
			check_eq(_drop(chargers[0]), &"shield", "%s charger drops shield" % seg)
	var d_worms := _in_segment("D", &"worm_formation")
	check(d_worms.size() == 1 and _drop(d_worms[0]) == &"drone", "D worm formation drops drone")
	var e_red_turrets: Array[String] = []
	for ev in _in_segment("E", &"turret"):
		if _drop(ev) != &"":
			e_red_turrets.append(String(_drop(ev)))
	e_red_turrets.sort()
	check_eq(e_red_turrets, ["missile", "speed"] as Array[String], "E red turrets")
	# F：掉落在最後的開闊段（窄通道打開之後）。
	for ev in data.spawns:
		if _segment_of(ev) == "F" and _drop(ev) != &"":
			check(_x(ev) - lead >= _last_narrow_x(), "F drop x=%s is in the open end" % ev.x)


## F 段窄通道結束的位置：最後一道增生壁的右緣。
func _last_narrow_x() -> float:
	var walls := _of_type(&"growth_wall")
	return _wall_right(walls[walls.size() - 1]) if not walls.is_empty() else 0.0


## 各段的增生壁、觸手、衝鋒體數量（GDD 6.3）。
func test_mechanisms_per_segment() -> void:
	var walls := {"C": 6, "F": 8}
	for seg: String in segments:
		var w := _in_segment(seg, &"growth_wall")
		check_eq(w.size(), 2 if walls.has(seg) else 0, "%s growth walls" % seg)
		for ev in w:
			check_eq(int(ev.get("thickness", 6)), int(walls.get(seg, 0)), "%s wall thickness" % seg)
		var tentacles := _in_segment(seg, &"tentacle")
		var want_t := {"E": 5, "F": 2}
		check_eq(tentacles.size(), int(want_t.get(seg, 0)), "%s tentacles" % seg)
		var chargers := _in_segment(seg, &"charger")
		if seg in ["D", "E"]:
			check_eq(chargers.size(), 1, "%s chargers" % seg)
		elif seg == "F":
			check(chargers.size() >= 1, "F has chargers")
		else:
			check_eq(chargers.size(), 0, "%s chargers" % seg)
	# A 只有游蟲與孢子；B 開始有壁砲；E 的壁砲穿插在觸手之間。
	check_eq(_in_segment("A", &"turret").size(), 0, "A has no turrets")
	check(_in_segment("B", &"turret").size() >= 4, "B turrets")
	check(_in_segment("B", &"spore").size() >= 3, "B spores")
	check(_in_segment("C", &"turret").size() >= 2, "C turrets")
	check(_in_segment("C", &"spore").size() >= 2, "C spores")
	check(_in_segment("E", &"turret").size() >= 4, "E turrets")


## 固定地形的通道高度：任何地方都至少 MIN_PASSAGE（增生壁另計）；各段的平均高度符合 GDD 6.3。
func test_passage_heights() -> void:
	var x := 0.0
	var lowest := SCREEN_H
	while x < data.length + SCREEN_W:
		var h := _bottom(x) - _top(x)
		lowest = minf(lowest, h)
		check(h >= MIN_PASSAGE, "passage at x=%d is %d px" % [x, h])
		x += CELL
	check(lowest >= MIN_PASSAGE, "lowest passage %d" % lowest)
	check_eq(_bottom(400.0) - _top(400.0), SCREEN_H, "A has no terrain")
	# 段內平均（扣掉兩端的過渡）。比例是佔畫面高 216 px。
	var targets := {"B": 0.60, "E": 0.45, "F": 0.40}
	for seg: String in targets:
		var r: Vector2 = segments[seg]
		var x1 := r.y - 100.0
		if seg == "F":
			x1 = _last_narrow_x()
		var sum := 0.0
		var n := 0
		x = r.x + 100.0
		while x < x1:
			sum += _bottom(x) - _top(x)
			n += 1
			x += CELL
		var ratio := sum / n / SCREEN_H
		check_near(ratio, float(targets[seg]), 0.05, "%s passage ratio" % seg)


## 主題：A、B 岩石，C 以後肉壁。
func test_themes() -> void:
	var c: Vector2 = segments["C"]
	var first_wall := _x(_of_type(&"growth_wall")[0])
	var x := 0.0
	while x < data.length + SCREEN_W:
		var col := floori(x / CELL)
		if x < c.x:
			check_eq(flesh[col], 0, "rock at x=%d" % x)
		elif x >= first_wall - 100.0:
			check_eq(flesh[col], 1, "flesh at x=%d" % x)
		x += CELL


## GDD 6.4 #4：相鄰觸手之間至少 48 px（扣掉根部寬度）。
func test_tentacle_spacing() -> void:
	var xs: Array[float] = []
	for ev in _of_type(&"tentacle"):
		xs.append(_x(ev))
	xs.sort()
	for i in range(1, xs.size()):
		var gap := xs[i] - xs[i - 1] - TENTACLE_WIDTH
		check(gap >= 48.0, "tentacles at %d and %d only %d px apart" % [xs[i - 1], xs[i], gap])


## GDD 6.4 #2：每道增生壁前 200 px 內沒有其他固定機關，也沒有東西放在牆裡。
## 自由飛行的敵人不在牆接近玩家、正在開路的期間生成（牆 x − 150 到牆右緣 + 300），
## 免得玩家開路時被孢子追，也免得敵人從牆裡穿過去。
func test_space_before_growth_walls() -> void:
	for wall in _of_type(&"growth_wall"):
		var wx := _x(wall)
		var right := _wall_right(wall)
		for ev in data.spawns:
			if ev == wall:
				continue
			var x := _x(ev)
			if _type(ev) in ATTACHED_TYPES:
				check(not (x >= wx - 200.0 and x < right),
						"%s at x=%d within 200 px before wall at %d" % [ev.type, x, wx])
			else:
				check(not (x > wx - 150.0 and x < right + 300.0),
						"%s at x=%d spawns while wall at %d is being opened" % [ev.type, x, wx])


## GDD 6.4 #3：F 段的衝鋒體只在玩家穿過增生壁之後才出現。
## 生成時（捲動到 x − 400）前一道牆的右緣必須已經在畫面 x ≤ 100，也就是 x ≥ 牆右緣 + 300；
## 而且不可以在 F 段第一道牆之前出現。
func test_f_chargers_after_walls() -> void:
	var f_walls := _in_segment("F", &"growth_wall")
	check(not f_walls.is_empty(), "F has walls")
	if f_walls.is_empty():
		return
	for ev in _in_segment("F", &"charger"):
		var x := _x(ev)
		var prev: Dictionary = {}
		for w in f_walls:
			if _x(w) < x:
				prev = w
		check(not prev.is_empty(), "F charger x=%d after the first wall" % x)
		if not prev.is_empty():
			var screen_right := _wall_right(prev) - (x - SPAWN_AHEAD)
			check(screen_right <= 100.0, "F charger x=%d: wall right edge at screen %d" % [x, screen_right])


## 自由飛行的敵人無視地形，所以它們在畫面內經過的路線不可以穿過固定地形或增生壁。
func test_free_enemies_avoid_terrain() -> void:
	var walls := _of_type(&"growth_wall")
	for ev in data.spawns:
		if not _type(ev) in FREE_TYPES:
			continue
		var path := _free_path(ev)
		var y := float(ev.y)
		var half := _free_half_height(ev)
		var p := _common_passage(maxf(path.x, 0.0), path.y)
		check(y - half >= p.x and y + half <= p.y,
				"%s at x=%d y=%d leaves passage %s" % [ev.type, ev.x, y, p])
		check(y - half >= 12.0, "%s at x=%d below the HUD" % [ev.type, ev.x])
		for w in walls:
			check(path.y <= _x(w) or path.x >= _wall_right(w),
					"%s at x=%d flies through wall at %s" % [ev.type, ev.x, w.x])


## GDD 6.4 #5：復活安全。
## 窄通道（B、C、E 與 F 的窄段）中，玩家可能在任何一欄 x（世界座標）復活。
## 無敵 2 秒內地形最多往左移 60 px，所以機體（寬 12）在這段時間掃過世界 [x − 6, x + 66]。
## 要求：這整段範圍內有一條共同的水平空間（每一欄的通道交集）至少 16 px 高，
## 且它的中心離該欄通道中心不超過 150 px（2 秒內以 90 px/s 移動得到）。
## 只檢查固定地形；增生壁與觸手是可以應對的機關，不算在內。
func test_respawn_safety() -> void:
	var ranges: Array[Vector2] = [segments["B"], segments["C"], segments["E"],
			Vector2(segments["F"].x, _last_narrow_x())]
	for r in ranges:
		var x := r.x
		while x < r.y:
			var p := _common_passage(x - RESPAWN_HALF_W, x + RESPAWN_SCROLL + RESPAWN_HALF_W)
			var tube := p.y - p.x
			var here := (_top(x) + _bottom(x)) / 2.0
			check(tube >= RESPAWN_TUBE, "respawn at x=%d: common space only %d px" % [x, tube])
			check(absf((p.x + p.y) / 2.0 - here) <= RESPAWN_REACH, "respawn at x=%d: space too far" % x)
			x += CELL


## Boss 區：最後 400 px 到 Boss 背後的肉壁是平直、開闊、薄天花板與地面的肉壁走廊，沒有固定機關；
## Boss 背後的肉壁加厚，與 Boss 本體（畫面 y 54–174）上下緣相接。
func test_boss_corridor() -> void:
	var x0 := data.length - 400.0
	var c0 := ceil_rows[floori(x0 / CELL)]
	var f0 := floor_rows[floori(x0 / CELL)]
	check(c0 <= 3 and f0 <= 3, "thin ceiling/floor (%d, %d)" % [c0, f0])
	check(c0 * CELL >= 12, "ceiling visible below the HUD")
	check((ROWS - f0 - c0) * CELL >= 160, "roomy arena for the 96×120 boss")
	var wall_x: float = data.BOSS_WALL_X
	var x := x0
	while x < data.length + SCREEN_W:
		var col := floori(x / CELL)
		if x < wall_x:
			check(ceil_rows[col] == c0 and floor_rows[col] == f0, "flat at x=%d" % x)
		else:
			check(ceil_rows[col] * CELL >= 54 and (ROWS - floor_rows[col]) * CELL <= 174,
					"wall behind the boss meets its body at x=%d" % x)
		check_eq(flesh[col], 1, "flesh at x=%d" % x)
		x += CELL
	for ev in data.spawns:
		if _type(ev) in ATTACHED_TYPES:
			check(_x(ev) < x0, "%s at x=%s inside the boss corridor" % [ev.type, ev.x])


## 生成事件都在捲動停止前觸發（之後的事件永遠不會生成）。
func test_events_trigger_before_end() -> void:
	for ev in data.spawns:
		check(_x(ev) <= data.length + SPAWN_AHEAD, "event x=%s never triggers" % ev.x)
