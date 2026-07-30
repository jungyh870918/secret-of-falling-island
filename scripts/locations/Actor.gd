class_name Actor
extends Node2D
## 화면에 서 있는 캐릭터. 명세서 §6.2, §6.6, §6.7.
##
## 원점은 **발밑 중앙**이다. 그래야 y 정렬과 걷기 좌표가 자연스럽다.
##
## [최종 에셋 교체 지점]
##   res://assets/sprites/characters/<character_id>.png 스프라이트시트가 존재하면
##   임시 도트(_draw) 대신 그 시트를 쓴다.
##   시트 규격: 가로 = 프레임 수, 세로 = 방향 수(아래/왼/오/위 순).
##   프레임 크기는 캐릭터 데이터의 frame_size 로 지정한다.

const SPRITE_DIR := "res://assets/sprites/characters"

## §6.6 애니메이션 원칙 — 과도하게 부드러우면 안 된다.
const IDLE_FPS := 3.0     ## 대기 2~4프레임
const WALK_FPS := 8.0     ## 걷기 방향당 6프레임
const TALK_FPS := 6.0     ## 말하기 2~3프레임

enum Facing { DOWN, LEFT, RIGHT, UP }

signal arrived()

var character_id := ""
var display_height := 46
var walk_speed := 90.0
var facing: Facing = Facing.DOWN
var is_walking := false
var is_talking := false

var colors := {
	"skin": Color.html("#d8a888"),
	"hair": Color.html("#2a2028"),
	"shirt": Color.html("#c9c6b4"),
	"pants": Color.html("#3d3a44"),
	"accent": Color.html("#8c3327"),
	"shoes": Color.html("#241f2b"),
	"outline": Color.html("#0d0b10"),
}
## §6.7 실루엣 구분용 특징. hair_style: "messy"|"bob"|"bald"|"slick"
var hair_style := "messy"
var has_bag := false
var has_coat := false

var _sprite: Sprite2D = null
var _frame_size := Vector2i(32, 48)
var _anim_time := 0.0
var _walk_target := Vector2.ZERO
var _has_target := false
var _walk_clamp: Callable = Callable()


func setup(def: Dictionary) -> void:
	character_id = str(def.get("character_id", def.get("id", "")))
	display_height = int(def.get("height", 46))
	walk_speed = float(def.get("walk_speed", 90.0))
	hair_style = str(def.get("hair_style", "messy"))
	has_bag = bool(def.get("has_bag", false))
	has_coat = bool(def.get("has_coat", false))
	facing = _facing_from(str(def.get("facing", "down")))

	var c = def.get("colors", {})
	if c is Dictionary:
		for k in (c as Dictionary).keys():
			colors[str(k)] = Palette.parse((c as Dictionary)[k], colors.get(str(k), Color.MAGENTA))

	var fs = def.get("frame_size", null)
	if fs is Array and (fs as Array).size() >= 2:
		_frame_size = Vector2i(int(fs[0]), int(fs[1]))

	_try_load_sprite()
	queue_redraw()


func _try_load_sprite() -> void:
	if character_id.is_empty():
		return
	var path := "%s/%s.png" % [SPRITE_DIR, character_id]
	if not ResourceLoader.exists(path):
		return
	var tex := ResourceLoader.load(path)
	if not (tex is Texture2D):
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.hframes = maxi(1, int((tex as Texture2D).get_width() / _frame_size.x))
	_sprite.vframes = maxi(1, int((tex as Texture2D).get_height() / _frame_size.y))
	_sprite.offset = Vector2(-_frame_size.x / 2.0, -_frame_size.y)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func set_walk_clamp(c: Callable) -> void:
	_walk_clamp = c


func place(pos: Vector2) -> void:
	position = pos.round()
	_has_target = false
	is_walking = false
	z_index = int(position.y)
	queue_redraw()


func walk_to(pos: Vector2) -> void:
	_walk_target = pos.round()
	_has_target = true
	is_walking = true


func stop() -> void:
	_has_target = false
	is_walking = false
	queue_redraw()


func face_towards(pos: Vector2) -> void:
	var d := pos - position
	if absf(d.x) >= absf(d.y):
		facing = Facing.RIGHT if d.x > 0 else Facing.LEFT
	else:
		facing = Facing.DOWN if d.y > 0 else Facing.UP
	queue_redraw()


func set_talking(v: bool) -> void:
	if is_talking == v:
		return
	is_talking = v
	queue_redraw()


## 자막을 띄울 머리 위 좌표.
func head_top() -> Vector2:
	return position + Vector2(0, -display_height - 3)


func _process(delta: float) -> void:
	_anim_time += delta

	if _has_target:
		var to := _walk_target - position
		var dist := to.length()
		if dist <= 1.0:
			position = _walk_target
			_has_target = false
			is_walking = false
			arrived.emit()
		else:
			var step: float = minf(walk_speed * delta, dist)
			var next := position + to.normalized() * step
			if _walk_clamp.is_valid():
				next = _walk_clamp.call(next) as Vector2
			face_towards(next if next != position else _walk_target)
			position = next
		# §21 pixel-perfect — 서브픽셀 위치를 남기지 않는다.
		position = position.round()
		z_index = int(position.y)

	if _sprite != null:
		_update_sprite_frame()
	elif is_walking or is_talking:
		queue_redraw()


func _update_sprite_frame() -> void:
	var row := int(facing) % maxi(_sprite.vframes, 1)
	var fps := IDLE_FPS
	if is_walking:
		fps = WALK_FPS
	elif is_talking:
		fps = TALK_FPS
	var col := int(_anim_time * fps) % maxi(_sprite.hframes, 1)
	if not is_walking and not is_talking:
		col = int(_anim_time * IDLE_FPS) % mini(2, maxi(_sprite.hframes, 1))
	_sprite.frame_coords = Vector2i(col, row)


