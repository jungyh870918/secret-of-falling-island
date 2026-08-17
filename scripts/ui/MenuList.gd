class_name MenuList
extends Control
## 타이틀/일시정지/설정이 공유하는 목록 위젯.
##
## DOS 시절 메뉴처럼 테두리 한 겹, 선택 항목은 색 반전. (§6.5)
## §18 "마우스, 키보드, 게임패드 지원" — 셋 다 같은 인덱스를 움직인다.

signal activated(index: int)
signal adjusted(index: int, delta: int)   ## 좌우 키 / 값 변경
signal cancelled()

const PAD := 5

## 항목이 많은 화면(설정)에서는 낮춘다.
var row_h := 12
## 항목이 많아 행 높이가 빡빡할 때 한 단계 작은 폰트를 쓴다.
## (도트 폰트는 크기를 줄이면 뭉개지므로 '작은 폰트' 로 갈아탄다)
var dense := false
var title_key := ""
var rows: Array = []      ## [{label:String, value:String, enabled:bool}]
var selected := 0
var box := Rect2i(56, 26, 208, 128)
var footer_key := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(p_title_key: String, p_rows: Array, p_footer_key: String = "") -> void:
	title_key = p_title_key
	rows = p_rows
	footer_key = p_footer_key
	selected = _first_enabled()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func set_rows(p_rows: Array) -> void:
	rows = p_rows
	if selected >= rows.size():
		selected = maxi(0, rows.size() - 1)
	queue_redraw()


func move(delta: int) -> void:
	if rows.is_empty():
		return
	var i := selected
	for _n in rows.size():
		i = posmod(i + delta, rows.size())
		if bool(rows[i].get("enabled", true)):
			break
	selected = i
	AudioDirector.play_sfx("click")
	queue_redraw()


func activate() -> void:
	if rows.is_empty() or not bool(rows[selected].get("enabled", true)):
		return
	AudioDirector.play_sfx("click")
	activated.emit(selected)


func adjust(delta: int) -> void:
	if rows.is_empty():
		return
	AudioDirector.play_sfx("click")
	adjusted.emit(selected, delta)


func cancel() -> void:
	cancelled.emit()


func click_at(p: Vector2) -> bool:
	if not visible:
		return false
	for i in rows.size():
		if _row_rect(i).has_point(p):
			if not bool(rows[i].get("enabled", true)):
				return true
			selected = i
			activate()
			return true
	return Rect2(box).has_point(p)


func hover_at(p: Vector2) -> void:
	if not visible:
		return
	for i in rows.size():
		if _row_rect(i).has_point(p) and bool(rows[i].get("enabled", true)):
			if selected != i:
				selected = i
				queue_redraw()
			return


func _first_enabled() -> int:
	for i in rows.size():
		if bool(rows[i].get("enabled", true)):
			return i
	return 0


func _content_top() -> float:
	return box.position.y + (16 if not title_key.is_empty() else PAD)


func _row_rect(i: int) -> Rect2:
	return Rect2(box.position.x + PAD, _content_top() + row_h * i, box.size.x - PAD * 2, row_h)


func _draw() -> void:
	if not visible:
		return
	var font := Theming.small_font if dense else Theming.base_font
	var size := Theming.small_font_size() if dense else Theming.font_size()

	# 화면 전체를 살짝 덮어 뒤가 읽히지 않게 한다.
	draw_rect(Rect2(0, 0, Layout.UI_SIZE.x, Layout.UI_SIZE.y), Color(0, 0, 0, 0.55), true)

	draw_rect(Rect2(box), Palette.ui("panel"), true)
	draw_rect(Rect2(box), Palette.ui("outline"), false, 1.0)
	draw_rect(Rect2(box).grow(-1), Palette.ui("panel_light"), false, 1.0)

	if not title_key.is_empty():
		var tf := Theming.base_font
		var ts := Theming.font_size()
		var t := Loc.t(title_key)
		var tw := tf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		draw_string(tf, Vector2(roundf(box.position.x + (box.size.x - tw) / 2.0),
			box.position.y + 3 + tf.get_ascent(ts)),
			t, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Palette.ui("text_hot"))
		draw_line(Vector2(box.position.x + 3, box.position.y + 14),
			Vector2(box.position.x + box.size.x - 3, box.position.y + 14),
			Palette.ui("panel_light"), 1.0)

	for i in rows.size():
		var row: Dictionary = rows[i]
		var r := _row_rect(i)
		var enabled := bool(row.get("enabled", true))
		var is_sel := i == selected and enabled

		if is_sel:
			draw_rect(r, Palette.ui("select"), true)

		var col := Palette.ui("text")
		if not enabled:
			col = Palette.ui("text_dim")
		elif is_sel:
			col = Palette.ui("text_hot")

		var y := roundf(r.position.y + font.get_ascent(size) + 1)
		draw_string(font, Vector2(r.position.x + 3, y), str(row.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x * 0.62), size, col)

		var value := str(row.get("value", ""))
		if not value.is_empty():
			var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_string(font, Vector2(r.position.x + r.size.x - 3 - vw, y), value,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

	if not footer_key.is_empty():
		var f := Loc.t(footer_key)
		draw_string(Theming.small_font, Vector2(box.position.x + PAD, box.position.y + box.size.y - 4),
			f, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - PAD * 2,
			Theming.small_font_size(), Palette.ui("text_dim"))
