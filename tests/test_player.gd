extends TestCase
## 玩家、武器、道具、僚機、護盾、死亡與復活（GDD 第 4 章）。
##
## 每個測試建一個完整的 GameWorld，但停掉 Stage 的物理處理（不捲動、不生成敵人），
## 需要地形時直接重建 Terrain。敵人一律用測試自己做的假目標。

const BEAM_SCENE := preload("res://scenes/weapons/beam.tscn")
const DRONE_ITEM_SCENE := preload("res://scenes/pickups/drone_item.tscn")


func after_each() -> void:
	Debug.god = false
	await super()


func _setup() -> Player:
	# 測試執行器以 -s 載入時，game_world.gd 會在 autoload 註冊前被編譯而失敗（找不到 Game），
	# 這裡在 autoload 就緒後重新編譯一次。
	var gw: GDScript = load("res://scripts/game/game_world.gd")
	if not gw.can_instantiate():
		gw.reload()
	var w := await make_world()
	w.stage.set_physics_process(false)
	var p: Player = w.players[0]
	p.external_input = true
	p.global_position = Vector2(64, 110)
	return p


## x 在 [x0, x1) 的欄位整欄（或只有天花板 ceil_rows 格）是實心地形。
func _wall(x0: int, x1: int, ceil_rows := Terrain.ROWS) -> void:
	Game.world.terrain().build([
		{x = 0, ceil = 0, floor = 0},
		{x = x0, ceil = 0, floor = 0},
		{x = x0, ceil = ceil_rows, floor = 0},
		{x = x1, ceil = ceil_rows, floor = 0},
		{x = x1, ceil = 0, floor = 0},
		{x = 1000, ceil = 0, floor = 0},
	], 1000)


## 有 take_damage() 的假目標，放在 layer 為 layer_bit 的層。
func _dummy(pos: Vector2, size: Vector2, layer_value := 8) -> Area2D:
	var s := GDScript.new()
	s.source_code = "extends Area2D\nvar hits := 0\nfunc take_damage(amount: int, _pid: int) -> void:\n\thits += amount\n"
	s.reload()
	var a := Area2D.new()
	a.set_script(s)
	a.collision_layer = layer_value
	a.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	a.add_child(shape)
	a.position = pos
	Game.world.enemies.add_child(a)
	return a


func test_movement_speed_and_cap() -> void:
	var p := await _setup()
	p.input_dir = Vector2(1, 0)
	await physics_frames(30)
	check_near(p.global_position.x, 64 + 45, 1.6, "90 px/s at level 0")
	p.input_dir = Vector2(-1, 1)
	var before := p.global_position
	await physics_frames(30)
	check_near(p.global_position.distance_to(before), 45, 1.6, "diagonal normalized")
	p.input_dir = Vector2.ZERO
	for i in 5:
		p.apply_powerup(&"speed")
	check_eq(p.speed_level, 5)
	check_near(p.move_speed(), 215, 0.01, "max speed")
	var score := Game.scores[0]
	p.apply_powerup(&"speed")
	check_eq(p.speed_level, 5, "capped")
	check_eq(Game.scores[0], score + 1000, "overflow gives 1000")


func test_playfield_clamp() -> void:
	var p := await _setup()
	p.input_dir = Vector2(-1, -1)
	await physics_frames(60)
	check(p.global_position.y >= Game.PLAYFIELD.position.y, "below HUD")
	check(p.global_position.x >= 0, "inside left edge")


func test_ring_beam_exclusive() -> void:
	var p := await _setup()
	check_eq(p.get_powerup_state().weapon, &"basic")
	p.apply_powerup(&"ring")
	check_eq(p.get_powerup_state().weapon, &"ring")
	p.apply_powerup(&"beam")
	check_eq(p.get_powerup_state().weapon, &"beam", "latest wins")
	var score := Game.scores[0]
	p.apply_powerup(&"beam")
	check_eq(Game.scores[0], score + 1000, "same weapon again is capped")
	p.apply_powerup(&"missile")
	p.apply_powerup(&"shield")
	var st := p.get_powerup_state()
	check(st.missile, "missile")
	check_eq(st.shield, 3, "shield")


func test_pickup_collected_by_touch() -> void:
	var p := await _setup()
	var changed := [0]
	p.powerup_changed.connect(func(): changed[0] += 1)
	Game.world.spawn_pickup(&"missile", p.global_position + Vector2(4, 0))
	await physics_frames(3)
	check(p.missile, "picked up missile")
	check(changed[0] > 0, "powerup_changed emitted")
	check_eq(Game.world.pickups.get_child_count(), 0, "pickup freed")


func test_pickup_drifts_left() -> void:
	await _setup()
	var item := Game.world.spawn_pickup(&"speed", Vector2(300, 50))
	await physics_frames(60)
	check_near(item.position.x, 270, 1.0, "30 px/s")


