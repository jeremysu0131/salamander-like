extends RefCounted
## UI 共用的顏色與小工具。顏色一律取自 Endesga 32 色盤（見 tools/art_common.py）。
##
## 字型是 5×7 點陣字（assets/fonts/pixel.fnt），每字寬 6 px、行高 8 px，
## 由 assets/ui/theme.tres 設成預設字型、字級 8。位置一律用整數，字不縮放，才會清晰。
##
## 不註冊 class_name，使用端以 preload 取用，避免依賴編輯器的全域類別快取。

const THEME := preload("res://assets/ui/theme.tres")
const ICONS := preload("res://assets/sprites/hud_icons.png")

## hud_icons.png 的幀順序。
enum Icon { SPEED, MISSILE, RING, BEAM, DRONE, SHIELD, LIFE }

const GLYPH_W := 6
const GLYPH_H := 7

const WHITE := Color("ffffff")
const CREAM := Color("ead4aa")
const LGREY := Color("c0cbdc")
const GREY := Color("8b9bb4")
const SLATE := Color("5a6988")
const DSLATE := Color("3a4466")
const BLACK := Color("181425")
const CYAN := Color("2ce8f5")
const BLUE := Color("0099db")
const RED := Color("e43b44")
const PINK := Color("f6757a")
const GREEN := Color("63c74d")

## 未持有的圖示與數字：乘上這個顏色變暗。
const DIM := Color(0.38, 0.4, 0.55, 1.0)


## 在 (x, y) 建立一個點陣字 Label。y 是字形頂端。
static func make_label(parent: Node, text: String, x: int, y: int, color := WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 以 cx 為中心擺放一行字（左緣對齊到整數像素）。
static func make_centered_label(parent: Node, text: String, cx: int, y: int, color := WHITE) -> Label:
	return make_label(parent, text, cx - text_width(text) / 2, y, color)


## 文字的像素寬度（不含最後一字右側的 1 px 空白）。
static func text_width(text: String) -> int:
	return maxi(text.length() * GLYPH_W - 1, 0)


## hud_icons.png 的一格（8×8）。
static func make_icon(parent: Node, icon: Icon, x: int, y: int) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = ICONS
	atlas.region = Rect2(icon * 8, 0, 8, 8)
	var t := TextureRect.new()
	t.texture = atlas
	t.position = Vector2(x, y)
	t.size = Vector2(8, 8)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


## 分數固定 6 位數補零。
static func format_score(score: int) -> String:
	return "%06d" % score
