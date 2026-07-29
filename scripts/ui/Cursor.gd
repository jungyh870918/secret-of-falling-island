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
	if p != pos:
		pos = p
		queue_redraw()
	elif over_hotspot:
		queue_redraw()


func _draw() -> void:
	var c := Palette.ui("text")
	if over_hotspot:
		c = Palette.ui("text_hot") if fposmod(_time, 0.5) < 0.25 else Palette.ui("text")

	# 십자 — 가운데 1px 은 비워서 대상이 가려지지 않게 한다.
	draw_rect(Rect2(pos.x - 4, pos.y, 3, 1), c, true)
	draw_rect(Rect2(pos.x + 2, pos.y, 3, 1), c, true)
	draw_rect(Rect2(pos.x, pos.y - 4, 1, 3), c, true)
	draw_rect(Rect2(pos.x, pos.y + 2, 1, 3), c, true)

	# 아이템을 들고 있으면 커서 옆에 색 블록을 붙인다.
	if not held_item.is_empty():
		var item := GameData.item(held_item)
		var col := Palette.parse(item.get("icon_color", "#8c3327"))
		draw_rect(Rect2(pos.x + 3, pos.y + 3, 6, 5), Palette.ui("outline"), true)
		draw_rect(Rect2(pos.x + 4, pos.y + 4, 4, 3), col, true)
