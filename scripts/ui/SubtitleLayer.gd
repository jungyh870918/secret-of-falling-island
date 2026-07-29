class_name SubtitleLayer
extends Control
## 대사 자막. 명세서 §5.1 "대사 말풍선 또는 자막", §18 접근성.
##
## 고전 SCUMM 방식대로 화자 머리 위에 화자 색으로 띄운다.
## §18: 자막 항상 표시 / 텍스트 속도 조절 / 클릭 시 즉시 표시.

const MAX_WIDTH := 210
const LINE_GAP := 1
const MARGIN := 4

## §18 텍스트 속도. 초당 글자 수. 마지막 값은 '즉시'.
const SPEED_CPS := [14.0, 26.0, 45.0, 0.0]
## 다 표시된 뒤 자동으로 넘어가기까지의 여유 시간
const HOLD_BASE := 0.9
const HOLD_PER_CHAR := 0.045

var _speaker := ""
var _full_text := ""
var _shown := 0
var _elapsed := 0.0
var _active := false
var _dismiss_requested := false
var _anchor := Vector2(160, 90)

## Main 이 주입한다. 화자 위치를 찾기 위해 LocationView 를 참조한다.
var location_provider: Callable = Callable()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func is_active() -> bool:
	return _active


## 대사 하나를 표시하고, 사용자가 넘길 때까지 기다린다. (코루틴)
func say(speaker: String, text: String) -> void:
	if text.is_empty():
		return
	_speaker = speaker
	_full_text = text
	_shown = 0
	_elapsed = 0.0
	_active = true
	_dismiss_requested = false
	_update_anchor()
	_set_talking(true)
	DialogueLog.add(speaker, text, "line")
	queue_redraw()

	while _active:
		await get_tree().process_frame

	_set_talking(false)


## 클릭/키 입력. 표시 중이면 전부 표시, 다 표시됐으면 넘긴다. (§18)
func advance() -> void:
	if not _active:
		return
	if _shown < _full_text.length():
		_shown = _full_text.length()
		queue_redraw()
	else:
		_dismiss_requested = true


func force_close() -> void:
	_active = false


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta

	var speed_idx: int = clampi(int(SaveManager.get_setting("text_speed", 1)), 0, SPEED_CPS.size() - 1)
	var cps: float = SPEED_CPS[speed_idx]
	var target: int = _full_text.length()
	if cps > 0.0:
		target = mini(_full_text.length(), int(_elapsed * cps))
	if target != _shown:
		_shown = target
		queue_redraw()

	if _shown >= _full_text.length():
		# '즉시' 모드(cps == 0)에서는 타자 시간이 0이다.
		# 이걸 안 나누면 즉시 모드가 오히려 제일 오래 걸린다.
		var reveal := 0.0 if cps <= 0.0 else float(_full_text.length()) / cps
		var hold := HOLD_BASE + _full_text.length() * HOLD_PER_CHAR
		if _dismiss_requested or _elapsed > reveal + hold:
			_active = false
			queue_redraw()


func _update_anchor() -> void:
	var view = location_provider.call() if location_provider.is_valid() else null
	if view != null and is_instance_valid(view):
		var a = view.actor(_speaker)
		if a == null and _speaker == "player":
			a = view.player
		if a != null and is_instance_valid(a):
			_anchor = a.head_top()
			return
	# 화자를 화면에서 찾을 수 없으면(내레이션 등) 장면 영역 중앙 위쪽.
	_anchor = Vector2(Layout.VIEW_RECT.size.x / 2.0, 34)


func _set_talking(v: bool) -> void:
	var view = location_provider.call() if location_provider.is_valid() else null
	if view == null or not is_instance_valid(view):
		return
	var a = view.actor(_speaker)
	if a == null and _speaker == "player":
		a = view.player
	if a != null and is_instance_valid(a):
		a.set_talking(v)


func _draw() -> void:
	if not _active or _full_text.is_empty():
		return
	var font := Theming.base_font
	var size := Theming.font_size()
	var color := Palette.speaker_color(_speaker)

	var lines := _wrap(_full_text.substr(0, _shown), font, size)
	if lines.is_empty():
		return

	var line_h := int(font.get_height(size)) + LINE_GAP
	var total_h := line_h * lines.size()

	var widest := 0.0
	for l in lines:
		widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)

	var cx: float = clampf(_anchor.x, widest / 2.0 + MARGIN, Layout.SCREEN.x - widest / 2.0 - MARGIN)
	var top: float = _anchor.y - total_h
	if top < MARGIN:
		# 머리 위 공간이 없으면 아래로 내린다.
		top = minf(_anchor.y + 8, Layout.VIEW_HEIGHT - total_h - MARGIN)
	top = maxf(top, MARGIN)

	# 배경 판때기 대신 1px 외곽선 — 배경 그림을 가리지 않으면서 읽힌다. (§6.5)
	var outline := Palette.ui("outline")
	for i in lines.size():
		var l: String = lines[i]
		var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2(roundf(cx - w / 2.0), roundf(top + line_h * i + font.get_ascent(size)))
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				draw_string(font, pos + Vector2(ox, oy), l, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline)
		draw_string(font, pos, l, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## 한국어는 어절 단위 줄바꿈이 자연스럽다. 공백이 없으면 글자 단위로 자른다.
static func _wrap(text: String, font: Font, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	if text.is_empty():
		return out
	for paragraph in text.split("\n"):
		var line := ""
		for word in (paragraph as String).split(" "):
			var candidate: String = word if line.is_empty() else line + " " + word
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= MAX_WIDTH:
				line = candidate
				continue
			if not line.is_empty():
				out.append(line)
				line = ""
			# 한 어절 자체가 너무 길면 글자 단위로 쪼갠다.
			var chunk := ""
			for ch in (word as String):
				if font.get_string_size(chunk + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > MAX_WIDTH:
					out.append(chunk)
					chunk = ""
				chunk += ch
			line = chunk
		if not line.is_empty():
			out.append(line)
	return out
