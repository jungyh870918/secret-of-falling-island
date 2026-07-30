class_name GameCursor
extends Control
## 커서. 명세서 §5.3.
##
## OS 커서를 숨기고 320×180 격자에 딱 맞는 십자 커서를 직접 그린다.
## 핫스폿 위에서는 색이 반전되어(§6.5) 상호작용 가능함을 알린다.

var pos := Vector2.ZERO
var over_hotspot := false
var held_item := ""

var _time := 0.0
var _drew_hot := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_process(true)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	_time += delta
	var p := get_viewport().get_mouse_position().round()
	if p != pos or over_hotspot != _drew_hot:
		pos = p
		queue_redraw()


func _draw() -> void:
	# 점멸 없음. 핫스폿 위에서는 색이 바뀌고 십자가 조여든다 — 즉각적으로 읽힌다.
	_drew_hot = over_hotspot
	var c := Palette.ui("text_hot") if over_hotspot else Palette.ui("text")
	var gap := 1 if over_hotspot else 2

	# 십자 — 가운데는 비워서 대상이 가려지지 않게 한다.
	draw_rect(Rect2(pos.x - gap - 3, pos.y, 3, 1), c, true)
	draw_rect(Rect2(pos.x + gap, pos.y, 3, 1), c, true)
	draw_rect(Rect2(pos.x, pos.y - gap - 3, 1, 3), c, true)
	draw_rect(Rect2(pos.x, pos.y + gap, 1, 3), c, true)
	if over_hotspot:
		draw_rect(Rect2(pos.x - 1, pos.y - 1, 3, 3), Palette.ui("outline"), false, 1.0)

	# 아이템을 들고 있으면 커서 옆에 색 블록을 붙인다.
	if not held_item.is_empty():
		var item := GameData.item(held_item)
		var col := Palette.parse(item.get("icon_color", "#8c3327"))
		draw_rect(Rect2(pos.x + 3, pos.y + 3, 6, 5), Palette.ui("outline"), true)
		draw_rect(Rect2(pos.x + 4, pos.y + 4, 4, 3), col, true)
