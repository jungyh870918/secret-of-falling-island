class_name CommandPanel
extends Control
## 하단 25% 명령 패널. 명세서 §5.1, §5.2, §5.3, §10.
##
##   [문장 라인]  사용하다 → 금속 자 → 금이 간 지지선
##   [동사 8개]                        [인벤토리 16칸]
##
## §5.2 설정에서 '고전 동사 UI'(8개)와 '간소화 UI'(4개)를 고를 수 있다.
##
## [최종 에셋 교체 지점]
##   아이템 아이콘: res://assets/ui/items/<item_id>.png (16x16)
##   패널 배경:     res://assets/ui/command_panel.png (320x45)

signal verb_selected(verb: int)
signal item_selected(item_id: String)
signal item_examined(item_id: String)
signal hint_requested()

const ICON_DIR := "res://assets/ui/items"
const PANEL_BG := "res://assets/ui/command_panel.png"
const HINT_RECT := Rect2i(3, 136, 10, 10)

var sentence := ""
var current_verb: int = Actions.Verb.LOOK
var held_item := ""

var _hover_verb := -1
var _hover_slot := -1
var _scroll := 0
var _icon_cache: Dictionary = {}
var _panel_bg: Texture2D = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PANEL_BG):
		var t := ResourceLoader.load(PANEL_BG)
		if t is Texture2D:
			_panel_bg = t
	GameState.inventory_changed.connect(_on_inventory_changed)
	set_process(false)


func _on_inventory_changed() -> void:
	_clamp_scroll()
	queue_redraw()


func is_simple_ui() -> bool:
	return str(SaveManager.get_setting("verb_ui", "classic")) == "simple"


func verb_layout() -> Array:
	return Actions.SIMPLE_LAYOUT if is_simple_ui() else Actions.CLASSIC_LAYOUT


func set_sentence(s: String) -> void:
	if sentence == s:
		return
	sentence = s
	queue_redraw()


func set_verb(v: int) -> void:
	current_verb = v
	queue_redraw()


func set_held_item(id: String) -> void:
	held_item = id
	queue_redraw()


# ---------------------------------------------------------------- 입력

func handles_point(p: Vector2) -> bool:
	return p.y >= Layout.PANEL_Y


## 좌클릭. 처리했으면 true.
func click(p: Vector2, right: bool = false) -> bool:
	if not handles_point(p):
		return false

	if Rect2(HINT_RECT).has_point(p):
		hint_requested.emit()
		AudioDirector.play_sfx("click")
		return true

	var layout := verb_layout()
	for i in layout.size():
		if Rect2(Layout.verb_cell_rect(i)).has_point(p):
			verb_selected.emit(layout[i])
			AudioDirector.play_sfx("click")
			return true

	if _scroll_up_rect().has_point(p):
		_scroll = maxi(0, _scroll - Layout.INV_COLS)
		queue_redraw()
		return true
	if _scroll_down_rect().has_point(p):
		_scroll = mini(maxi(0, GameState.inventory.size() - Layout.INV_VISIBLE), _scroll + Layout.INV_COLS)
		queue_redraw()
		return true

	var slot := slot_at(p)
	if slot >= 0:
		var idx := _scroll + slot
		if idx < GameState.inventory.size():
			var id: String = GameState.inventory[idx]
			if right:
				item_examined.emit(id)
			else:
				item_selected.emit(id)
			AudioDirector.play_sfx("click")
			return true

	return true  # 패널 영역 클릭은 장면으로 흘려보내지 않는다.


func hover(p: Vector2) -> void:
	var hv := -1
	var hs := -1
	if handles_point(p):
		var layout := verb_layout()
		for i in layout.size():
			if Rect2(Layout.verb_cell_rect(i)).has_point(p):
				hv = i
				break
		hs = slot_at(p)
	if hv != _hover_verb or hs != _hover_slot:
		_hover_verb = hv
		_hover_slot = hs
		queue_redraw()


func hovered_item_id() -> String:
	if _hover_slot < 0:
		return ""
	var idx := _scroll + _hover_slot
	if idx < GameState.inventory.size():
		return GameState.inventory[idx]
	return ""


func hovered_verb() -> int:
	var layout := verb_layout()
	if _hover_verb >= 0 and _hover_verb < layout.size():
		return layout[_hover_verb]
	return -1


func slot_at(p: Vector2) -> int:
	for i in Layout.INV_VISIBLE:
		if Rect2(Layout.inv_cell_rect(i)).has_point(p):
			return i
	return -1


func _scroll_up_rect() -> Rect2:
	return Rect2(Layout.INV_ORIGIN.x - 8, Layout.INV_ORIGIN.y, 7, 7)


func _scroll_down_rect() -> Rect2:
	return Rect2(Layout.INV_ORIGIN.x - 8, Layout.INV_ORIGIN.y + 8, 7, 7)


func _clamp_scroll() -> void:
	_scroll = clampi(_scroll, 0, maxi(0, GameState.inventory.size() - Layout.INV_VISIBLE))


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	if _panel_bg != null:
		draw_texture_rect(_panel_bg, Rect2(Layout.PANEL_RECT), false)
	else:
		draw_rect(Rect2(Layout.PANEL_RECT), Palette.ui("panel"), true)
		draw_line(Vector2(0, Layout.PANEL_Y), Vector2(Layout.UI_SIZE.x, Layout.PANEL_Y), Palette.ui("outline"), 1.0)
		draw_line(Vector2(0, Layout.PANEL_Y + 1), Vector2(Layout.UI_SIZE.x, Layout.PANEL_Y + 1), Palette.ui("panel_light"), 1.0)

	_draw_sentence()
	_draw_verbs()
	_draw_inventory()