# ---------------------------------------------------------------- 임시 도트

func _draw() -> void:
	if _sprite != null:
		return

	var h := display_height
	var w := int(roundf(h * 0.42))          # 어깨 폭
	var head_h := int(roundf(h * 0.24))
	var head_w := int(roundf(h * 0.23))
	var leg_h := int(roundf(h * 0.38))
	var body_h := h - head_h - leg_h

	var ol: Color = colors["outline"]
	var bob := 0
	if is_walking:
		bob = 1 if (int(_anim_time * WALK_FPS) % 2 == 0) else 0
	elif is_talking:
		bob = 1 if (int(_anim_time * TALK_FPS) % 2 == 0) else 0

	# 그림자 (§6.4 대형 그림자에 디더링)
	_rect(Rect2(-w / 2 - 1, -2, w + 2, 2), Color(0, 0, 0, 0.35))

	# 다리
	var leg_w := maxi(2, int(w * 0.3))
	var swing := 0
	if is_walking:
		swing = int([0, 1, 0, -1][int(_anim_time * WALK_FPS) % 4])
	_rect(Rect2(-w / 2 + 1, -leg_h, leg_w, leg_h - 2), colors["pants"], ol)
	_rect(Rect2(w / 2 - leg_w - 1, -leg_h, leg_w, leg_h - 2), colors["pants"], ol)
	# 신발
	_rect(Rect2(-w / 2 + 1 + swing, -2, leg_w + 1, 2), colors["shoes"])
	_rect(Rect2(w / 2 - leg_w - 1 - swing, -2, leg_w + 1, 2), colors["shoes"])

	# 몸통
	var body_y := -leg_h - body_h
	_rect(Rect2(-w / 2, body_y, w, body_h), colors["shirt"], ol)
	# 넥타이/포인트 색 (§6.7 각 캐릭터의 시각적 특징)
	_rect(Rect2(-1, body_y + 1, 2, int(body_h * 0.6)), colors["accent"])

	if has_coat:
		# §6.7 윤세라 — 각진 실루엣의 긴 코트
		_rect(Rect2(-w / 2 - 1, body_y, 2, body_h + int(leg_h * 0.6)), colors["accent"], ol)
		_rect(Rect2(w / 2 - 1, body_y, 2, body_h + int(leg_h * 0.6)), colors["accent"], ol)

	if has_bag:
		# §6.7 한개미 — 낡은 직장인 가방
		_rect(Rect2(w / 2 - 1, body_y + 3, 4, 5), colors["accent"], ol)

	# 팔
	var arm_y := body_y + 1 + bob
	_rect(Rect2(-w / 2 - 2, arm_y, 2, int(body_h * 0.8)), colors["shirt"], ol)
	_rect(Rect2(w / 2, arm_y, 2, int(body_h * 0.8)), colors["shirt"], ol)

	# 머리
	var head_y := body_y - head_h + bob
	_rect(Rect2(-head_w / 2, head_y, head_w, head_h), colors["skin"], ol)

	# 머리 모양 — 작은 스프라이트에서 실루엣으로 구분되게 (§6.1)
	match hair_style:
		"bob":   # 단발
			_rect(Rect2(-head_w / 2 - 1, head_y - 1, head_w + 2, int(head_h * 0.55)), colors["hair"])
			_rect(Rect2(-head_w / 2 - 1, head_y, 2, head_h), colors["hair"])
			_rect(Rect2(head_w / 2 - 1, head_y, 2, head_h), colors["hair"])
		"bald":
			_rect(Rect2(-head_w / 2, head_y, head_w, 1), colors["hair"])
		"slick":
			_rect(Rect2(-head_w / 2, head_y - 1, head_w, int(head_h * 0.35)), colors["hair"])
		_:       # messy
			_rect(Rect2(-head_w / 2 - 1, head_y - 2, head_w + 2, int(head_h * 0.42)), colors["hair"])
			_rect(Rect2(-head_w / 2 - 1, head_y - 3, 2, 2), colors["hair"])
			_rect(Rect2(head_w / 2 - 2, head_y - 3, 3, 2), colors["hair"])

	# 눈 — 방향에 따라 위치만 바꾼다
	var eye_y := head_y + int(head_h * 0.5)
	var eye_dx := 0
	match facing:
		Facing.LEFT: eye_dx = -1
		Facing.RIGHT: eye_dx = 1
		_: eye_dx = 0
	if facing != Facing.UP:
		_rect(Rect2(-2 + eye_dx, eye_y, 1, 1), ol)
		_rect(Rect2(1 + eye_dx, eye_y, 1, 1), ol)

	# 말하기 — 입이 2프레임으로 열리고 닫힌다 (§6.6)
	if is_talking:
		var mouth_h := 2 if bob == 1 else 1
		_rect(Rect2(-1, head_y + head_h - 3, 2, mouth_h), ol)


func _rect(r: Rect2, fill: Color, outline: Color = Color(0, 0, 0, 0)) -> void:
	if outline.a > 0.0:
		draw_rect(Rect2(r.position - Vector2.ONE, r.size + Vector2(2, 2)), outline, true)
	draw_rect(r, fill, true)


static func _facing_from(s: String) -> Facing:
	match s:
		"left": return Facing.LEFT
		"right": return Facing.RIGHT
		"up": return Facing.UP
		_: return Facing.DOWN
