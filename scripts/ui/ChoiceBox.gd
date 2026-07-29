class_name ChoiceBox
extends Control
## 대화 선택지. 명세서 §5.4 "화면 하단에 최대 4개의 선택지를 표시한다".
##
## §13.1 "대화 선택지는 모두 최소한 한 번은 읽을 가치가 있어야 함" — UI 는 4개를 다 보여준다.
## 이미 고른 선택지는 흐리게 표시해 반복 플레이 시 탐색을 돕는다.

const ROW_H := 10
const PAD_X := 4

var _options: Array = []      ## [{text:String, seen:bool}]
var _selected := 0
var _active := false
var _result := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func is_active() -> bool:
	return _active


## 선택지를 띄우고 고를 때까지 기다린다. 반환값은 인덱스. (코루틴)
func present(options: Array) -> int:
	_options = options
	_selected = 0
	_result = -1
	_active = true
	visible = true
	queue_redraw()
	while _active:
		await get_tree().process_frame
	visible = false
	return _result


func move_selection(delta: int) -> void:
	if not _active or _options.is_empty():
		return
	_selected = posmod(_selected + delta, _options.size())
	AudioDirector.play_sfx("click")
	queue_redraw()


func confirm() -> void:
	if not _active or _options.is_empty():
		return
	_result = _selected
	_active = false
	AudioDirector.play_sfx("click")


## 숫자키 직접 선택.
func select_index(i: int) -> void:
	if not _active or i < 0 or i >= _options.size():
		return
	_selected = i
	confirm()


func select_at(point: Vector2) -> bool:
	if not _active:
		return false
	for i in _options.size():
		if _row_rect(i).has_point(point):
			_selected = i
			confirm()
			return true
	return false


func hover_at(point: Vector2) -> void:
	if not _active:
		return
	for i in _options.size():
		if _row_rect(i).has_point(point):
			if _selected != i:
				_selected = i
				queue_redraw()
			return


func _row_rect(i: int) -> Rect2:
	var total: int = _options.size()
	var block_h := ROW_H * total
	var top: float = Layout.CHOICE_RECT.position.y + (Layout.CHOICE_RECT.size.y - block_h) / 2.0
	return Rect2(Layout.CHOICE_RECT.position.x, top + ROW_H * i, Layout.CHOICE_RECT.size.x, ROW_H)


func _draw() -> void:
	if not _active:
		return
	var font := Theming.base_font
	var size := Theming.font_size()

	draw_rect(Rect2(Layout.CHOICE_RECT), Palette.ui("panel_dark"), true)
	draw_rect(Rect2(Layout.CHOICE_RECT), Palette.ui("outline"), false, 1.0)

	for i in _options.size():
		var o: Dictionary = _options[i]
		var r := _row_rect(i)
		var is_sel := i == _selected
		if is_sel:
			# §6.5 발광 대신 색 반전
			draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 1)), Palette.ui("select"), true)

		var text_col := Palette.ui("text")
		if bool(o.get("seen", false)) and not is_sel:
			text_col = Palette.ui("text_dim")
		if is_sel:
			text_col = Palette.ui("text_hot")

		var num := "%d." % (i + 1)
		var base := Vector2(r.position.x + PAD_X, r.position.y + font.get_ascent(size) - 1)
		draw_string(font, base, num, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_dim"))
		draw_string(font, base + Vector2(12, 0), str(o.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x - 18), size, text_col)
