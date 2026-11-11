extends TestCase
## 第 1 關 Boss（GDD 第 7 章）：HP 與階段、轉換無敵、開合與判定、扇形彈、孢子、觸手、超時與擊破。
##
## Boss 的 physics_process 關掉，改用 step() 同步快轉，時間精準且不必真的等。
## 不依賴玩家場景：用假的目標節點代替玩家。

const DT := 1.0 / 60.0
## 通道 y 16–200（天花板、地面各 2 格），與第 1 關 Boss 區相同。
const PROFILE := [
	{x = 0, ceil = 2, floor = 2},
	{x = 2000, ceil = 2, floor = 2},
]


func after_each() -> void:
	Game.difficulty = 1.0
	await super()


func _world() -> GameWorld:
	_ensure_game_world_compiled()
	var w := await make_world()
	w.stage.scrolling = false
	w.stage.scroll_x = 0.0
	w.stage.world.position.x = 0.0
	w.stage.data.spawns.clear()
	w.terrain().build(PROFILE, 1600)
	for n: Node in w.enemies.get_children() + w.enemy_bullets.get_children() \
			+ w.pickups.get_children() + w.players_root.get_children():
		n.queue_free()
	w.players.clear()
	Game.reset_run()
	await tree.process_frame
	return w


## 假玩家：get_target_player() 會選到它；HUD 也會綁定它，所以要有強化狀態的介面。
func _fake_player(w: GameWorld, pos: Vector2) -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nsignal powerup_changed\nvar player_id := 0\n" \
			+ "func is_alive() -> bool:\n\treturn true\n" \
			+ "func get_powerup_state() -> Dictionary:\n" \
			+ "\treturn {speed = 0, missile = false, weapon = &\"basic\", drones = 0, shield = 0}\n"
	s.reload()
	var n := Node2D.new()
	n.set_script(s)
	n.position = pos
	w.add_child(n)
	w.players.append(n)
	return n


## 生成 Boss 並跑完滑入。
func _boss(w: GameWorld, skip_entrance := true) -> Boss:
	var b: Boss = load("res://scenes/boss/boss.tscn").instantiate()
	w.enemies.add_child(b)
	b.set_physics_process(false)
	if skip_entrance:
		_run(b, Boss.ENTER_TIME + DT)
	return b


## 快轉 seconds 秒（Boss 與它的觸手）。
func _run(b: Boss, seconds: float) -> void:
	var n := roundi(seconds / DT)
	for i in n:
		b.step(DT)
		for t in b.tentacles:
			if t != null and is_instance_valid(t):
				t._physics_process(DT)


func _count_spores(w: GameWorld) -> int:
	var c := 0
	for n in w.enemies.get_children():
		if n is Spore and not n.is_queued_for_deletion():
			c += 1
	return c


func _count_bullets(w: GameWorld) -> int:
	var c := 0
	for n in w.enemy_bullets.get_children():
		if not n.is_queued_for_deletion():
			c += 1
	return c


func test_entrance_hp_and_phase() -> void:
	var w := await _world()
	var b := _boss(w, false)
	check_eq(b.hp, 240, "hp")
	check_eq(b.phase, 1, "phase")
	check(b.global_position.x > Boss.HOME.x, "starts off to the right")
	b._core_part.take_damage(5, 0)
	check_eq(b.hp, 240, "invulnerable during entrance")
	_run(b, Boss.ENTER_TIME + DT)
	check_eq(b.state, Boss.State.FIGHT)
	check_eq(b.global_position, Boss.HOME, "against the right edge")
	check(b.valves_open, "fight starts open")
	b._core_part.take_damage(5, 0)
	check_eq(b.hp, 235, "core damage while open")
	check_eq(b.phase, 1)
	# 本體貼右緣、垂直置中。
	check_eq(Boss.HOME.x - Boss.BODY_SOCKET.x + Boss.BODY_SIZE.x, Game.SCREEN_SIZE.x)
	check_eq(Boss.HOME.y - Boss.BODY_SOCKET.y + Boss.BODY_SIZE.y / 2.0, Game.PLAYFIELD.get_center().y)


func test_transition_clamps_damage_and_invulnerable() -> void:
	var w := await _world()
	var b := _boss(w)
	b._core_part.take_damage(200, 0)
	check_eq(b.hp, 120, "damage beyond 120 does not carry over")
	check_eq(b.phase, 2)
	check_eq(b.state, Boss.State.TRANSITION)
	check(not b._valves[1].visible, "front valve shattered")
	b._core_part.take_damage(10, 0)
	b._gap_part.take_damage(10, 0)
	check_eq(b.hp, 120, "invulnerable during the show")
	_run(b, 1.4)
	b._core_part.take_damage(10, 0)
	check_eq(b.hp, 120, "still invulnerable at 1.4 s")
	check(not b._core_part.monitorable, "core shots pass through during the show")
	_run(b, 0.15)
	check_eq(b.state, Boss.State.FIGHT, "show lasts 1.5 s")
	check(b.valves_open, "phase 2 starts open")
	b._core_part.take_damage(1, 0)
	check_eq(b.hp, 119)


func test_phase1_closed_blocks_core() -> void:
	var w := await _world()
	var b := _boss(w)
	_run(b, 2.05)
	check(not b.valves_open, "closed after 2 s")
	check(not b._core_part.monitorable, "core hurtbox off")
	check(not b._gap_part.monitorable, "no gap in phase 1")
	check(b._shutter_full.monitorable, "closed valves stop bullets")
	b._core_part.take_damage(5, 0)
	b._gap_part.take_damage(5, 0)
	check_eq(b.hp, 240, "no damage while closed")
	check_eq(Game.scores[0], 0)


func test_phase2_gap_band() -> void:
	var w := await _world()
	var b := _boss(w)
	b.set_phase2()
	_run(b, 2.05)
	check(not b.valves_open, "closed")
	check(not b._core_part.monitorable, "full core off")
	check(b._gap_part.monitorable, "gap band on")
	check(b._shutter_split.monitorable and not b._shutter_full.monitorable, "split shutters")
	var shape: RectangleShape2D = (b._gap_part.get_child(0) as CollisionShape2D).shape
	check_eq(shape.size, Vector2(16, 4), "thin band")
	b._core_part.take_damage(3, 0)
	check_eq(b.hp, 120, "core part ignored while closed")
	b._gap_part.take_damage(3, 0)
	check_eq(b.hp, 117, "gap band damageable")
	# 實際的子彈：瞄準縫隙的會打中，偏 6 px 的被瓣膜擋下。
	for dy: float in [0.0, 6.0, -6.0]:
		var before := b.hp
		var bullet: Node2D = load("res://scenes/weapons/bullet.tscn").instantiate()
		bullet.position = b.global_position + Vector2(-60, dy)
		w.player_bullets.add_child(bullet)
		await physics_frames(20)
		check(not is_instance_valid(bullet), "bullet at dy=%d stopped by the boss" % dy)
		if dy == 0.0:
			check_eq(b.hp, before - 1, "bullet through the gap hits")
		else:
			check_eq(b.hp, before, "bullet at dy=%d blocked" % dy)
	# 張開時縫隙判定關掉，改用整個核心。
	_run(b, 1.0)
	check(b.valves_open)
	check(b._core_part.monitorable and not b._gap_part.monitorable)


func test_cycle_timings() -> void:
	var w := await _world()
	var b := _boss(w)
	var expect := [[1.9, true], [2.1, false], [3.9, false], [4.1, true], [5.9, true], [6.1, false]]
	var t := 0.0
	for e: Array in expect:
		var at: float = e[0]
		_run(b, at - t)
		t = at
		check_eq(b.valves_open, e[1], "phase 1 at %.1f s" % at)
	b.set_phase2()
	expect = [[1.9, true], [2.1, false], [2.9, false], [3.1, true], [4.9, true], [5.1, false], [6.1, true]]
	t = 0.0
	for e: Array in expect:
		var at: float = e[0]
		_run(b, at - t)
		t = at
		check_eq(b.valves_open, e[1], "phase 2 at %.1f s" % at)


func test_fan_counts_and_rate() -> void:
	var w := await _world()
	_fake_player(w, Vector2(64, 114))
	var b := _boss(w)
	_run(b, 0.35)
	check_eq(_count_bullets(w), 5, "5-way in phase 1")
	var from := b.global_position + Boss.MUZZLE
	var speeds_ok := true
	var aimed := false
	for n in w.enemy_bullets.get_children():
		var v: Vector2 = n.velocity
		speeds_ok = speeds_ok and absf(v.length() - Boss.FAN_SPEED) < 0.01
		if absf(v.angle_to(Vector2(64, 114) - from)) < 0.01:
			aimed = true
	check(speeds_ok, "bullet speed")
	check(aimed, "center bullet aimed at the player")
	_run(b, 1.0)
	check_eq(_count_bullets(w), 10, "1 volley per second")
	_run(b, 2.5)  # 閉合期間不發射
	check_eq(_count_bullets(w), 10, "no fan while closed")
	for n in w.enemy_bullets.get_children():
		n.free()
	b.set_phase2()
	_run(b, 0.35)
	check_eq(_count_bullets(w), 7, "7-way in phase 2")


func test_fan_respects_difficulty() -> void:
	var w := await _world()
	_fake_player(w, Vector2(64, 114))
	Game.difficulty = 2.0
	var b := _boss(w)
	_run(b, 1.95)
	# 0.3、0.8、1.3、1.8 秒各 1 輪。
	check_eq(_count_bullets(w), 20, "interval halved")
	var v: Vector2 = w.enemy_bullets.get_child(0).velocity
	check_near(v.length(), Boss.FAN_SPEED * 2.0, 0.01, "speed doubled")


func test_spores_while_closed_phase1() -> void:
	var w := await _world()
	_fake_player(w, Vector2(64, 114))
	var b := _boss(w)
	_run(b, 1.9)
	check_eq(_count_spores(w), 0, "none while open")
	_run(b, 2.0)
	check_eq(_count_spores(w), 4, "2 from each hole")
	var ys := {}
	for n in w.enemies.get_children():
		if n is Spore:
			ys[roundi(n.global_position.y)] = true
	check_eq(ys.size(), 2, "two holes")
	_run(b, 2.0)
	check_eq(_count_spores(w), 4, "none while open again")
	b.set_phase2()
	_run(b, 3.0)
	check_eq(_count_spores(w), 4, "no spores in phase 2")


func test_tentacle_strikes_every_6s() -> void:
	var w := await _world()
	var p := _fake_player(w, Vector2(120, 114))
	var b := _boss(w)
	_run(b, 10.0)
	check(b.tentacles[0] == null, "no tentacles in phase 1")
	b.set_phase2()
	_run(b, Boss.STRIKE_FIRST - 0.05)
	check(is_nan(b.last_strike_x), "not yet")
	_run(b, 0.1)
	check_eq(b.last_strike_x, 120.0, "aimed at the player's x")
	var top := b.tentacles[0]
	var bottom := b.tentacles[1]
	check(top != null and top.is_striking() and top.strike_state == Tentacle.Strike.WARN, "top warns first")
	check(bottom != null and bottom.is_striking(), "bottom strikes")
	check_eq(top.global_position, Vector2(120, 16), "from the ceiling surface")
	check_eq(bottom.global_position, Vector2(120, 200), "from the floor surface")
	# 預警 1 秒後伸出；伸到最長時上下兩條在中央重疊，正中間也躲不掉。
	_run(b, Tentacle.STRIKE_WARN + Tentacle.STRIKE_EXTEND + 0.05)
	check_eq(top.strike_state, Tentacle.Strike.HOLD)
	check(top.extension + bottom.extension >= 184.0, "covers the whole passage")
	# 橫移 24 px 就能躲開：所有的節都在瞄準的 x ±4 px 之內。
	for t in [top, bottom]:
		for seg: Area2D in t.segments:
			if seg.visible:
				check(absf(seg.global_position.x - 120.0) <= 4.0, "segment within ±4 px")
	# 下一次在 6 秒後，瞄準玩家那時的 x。
	p.position = Vector2(200, 114)
	_run(b, 6.0 - (Tentacle.STRIKE_WARN + Tentacle.STRIKE_EXTEND + 0.05) - 0.1)
	check_eq(b.last_strike_x, 120.0, "not before 6 s")
	_run(b, 0.1)
	check_eq(b.last_strike_x, 200.0, "6 s later at the new x")
	check_eq(top.global_position.x, 200.0)


func test_destroyed_tentacle_is_replaced() -> void:
	var w := await _world()
	_fake_player(w, Vector2(120, 114))
	var b := _boss(w)
	b.set_phase2()
	_run(b, Boss.STRIKE_FIRST + Tentacle.STRIKE_WARN + 0.2)
	var top := b.tentacles[0]
	top.root.take_damage(6, 0)
	check_eq(Game.scores[0], 500, "root worth 500")
	check(b.tentacles[0] == null, "forgotten")
	_run(b, Boss.STRIKE_INTERVAL)
	check(b.tentacles[0] != null and is_instance_valid(b.tentacles[0]), "new tentacle")
	check(b.tentacles[0] != top, "different node")
	check(b.tentacles[0].is_striking())


func test_time_limit_retreat() -> void:
	var w := await _world()
	var b := _boss(w)
	var got: Array[bool] = []
	b.finished.connect(func(d: bool) -> void: got.append(d))
	b.elapsed = Boss.TIME_LIMIT - 0.05
	_run(b, 0.1)
	check_eq(b.state, Boss.State.RETREAT, "retreats at the time limit")
	b._core_part.take_damage(10, 0)
	b._gap_part.take_damage(10, 0)
	check_eq(b.hp, 240, "invulnerable while retreating")
	check(got.is_empty(), "not finished yet")
	_run(b, Boss.RETREAT_TIME + DT)
	check(b.global_position.x > Boss.HOME.x + 100.0, "slid into the wall")
	check_eq(got, [false] as Array[bool], "finished(false) once")
	check_eq(Game.scores[0], 0, "no points")


func test_time_limit_counts_from_fight_start() -> void:
	var w := await _world()
	var b := _boss(w, false)
	_run(b, Boss.ENTER_TIME)
	check_near(b.elapsed, 0.0, 0.02, "entrance not counted")
	_run(b, 10.0)
	check_near(b.time_left(), Boss.TIME_LIMIT - 10.0, 0.05)


func test_defeat() -> void:
	var w := await _world()
	_fake_player(w, Vector2(64, 114))
	var b := _boss(w)
	var got: Array[bool] = []
	b.finished.connect(func(d: bool) -> void: got.append(d))
	b.set_phase2()
	_run(b, 0.5)
	check(_count_bullets(w) > 0, "some bullets on screen")
	b._core_part.take_damage(500, 0)
	check_eq(b.hp, 0)
	check_eq(b.state, Boss.State.DYING)
	check_eq(Game.scores[0], 10000, "10000 to the killer")
	check_eq(_count_bullets(w), 0, "enemy bullets cleared")
	b._core_part.take_damage(5, 0)
	check_eq(Game.scores[0], 10000, "only once")
	_run(b, DT)
	check(not b._body_hazard.monitorable, "dying boss is harmless")
	_run(b, 1.9 - DT)
	check(got.is_empty(), "explosions for 2 s first")
	check(not b._flash_layer.visible, "no flash yet")
	_run(b, 0.2)
	check(b._flash_layer.visible, "white flash")
	_run(b, Boss.DEFEAT_FLASH)
	check_eq(got, [true] as Array[bool], "finished(true)")
	check(not b._flash_layer.visible, "flash over")


func test_kill_through_both_phases() -> void:
	var w := await _world()
	var b := _boss(w)
	var hits := 0
	# 只在打得到的時候打：模擬持續射擊，每 0.1 秒 1 發瞄準縫隙／核心。
	for i in 3000:
		if b.state == Boss.State.DYING:
			break
		var part := b._gap_part if b.is_gap_vulnerable() else b._core_part
		if part.monitorable:
			part.take_damage(1, 0)
			hits += 1
		_run(b, 0.1)
	check_eq(b.state, Boss.State.DYING, "defeated")
	check_eq(hits, 240, "exactly 240 damage needed")


func _ensure_game_world_compiled() -> void:
	var s: GDScript = load("res://scripts/game/game_world.gd")
	if not s.can_instantiate():
		s.reload()
