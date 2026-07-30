class_name CardView
extends Control
## 컷신 카드. 명세서 §3.2 "컷신: 시작, 세라 첫 등장, 챕터 종료".
##
## 검은 화면에 문장만 띄우는 가장 오래된 형태의 연출.
## 실제 컷신 스프라이트가 들어오기 전까지 이 형태를 쓴다.
##
## [최종 에셋 교체 지점] res://assets/sprites/effects/card_<id>.png

const IMAGE_DIR := "res://assets/sprites/effects"

var _lines: PackedStringArray = []
var _active := false
var _elapsed := 0.0
var _image: Texture2D = null

const MIN_HOLD := 0.6


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func is_active() -> bool:
	return _active


## 문구를 보여주고 넘길 때까지 기다린다. (코루틴)
func show_card(keys: Array, image_id: String = "") -> void:
	_lines.clear()
	for k in keys:
		var line := Loc.t(str(k))
		_lines.append(line)
		# 컷신 문구도 서사다. §18 대화 기록에 남긴다.
		DialogueLog.add("narrator", line, "system")
	_image = null
	if not image_id.is_empty():
		var p := "%s/card_%s.png" % [IMAGE_DIR, image_id]
		if ResourceLoader.exists(p):
			var t := ResourceLoader.load(p)
			if t is Texture2D:
				_image = t
	_active = true
	_elapsed = 0.0
	visible = true
	set_process(true)
	queue_redraw()
	while _active:
		await get_tree().process_frame
	visible = false
	set_process(false)


func dismiss() -> void:
	if _active and _elapsed >= MIN_HOLD:
		_active = false


func _process(delta: float) -> void:
	_elapsed += delta


func _draw() -> void:
	if not _active:
		return
	draw_rect(Rect2(0, 0, Layout.SCREEN.x, Layout.SCREEN.y), Color.BLACK, true)

	var top := 40.0
	if _image != null:
		var s := _image.get_size()
		draw_texture_rect(_image, Rect2((Layout.SCREEN.x - s.x) / 2.0, 18, s.x, s.y), false)
		top = 18 + s.y + 10

	var font := Theming.base_font
	var size := Theming.font_size()
	var line_h := int(font.get_height(size)) + 4
	var total := line_h * _lines.size()
	var y: float = maxf(top, (Layout.SCREEN.y - total) / 2.0)

	for i in _lines.size():
		var l := _lines[i]
		var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(roundf((Layout.SCREEN.x - w) / 2.0), roundf(y + line_h * i + font.get_ascent(size))),
			l, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text"))

	if _elapsed >= MIN_HOLD and fposmod(_elapsed, 1.2) < 0.6:
		var hint := Loc.t("ui.card.continue")
		var sf := Theming.small_font
		var ss := Theming.small_font_size()
		var hw := sf.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
		draw_string(sf, Vector2(roundf((Layout.SCREEN.x - hw) / 2.0), Layout.SCREEN.y - 12),
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Palette.ui("text_dim"))
