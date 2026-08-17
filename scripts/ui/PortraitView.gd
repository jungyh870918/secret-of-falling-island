class_name PortraitView
extends Control
## 대화 초상화. 명세서 §5.4 "대화 UI", §6.2 초상화 96×96, §22 초상화 프롬프트.
##
## 일반 대사(핫스폿 관찰 한두 줄)에는 뜨지 않는다. 분기 대화와 대화 배틀에서만 뜬다 —
## 그래야 초상화가 '지금은 사람과 이야기하는 중' 이라는 신호로 읽힌다.
##
## [최종 에셋 교체 지점]
##   res://assets/sprites/portraits/<character_id>.png (96×96) 를 넣으면
##   아래 _draw_generated() 대신 그 그림을 쓴다. 코드 수정은 필요 없다.
##
## 임시 도트는 캐릭터 데이터의 colors / hair_style / portrait.traits 만 보고 그린다.
## 인물별 if 문이 아니라 특징 목록의 조합이므로, 새 인물은 JSON 한 덩이로 추가된다.

const PORTRAIT_DIR := "res://assets/sprites/portraits"
const FADE_SPEED := 8.0
const TALK_PERIOD := 0.18

var enabled := false            ## 분기 대화 중에만 true
var speaker := ""
var talking := false

## 화자 배우가 화면 어디에 서 있는지. 초상화를 반대쪽 모서리로 보내는 데 쓴다.
var location_provider: Callable = Callable()

## §5.4 "대화 배틀에서는 상대 초상" — 배틀 동안에는 화자가 바뀌어도 상대 얼굴을 붙잡아 둔다.
var _pinned := ""
## 실제로 지금 말하고 있는 사람. 고정된 얼굴과 다를 수 있다.
var _live_speaker := ""

var _alpha := 0.0
var _time := 0.0
var _on_left := true
var _tex_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	visible = true


## 분기 대화 시작/끝. 끝나면 화자와 무관하게 사라진다.
func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		speaker = ""


## 화자가 바뀔 때마다 호출된다. 내레이션·시스템·힌트는 얼굴이 없으므로 숨긴다.
func set_speaker(p_speaker: String) -> void:
	_live_speaker = p_speaker
	if not _pinned.is_empty():
		return
	if p_speaker in ["narrator", "system", "hint", ""]:
		speaker = ""
		return
	speaker = p_speaker
	_time = 0.0
	_pick_side()


## 배틀 동안 상대 얼굴을 고정한다. (§5.4)
func pin(character_id: String) -> void:
	_pinned = character_id
	speaker = character_id
	_time = 0.0
	_pick_side()


func unpin() -> void:
	_pinned = ""


## 입은 지금 그려진 얼굴의 주인이 말할 때만 움직인다.
## 배틀에서 상대 초상을 고정해 둔 동안 한개미가 말하면 상대 입은 다물고 있어야 한다.
func set_talking(v: bool) -> void:
	talking = v and _live_speaker == speaker


func _is_showing() -> bool:
	return enabled and not speaker.is_empty() and bool(SaveManager.get_setting("show_portraits", true))


## 초상화가 실제로 덮는 영역. SubtitleLayer 가 자막을 피해 놓는 데 쓴다.
func occupied_rect() -> Rect2i:
	if _alpha <= 0.02:
		return Rect2i(0, 0, 0, 0)
	return Layout.portrait_rect(_on_left)


func _process(delta: float) -> void:
	_time += delta
	var want := 1.0 if _is_showing() else 0.0
	var next: float = move_toward(_alpha, want, FADE_SPEED * delta)
	if not is_equal_approx(next, _alpha):
		_alpha = next
		queue_redraw()
	elif _alpha > 0.0 and talking:
		queue_redraw()


