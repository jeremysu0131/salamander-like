class_name Autopilot
extends RefCounted
## 自動駕駛（Debug.autopilot）：取代玩家輸入的簡單機器人，用來搭配 --god 跑完整關。
##
## - 一直射擊。
## - 往前方通道的垂直中央靠；前方被增生壁之類擋住時，找那一欄最近的空隙。
## - 閃開附近的敵彈與敵人。
## - 水平位置維持在 x 60–140 附近。
## 不求打得好，只求不要一直卡在地形裡。

const MIN_X := 60.0
const MAX_X := 140.0
const HOME_X := 96.0
## 看前方多遠的通道。
const LOOKAHEAD: Array[float] = [0.0, 24.0, 48.0, 72.0]
## 檢查前方有沒有被擋住的距離。
const BLOCK_CHECK_X := 32.0
const BULLET_RADIUS := 40.0
const ENEMY_RADIUS := 44.0
## 方向分量小於這個值（px）就不動，避免在目標附近抖動。
const DEADZONE := 3.0


## 回傳這一幀的移動方向（各分量為 -1、0、1）。
func steer(player: Player) -> Vector2:
	if Game.world == null or Game.world.stage == null:
		return Vector2.ZERO
	var t := Game.world.terrain()
	var pos := player.global_position
	var target := Vector2(HOME_X, _target_y(t, pos))
	var want := target - pos
	var danger := _danger(pos)
	want += danger * 60.0
	if pos.x < MIN_X:
		want.x = maxf(want.x, DEADZONE + 1.0)
	elif pos.x > MAX_X:
		want.x = minf(want.x, -DEADZONE - 1.0)
	var dir := Vector2(_axis(want.x), _axis(want.y))
	# 不要自己飛進地形：先試完整方向，不行就只保留一個分量。
	if player.is_invulnerable():
		return dir
	var step := player.move_speed() * 0.12
	for cand: Vector2 in [dir, Vector2(0, dir.y), Vector2(dir.x, 0), Vector2.ZERO]:
		if not t.is_solid_rect(Rect2(pos + cand * step - Vector2(5, 4), Vector2(10, 8))):
			return cand
	return dir


func _axis(v: float) -> float:
	if v > DEADZONE:
		return 1.0
	if v < -DEADZONE:
		return -1.0
	return 0.0


## 前方通道的中央 y；前方被擋住時改為那一欄最近的空隙。
func _target_y(t: Terrain, pos: Vector2) -> float:
	var top := Game.PLAYFIELD.position.y
	var bottom := Game.PLAYFIELD.end.y
	for dx in LOOKAHEAD:
		var p := t.passage_at(pos.x + dx)
		top = maxf(top, p.x)
		bottom = minf(bottom, p.y)
	var center := (top + bottom) / 2.0
	if bottom - top < 16.0:
		# 通道在前方急轉，只看眼前這一欄。
		var p := t.passage_at(pos.x + LOOKAHEAD[1])
		center = (p.x + p.y) / 2.0
	# 增生壁之類不在 passage_at 裡的地形：找前方那一欄最接近目前高度的空隙。
	var ahead_x := pos.x + BLOCK_CHECK_X
	if t.is_solid_rect(Rect2(Vector2(pos.x, pos.y - 5), Vector2(BLOCK_CHECK_X, 10))):
		var best := center
		var best_d := INF
		var y := Game.PLAYFIELD.position.y + 8.0
		while y < Game.PLAYFIELD.end.y - 8.0:
			if not t.is_solid_rect(Rect2(Vector2(ahead_x - 4, y - 6), Vector2(8, 12))):
				var d := absf(y - pos.y)
				if d < best_d:
					best_d = d
					best = y
			y += 4.0
		return best
	return center


## 附近敵彈與敵人的推力（離得越近越強）。
func _danger(pos: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for n in Game.world.enemy_bullets.get_children():
		var b := n as Node2D
		if b == null:
			continue
		var rel := pos - b.global_position
		var d := rel.length()
		if d >= BULLET_RADIUS or d < 0.01:
			continue
		var v: Vector2 = b.get("velocity") if "velocity" in b else Vector2.ZERO
		if v != Vector2.ZERO and rel.dot(v) < 0.0:
			continue  # 已經飛過去了
		# 往子彈行進方向的垂直方向閃。
		var away := rel.normalized()
		if v != Vector2.ZERO:
			var perp := Vector2(-v.y, v.x).normalized()
			away = perp if perp.dot(rel) >= 0.0 else -perp
		push += away * (1.0 - d / BULLET_RADIUS)
	for n in Game.world.enemies.get_children():
		var e := n as Node2D
		if e == null:
			continue
		var rel := pos - e.global_position
		var d := rel.length()
		if d >= ENEMY_RADIUS or d < 0.01:
			continue
		push += rel.normalized() * (1.0 - d / ENEMY_RADIUS)
	return push
