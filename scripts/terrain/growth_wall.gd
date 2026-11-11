class_name GrowthWall
extends Node2D
## 增生壁（GDD 6.2）：封住整個通道的肉壁，可以被射擊削掉，會再長回來。
##
## 生成參數（setup）：
##   thickness: int   厚度（格數），預設 6（48 px）。F 段的加厚牆用 8
##
## 是 Stage.world 的子節點（attached）。加入場景樹時把 x 對齊地形格子，
## 每一欄從天花板表面填到地面表面（Terrain.passage_at），生成事件的 y 會被忽略。
##
## 以「提供者」身份註冊到 Terrain（add_provider），實作 is_solid_at() 與 hit()，
## 所以玩家、子彈、飛彈的地形判定自動包含這道牆。離開場景樹時 Terrain 會自動移除它。
##
## 規則：
## - 每格 HP 1，被削掉 1 格給該玩家 10 分。hit() 只傷害「該點所在的那一格」；
##   環波砲削一整直排、光束鑽一整橫排，是由武器在對應的點呼叫 terrain().hit() 達成。
## - 再生：整道牆共用一個計時器，有空格時每 REGROW_INTERVAL 秒補 1 格（每秒 2 格）。
## - 補哪一格（固定、可預測）：候選是「上下左右緊鄰實心（牆格、原本的地形或畫面外）」的空格，
##   依序比較：
##     1. 緊鄰的實心面越多越優先（凹洞先填平）
##     2. 離通道上下緣（天花板或地面表面）越近越優先 → 開出的通道從邊緣往內收窄
##     3. 欄位小者（左側）優先，再來列小者（上方）優先
## - 預警：補回的格子先以半透明芽體出現 BUD_TIME 秒，期間沒有判定，之後才變成實心。

## 補回 1 格的間隔（秒）。
const REGROW_INTERVAL := 0.5
## 芽體持續時間（秒），期間沒有判定。
const BUD_TIME := 0.3
const CELL_HP := 1
const CELL_SCORE := 10
const DEFAULT_THICKNESS := 6
const BUD_ALPHA := 0.45
## 離開畫面左側多遠後刪除。
const OFFSCREEN_LEFT := 32.0

enum Cell { NONE, SOLID, EMPTY, BUD }

var thickness := DEFAULT_THICKNESS

## 每格的狀態，索引為 c * Terrain.ROWS + r。NONE 表示不屬於這道牆（在地形裡）。
var _cells := PackedByteArray()
## 芽體剩餘時間：Vector2i(c, r) → float。
var _buds := {}
var _empty_count := 0
var _regrow_timer := 0.0
var _layer: TileMapLayer
var _bud_layer: TileMapLayer


func setup(params: Dictionary) -> void:
	thickness = maxi(1, int(params.get("thickness", DEFAULT_THICKNESS)))


func _ready() -> void:
	_layer = TileMapLayer.new()
	_layer.tile_set = Terrain.make_tileset()
	add_child(_layer)
	_bud_layer = TileMapLayer.new()
	_bud_layer.tile_set = _layer.tile_set
	_bud_layer.modulate.a = BUD_ALPHA
	add_child(_bud_layer)
	_build()


func _terrain() -> Terrain:
	return Game.world.terrain() if Game.world else null


## 對齊地形格子並依通道範圍填滿格子。
func _build() -> void:
	var terrain := _terrain()
	var rows := Terrain.ROWS
	_cells.resize(thickness * rows)
	_cells.fill(Cell.NONE)
	_layer.clear()
	_bud_layer.clear()
	_buds.clear()
	_empty_count = 0
	var gx := global_position.x
	if terrain:
		var col0 := floori((gx - terrain.global_position.x) / Terrain.CELL)
		gx = terrain.global_position.x + col0 * Terrain.CELL
	global_position = Vector2(gx, 0)
	for c in thickness:
		var passage := Vector2(0, Game.SCREEN_SIZE.y)
		if terrain:
			passage = terrain.passage_at(gx + c * Terrain.CELL + Terrain.CELL / 2.0)
		var top := floori(passage.x / Terrain.CELL)
		var bottom := floori(passage.y / Terrain.CELL)
		for r in range(maxi(top, 0), mini(bottom, rows)):
			_set_cell(c, r, Cell.SOLID)
	if terrain:
		terrain.add_provider(self)


func _physics_process(delta: float) -> void:
	_update_buds(delta)
	if _empty_count > 0:
		_regrow_timer += delta
		if _regrow_timer >= REGROW_INTERVAL - 0.0001:
			_regrow_timer -= REGROW_INTERVAL
			var next := next_regrow_cell()
			if next.x >= 0:
				_set_cell(next.x, next.y, Cell.BUD)
				_buds[next] = BUD_TIME
	else:
		_regrow_timer = 0.0
	if global_position.x + thickness * Terrain.CELL < -OFFSCREEN_LEFT:
		queue_free()