## 말하는 사람이 왼쪽에 서 있으면 초상화는 오른쪽으로 간다.
func _pick_side() -> void:
	var view = location_provider.call() if location_provider.is_valid() else null
	if view == null or not is_instance_valid(view):
		_on_left = true
		return
	var a = view.actor(speaker)
	if a == null and speaker == "player":
		a = view.player
	if a == null or not is_instance_valid(a):
		_on_left = true
		return
	_on_left = Layout.world_to_ui(a.position).x > Layout.UI_SIZE.x / 2.0


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	if _alpha <= 0.02 or speaker.is_empty():
		return
	var box := Layout.portrait_rect(_on_left)
	var def: Dictionary = GameData.characters.get(speaker, {})

	var tex := _texture_for(speaker)
	if tex != null:
		draw_texture_rect(tex, Rect2(box), false, Color(1, 1, 1, _alpha))
	else:
		_draw_generated(box, def)

	# 액자 — 1px 외곽선 두 겹. §6.5 "라인은 얇게, 대신 명확하게"
	draw_rect(Rect2(box), Palette.ui("outline") * Color(1, 1, 1, _alpha), false, 1.0)
	var inner := Rect2(box).grow(-1)
	draw_rect(inner, Palette.speaker_color(speaker) * Color(1, 1, 1, _alpha * 0.5), false, 1.0)

	_draw_nameplate(box)


func _draw_nameplate(box: Rect2i) -> void:
	var name_key := "speaker.%s" % speaker
	var label := Loc.t(name_key)
	if label.is_empty():
		return
	var font := Theming.base_font
	var size := Theming.font_size()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := int(font.get_height(size))
	var plate := Rect2(box.position.x, box.position.y + box.size.y - h - 1, w + 6, h + 2)
	draw_rect(plate, Palette.ui("panel_dark") * Color(1, 1, 1, _alpha * 0.85))
	draw_rect(plate, Palette.ui("outline") * Color(1, 1, 1, _alpha), false, 1.0)
	draw_string(font, Vector2(plate.position.x + 3, plate.position.y + 1 + font.get_ascent(size)),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Palette.speaker_color(speaker) * Color(1, 1, 1, _alpha))


