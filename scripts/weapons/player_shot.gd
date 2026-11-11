class_name PlayerShot
extends Area2D
## 玩家子彈的共用部分：player_bullet 層（3）、偵測 enemy 層（4）。
##
## 子類別在 _physics_process 裡自己移動、自己查地形（Terrain.hit），
## 碰到敵人時呼叫 _hit_enemy()，由敵人的 take_damage() 扣血。

## 離開畫面多遠之後回收。
const OFF_SCREEN_MARGIN := 16.0

## 得分記給誰。
var player_id := 0
var damage := 1
var velocity := Vector2.ZERO


## 對碰到的 Area2D 造成傷害。對方沒有 take_damage() 時不做事。
func _hit_enemy(area: Area2D) -> void:
	if area.has_method("take_damage"):
		area.take_damage(damage, player_id)


func _is_off_screen(margin := OFF_SCREEN_MARGIN) -> bool:
	var p := global_position
	return p.x < -margin or p.x > Game.SCREEN_SIZE.x + margin \
			or p.y < -margin or p.y > Game.SCREEN_SIZE.y + margin


## 目前關卡的地形；沒有 GameWorld 時（單獨測試）回傳 null。
func _terrain() -> Terrain:
	if Game.world == null or Game.world.stage == null:
		return null
	return Game.world.terrain()
