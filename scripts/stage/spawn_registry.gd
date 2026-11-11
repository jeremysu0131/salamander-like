class_name SpawnRegistry
extends RefCounted
## 生成事件的 type 對應到哪個場景。
##
## attached 為 true 的敵人固定在地形上：加進 Stage.world，跟著地形捲動，位置是世界座標。
## attached 為 false 的敵人自由飛行：加進 GameWorld.enemies，位置是畫面座標。

const ENTRIES := {
	# &"type": {scene = "res://scenes/enemies/xxx.tscn", attached = false},
}
