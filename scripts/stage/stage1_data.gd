extends StageData
## 第 1 關：活體小行星・內腔（GDD 第 6 章）。
##
## ── 座標換算 ──
## 捲動 30 px/s。時間 t 秒時畫面左緣在世界 x = 30·t，玩家（畫面 x 約 64–140）在世界 x ≈ 30·t + 100。
##   - 地形與固定在地形上的東西（壁砲、增生壁、觸手）：x 就是它在地形上的位置，
##     玩家在 t ≈ (x − 100) / 30 時碰到它，它在 t = (x − 384) / 30 進入畫面。
##   - 自由飛行的敵人（游蟲、孢子、衝鋒體）：捲動到 x − 400 時在畫面右緣外生成，
##     也就是時間 t = (x − 400) / 30；那時玩家在世界 x ≈ x − 300。
## 下面 SEGMENTS 的範圍是「玩家所在的世界 x」，自由飛行的事件依 x − 300 歸段。
##
## ── 地形（27 列 × 8 px；HUD 蓋住最上面 12 px）──
##   A     0–1000  沒有地形
##   B  1000–2050  岩石，天花板 6 格、地面 5 格 → 通道 y 48–176（128 px，約畫面高 60%）
##   C  2050–3200  2000–2100 轉為肉壁，天花板 5、地面 5 → 通道 y 40–176（136 px）
##   D  3200–3700  開闊肉壁，天花板 3、地面 2
##   E  3700–5050  窄通道，天花板 8、地面 7 → 通道 y 64–160（96 px，約 45%）
##   F  5050–6300  更窄，天花板 8、地面 8 → 通道 y 64–152（88 px，約 40%）；5830–5880 打開
##   Boss 5880–    平直的薄肉壁走廊（天花板 3、地面 2，沒有起伏），Boss 戰在捲動停在 6300 時開始
## 起伏（rough）1 格：通道最窄時比上面少 16 px，F 段最窄 72 px。
##
## ── 排關約束（GDD 6.4，tests/test_stage1.gd 自動檢查）──
## - 增生壁前 200 px 內沒有其他固定機關（壁砲、觸手、增生壁）。
## - 自由飛行的敵人不在「增生壁接近玩家、正在開路」的期間生成（牆 x − 150 到牆右緣 + 300），
##   F 段的衝鋒體在這之後才出現：生成時牆的右緣已經在畫面 x ≤ 100，玩家已經穿過缺口。
## - 相鄰觸手扣掉根部寬度（12 px）後至少相距 48 px。
## - 道具：加速 ×4、飛彈 ×2、環波砲 ×1、貫穿光束 ×1、僚機 ×4、護盾 ×2（GDD 6.5）。

## 各段在世界座標上的範圍（玩家所在位置，見上方說明）。測試用來檢查各段的內容。
const SEGMENTS := {
	A = Vector2(0, 1000),
	B = Vector2(1000, 2050),
	C = Vector2(2050, 3200),
	D = Vector2(3200, 3700),
	E = Vector2(3700, 5050),
	F = Vector2(5050, 6300),
}

## 自由飛行的事件生成時，玩家大約在世界 x − 這個值的位置。
const FREE_SPAWN_LEAD := 300.0


func _init() -> void:
	length = 6300.0
	terrain_profile = [
		# A 入口：開闊，沒有地形。
		{x = 0, ceil = 0, floor = 0, theme = "rock"},
		{x = 880, ceil = 0, floor = 0, theme = "rock"},
		# B 岩殼。
		{x = 1000, ceil = 6, floor = 5, theme = "rock", rough = 1},
		{x = 2000, ceil = 6, floor = 5, theme = "rock", rough = 1},
		# C 增生區：轉為肉壁。
		{x = 2100, ceil = 5, floor = 5, theme = "flesh", rough = 1},
		{x = 3100, ceil = 5, floor = 5, theme = "flesh", rough = 1},
		# D 喘息：開闊。
		{x = 3200, ceil = 3, floor = 2, theme = "flesh", rough = 1},
		{x = 3700, ceil = 3, floor = 2, theme = "flesh", rough = 1},
		# E 觸手廊。
		{x = 3800, ceil = 8, floor = 7, theme = "flesh", rough = 1},
		{x = 5000, ceil = 8, floor = 7, theme = "flesh", rough = 1},
		# F 咽喉。
		{x = 5080, ceil = 8, floor = 8, theme = "flesh", rough = 1},
		{x = 5830, ceil = 8, floor = 8, theme = "flesh", rough = 1},
		# F 末段與 Boss 區：平直的薄肉壁走廊。
		{x = 5880, ceil = 3, floor = 2, theme = "flesh"},
		{x = 6800, ceil = 3, floor = 2, theme = "flesh"},
	]
	_segment_a()
	_segment_b()
	_segment_c()
	_segment_d()
	_segment_e()
	_segment_f()


