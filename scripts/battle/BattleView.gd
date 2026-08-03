class_name BattleView
extends Control
## 대화 배틀 HUD. 명세서 §5.4 "대화 배틀에서는 상대 초상, 멘탈 차트, 군중 반응 아이콘이 추가된다."
##
## 상대 초상은 PortraitView 가 이미 담당하므로 여기서는 그리지 않는다.
## 이 뷰는 §9.2 상태값 세 가지를 눈에 보이게 만드는 일만 한다.
##
##   confidence     자신감 → 멘탈 차트(캔들). 지지선을 이탈하면 승리 (§9.4-7)
##   crowd_support  군중 지지 → 사람 아이콘 줄
##   contradictions 모순 카드 → 아래쪽 카드 줄 (§9.4-5)
##
## 차트는 장식이 아니라 상태 표시다. 캔들 하나가 선택지 하나이고,
## 색은 §6.3 상승장/하락장 계열을 그대로 쓴다.

## 세 칸은 서로 겹치지 않는다. 폰트가 커져도(§18 글자 크게) 행 높이 13px 안에서 읽힌다.
const CHART := Rect2i(190, 5, 124, 46)
const CROWD := Rect2i(190, 53, 124, 13)
const CARDS := Rect2i(190, 68, 124, 13)
const MAX_CANDLES := 10

var confidence := 100
var crowd := 50
var support_line := 30
var cards: Array = []            ## [{key: String}] 획득한 모순 카드
var history: Array = []          ## [{from:int, to:int}] 캔들 하나가 선택 하나

var _shake := 0.0
var _flash := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)


func open(p_confidence: int, p_crowd: int, p_support_line: int) -> void:
	confidence = p_confidence
	crowd = p_crowd
	support_line = p_support_line
	cards.clear()
	history.clear()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


## 선택 하나의 결과를 반영한다. 캔들이 하나 늘어난다.
func apply(delta_conf: int, delta_crowd: int, card_key: String = "") -> void:
	var before := confidence
	confidence = clampi(confidence + delta_conf, 0, 100)
	crowd = clampi(crowd + delta_crowd, 0, 100)
	history.append({"from": before, "to": confidence})
	if history.size() > MAX_CANDLES:
		history.remove_at(0)
	if not card_key.is_empty():
		cards.append(card_key)
	# §6.6 "흔들림은 사건이 있을 때만". 자신감이 크게 깎였을 때만 흔든다.
	if delta_conf <= -10 and not bool(SaveManager.get_setting("reduce_shake", false)):
		_shake = 0.22
	if delta_conf > 0:
		_flash = 0.2
	queue_redraw()


func is_broken() -> bool:
	return confidence < support_line


func _process(delta: float) -> void:
	if _shake > 0.0 or _flash > 0.0:
		_shake = maxf(0.0, _shake - delta)
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


func _draw() -> void:
	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(randi_range(-1, 1), randi_range(-1, 1))

	_draw_chart(Rect2(CHART).position + jitter)
	_draw_crowd()
	_draw_cards()


# ---------------------------------------------------------------- 멘탈 차트

func _draw_chart(origin: Vector2) -> void:
	var w := float(CHART.size.x)
	var h := float(CHART.size.y)
	var frame := Rect2(origin, Vector2(w, h))

	draw_rect(frame, Palette.parse("#141c2e"))
	if _flash > 0.0:
		draw_rect(frame, Color(0.9, 0.3, 0.2, _flash * 0.5))
	draw_rect(frame, Palette.ui("outline"), false, 1.0)

	# 제목 줄
	var font := Theming.base_font
	var size := Theming.font_size()
	draw_string(font, origin + Vector2(3, 2 + font.get_ascent(size)),
		Loc.t("battle.ui.mental"), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_dim"))

	var plot_top := origin.y + 12.0
	var plot_h := h - 16.0

	# §9.4-7 지지선. 이 아래로 내려가면 승리.
	var y_support := plot_top + plot_h * (1.0 - support_line / 100.0)
	var dash := Palette.parse("#e0b23a")
	for x in range(int(origin.x) + 2, int(origin.x + w) - 2, 4):
		draw_rect(Rect2(x, roundf(y_support), 2, 1), dash)

	# 캔들 — 하나가 선택 하나
	var slot := (w - 6.0) / float(MAX_CANDLES)
	for i in history.size():
		var e: Dictionary = history[i]
		var f: float = plot_top + plot_h * (1.0 - float(e["from"]) / 100.0)
		var t: float = plot_top + plot_h * (1.0 - float(e["to"]) / 100.0)
		var down: bool = float(e["to"]) < float(e["from"])
		var col := Palette.parse("#5ce0d0") if down else Palette.parse("#c8352e")
		var x := origin.x + 3.0 + slot * i
		var top: float = minf(f, t)
		var body: float = maxf(2.0, absf(t - f))
		draw_rect(Rect2(roundf(x + slot * 0.5) - 0.0, roundf(top) - 2.0, 1, body + 4.0), col.darkened(0.3))
		draw_rect(Rect2(roundf(x + 1), roundf(top), maxf(2.0, slot - 3.0), body), col)

	# 현재 수치
	var label := "%d" % confidence
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(origin.x + w - lw - 3, origin.y + 2 + font.get_ascent(size)),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Palette.parse("#5ce0d0") if is_broken() else Palette.ui("text"))


# ---------------------------------------------------------------- 군중 반응

## 라벨은 왼쪽, 내용은 오른쪽. 한 행 안에서 끝나야 폰트 크기를 키워도 안 겹친다.
func _draw_row(box: Rect2i, label_key: String) -> float:
	draw_rect(Rect2(box), Palette.parse("#141c2e"))
	draw_rect(Rect2(box), Palette.ui("outline"), false, 1.0)

	var font := Theming.base_font
	var size := Theming.font_size()
	var label := Loc.t(label_key)
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := box.position.y + (box.size.y - font.get_height(size)) / 2.0 + font.get_ascent(size)
	draw_string(font, Vector2(box.position.x + 2, roundf(baseline)),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_dim"))
	return box.position.x + lw + 5.0


func _draw_crowd() -> void:
	var x0 := _draw_row(CROWD, "battle.ui.crowd")

	# 사람 아이콘 10개. 채워진 수가 군중 지지.
	var filled := int(roundf(crowd / 10.0))
	var y := CROWD.position.y + 3
	for i in 10:
		var x := x0 + i * 6.0
		if x + 5 > CROWD.position.x + CROWD.size.x - 1:
			break
		var col := Palette.parse("#e0b23a") if i < filled else Palette.ui("panel_light")
		draw_rect(Rect2(x + 1, y, 3, 2), col)         # 머리
		draw_rect(Rect2(x, y + 3, 5, 4), col)         # 몸


# ---------------------------------------------------------------- 모순 카드

func _draw_cards() -> void:
	var x := _draw_row(CARDS, "battle.ui.cards")
	var y := CARDS.position.y + 3.0
	for i in cards.size():
		var w := 11.0
		if x + w > CARDS.position.x + CARDS.size.x - 1:
			break
		draw_rect(Rect2(x, y, w, 7), Palette.parse("#e8d9b8"))
		draw_rect(Rect2(x, y, w, 7), Palette.ui("outline"), false, 1.0)
		draw_rect(Rect2(x + 2, y + 2, w - 4, 1), Palette.parse("#8c3327"))
		draw_rect(Rect2(x + 2, y + 4, w - 5, 1), Palette.parse("#4a4a4c"))
		x += w + 2.0
