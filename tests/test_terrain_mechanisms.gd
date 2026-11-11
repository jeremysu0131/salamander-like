extends TestCase
## 地形機關（GDD 6.2）：增生壁與伸縮觸手。

## 通道 y 32–192：天花板 4 格（列 0–3）、地面 3 格（列 24–26），中間列 4–23 共 20 列。
const PROFILE := [
	{x = 0, ceil = 4, floor = 3},
	{x = 2000, ceil = 4, floor = 3},
]
const TOP_ROW := 4
const BOTTOM_ROW := 24


func _world() -> GameWorld:
	_ensure_game_world_compiled()
	var w := await make_world()
	w.stage.scrolling = false
	w.stage.scroll_x = 0.0
	w.stage.world.position.x = 0.0
	w.stage.data.spawns.clear()
	w.terrain().build(PROFILE, 1600)
	for n: Node in w.enemies.get_children():
		n.queue_free()
	w.players.clear()
	Game.reset_run()
	await tree.process_frame
	return w


func _wall(w: GameWorld, x := 203.0, thickness := 6) -> GrowthWall:
	var g: GrowthWall = load("res://scenes/terrain/growth_wall.tscn").instantiate()
	g.setup({thickness = thickness})
	g.position = Vector2(x, 77)
	w.stage.world.add_child(g)
	return g


func _tentacle(w: GameWorld, params: Dictionary, x := 200.0) -> Tentacle:
	var t: Tentacle = load("res://scenes/terrain/tentacle.tscn").instantiate()
	t.setup(params)
	t.position = Vector2(x, 0)
	w.stage.world.add_child(t)
	return t


func test_wall_fills_passage_aligned() -> void:
	var w := await _world()
	var g := _wall(w)
	check_eq(g.global_position, Vector2(200, 0), "aligned to grid")
	check_eq(g.count_cells(GrowthWall.Cell.SOLID), 6 * 20, "6 × 20 cells")
	var t := w.terrain()
	check(t.is_solid_at(Vector2(201, 100)), "wall solid via terrain")
	check(t.is_solid_at(Vector2(247, 32)), "top cell")
	check(t.is_solid_at(Vector2(247, 191)), "bottom cell")
	check(not t.is_solid_at(Vector2(248, 100)), "right of wall")
	check(not t.is_solid_at(Vector2(199, 100)), "left of wall")
	check_eq(g.column_rows(0), Vector2i(TOP_ROW, BOTTOM_ROW))


func test_wall_default_thickness() -> void:
	var w := await _world()
	var g: GrowthWall = load("res://scenes/terrain/growth_wall.tscn").instantiate()
	g.setup({})
	w.stage.world.add_child(g)
	check_eq(g.thickness, 6)


func test_wall_hit_destroys_one_cell() -> void:
	var w := await _world()
	var g := _wall(w)
	var t := w.terrain()
	var p := Vector2(205, 100)  # 欄 0、列 12
	check(t.hit(p, 1, 0), "hit returns true on solid")
	check_eq(g.count_cells(GrowthWall.Cell.SOLID), 119, "exactly one destroyed")
	check_eq(g.cell_state(0, 12), GrowthWall.Cell.EMPTY)
	check(not t.is_solid_at(p), "hole")
	check(t.is_solid_at(Vector2(205, 92)), "cell above intact")
	check(t.is_solid_at(Vector2(213, 100)), "cell right intact")
	check_eq(Game.scores[0], 10, "10 points per cell")
	check(not t.hit(p, 1, 0), "hit on hole returns false")
	check_eq(Game.scores[0], 10)
	check(not g.hit(Vector2(100, 100), 1, 0), "outside wall")


