extends StageData
## 第 1 關：活體小行星・內腔（GDD 第 6 章）。
##
## 暫代版本：只有地形輪廓，沒有敵人。正式內容在 M4 填入。


func _init() -> void:
	length = 6300.0
	terrain_profile = [
		{x = 0, ceil = 0, floor = 0, theme = "rock"},
		{x = 900, ceil = 0, floor = 0, theme = "rock"},
		{x = 1000, ceil = 4, floor = 4, theme = "rock", rough = 1},
		{x = 1950, ceil = 5, floor = 5, theme = "flesh", rough = 1},
		{x = 3150, ceil = 2, floor = 2, theme = "flesh", rough = 1},
		{x = 3600, ceil = 7, floor = 7, theme = "flesh", rough = 1},
		{x = 6000, ceil = 2, floor = 2, theme = "flesh", rough = 0},
		{x = 6700, ceil = 2, floor = 2, theme = "flesh", rough = 0},
	]
