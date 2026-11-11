class_name SpawnRegistry
extends RefCounted
## 生成事件的 type 對應到哪個場景。
##
## attached 為 true 的敵人固定在地形上：加進 Stage.world，跟著地形捲動，位置是世界座標。
## attached 為 false 的敵人自由飛行：加進 GameWorld.enemies，位置是畫面座標。

const ENTRIES := {
	# &"type": {scene = "res://scenes/enemies/xxx.tscn", attached = false},
	&"worm_formation": {scene = "res://scenes/enemies/worm_formation.tscn", attached = false},
	&"spore": {scene = "res://scenes/enemies/spore.tscn", attached = false},
	&"turret": {scene = "res://scenes/enemies/turret.tscn", attached = true},
	&"charger": {scene = "res://scenes/enemies/charger.tscn", attached = false},
	&"growth_wall": {scene = "res://scenes/terrain/growth_wall.tscn", attached = true},
	&"tentacle": {scene = "res://scenes/terrain/tentacle.tscn", attached = true},
}