## A 入口（0:00–0:30）：3 波游蟲編隊，掉加速、加速、僚機。中間 2 隻孢子當練習。
func _segment_a() -> void:
	_worms(520, 80, &"speed")
	_worms(760, 140, &"speed")
	_spore(880, 70)
	_worms(1000, 108, &"drone")
	_spore(1100, 150)


## B 岩殼（0:30–1:05）：壁砲與孢子登場。紅色壁砲掉飛彈，紅色孢子掉僚機。
func _segment_b() -> void:
	_turret(1120, false)
	_spore(1200, 90)
	_turret(1260, true)
	_turret(1400, false, &"missile")
	_spore(1480, 130)
	_spore(1520, 96)
	_turret(1560, true)
	_turret(1680, false)
	_spore(1740, 110, &"drone")
	_turret(1820, true)
	_spore(1880, 80)
	_turret(1960, false)
	_spore(2000, 136)


## C 增生區（1:05–1:45）：兩道增生壁（6 格），中間夾壁砲與孢子。
## 同一個 x 上下各一座紅色壁砲：天花板掉環波砲、地面掉貫穿光束，主武器只能留一種。
func _segment_c() -> void:
	_wall(2250, 6)
	_turret(2440, true, &"ring")
	_turret(2440, false, &"beam")
	_turret(2600, false)
	_spore(2620, 84)
	_spore(2700, 136)
	_turret(2720, true)
	_spore(2780, 104)
	_wall(3000, 6)


## D 喘息（1:45–2:00）：開闊。1 波游蟲掉僚機，1 隻紅色衝鋒體掉護盾。
func _segment_d() -> void:
	_worms(3600, 108, &"drone")
	_charger(3780, 108, &"shield")


## E 觸手廊（2:00–2:45）：觸手 5 條上下交錯，壁砲穿插。
## 紅色壁砲掉加速與飛彈，中途 1 隻紅色衝鋒體掉護盾。
func _segment_e() -> void:
	_turret(3880, false)
	_tentacle(3960, true, 0.0)
	_turret(4100, true, &"speed")
	_tentacle(4200, false, 1.5)
	_turret(4320, false)
	_tentacle(4440, true, 0.0)
	_charger(4560, 112, &"shield")
	_tentacle(4640, false, 1.5)
	_turret(4760, false, &"missile")
	_tentacle(4860, true, 0.0)
	_turret(4960, true)


## F 咽喉（2:45–3:30）：兩道加厚的增生壁（8 格），中間夾 2 條觸手。
## 衝鋒體在玩家穿過每道牆之後才從後方衝入。最後開闊，掉加速與僚機。
func _segment_f() -> void:
	_wall(5200, 8)
	_tentacle(5400, true, 0.0)
	_tentacle(5500, false, 1.5)
	_charger(5600, 108)
	_wall(5760, 8)
	_charger(6180, 108)
	_worms(6200, 108, &"speed")
	_spore(6300, 108, &"drone")


func _add(ev: Dictionary) -> void:
	spawns.append(ev)


func _worms(x: float, y: float, drop: StringName = &"") -> void:
	_add({x = x, y = y, type = &"worm_formation", drop = drop})


func _spore(x: float, y: float, drop: StringName = &"") -> void:
	_add({x = x, y = y, type = &"spore", red = drop != &"", drop = drop})


func _charger(x: float, y: float, drop: StringName = &"") -> void:
	_add({x = x, y = y, type = &"charger", red = drop != &"", drop = drop})


func _turret(x: float, ceiling: bool, drop: StringName = &"") -> void:
	_add({x = x, y = 0, type = &"turret", ceiling = ceiling, red = drop != &"", drop = drop})


func _wall(x: float, thickness: int) -> void:
	_add({x = x, y = 0, type = &"growth_wall", thickness = thickness})


func _tentacle(x: float, ceiling: bool, phase: float) -> void:
	_add({x = x, y = 0, type = &"tentacle", ceiling = ceiling, phase = phase})
