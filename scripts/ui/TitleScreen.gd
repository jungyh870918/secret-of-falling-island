class_name TitleScreen
extends MenuList
## 타이틀 화면. 명세서 §23 "게임 실행 후 타이틀 화면 진입".
##
## [최종 에셋 교체 지점] res://assets/ui/title.png (320x180)

const TITLE_ART := "res://assets/ui/title.png"

var _art: Texture2D = null
var _time := 0.0


func _ready() -> void:
	super._ready()
	box = Rect2i(102, 102, 116, 70)
	if ResourceLoader.exists(TITLE_ART):
		var t := ResourceLoader.load(TITLE_ART)
		if t is Texture2D:
			_art = t
	set_process(true)


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var font := Theming.base_font

	if _art != null:
		draw_texture_rect(_art, Rect2(0, 0, Layout.UI_SIZE.x, Layout.UI_SIZE.y), false)
	else:
		_draw_placeholder_art()

	# MenuList 의 어두운 오버레이는 타이틀에서 필요 없으므로 박스만 다시 그린다.
	draw_rect(Rect2(box), Palette.ui("panel"), true)
	draw_rect(Rect2(box), Palette.ui("outline"), false, 1.0)
	draw_rect(Rect2(box).grow(-1), Palette.ui("panel_light"), false, 1.0)

	var size := Theming.font_size()
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
		draw_string(font, Vector2(r.position.x + 4, roundf(r.position.y + font.get_ascent(size) + 1)),
			str(row.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x - 8), size, col)

	var ver := Loc.t("ui.title.version")
	draw_string(Theming.small_font, Vector2(4, Layout.UI_SIZE.y - 4), ver,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Theming.small_font_size(), Palette.ui("text_dim"))


## 타이틀 아트가 없을 때의 임시 화면.
## §6.3 하락장 계열 배경 + 붉은 양초 실루엣.
func _draw_placeholder_art() -> void:
	draw_rect(Rect2(0, 0, Layout.UI_SIZE.x, Layout.UI_SIZE.y), Palette.parse("pal.bear.navy"), true)

	# 바다 — §6.4 디더링
	var sea := Palette.parse("pal.bear.ink")
	var sea2 := Palette.parse("pal.bear.teal")
	for y in range(120, 180, 2):
		for x in range(0, 320, 2):
			draw_rect(Rect2(x, y, 1, 1), sea2 if ((x + y) / 2) % 3 == 0 else sea, true)
	draw_rect(Rect2(0, 122, 320, 58), Color(0, 0, 0, 0.25), true)

	# 붉은 양초 등대 (§8.7 떡락섬 / 프로젝트 상징)
	var wax := Palette.parse("pal.bull.scarlet")
	var wax_d := Palette.parse("pal.bull.wine")
	draw_rect(Rect2(150, 52, 20, 70), wax, true)
	draw_rect(Rect2(150, 52, 20, 70), Palette.ui("outline"), false, 1.0)
	draw_rect(Rect2(150, 52, 6, 70), wax_d, true)
	draw_rect(Rect2(158, 26, 4, 26), wax_d, true)  # 심지 = 캔들 꼬리

	# 불꽃 — §6.6 "양초 불꽃이 흔들림"
	var flick := int(fposmod(_time * 6.0, 3.0))
	var fx := 158 + (flick - 1)
	draw_rect(Rect2(fx, 18, 4, 9), Palette.parse("pal.bull.ember"), true)
	draw_rect(Rect2(fx + 1, 14, 2, 5), Palette.parse("pal.bull.old_gold"), true)

	# 제목
	var font := Theming.base_font
	var t := Loc.t("ui.title.name")
	var s := Loc.t("ui.title.subtitle")
	var big := Theming.font_size() + 2
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	for ox in [-1, 1]:
		for oy in [-1, 1]:
			draw_string(font, Vector2(roundf((320 - tw) / 2.0) + ox, 72 + oy), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, big, Palette.ui("outline"))
	draw_string(font, Vector2(roundf((320 - tw) / 2.0), 72), t,
		HORIZONTAL_ALIGNMENT_LEFT, -1, big, Palette.parse("pal.bull.ivory"))
	# 부제목도 외곽선을 넣는다. 양초 위에 걸치면 어두운 글자색이 묻힌다.
	var sf := Theming.small_font
	var ss := Theming.small_font_size()
	var sw := sf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	var sx := roundf((320 - sw) / 2.0)
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			if ox != 0 or oy != 0:
				draw_string(sf, Vector2(sx + ox, 84 + oy), s,
					HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Palette.ui("outline"))
	# 금색은 붉은 양초 위에서 묻힌다. 아이보리로 — 크기 차이(9px vs 11px)만으로
	# 이미 제목과 위계가 구분된다.
	draw_string(sf, Vector2(sx, 84), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Palette.parse("pal.bull.ivory"))