func test_wall_regrowth_rate_and_bud() -> void:
	var w := await _world()
	var g := _wall(w)
	for r in range(10, 16):
		g.hit(g.cell_center(2, r), 1, 0)
	check_eq(g.count_cells(GrowthWall.Cell.EMPTY), 6)
	await physics_frames(29)
	check_eq(g.count_cells(GrowthWall.Cell.BUD), 0, "no bud before 0.5 s")
	await physics_frames(2)
	check_eq(g.count_cells(GrowthWall.Cell.BUD), 1, "bud at 0.5 s")
	var bud := Vector2i(-1, -1)
	for r in range(10, 16):
		if g.cell_state(2, r) == GrowthWall.Cell.BUD:
			bud = Vector2i(2, r)
	check(bud.x >= 0, "bud in the hole")
	check(not w.terrain().is_solid_at(g.cell_center(bud.x, bud.y)), "bud not solid")
	check(not w.terrain().hit(g.cell_center(bud.x, bud.y), 1, 0), "bullets pass buds")
	await physics_frames(15)
	check(not w.terrain().is_solid_at(g.cell_center(bud.x, bud.y)), "still bud at 0.25 s")
	await physics_frames(4)
	check(w.terrain().is_solid_at(g.cell_center(bud.x, bud.y)), "solid after 0.3 s")
	# 從破壞起算 2.33 秒：0.8、1.3、1.8、2.3 秒各長回 1 格 → 每秒 2 格。
	await physics_frames(140 - 50)
	check_eq(g.count_cells(GrowthWall.Cell.EMPTY) + g.count_cells(GrowthWall.Cell.BUD), 2, "4 regrown in 2.33 s")
	await physics_frames(60)
	check_eq(g.count_cells(GrowthWall.Cell.SOLID), 120, "all regrown")
	await physics_frames(60)
	check_eq(g.count_cells(GrowthWall.Cell.BUD), 0, "idle when full")


func test_wall_regrows_from_edges_inward() -> void:
	var w := await _world()
	var g := _wall(w)
	# 削掉中間一整直排（像環波砲），再看長回來的順序。
	for r in range(TOP_ROW, BOTTOM_ROW):
		g.hit(g.cell_center(3, r), 1, 0)
	var order: Array[int] = []
	for i in 6:
		var next := g.next_regrow_cell()
		check_eq(next.x, 3, "same column")
		order.append(next.y)
		g._set_cell(next.x, next.y, GrowthWall.Cell.SOLID)
	check_eq(order, [4, 23, 5, 22, 6, 21] as Array[int], "edges inward")


func test_wall_tunnel_closes_from_rim() -> void:
	var w := await _world()
	var g := _wall(w)
	# 鑽穿一整橫排（像光束）。
	for c in 6:
		g.hit(g.cell_center(c, 14), 1, 0)
	var first := g.next_regrow_cell()
	check_eq(first, Vector2i(0, 14), "deterministic first cell")
	g._set_cell(first.x, first.y, GrowthWall.Cell.SOLID)
	check_eq(g.next_regrow_cell(), Vector2i(1, 14), "then continues next to it")


func test_wall_provider_removed_when_freed() -> void:
	var w := await _world()
	var g := _wall(w)
	var t := w.terrain()
	check(t.is_solid_at(Vector2(220, 100)))
	g.queue_free()
	await tree.process_frame
	check(not t.is_solid_at(Vector2(220, 100)), "no longer solid")
	check(not t.hit(Vector2(220, 100), 1, 0), "no longer hit")


func test_wall_frees_offscreen_and_scrolls() -> void:
	var w := await _world()
	var g := _wall(w, 100.0)
	w.stage.world.position.x = -150
	check(w.terrain().is_solid_at(Vector2(-46, 100)), "moves with world")
	w.stage.world.position.x = -190
	await physics_frames(2)
	check(not is_instance_valid(g), "freed off screen")


func test_tentacle_layers_and_cycle() -> void:
	var w := await _world()
	var t := _tentacle(w, {length = 64.0})
	check_eq(t.global_position, Vector2(200, 192), "rooted on floor")
	check_eq(t.direction, Vector2.UP)
	check_eq(t.root.collision_layer, 1 << 3, "root enemy layer")
	check_eq(t.root.hp, 6)
	check_eq(t.segments.size(), 8)
	for s in t.segments:
		check_eq(s.collision_layer, 1 << 7, "segment hazard layer")
		check_eq(s.collision_mask, 0)
	check_eq(t.extension, 0.0, "starts retracted")
	var max_e := 0.0
	var shown_at_max := 0
	for i in 180:
		await tree.physics_frame
		if t.extension > max_e:
			max_e = t.extension
		if t.extension >= 64.0:
			shown_at_max = 0
			for s in t.segments:
				if s.monitorable:
					shown_at_max += 1
	check_near(max_e, 64.0, 0.01, "reaches length")
	check_eq(shown_at_max, 8, "all segments out at full length")
	check_near(t.segments[0].global_position.y, 192.0 - t.extension + 4.0, 0.5, "tip position")
	check_eq(t.cycle_extension(0.1), 0.0)
	check_eq(t.cycle_extension(1.7), 64.0)
	check_eq(t.cycle_extension(2.9), 0.0)