func test_drone_cap() -> void:
	var p := await _setup()
	for i in 4:
		p.apply_powerup(&"drone")
	check_eq(p.get_powerup_state().drones, 4)
	var score := Game.scores[0]
	p.apply_powerup(&"drone")
	check_eq(p.get_powerup_state().drones, 4, "capped at 4")
	check_eq(Game.scores[0], score + 1000)


func test_drone_trail() -> void:
	var p := await _setup()
	p.apply_powerup(&"drone")
	p.apply_powerup(&"drone")
	p.input_dir = Vector2(1, 0)
	await physics_frames(60)
	var ship := p.global_position
	var d := p.drones()
	# 90 px/s = 1.5 px/幀，落後 16 個記錄點 = 24 px。
	check_near(d[0].global_position.x, ship.x - 24, 0.01, "drone 0 spacing")
	check_near(d[1].global_position.x, ship.x - 48, 0.01, "drone 1 spacing")
	check_near(d[0].global_position.y, ship.y, 0.01)
	var d0 := d[0].global_position
	p.input_dir = Vector2.ZERO
	await physics_frames(30)
	check_eq(d[0].global_position, d0, "drones stop when ship stops")
	# 往下走：僚機先沿原本的水平軌跡走到轉角。
	p.input_dir = Vector2(0, 1)
	await physics_frames(8)
	check_near(d[0].global_position.y, ship.y, 0.01, "drone still on old path")
	check_near(d[0].global_position.x, ship.x - 12, 0.01)


func test_terrain_kills() -> void:
	var p := await _setup()
	_wall(200, 264)
	p.global_position = Vector2(180, 110)
	p.input_dir = Vector2(1, 0)
	await physics_frames(30)
	check(not p.is_alive(), "died on terrain")
	check_eq(Game.lives[0], 2)


func test_god_never_dies() -> void:
	Debug.god = true
	var p := await _setup()
	_wall(200, 264)
	p.global_position = Vector2(180, 110)
	p.input_dir = Vector2(1, 0)
	await physics_frames(30)
	check(p.is_alive(), "god survives terrain")
	check_eq(Game.lives[0], 3)
	var bullet := _dummy(p.global_position, Vector2(4, 4), 16)
	await physics_frames(3)
	check(p.is_alive(), "god survives bullets")
	bullet.queue_free()


func test_respawn_invulnerability() -> void:
	var p := await _setup()
	_wall(200, 264)
	p.apply_powerup(&"speed")
	p.apply_powerup(&"missile")
	p.global_position = Vector2(100, 110)
	p.die()
	check(not p.is_alive())
	var st := p.get_powerup_state()
	check_eq(st.speed, 0, "powerups reset")
	check(not st.missile, "missile reset")
	await physics_frames(30)
	check(not p.is_alive(), "still dead after 0.5 s")
	await physics_frames(35)
	check(p.is_alive(), "respawned after 1 s")
	check(p.is_invulnerable(), "invulnerable")
	check_near(p.global_position.x, 100, 0.01, "respawn in place")
	# 無敵中可以穿過地形，也不會被敵彈打死。
	p.global_position = Vector2(232, 110)
	var bullet := _dummy(p.global_position, Vector2(4, 4), 16)
	await physics_frames(60)
	check(p.is_alive(), "passes through terrain while invulnerable")
	bullet.queue_free()
	# 無敵結束時仍在地形內則死亡。
	await physics_frames(70)
	check(not p.is_alive(), "dies inside terrain when invulnerability ends")
	check_eq(Game.lives[0], 1)


func test_respawn_moves_out_of_terrain() -> void:
	var p := await _setup()
	# 這幾欄的天花板一直延伸到 y=160。
	_wall(200, 264, 20)
	Debug.god = false
	p.global_position = Vector2(232, 100)
	await physics_frames(2)
	check(not p.is_alive(), "died in ceiling")
	await physics_frames(65)
	check(p.is_alive(), "respawned")
	check_near(p.global_position.x, 232, 0.01, "same x")
	check(not Game.world.terrain().is_solid_rect(p.hitbox_rect()), "moved to open space")
	check(p.global_position.y > 160, "below the ceiling")


func test_out_of_lives() -> void:
	var p := await _setup()
	var gone := [false]
	p.out_of_lives.connect(func(): gone[0] = true)
	for i in 3:
		p.die()
		if i < 2:
			await physics_frames(62)
			check(p.is_alive(), "respawn %d" % i)
			p.invuln_time = 0.0
	check(gone[0], "out_of_lives emitted")
	await physics_frames(70)
	check(not p.is_alive(), "stays dead")


