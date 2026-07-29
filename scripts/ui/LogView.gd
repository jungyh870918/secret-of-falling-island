class_name LogView
extends Control
## 대화 기록 화면. 명세서 §18 "대화 기록", §23 "대화 로그 확인 가능".

const BOX := Rect2i(10, 10, 300, 160)
const LINE_GAP := 1

var _scroll := 0
var _wrapped: Array = []   ## [{text, color}]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	DialogueLog.subscribe(Callable(self, "_rebuild"))


func open() -> void:
	_rebuild()
	_scroll = maxi(0, _wrapped.size() - _visible_lines())
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func scroll_by(delta: int) -> void:
	_scroll = clampi(_scroll + delta, 0, maxi(0, _wrapped.size() - _visible_lines()))
	queue_redraw()


func _visible_lines() -> int:
	var line_h := int(Theming.base_font.get_height(Theming.font_size())) + LINE_GAP
	# 위 제목(18px)과 아래 안내문(16px) 자리를 비워 둔다.
	return maxi(1, int((BOX.size.y - 34) / line_h))


func _rebuild() -> void:
	_wrapped.clear()
	var font := Theming.base_font
	var size := Theming.font_size()
	var max_w := BOX.size.x - 12

	for e in DialogueLog.entries():
		var speaker := str(e.get("speaker", "player"))
		var kind := str(e.get("kind", "line"))
		var color := Palette.speaker_color(speaker)
		if kind == "choice":
			color = Palette.ui("text_hot")
		elif kind == "system":
			color = Palette.ui("text_dim")

		var prefix := ""
		if kind == "line":
			var name_key := "speaker.%s" % speaker
			if Loc.has(name_key):
				prefix = Loc.t(name_key) + ": "
		var full := prefix + str(e.get("text", ""))

		for line in _wrap(full, font, size, max_w):
			_wrapped.append({"text": line, "color": color})

	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var font := Theming.base_font
	var size := Theming.font_size()
	var line_h := int(font.get_height(size)) + LINE_GAP

	draw_rect(Rect2(0, 0, Layout.SCREEN.x, Layout.SCREEN.y), Color(0, 0, 0, 0.7), true)
	draw_rect(Rect2(BOX), Palette.ui("panel"), true)
	draw_rect(Rect2(BOX), Palette.ui("outline"), false, 1.0)

	var title := Loc.t("ui.log.title")
	draw_string(font, Vector2(BOX.position.x + 5, BOX.position.y + 3 + font.get_ascent(size)),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_hot"))
	draw_line(Vector2(BOX.position.x + 3, BOX.position.y + 14),
		Vector2(BOX.position.x + BOX.size.x - 3, BOX.position.y + 14), Palette.ui("panel_light"), 1.0)

	if _wrapped.is_empty():
		draw_string(font, Vector2(BOX.position.x + 6, BOX.position.y + 26),
			Loc.t("ui.log.empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_dim"))
	else:
		var count := _visible_lines()
		for i in count:
			var idx := _scroll + i
			if idx >= _wrapped.size():
				break
			var w: Dictionary = _wrapped[idx]
			draw_string(font, Vector2(BOX.position.x + 6, BOX.position.y + 18 + line_h * i + font.get_ascent(size)),
				str(w["text"]), HORIZONTAL_ALIGNMENT_LEFT, BOX.size.x - 12, size, w["color"])

	draw_string(font, Vector2(BOX.position.x + 5, BOX.position.y + BOX.size.y - 4),
		Loc.t("ui.log.footer"), HORIZONTAL_ALIGNMENT_LEFT, BOX.size.x - 10,
		Theming.small_font_size(), Palette.ui("text_dim"))


static func _wrap(text: String, font: Font, size: int, max_w: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var candidate: String = word if line.is_empty() else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			line = candidate
			continue
		if not line.is_empty():
			out.append(line)
		var chunk := ""
		for ch in (word as String):
			if font.get_string_size(chunk + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
				out.append(chunk)
				chunk = ""
			chunk += ch
		line = chunk
	if not line.is_empty():
		out.append(line)
	return out