func test_tentacle_ceiling_auto_length() -> void:
	var w := await _world()
	var t := _tentacle(w, {ceiling = true, phase = 1.5})
	check_eq(t.global_position, Vector2(200, 32), "rooted on ceiling")
	check_eq(t.direction, Vector2.DOWN)
	check_near(t.reach, 160.0 * 0.6, 0.01, "auto length")
	await physics_frames(2)
	check(t.extension > 0.0, "phase offset")
	check(t.root.global_position.y > 32.0, "root below ceiling")


func test_tentacle_root_kill_destroys_all() -> void:
	var w := await _world()
	var t := _tentacle(w, {length = 48.0})
	var segs := t.segments.duplicate()
	var killed := [-1]
	t.destroyed.connect(func(pid: int) -> void: killed[0] = pid)
	for i in 5:
		t.root.take_damage(1, 0)
	check(is_instance_valid(t) and not t.is_queued_for_deletion(), "survives 5 damage")
	t.root.take_damage(1, 0)
	check_eq(Game.scores[0], 500, "root score")
	check_eq(killed[0], 0, "destroyed signal")
	await tree.process_frame
	check(not is_instance_valid(t), "tentacle freed")
	for s in segs:
		check(not is_instance_valid(s), "segment freed")


func test_tentacle_strike_timing() -> void:
	var w := await _world()
	var t: Tentacle = load("res://scenes/terrain/tentacle.tscn").instantiate()
	t.setup({mode = &"strike"})
	w.enemies.add_child(t)
	await physics_frames(5)
	check(not t.root.visible and not t.root.monitorable, "hidden while idle")
	check_eq(t.extension, 0.0)
	var finished := [false]
	t.strike_finished.connect(func() -> void: finished[0] = true)
	check(t.strike(150.0, true), "strike accepted")
	check(not t.strike(100.0, false), "ignored while striking")
	check_eq(t.global_position, Vector2(150, 32), "from ceiling surface")
	await physics_frames(55)
	check(t.root.visible, "warning bulge visible")
	check(not t.root.monitorable, "no hit box during warning")
	check_eq(t.extension, 0.0, "not extended during 1 s warning")
	for s in t.segments:
		check(not s.monitorable, "no hazard during warning")
	await physics_frames(10)  # 1.08 s
	check(t.extension > 0.0, "extending after warning")
	check(t.root.monitorable, "root hittable")
	await physics_frames(20)  # 1.42 s：伸出 0.35 秒後停在最長
	check_near(t.extension, Tentacle.STRIKE_LENGTH, 0.01, "full length")
	check(t.segments[0].monitorable, "tip is hazard")
	check(not finished[0])
	await physics_frames(55)  # 2.33 s：1 + 0.35 + 0.4 + 0.5 = 2.25 秒結束
	check(finished[0], "strike finished")
	check(not t.is_striking())
	check_eq(t.extension, 0.0)
	check(not t.root.visible, "hidden again")
	check(t.strike(250.0, false), "can strike again")
	check_eq(t.global_position, Vector2(250, 192), "from floor surface")
	check_eq(t.direction, Vector2.UP)


func test_tentacle_free_configure() -> void:
	var w := await _world()
	var t: Tentacle = load("res://scenes/terrain/tentacle.tscn").instantiate()
	t.configure(Vector2(100, 60), Vector2.RIGHT, 40.0)
	w.enemies.add_child(t)
	check_eq(t.global_position, Vector2(100, 60))
	check_eq(t.segments.size(), 5)
	t._apply_extension(40.0)
	check_near(t.segments[0].global_position.x, 136.0, 0.5, "tip extends along direction")
	check_near(t.segments[0].global_position.y, 60.0, 0.5)


## test_case.gd 在 autoload 就緒前就被編譯，連帶編譯 game_world.gd 時找不到 Game 而失敗，
## 失敗的腳本會留在快取裡。這裡在 autoload 就緒後重新編譯一次。
func _ensure_game_world_compiled() -> void:
	var s: GDScript = load("res://scripts/game/game_world.gd")
	if not s.can_instantiate():
		s.reload()
