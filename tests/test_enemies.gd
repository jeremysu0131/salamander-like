extends TestCase
## 雜兵與敵彈（GDD 5 章）：受傷、計分、掉落、編隊獎勵、壁砲貼齊與射擊間隔。
##
## 不依賴玩家場景：用假的目標節點代替玩家，用假的道具場景接住掉落。

const PROFILE := [
	{x = 0, ceil = 4, floor = 3},
	{x = 2000, ceil = 4, floor = 3},
]


func after_each() -> void:
	Game.difficulty = 1.0
	await super()


## 建一個停止捲動、沒有關卡事件、地形固定（通道 y 32–192）的 GameWorld。
func _world() -> GameWorld:
	_ensure_game_world_compiled()
	var w := await make_world()
	w.stage.scrolling = false
	w.stage.scroll_x = 0.0
	w.stage.world.position.x = 0.0
	w.stage.data.spawns.clear()
	w.terrain().build(PROFILE, 1600)
	for n: Node in w.enemies.get_children() + w.enemy_bullets.get_children() + w.pickups.get_children():
		n.queue_free()
	w.players.clear()
	w._scenes[GameWorld.PICKUP_SCENE] = _fake_scene("extends Node2D\nvar type: StringName\n")
	Game.reset_run()
	await tree.process_frame
	return w


func _fake_scene(source: String) -> PackedScene:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	var ps := PackedScene.new()
	ps.pack(n)
	n.free()
	return ps


## 假玩家：get_target_player() 會選到它。
func _fake_player(w: GameWorld, pos: Vector2) -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar player_id := 0\nfunc is_alive() -> bool:\n\treturn true\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	n.position = pos
	w.add_child(n)
	w.players.append(n)
	return n


func _spawn(w: GameWorld, path: String, params: Dictionary, pos: Vector2, attached := false) -> Node2D:
	var n: Node2D = load(path).instantiate()
	n.setup(params)
	n.position = pos
	if attached:
		w.stage.world.add_child(n)
	else:
		w.enemies.add_child(n)
	return n


func test_registry_entries() -> void:
	for type: StringName in [&"worm_formation", &"spore", &"turret", &"charger", &"growth_wall", &"tentacle"]:
		check(SpawnRegistry.ENTRIES.has(type), "registry has %s" % type)
		var entry: Dictionary = SpawnRegistry.ENTRIES.get(type, {})
		var path: String = entry.get("scene", "")
		check(ResourceLoader.exists(path), "scene exists for %s" % type)
	var turret: Dictionary = SpawnRegistry.ENTRIES[&"turret"]
	check(turret.attached, "turret attached")
	var spore: Dictionary = SpawnRegistry.ENTRIES[&"spore"]
	check(not spore.attached, "spore free")


func test_red_enemy_damage_score_and_drop() -> void:
	var w := await _world()
	var e: Enemy = _spawn(w, "res://scenes/enemies/charger.tscn", {red = true, drop = &"shield"}, Vector2(300, 100))
	await physics_frames(1)
	check_eq(e.collision_layer, 1 << 3, "enemy layer")
	check_eq(e.collision_mask, 0, "enemy mask")
	check_eq(e.sprite.frame_coords.y, 1, "red row")
	e.take_damage(1, 0)
	check(not e.dead, "HP 2 survives 1 damage")
	check_eq(e.hp, 1)
	check_eq(e.sprite.material.get_shader_parameter(&"flash"), 1.0, "flash on hit")
	await physics_frames(3)
	check_eq(e.sprite.material.get_shader_parameter(&"flash"), 0.0, "flash ends")
	check_eq(Game.scores[0], 0)
	e.take_damage(1, 0)
	check(e.dead, "killed")
	check_eq(Game.scores[0], 200, "charger score")
	await tree.process_frame  # 道具延後一幀加入（GameWorld.spawn_pickup）
	check_eq(w.pickups.get_child_count(), 1, "dropped item")
	if w.pickups.get_child_count() == 1:
		check_eq(w.pickups.get_child(0).type, &"shield", "drop type")
	e.take_damage(1, 0)
	check_eq(Game.scores[0], 200, "no double score")
	await physics_frames(1)
	check(not is_instance_valid(e), "freed")


