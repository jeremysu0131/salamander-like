class_name StageData
extends RefCounted
## 一個關卡的資料：長度、地形輪廓、生成事件。關卡內容寫在繼承這個類別的腳本裡。

## 捲動到這個距離時停止捲動並進入 Boss 戰。
var length := 6300.0

## 地形輪廓關鍵點，格式見 Terrain.build()。依 x 遞增排列。
var terrain_profile: Array[Dictionary] = []

## 生成事件，依 x 遞增排列。每個事件至少有：
##   x: 世界座標 x（像素）。捲動到這個位置進入畫面右緣外 16 px 時生成
##   y: 畫面座標 y
##   type: 敵人種類，見 SpawnRegistry.ENTRIES
## 其餘欄位原封不動傳給敵人的 setup(params)，例如 red、drop、ceiling。
var spawns: Array[Dictionary] = []
