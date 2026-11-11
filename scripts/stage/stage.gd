class_name Stage
extends Node2D
## 關卡：負責捲動、背景、地形與生成事件。
##
## 攝影機與玩家活動範圍固定不動，由 Stage 把 world（地形與固定在地形上的敵人）往左移
## （GDD 12.3）。所以玩家座標就是畫面座標。

signal end_reached

const BG_ROCK := "res://assets/sprites/bg_rock.png"
const BG_FLESH := "res://assets/sprites/bg_flesh.png"
const BG_SPEED := 0.5
## 生成點在畫面右緣外多少像素（GDD 5.1）。
const SPAWN_MARGIN := 16.0

var data: StageData
## 已捲動的距離（像素）。
var scroll_x := 0.0
var scrolling := true
## 捲動的內容：地形與固定在地形上的敵人。座標為世界座標。
var world: Node2D
var terrain: Terrain

var _next_spawn := 0
var _bg_rock: Sprite2D
var _bg_flesh: Sprite2D


func setup(stage_data: StageData, start_x := 0.0) -> void:
	data = stage_data
	_build_background()
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	terrain.build(data.terrain_profile, data.length)
	scroll_x = clampf(start_x, 0.0, data.length)
	world.position.x = -scroll_x
	# 跳關時略過已經在畫面左側的事件，但保留畫面範圍內的。
	while _next_spawn < data.spawns.size() and data.spawns[_next_spawn].x < scroll_x:
		_next_spawn += 1


func _physics_process(delta: float) -> void:
	if scrolling:
		scroll_x += Game.SCROLL_SPEED * delta
		if scroll_x >= data.length:
			scroll_x = data.length
			scrolling = false
			end_reached.emit()
		world.position.x = -scroll_x
	_update_background()
	_process_spawns()


func world_to_screen(p: Vector2) -> Vector2:
	return p + world.position


func screen_to_world(p: Vector2) -> Vector2:
	return p - world.position


func _process_spawns() -> void:
	var trigger := scroll_x + Game.SCREEN_SIZE.x + SPAWN_MARGIN
	while _next_spawn < data.spawns.size() and data.spawns[_next_spawn].x <= trigger:
		_spawn(data.spawns[_next_spawn])
		_next_spawn += 1


func _spawn(ev: Dictionary) -> void:
	var entry: Dictionary = SpawnRegistry.ENTRIES.get(StringName(ev.type), {})
	if entry.is_empty():
		push_warning("Unknown spawn type: %s" % ev.type)
		return
	var node: Node2D = load(entry.scene).instantiate()
	if node.has_method("setup"):
		node.setup(ev)
	var world_pos := Vector2(ev.x, ev.y)
	if entry.attached:
		node.position = world_pos
		world.add_child(node)
	else:
		node.position = world_to_screen(world_pos)
		Game.world.enemies.add_child(node)


## 背景只有 1 層，以 0.5 倍速捲動（GDD 10.3）。岩石與肉壁兩張圖依畫面中央的地形主題交叉淡入淡出。
func _build_background() -> void:
	_bg_rock = _make_bg(BG_ROCK)
	_bg_flesh = _make_bg(BG_FLESH)
	_bg_flesh.modulate.a = 0.0


func _make_bg(path: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	if ResourceLoader.exists(path):
		s.texture = load(path)
	add_child(s)
	return s


func _update_background() -> void:
	for s: Sprite2D in [_bg_rock, _bg_flesh]:
		if s.texture:
			var h := s.texture.get_height()
			s.region_rect = Rect2(scroll_x * BG_SPEED, 0, Game.SCREEN_SIZE.x, h)
			s.position.y = Game.SCREEN_SIZE.y - h
	var target := 1.0 if terrain and terrain.is_flesh_at(Game.SCREEN_SIZE.x / 2) else 0.0
	_bg_flesh.modulate.a = move_toward(_bg_flesh.modulate.a, target, 0.5 / Engine.physics_ticks_per_second)
