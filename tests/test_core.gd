extends TestCase
## 核心框架：捲動、地形查詢、分數與加命。


func test_terrain_profile_and_queries() -> void:
	var t := Terrain.new()
	add(t)
	t.build([
		{x = 0, ceil = 0, floor = 0},
		{x = 80, ceil = 4, floor = 3},
		{x = 400, ceil = 4, floor = 3, theme = "flesh"},
	], 400)
	check(not t.is_solid_at(Vector2(4, 4)), "open area at x=0")
	# x=200 落在 80 之後，天花板 4 格（0–31 px）、地面 3 格（192–215 px）。
	check(t.is_solid_at(Vector2(200, 31)), "ceiling bottom row")
	check(not t.is_solid_at(Vector2(200, 32)), "just below ceiling")
	check(t.is_solid_at(Vector2(200, 192)), "floor top row")
	check(not t.is_solid_at(Vector2(200, 191)), "just above floor")
	check_eq(t.passage_at(200), Vector2(32, 192), "passage")
	check(t.is_solid_rect(Rect2(196, 28, 6, 4)), "rect overlapping ceiling")
	check(not t.is_solid_rect(Rect2(196, 100, 6, 4)), "rect in passage")


func test_terrain_follows_scroll() -> void:
	var t := Terrain.new()
	add(t)
	t.build([{x = 0, ceil = 0, floor = 0}, {x = 100, ceil = 5, floor = 0}, {x = 200, ceil = 5, floor = 0}], 200)
	check(t.is_solid_at(Vector2(150, 8)))
	t.position.x = -100
	check(t.is_solid_at(Vector2(50, 8)), "moved with node")
	check(not t.is_solid_at(Vector2(-110, 8)), "left of start")


func test_score_extends() -> void:
	Game.reset_run()
	Game.add_score(0, 29999)
	check_eq(Game.lives[0], 3)
	Game.add_score(0, 1)
	check_eq(Game.lives[0], 4, "first extend at 30000")
	Game.add_score(0, 70000)
	check_eq(Game.lives[0], 5, "second extend at 100000")
	Game.reset_run()


func test_stage_scrolls_and_ends() -> void:
	var s := Stage.new()
	var data := StageData.new()
	data.length = 30.0
	data.terrain_profile = [{x = 0, ceil = 0, floor = 0}]
	s.setup(data)
	add(s)
	var ended := [false]
	s.end_reached.connect(func(): ended[0] = true)
	await physics_frames(30)
	check_near(s.scroll_x, 15.0, 1.0, "scroll after 0.5 s")
	await physics_frames(40)
	check(ended[0], "end reached")
	check_eq(s.scroll_x, 30.0)
	check(not s.scrolling)
