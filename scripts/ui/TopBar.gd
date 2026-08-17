class_name TopBar
extends Control
## §05 Interaction 층 — 세로 셸의 상단 바.
##
## 목업 `01_explore` 를 재서 옮겼다. 941 캔버스에서 높이 146, 양 끝에 104×104 버튼,
## 가운데에 「CH.1 황소항」. UI 좌표(÷3)로는 높이 49, 버튼 35×35.
##
## **전부 코드가 그린다.** 배경과 같은 자리표시자 규칙이다 —
## `assets/ui/topbar.png` 를 넣으면 코드 대신 그 그림을 쓴다. (§21)
##
## 목업의 오른쪽은 «수첩» 버튼이지만 수첩 화면이 아직 없다.
## 대신 있는 것(대화 기록)을 건다. 없는 문을 그려 두지 않는다.

signal menu_pressed
signal log_pressed

const BG_PATH := "res://assets/ui/topbar.png"

## 모서리 깎기 — §06 v2.2 「반경 0. 다만 1~2 게임픽셀 계단형 깎기는 허용」
const CHAMFER := 2
const BTN := 35
const BTN_MARGIN := 6

var _bg: Texture2D = null
var _hover := -1        # 0 메뉴 · 1 기록

var chapter_label := "CH.1"

var _drawn_scene := ""


func _init() -> void:
	name = "TopBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(BG_PATH):
		var res := load(BG_PATH)
		if res is Texture2D:
			_bg = res


func _ready() -> void:
	Theming.font_size_changed.connect(func(_px): queue_redraw())
	set_process(true)


## 장면 이름은 GameState 를 그때그때 읽는다. 바뀌었을 때만 다시 그린다
func _process(_delta: float) -> void:
	if GameState.scene_id != _drawn_scene:
		_drawn_scene = GameState.scene_id
		queue_redraw()


func menu_rect() -> Rect2:
	return Rect2(BTN_MARGIN, BTN_MARGIN, BTN, BTN)


func log_rect() -> Rect2:
	return Rect2(Layout.UI_SIZE.x - BTN - BTN_MARGIN, BTN_MARGIN, BTN, BTN)


func handles_point(p: Vector2) -> bool:
	return p.y < Layout.UI_TOPBAR_RECT.size.y


## 화면이 아니라 UI 좌표를 받는다. 눌린 버튼이 있으면 true.
func click(p: Vector2) -> bool:
	if menu_rect().has_point(p):
		menu_pressed.emit()
		return true
	if log_rect().has_point(p):
		log_pressed.emit()
		return true
	return false


func hover(p: Vector2) -> void:
	var h := -1
	if menu_rect().has_point(p):
		h = 0
	elif log_rect().has_point(p):
		h = 1
	if h != _hover:
		_hover = h
		queue_redraw()


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	var r := Rect2(Layout.UI_TOPBAR_RECT)
	if _bg != null:
		draw_texture_rect(_bg, r, false)
	else:
		draw_rect(r, Palette.ui("panel"), true)
		# 월드와의 경계선 — 1 게임픽셀
		draw_line(Vector2(0, r.size.y - 1), Vector2(r.size.x, r.size.y - 1),
			Palette.ui("outline"), 1.0)

	_draw_button(menu_rect(), _hover == 0)
	_draw_hamburger(menu_rect())
	_draw_button(log_rect(), _hover == 1)
	_draw_book(log_rect())
	_draw_title()


## 모서리를 깎은 사각 테두리. 곡선이 아니라 계단이다
func _draw_button(r: Rect2, hot: bool) -> void:
	var c: Color = Palette.ui("text_hot") if hot else Palette.ui("outline")
	var c2 := CHAMFER
	var pts := PackedVector2Array([
		Vector2(r.position.x + c2, r.position.y),
		Vector2(r.end.x - c2, r.position.y),
		Vector2(r.end.x, r.position.y + c2),
		Vector2(r.end.x, r.end.y - c2),
		Vector2(r.end.x - c2, r.end.y),
		Vector2(r.position.x + c2, r.end.y),
		Vector2(r.position.x, r.end.y - c2),
		Vector2(r.position.x, r.position.y + c2),
		Vector2(r.position.x + c2, r.position.y)])
	draw_polyline(pts, c, 1.0)


func _draw_hamburger(r: Rect2) -> void:
	var c := Palette.ui("text")
	var w := r.size.x * 0.52
	var x := r.position.x + (r.size.x - w) / 2.0
	for i in 3:
		var y := roundf(r.position.y + r.size.y * (0.32 + 0.18 * i))
		draw_rect(Rect2(x, y, w, 2), c, true)


## 수첩이 아니라 «대화 기록». 링 노트 실루엣만 세운다
func _draw_book(r: Rect2) -> void:
	var c := Palette.ui("text")
	var inner := Rect2(r.position + r.size * 0.26, r.size * 0.48)
	draw_rect(inner, c, false, 1.0)
	for i in 3:
		var y := roundf(inner.position.y + inner.size.y * (0.22 + 0.28 * i))
		draw_rect(Rect2(inner.position.x + 2, y, inner.size.x - 4, 1), c, true)


func _draw_title() -> void:
	var font: Font = Theming.base_font
	var size := Theming.font_size()
	if font == null:
		return
	var place := Loc.t(str(GameData.scene(GameState.scene_id).get("name_key", "")))
	var y := roundf((Layout.UI_TOPBAR_RECT.size.y + font.get_ascent(size)) / 2.0) - 2

	var ch_w: float = font.get_string_size(chapter_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap := float(size)
	var pl_w: float = font.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := roundf((Layout.UI_SIZE.x - (ch_w + gap + pl_w)) / 2.0)

	draw_string(font, Vector2(x, y), chapter_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Palette.ui("text_hot"))
	draw_string(font, Vector2(x + ch_w + gap, y), place, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Palette.ui("text"))
