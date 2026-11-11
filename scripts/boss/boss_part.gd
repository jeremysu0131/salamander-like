class_name BossPart
extends Area2D
## Boss 可被子彈打中的部位（enemy 層，第 4 層）：核心、第二階段的縫隙判定帶、擋子彈的外殼。
##
## 本身不扣血，只把命中轉給 Boss（訊號 hit），由 Boss 依目前狀態決定要不要算傷害。
## 外殼部位的命中 Boss 一律忽略，用途只是讓子彈打在瓣膜與肉壁上消失，而不是穿過去。

signal hit(part: BossPart, amount: int, player_id: int)

const LAYER_ENEMY := 1 << 3


func _init() -> void:
	collision_layer = LAYER_ENEMY
	collision_mask = 0
	monitoring = false


## 加一個矩形判定（rect 為相對於這個節點的座標）。
func add_rect(rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = rect.get_center()
	add_child(cs)


## 玩家子彈呼叫（ARCHITECTURE.md 的敵人介面）。
func take_damage(amount: int, player_id: int) -> void:
	hit.emit(self, amount, player_id)
