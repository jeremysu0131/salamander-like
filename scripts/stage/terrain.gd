class_name Terrain
extends Node2D
## 關卡地形。由 StageData.terrain_profile 產生，以 8×8 的格子表示。
##
## 地形碰撞不走物理引擎，一律用格子查詢。所有查詢函式都吃「畫面座標」
## （等於 global_position，因為攝影機固定不動、只有地形在捲動）。
##
## 會變化的地形（增生壁等）以「提供者」的身份註冊進來，見 add_provider()。

const CELL := 8
const ROWS := 27

enum Tile {
	ROCK_FILL, ROCK_CEIL_EDGE, ROCK_FLOOR_EDGE,
	FLESH_FILL, FLESH_CEIL_EDGE, FLESH_FLOOR_EDGE,
	GROWTH, GROWTH_BUD,
}

const TILES_PATH := "res://assets/sprites/tiles.png"

## 每一欄天花板佔幾格（從畫面頂端往下算）。
var ceil_rows := PackedInt32Array()
## 每一欄地面佔幾格（從畫面底端往上算）。
var floor_rows := PackedInt32Array()
## 每一欄是否為肉壁主題（否則為岩石）。
var flesh := PackedByteArray()

var _layer: TileMapLayer
var _providers: Array[Node] = []


## 依地形輪廓產生格子資料與圖塊。
##
## profile 的每個關鍵點：{x: 像素, ceil: 格數, floor: 格數, theme: "rock" 或 "flesh", rough: 0–2}
## 相鄰關鍵點之間的天花板與地面高度線性內插，主題沿用左側關鍵點。
## rough 是邊緣的起伏幅度（格數），讓地形看起來不那麼死板。
func build(profile: Array, length_px: float) -> void:
	var cols := int(ceil(length_px / CELL)) + 64
	ceil_rows.resize(cols)
	floor_rows.resize(cols)
	flesh.resize(cols)
	var k := 0
	for col in cols:
		var x := col * CELL
		while k + 1 < profile.size() and profile[k + 1].x <= x:
			k += 1
		var a: Dictionary = profile[k]
		var b: Dictionary = profile[mini(k + 1, profile.size() - 1)]
		var t := 0.0
		if b.x > a.x:
			t = clampf(float(x - a.x) / float(b.x - a.x), 0.0, 1.0)
		var rough: float = a.get("rough", 0)
		var c := lerpf(a.ceil, b.ceil, t)
		var f := lerpf(a.floor, b.floor, t)
		if c > 0:
			c += _noise(col, 1) * rough
		if f > 0:
			f += _noise(col, 2) * rough
		ceil_rows[col] = clampi(roundi(c), 0, ROWS)
		floor_rows[col] = clampi(roundi(f), 0, ROWS)
		flesh[col] = 1 if a.get("theme", "rock") == "flesh" else 0
	_build_tiles()


func columns() -> int:
	return ceil_rows.size()


## 這個畫面座標是否為實心地形（包含所有提供者）。
func is_solid_at(screen_pos: Vector2) -> bool:
	if _base_solid(screen_pos):
		return true
	for p in _providers:
		if p.is_solid_at(screen_pos):
			return true
	return false


## 矩形範圍內是否碰到地形。以不超過 4 px 的間距取樣。
func is_solid_rect(screen_rect: Rect2) -> bool:
	var nx := maxi(1, ceili(screen_rect.size.x / 4.0))
	var ny := maxi(1, ceili(screen_rect.size.y / 4.0))
	for i in nx + 1:
		for j in ny + 1:
			var p := screen_rect.position + Vector2(
					screen_rect.size.x * i / nx, screen_rect.size.y * j / ny)
			if is_solid_at(p):
				return true
	return false


## 子彈命中檢查：若這個位置是地形則回傳 true（子彈應消失），
## 可破壞的地形（提供者）會在這裡受到傷害，得分記給 player_id。
func hit(screen_pos: Vector2, damage := 1, player_id := 0) -> bool:
	if _base_solid(screen_pos):
		return true
	for p in _providers:
		if p.hit(screen_pos, damage, player_id):
			return true
	return false


## 註冊會變化的地形。提供者必須實作：
##   is_solid_at(screen_pos: Vector2) -> bool
##   hit(screen_pos: Vector2, damage: int, player_id: int) -> bool    命中時回傳 true，並自行扣血與加分
## 提供者離開場景樹時會自動移除。
func add_provider(provider: Node) -> void:
	_providers.append(provider)
	provider.tree_exiting.connect(func(): _providers.erase(provider))


## 某個畫面 x 座標的通道範圍（天花板底端與地面頂端的 y，不含提供者）。
func passage_at(screen_x: float) -> Vector2:
	var col := _col_at(screen_x)
	if col < 0 or col >= columns():
		return Vector2(0, Game.SCREEN_SIZE.y)
	return Vector2(ceil_rows[col] * CELL, (ROWS - floor_rows[col]) * CELL)


## 畫面上這一欄的地形主題是否為肉壁。
func is_flesh_at(screen_x: float) -> bool:
	var col := clampi(_col_at(screen_x), 0, columns() - 1)
	return flesh[col] == 1


func _col_at(screen_x: float) -> int:
	return floori((screen_x - global_position.x) / CELL)


func _base_solid(screen_pos: Vector2) -> bool:
	var col := _col_at(screen_pos.x)
	if col < 0 or col >= columns():
		return false
	var row := floori(screen_pos.y / CELL)
	return row < ceil_rows[col] or row >= ROWS - floor_rows[col]


## 以欄位編號產生 -1..1 之間平滑的偽隨機值，同一關每次產生的地形都一樣。
func _noise(col: int, seed_offset: int) -> float:
	var x := col / 6.0
	var i := floori(x)
	var frac := x - i
	var a := _hash(i, seed_offset)
	var b := _hash(i + 1, seed_offset)
	return lerpf(a, b, frac * frac * (3.0 - 2.0 * frac))


func _hash(i: int, s: int) -> float:
	var h := (i * 374761393 + s * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 2001) / 1000.0 - 1.0


func _build_tiles() -> void:
	if _layer:
		_layer.queue_free()
	_layer = TileMapLayer.new()
	_layer.tile_set = make_tileset()
	add_child(_layer)
	for col in columns():
		var base := Tile.FLESH_FILL if flesh[col] else Tile.ROCK_FILL
		for row in ceil_rows[col]:
			var tile := base + (1 if row == ceil_rows[col] - 1 else 0)
			_layer.set_cell(Vector2i(col, row), 0, Vector2i(tile, 0))
		for i in floor_rows[col]:
			var row := ROWS - 1 - i
			var tile := base + (2 if i == floor_rows[col] - 1 else 0)
			_layer.set_cell(Vector2i(col, row), 0, Vector2i(tile, 0))


## 圖塊集：tiles.png 是 8 個 8×8 圖塊橫排，順序同 Tile 列舉。增生壁也用這個圖塊集。
static func make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	var src := TileSetAtlasSource.new()
	src.texture = load(TILES_PATH)
	src.texture_region_size = Vector2i(CELL, CELL)
	for i in Tile.size():
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	return ts