func test_normal_enemy_no_drop() -> void:
	var w := await _world()
	var e: Enemy = _spawn(w, "res://scenes/enemies/spore.tscn", {}, Vector2(300, 100))
	await physics_frames(1)
	check_eq(e.sprite.frame_coords.y, 0, "normal row")
	e.take_damage(1, 0)
	check_eq(Game.scores[0], 100)
	check_eq(w.pickups.get_child_count(), 0)


func test_offscreen_left_is_freed() -> void:
	var w := await _world()
	var e: Enemy = _spawn(w, "res://scenes/enemies/charger.tscn", {}, Vector2(300, 100))
	await physics_frames(1)
	e.warning = false
	e.global_position.x = -30
	await physics_frames(3)
	check(not is_instance_valid(e), "freed past -32")


func _formation(w: GameWorld) -> WormFormation:
	var f: WormFormation = _spawn(w, "res://scenes/enemies/worm_formation.tscn", {drop = &"speed"}, Vector2(400, 100))
	# 5 隻每 0.25 秒放出 1 隻。
	await physics_frames(70)
	return f


func test_formation_all_killed_gives_bonus_and_drop() -> void:
	var w := await _world()
	var f := await _formation(w)
	var worms := f.worms()
	check_eq(worms.size(), 5, "5 worms")
	check(worms[0].global_position.x < worms[4].global_position.x, "in a row")
	for i in worms.size():
		worms[i].take_damage(1, 0)
		if i < 4:
			check_eq(w.pickups.get_child_count(), 0, "no drop before last")
	check_eq(Game.scores[0], 5 * 100 + 500, "bonus")
	await tree.process_frame  # 道具延後一幀加入（GameWorld.spawn_pickup）
	check_eq(w.pickups.get_child_count(), 1, "drop at last")
	if w.pickups.get_child_count() == 1:
		var p: Node2D = w.pickups.get_child(0)
		check_eq(p.type, &"speed")
		check(p.position.distance_to(worms[4].global_position) < 1.0, "at last worm")


func test_formation_no_bonus_if_one_escapes() -> void:
	var w := await _world()
	var f := await _formation(w)
	var worms := f.worms()
	worms[0].queue_free()  # 逃走（不是被擊破）
	await physics_frames(1)
	for i in range(1, 5):
		worms[i].take_damage(1, 0)
	check_eq(Game.scores[0], 400, "no bonus")
	check_eq(w.pickups.get_child_count(), 0, "no drop")
	await physics_frames(2)
	check(not is_instance_valid(f), "formation frees itself")


func test_worm_follows_sine_path_left() -> void:
	var w := await _world()
	var f := await _formation(w)
	var worm: Worm = f.worms()[0]
	var x0 := worm.global_position.x
	await physics_frames(30)
	check_near(x0 - worm.global_position.x, 40.0, 2.0, "80 px/s")
	check(absf(worm.global_position.y - 100.0) <= 24.5, "within amplitude")


func test_turret_snaps_to_floor_and_ceiling() -> void:
	var w := await _world()
	var floor_t: Turret = _spawn(w, "res://scenes/enemies/turret.tscn", {}, Vector2(200, 50), true)
	var ceil_t: Turret = _spawn(w, "res://scenes/enemies/turret.tscn", {ceiling = true}, Vector2(260, 150), true)
	check_eq(floor_t.global_position.y, 192.0 - 8.0, "floor turret on floor surface")
	check(not floor_t.sprite.flip_v, "floor not flipped")
	check_eq(ceil_t.global_position.y, 32.0 + 8.0, "ceiling turret under ceiling")
	check(ceil_t.sprite.flip_v, "ceiling flipped")
	check_eq(floor_t.get_parent(), w.stage.world, "attached to world")


func _count_bullets(w: GameWorld, frames: int) -> int:
	var count := [0]
	var cb := func(_n: Node) -> void: count[0] += 1
	w.enemy_bullets.child_entered_tree.connect(cb)
	await physics_frames(frames)
	w.enemy_bullets.child_entered_tree.disconnect(cb)
	return count[0]


func test_turret_fire_interval_and_difficulty() -> void:
	var w := await _world()
	_fake_player(w, Vector2(60, 110))
	var t: Turret = _spawn(w, "res://scenes/enemies/turret.tscn", {}, Vector2(200, 0), true)
	# 2 秒 1 發：2.5 秒內 1 發。
	check_eq(await _count_bullets(w, 150), 1, "1 shot per 2 s")
	check_eq(t.sprite.frame_coords.x, 0, "back to idle frame")
	var t2: Turret = _spawn(w, "res://scenes/enemies/turret.tscn", {}, Vector2(300, 0), true)
	t.queue_free()
	Game.difficulty = 2.0
	check_near(t2.fire_interval(), 1.0, 0.001, "interval / difficulty")
	check_eq(await _count_bullets(w, 150), 2, "2 shots in 2.5 s at difficulty 2")