func _texture_for(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var path := "%s/%s.png" % [PORTRAIT_DIR, id]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			tex = res
	_tex_cache[id] = tex
	return tex


# ---------------------------------------------------------------- 임시 도트 초상화

func _draw_generated(box: Rect2i, def: Dictionary) -> void:
	var portrait: Dictionary = def.get("portrait", {}) if def.get("portrait", null) is Dictionary else {}
	var traits: Array = portrait.get("traits", []) if portrait.get("traits", null) is Array else []
	var colors: Dictionary = def.get("colors", {}) if def.get("colors", null) is Dictionary else {}
	var hair_style := str(def.get("hair_style", "messy"))

	var skin := _col(colors, "skin", "#d8a888")
	var hair := _col(colors, "hair", "#241c22")
	var shirt := _col(colors, "shirt", "#e8d9b8")
	var accent := _col(colors, "accent", "#8c3327")
	var backdrop := Palette.parse(portrait.get("backdrop", "#241f2b"), Color.html("#241f2b"))
	var ink := Palette.ui("outline")

	# 배경 — 단색 대신 2x2 디더로 §6.4 를 지킨다
	_rect(box, 0, 0, 96, 96, backdrop)
	_dither(box, 0, 48, 96, 48, backdrop.darkened(0.25))

	if traits.has("overexposed"):
		# §6.7 박프로 — 스튜디오 조명에 과도하게 노출된 얼굴
		_rect(box, 0, 0, 96, 30, Color(1, 1, 1, 0.10 * _alpha))

	# 어깨와 상의
	_rect(box, 6, 72, 84, 24, shirt.darkened(0.15))
	_rect(box, 6, 72, 84, 2, shirt)
	if bool(def.get("has_coat", false)):
		_rect(box, 6, 72, 16, 24, accent.darkened(0.35))
		_rect(box, 74, 72, 16, 24, accent.darkened(0.35))

	# 목
	_rect(box, 41, 60, 14, 14, skin.darkened(0.18))

	# 머리
	_rect(box, 30, 20, 36, 46, skin)
	_rect(box, 27, 38, 3, 10, skin.darkened(0.12))
	_rect(box, 66, 38, 3, 10, skin.darkened(0.12))
	_rect(box, 30, 60, 36, 6, skin.darkened(0.12))

	_draw_hair(box, hair_style, hair)

	# 눈썹 — §6.7 세라는 "눈썹과 시선으로 미묘하게 표현"
	_rect(box, 34, 35, 10, 2, hair)
	_rect(box, 52, 35, 10, 2, hair)

	var pupil_dx := 2 if traits.has("shifty") else 0
	_rect(box, 35, 39, 9, 6, Color.html("#e8d9b8"))
	_rect(box, 53, 39, 9, 6, Color.html("#e8d9b8"))
	_rect(box, 38 + pupil_dx, 40, 3, 4, ink)
	_rect(box, 56 + pupil_dx, 40, 3, 4, ink)

	if traits.has("glasses"):
		_frame(box, 33, 37, 13, 10, ink)
		_frame(box, 51, 37, 13, 10, ink)
		_rect(box, 46, 41, 5, 1, ink)

	# 코
	_rect(box, 46, 46, 4, 8, skin.darkened(0.22))

	_draw_mouth(box, traits, ink, accent)

	if traits.has("tie"):
		_rect(box, 44, 70, 8, 4, accent)
		_rect(box, 45, 74, 6, 20, accent)

	# 얼굴 실루엣 외곽선
	_frame(box, 30, 20, 36, 46, ink)
	_frame(box, 6, 72, 84, 24, ink)


func _draw_hair(box: Rect2i, style: String, hair: Color) -> void:
	match style:
		"bald":
			# §6.7 부장 — 벗겨진 머리. 옆머리만 남는다.
			_rect(box, 28, 30, 4, 14, hair)
			_rect(box, 64, 30, 4, 14, hair)
			_rect(box, 32, 20, 32, 3, hair.lightened(0.1))
		"bob":
			# §6.7 윤세라 — 적갈색 단발, 각진 실루엣
			_rect(box, 26, 14, 44, 16, hair)
			_rect(box, 26, 30, 6, 30, hair)
			_rect(box, 64, 30, 6, 30, hair)
			_rect(box, 26, 14, 44, 3, hair.lightened(0.15))
		"slick":
			_rect(box, 28, 15, 40, 11, hair)
			_rect(box, 28, 15, 40, 2, hair.lightened(0.3))
			_rect(box, 28, 26, 6, 8, hair)
			_rect(box, 62, 26, 6, 8, hair)
		_:
			# messy — §6.7 한개미, 약간 헝클어진 머리
			_rect(box, 28, 16, 40, 13, hair)
			_rect(box, 31, 12, 8, 5, hair)
			_rect(box, 45, 11, 7, 6, hair)
			_rect(box, 57, 13, 7, 4, hair)
			_rect(box, 28, 29, 5, 8, hair)
			_rect(box, 63, 29, 5, 8, hair)


func _draw_mouth(box: Rect2i, traits: Array, ink: Color, accent: Color) -> void:
	var open := talking and fmod(_time, TALK_PERIOD * 2.0) < TALK_PERIOD
	if traits.has("wide_smile"):
		# §6.7 김실장·박프로 계열 — 입꼬리는 웃지만 눈은 웃지 않는다
		_rect(box, 37, 55, 22, 3 if not open else 6, ink)
		_rect(box, 35, 53, 3, 3, ink)
		_rect(box, 58, 53, 3, 3, ink)
		if open:
			_rect(box, 39, 57, 18, 2, accent.darkened(0.4))
		return
	if open:
		_rect(box, 42, 54, 12, 6, ink)
		_rect(box, 44, 56, 8, 3, accent.darkened(0.4))
	else:
		_rect(box, 42, 56, 12, 2, ink)


# ---------------------------------------------------------------- 픽셀 헬퍼
# 전부 box 기준 상대 좌표. 320x180 내부 해상도에서 1:1 이므로 그대로 도트가 된다.

func _rect(box: Rect2i, x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(box.position.x + x, box.position.y + y, w, h), Color(c.r, c.g, c.b, c.a * _alpha))


func _frame(box: Rect2i, x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(box.position.x + x, box.position.y + y, w, h),
		Color(c.r, c.g, c.b, c.a * _alpha), false, 1.0)


## §6.4 "그라데이션 대신 디더링". 2x2 체커.
func _dither(box: Rect2i, x: int, y: int, w: int, h: int, c: Color) -> void:
	var col := Color(c.r, c.g, c.b, c.a * _alpha)
	for j in range(0, h, 2):
		for i in range(0, w, 2):
			draw_rect(Rect2(box.position.x + x + i, box.position.y + y + j, 1, 1), col)
			draw_rect(Rect2(box.position.x + x + i + 1, box.position.y + y + j + 1, 1, 1), col)


static func _col(colors: Dictionary, key: String, fallback: String) -> Color:
	return Palette.parse(colors.get(key, fallback), Color.html(fallback))