## §5.3 커서가 핫스폿 위에 올라가면 명사명이 표시된다.
func _draw_sentence() -> void:
	var font := Theming.base_font
	var size := Theming.font_size()
	# 힌트 버튼 (§11.3 페널티 없음 — 항상 눌러도 된다는 뜻으로 상시 표시)
	draw_rect(Rect2(HINT_RECT), Palette.ui("panel_dark"), true)
	draw_string(font, Vector2(HINT_RECT.position.x + 3, HINT_RECT.position.y + font.get_ascent(size) - 2),
		"?", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_hot"))

	if sentence.is_empty():
		return
	var pos := Vector2(Layout.SENTENCE_RECT.position.x + 13,
		Layout.SENTENCE_RECT.position.y + font.get_ascent(size) - 1)
	draw_string(font, pos, sentence, HORIZONTAL_ALIGNMENT_LEFT,
		Layout.SENTENCE_RECT.size.x - 15, size, Palette.ui("text_hot"))


func _draw_verbs() -> void:
	# 동사 칸은 폭이 고정이므로 한 단계 작은 도트 폰트를 쓴다.
	var font := Theming.small_font
	var size := Theming.small_font_size()
	var layout := verb_layout()
	var simple := is_simple_ui()

	for i in layout.size():
		var r := Rect2(Layout.verb_cell_rect(i))
		var v: int = layout[i]
		var is_current := v == current_verb
		var is_hover := i == _hover_verb

		var bg := Palette.ui("panel_dark")
		if is_current:
			bg = Palette.ui("select")
		elif is_hover:
			bg = Palette.ui("panel_light")
		draw_rect(r, bg, true)
		draw_rect(r, Palette.ui("outline"), false, 1.0)

		var col := Palette.ui("text")
		if is_current:
			col = Palette.ui("text_hot")
		elif is_hover:
			col = Palette.ui("text")
		var label := Loc.t(Actions.label_key(v, simple))
		# 폭을 넘기면 클립되도록 셀 폭을 넘긴다. §18 '글자 크게' 에서 이웃 버튼을 침범하지 않는다.
		draw_string(font, Vector2(r.position.x + 1,
			roundf(r.position.y + (r.size.y + font.get_ascent(size)) / 2.0 - 1)),
			label, HORIZONTAL_ALIGNMENT_CENTER, int(r.size.x - 2), size, col)


func _draw_inventory() -> void:
	var inv := GameState.inventory
	for i in Layout.INV_VISIBLE:
		var r := Rect2(Layout.inv_cell_rect(i))
		var idx := _scroll + i
		var has := idx < inv.size()
		var id: String = inv[idx] if has else ""

		var bg := Palette.ui("panel_dark")
		if has and id == held_item:
			bg = Palette.ui("select")
		elif i == _hover_slot and has:
			bg = Palette.ui("panel_light")
		draw_rect(r, bg, true)
		draw_rect(r, Palette.ui("outline"), false, 1.0)

		if has:
			_draw_item_icon(id, r)

	# 스크롤 화살표 — 16칸을 넘길 때만
	if inv.size() > Layout.INV_VISIBLE:
		_draw_arrow(_scroll_up_rect(), true, _scroll > 0)
		_draw_arrow(_scroll_down_rect(), false, _scroll + Layout.INV_VISIBLE < inv.size())


func _draw_arrow(r: Rect2, up: bool, enabled: bool) -> void:
	var c := Palette.ui("text") if enabled else Palette.ui("text_dim")
	var cx := r.position.x + r.size.x / 2.0
	if up:
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, r.position.y + 1),
			Vector2(r.position.x + 1, r.position.y + r.size.y - 1),
			Vector2(r.position.x + r.size.x - 1, r.position.y + r.size.y - 1)]), c)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(r.position.x + 1, r.position.y + 1),
			Vector2(r.position.x + r.size.x - 1, r.position.y + 1),
			Vector2(cx, r.position.y + r.size.y - 1)]), c)


func _draw_item_icon(id: String, cell: Rect2) -> void:
	var tex := _icon(id)
	if tex != null:
		var s := Vector2(mini(16, int(cell.size.x) - 2), mini(12, int(cell.size.y) - 2))
		draw_texture_rect(tex, Rect2(cell.position + (cell.size - s) / 2.0, s), false)
		return

	# 임시 아이콘: 아이템 색 블록 + 이름 첫 글자. (§21 단색 픽셀 블록 허용)
	var item := GameData.item(id)
	var c := Palette.parse(item.get("icon_color", "#8c3327"))
	var inner := Rect2(cell.position + Vector2(3, 2), cell.size - Vector2(6, 4))
	draw_rect(inner, c, true)
	draw_rect(inner, Palette.ui("outline"), false, 1.0)

	var item_name := Loc.t(str(item.get("name_key", "")))
	if item_name.is_empty():
		return
	var font := Theming.small_font
	var size := Theming.small_font_size()
	var ch := item_name.substr(0, 1)
	var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(roundf(cell.position.x + (cell.size.x - w) / 2.0),
		roundf(cell.position.y + (cell.size.y + font.get_ascent(size)) / 2.0 - 1)),
		ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text"))


func _icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var item := GameData.item(id)
	var path := str(item.get("icon", "%s/%s.png" % [ICON_DIR, id]))
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var r := ResourceLoader.load(path)
		if r is Texture2D:
			tex = r
	_icon_cache[id] = tex
	return tex