func test_turret_fire_frame_and_aim() -> void:
	var w := await _world()
	_fake_player(w, Vector2(100, 120))
	var t: Turret = _spawn(w, "res://scenes/enemies/turret.tscn", {}, Vector2(200, 0), true)
	var frames := 0
	while w.enemy_bullets.get_child_count() == 0 and frames < 200:
		await tree.physics_frame
		frames += 1
	check_near(frames, 120, 2, "first shot after 2 s")
	await tree.physics_frame
	check_eq(t.sprite.frame_coords.x, 1, "firing frame")
	check_eq(w.enemy_bullets.get_child_count(), 1)
	if w.enemy_bullets.get_child_count() == 1:
		var b: EnemyBullet = w.enemy_bullets.get_child(0)
		check_eq(b.collision_layer, 1 << 4, "enemy bullet layer")
		check_near(b.velocity.length(), 100.0, 0.01, "base speed")
		check(b.velocity.x < 0 and b.velocity.y < 0, "aimed up-left")


func test_turret_no_target_no_fire() -> void:
	var w := await _world()
	_spawn(w, "res://scenes/enemies/turret.tscn", {}, Vector2(200, 0), true)
	check_eq(await _count_bullets(w, 130), 0, "no target")


func test_enemy_bullet_freed_by_terrain_and_screen() -> void:
	var w := await _world()
	var b: EnemyBullet = w.spawn_enemy_bullet(Vector2(100, 180), Vector2(0, 100))
	await physics_frames(12)  # 10 px 內落到地面（y 192）
	check(not is_instance_valid(b), "freed in terrain")
	var b2: EnemyBullet = w.spawn_enemy_bullet(Vector2(4, 100), Vector2(-300, 0))
	await physics_frames(4)
	check(not is_instance_valid(b2), "freed off screen")
	var b3: EnemyBullet = w.spawn_enemy_bullet(Vector2(200, 100), Vector2(-60, 0))
	await physics_frames(30)
	check(is_instance_valid(b3), "alive in passage")
	if is_instance_valid(b3):
		check_near(b3.position.x, 170.0, 1.0, "moves")


func test_charger_warning_then_charge() -> void:
	var w := await _world()
	var c: Charger = _spawn(w, "res://scenes/enemies/charger.tscn", {}, Vector2(400, 90))
	await physics_frames(20)
	check(c.warning, "warning first")
	check(not c.monitorable, "no hit box while warning")
	check(not c.sprite.visible, "hidden while warning")
	await physics_frames(12)
	check(not c.warning, "charging after 0.5 s")
	check(c.monitorable)
	var x0 := c.global_position.x
	await physics_frames(30)
	check_near(x0 - c.global_position.x, 100.0, 4.0, "200 px/s")
	check_eq(c.global_position.y, 90.0, "straight line")


func test_spore_dashes_at_player() -> void:
	var w := await _world()
	var p := _fake_player(w, Vector2(80, 60))
	var s: Spore = _spawn(w, "res://scenes/enemies/spore.tscn", {}, Vector2(260, 140))
	await physics_frames(10)
	check_eq(s.state, Spore.State.DRIFT, "drifting while far")
	s.global_position.x = p.global_position.x + Spore.DASH_RANGE - 4
	await physics_frames(2)
	check_eq(s.state, Spore.State.TURN, "turns near player")
	await physics_frames(int(Spore.TURN_TIME * 60) + 2)
	check_eq(s.state, Spore.State.DASH, "dashing")
	var to_player := (p.global_position - s.global_position).normalized()
	check(s.dash_velocity.normalized().dot(to_player) > 0.95, "dash aimed at player")
	check_near(s.dash_velocity.length(), Spore.DASH_SPEED, 0.01)


## test_case.gd 在 autoload 就緒前就被編譯，連帶編譯 game_world.gd 時找不到 Game 而失敗，
## 失敗的腳本會留在快取裡。這裡在 autoload 就緒後重新編譯一次。
func _ensure_game_world_compiled() -> void:
	var s: GDScript = load("res://scripts/game/game_world.gd")
	if not s.can_instantiate():
		s.reload()