func _update_buds(delta: float) -> void:
	if _buds.is_empty():
		return
	for key: Vector2i in _buds.keys():
		var left: float = _buds[key]
		left -= delta
		if left <= 0.0001:
			_buds.erase(key)
			_set_cell(key.x, key.y, Cell.SOLID)
		else:
			_buds[key] = left


## 提供者介面：這個畫面座標是否為實心的牆格（芽體不算）。
func is_solid_at(screen_pos: Vector2) -> bool:
	var cell := cell_at(screen_pos)
	return cell_state(cell.x, cell.y) == Cell.SOLID


## 提供者介面：子彈命中檢查。該點是實心牆格時削掉那 1 格（HP 1），給 player_id 10 分，回傳 true。
func hit(screen_pos: Vector2, damage: int, player_id: int) -> bool:
	var cell := cell_at(screen_pos)
	if cell_state(cell.x, cell.y) != Cell.SOLID:
		return false
	if damage >= CELL_HP:
		_set_cell(cell.x, cell.y, Cell.EMPTY)
		Game.add_score(player_id, CELL_SCORE)
	return true


## 畫面座標所在的格子（相對於牆的欄、列）。
func cell_at(screen_pos: Vector2) -> Vector2i:
	var local := screen_pos - global_position
	return Vector2i(floori(local.x / Terrain.CELL), floori(local.y / Terrain.CELL))


## 某格的狀態（Cell 列舉）。超出範圍為 NONE。
func cell_state(c: int, r: int) -> int:
	if c < 0 or c >= thickness or r < 0 or r >= Terrain.ROWS:
		return Cell.NONE
	return _cells[c * Terrain.ROWS + r]


## 某格中心的畫面座標。
func cell_center(c: int, r: int) -> Vector2:
	return global_position + Vector2((c + 0.5) * Terrain.CELL, (r + 0.5) * Terrain.CELL)


## 該欄屬於這道牆的列範圍：Vector2i(第一列, 最後一列 + 1)。
func column_rows(c: int) -> Vector2i:
	var first := -1
	var last := -1
	for r in Terrain.ROWS:
		if cell_state(c, r) != Cell.NONE:
			if first < 0:
				first = r
			last = r
	return Vector2i(first, last + 1)


func count_cells(state: int) -> int:
	var n := 0
	for v in _cells:
		if v == state:
			n += 1
	return n


## 下一個要長回來的格子；沒有候選時回傳 (-1, -1)。規則見檔案開頭。
func next_regrow_cell() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := -1
	var best_d := 0
	for c in thickness:
		var span := column_rows(c)
		for r in range(span.x, span.y):
			if cell_state(c, r) != Cell.EMPTY:
				continue
			var n := 0
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if _neighbor_solid(c + d.x, r + d.y):
					n += 1
			if n == 0:
				continue
			var edge := mini(r - span.x, span.y - 1 - r)
			# 依序比較：實心鄰居多、離通道上下緣近；欄、列由小到大掃描所以平手時保留先找到的。
			if n > best_n or (n == best_n and edge < best_d):
				best = Vector2i(c, r)
				best_n = n
				best_d = edge
	return best


func _neighbor_solid(c: int, r: int) -> bool:
	if r < 0 or r >= Terrain.ROWS:
		return true
	if c >= 0 and c < thickness:
		var s := cell_state(c, r)
		if s == Cell.NONE:
			return true  # 牆所在欄位的通道外，就是原本的地形
		return s == Cell.SOLID
	# 牆的左右兩側：看原本的地形
	var terrain := _terrain()
	if terrain == null:
		return false
	var passage := terrain.passage_at(global_position.x + (c + 0.5) * Terrain.CELL)
	var y := (r + 0.5) * Terrain.CELL
	return y < passage.x or y >= passage.y


func _set_cell(c: int, r: int, state: int) -> void:
	var i := c * Terrain.ROWS + r
	var old := _cells[i]
	if old == Cell.EMPTY:
		_empty_count -= 1
	if state == Cell.EMPTY:
		_empty_count += 1
	_cells[i] = state
	var at := Vector2i(c, r)
	_layer.erase_cell(at)
	_bud_layer.erase_cell(at)
	if state == Cell.SOLID:
		_layer.set_cell(at, 0, Vector2i(Terrain.Tile.GROWTH, 0))
	elif state == Cell.BUD:
		_bud_layer.set_cell(at, 0, Vector2i(Terrain.Tile.GROWTH_BUD, 0))