func test_drone_drop_and_recovery() -> void:
	var p := await _setup()
	p.apply_powerup(&"drone")
	p.apply_powerup(&"drone")
	p.global_position = Vector2(200, 110)
	p.die()
	await physics_frames(1)
	var items: Array[Node] = []
	for n in Game.world.pickups.get_children():
		if n is DroneItem:
			items.append(n)
	check_eq(items.size(), 2, "drones dropped")
	check_eq(p.get_powerup_state().drones, 0)
	var x0: float = (items[0] as Node2D).position.x
	await physics_frames(64)
	check(p.is_alive())
	check_near((items[0] as Node2D).position.x, x0 - 20.0 * 64 / 60.0, 1.0, "drifts 20 px/s")
	(items[0] as Node2D).global_position = p.global_position
	await physics_frames(3)
	check_eq(p.get_powerup_state().drones, 1, "recovered one drone")
	check(not is_instance_valid(items[0]) or items[0].is_queued_for_deletion(), "item consumed")
	# 5 秒後消失。
	var other: Node = items[1]
	other.set("_age", 4.9)
	await physics_frames(10)
	check(not is_instance_valid(other), "item expires after 5 s")


func test_shield_absorbs_bullet() -> void:
	var p := await _setup()
	p.apply_powerup(&"shield")
	await physics_frames(2)
	var bullet := _dummy(p.global_position + Vector2(18, 0), Vector2(4, 4), 16)
	Game.world.enemies.remove_child(bullet)
	Game.world.enemy_bullets.add_child(bullet)
	await physics_frames(3)
	check(not is_instance_valid(bullet), "bullet freed")
	check_eq(p.shield, 2, "shield -1")
	check(p.is_alive(), "player alive")
	# 敵人本體：扣 1 次，0.5 秒內不重複扣。
	var enemy := _dummy(p.global_position + Vector2(20, 0), Vector2(8, 8))
	await physics_frames(10)
	check_eq(p.shield, 1, "enemy contact -1 once")
	check_eq(enemy.get("hits"), 0, "shield does not damage enemy")
	await physics_frames(30)
	check_eq(p.shield, 0, "second contact after immunity")
	enemy.queue_free()


func test_basic_shot_limit() -> void:
	var p := await _setup()
	p.input_shoot = true
	var most := 0
	for i in 60:
		await physics_frames(1)
		most = maxi(most, Game.world.player_bullets.get_child_count())
	check_eq(most, 2, "at most 2 basic shots on screen")


func test_point_blank_fire_rate() -> void:
	var p := await _setup()
	var target := _dummy(p.global_position + Vector2(24, 0), Vector2(16, 16))
	p.input_shoot = true
	await physics_frames(60)
	var hits: int = target.get("hits")
	check(hits >= 5 and hits <= 7, "about 6 shots/s point blank, got %d" % hits)


func test_beam_damage_rate() -> void:
	await _setup()
	var target := _dummy(Vector2(140, 110), Vector2(16, 16))
	var beam: Beam = BEAM_SCENE.instantiate()
	beam.length = 60.0
	beam.speed = 0.0
	beam.position = Vector2(100, 110)
	Game.world.player_bullets.add_child(beam)
	await physics_frames(60)
	var hits: int = target.get("hits")
	check(hits == 15, "stationary beam: 1 damage per 4 frames over 1 s, got %d" % hits)


## 飛行中的光束掃過 16 px 的目標約造成 3 點（每個發射源約每秒 5 點的依據）。
func test_beam_damage_per_pass() -> void:
	await _setup()
	var target := _dummy(Vector2(240, 110), Vector2(16, 16))
	var beam: Beam = BEAM_SCENE.instantiate()
	beam.position = Vector2(100, 110)
	Game.world.player_bullets.add_child(beam)
	await physics_frames(60)
	var hits: int = target.get("hits")
	check(hits == 3, "one pass deals 3, got %d" % hits)


func test_beam_blocked_by_terrain() -> void:
	var p := await _setup()
	_wall(160, 224)
	p.apply_powerup(&"beam")
	p.global_position = Vector2(100, 110)
	p.input_shoot = true
	var longest := 0.0
	for i in 30:
		await physics_frames(1)
		for n in Game.world.player_bullets.get_children():
			if n is Beam:
				var b: Beam = n
				longest = maxf(longest, b.global_position.x + b.length)
	check(longest <= 160.5, "beam stops at terrain, head reached %s" % longest)
	check(longest > 150.0, "beam reached the wall")


func test_missiles_fire_in_pairs() -> void:
	var p := await _setup()
	p.apply_powerup(&"missile")
	p.input_shoot = true
	await physics_frames(4)
	check_eq(p.gun.missile_count(), 2, "one pair")
	var ys: Array[float] = []
	for n in Game.world.player_bullets.get_children():
		if n is Missile:
			ys.append((n as Node2D).global_position.y)
	check_eq(ys.size(), 2)
	if ys.size() == 2:
		check((ys[0] - 110) * (ys[1] - 110) < 0, "one up, one down: %s" % [ys])
