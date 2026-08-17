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
const WALK_FPS := 10.0    ## 걷기 방향당 6프레임 (10fps × 6프레임 = 한 걸음 0.6초)
const TALK_FPS := 6.0     ## 말하기 2~3프레임

## §6.6 "걷기: 방향당 6프레임". 6프레임 한 주기의 포즈 표.
## 0·3 이 접지(발이 벌어지고 몸이 내려감), 1·2·4·5 가 통과 구간이다.
## 값을 표로 빼 두면 프레임 수를 바꿔도 그리는 코드는 그대로다.
const WALK_LEG   := [3, 2, 0, -3, -2, 0]    ## 앞다리 오프셋. 뒷다리는 부호 반대.
const WALK_BOB   := [0, 1, 1, 0, 1, 1]      ## 몸통 상하
const WALK_ARM   := [-2, -1, 0, 2, 1, 0]    ## 팔은 다리와 반대로
## 대기 3프레임 — 숨 쉬는 정도만. §6.6 "대기 2~4프레임"
const IDLE_BOB   := [0, 0, 1]

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
## §6.7 실루엣 구분용 특징. hair_style: "messy"|"bob"|"long_wave"|"bald"|"slick"
var hair_style := "messy"
var has_bag := false
var has_coat := false
var has_ruler := false        ## §6.7 윤세라 — 허리의 금속 자
var rolled_sleeves := false   ## §6.7 한개미 — 와이셔츠 소매를 걷은 모습

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
	has_ruler = bool(def.get("has_ruler", false))
	rolled_sleeves = bool(def.get("rolled_sleeves", false))
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

## 지금 프레임의 포즈. 걷기 6프레임 / 대기 3프레임 / 말하기 2프레임. (§6.6)
func _pose() -> Dictionary:
	if is_walking:
		var f := int(_anim_time * WALK_FPS) % 6
		return {"leg": int(WALK_LEG[f]), "arm": int(WALK_ARM[f]), "bob": int(WALK_BOB[f]),
				"mouth": 0}
	var idle_f := int(_anim_time * IDLE_FPS) % IDLE_BOB.size()
	var mouth := 0
	if is_talking:
		mouth = 1 if int(_anim_time * TALK_FPS) % 2 == 0 else 0
	return {"leg": 0, "arm": 0, "bob": int(IDLE_BOB[idle_f]), "mouth": mouth}


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
	var p := _pose()
	var bob: int = p["bob"]
	var side := facing == Facing.LEFT or facing == Facing.RIGHT
	var dir := -1 if facing == Facing.LEFT else 1

	# 그림자 — 발밑에만. §6.4 대형 그라데이션 대신 단색 두 겹.
	_rect(Rect2(-w / 2 - 1, -2, w + 2, 2), Color(0, 0, 0, 0.35))
	_rect(Rect2(-w / 2 + 1, -3, w - 2, 1), Color(0, 0, 0, 0.18))

	# ---- 다리. 옆을 볼 때는 앞뒤로, 앞뒤를 볼 때는 좌우로 벌어진다.
	var leg_w := maxi(2, int(w * 0.3))
	var swing: int = p["leg"]
	var lx_a: int = -w / 2 + 1
	var lx_b: int = w / 2 - leg_w - 1
	if side:
		# 옆모습에서는 두 다리가 거의 겹치고, 스윙만 앞뒤로 나온다.
		lx_a = -leg_w / 2 + swing * dir
		lx_b = -leg_w / 2 - swing * dir
		_rect(Rect2(lx_b, -leg_h, leg_w, leg_h - 2), colors["pants"].darkened(0.25), ol)
		_rect(Rect2(lx_b - 1, -2, leg_w + 2, 2), colors["shoes"].darkened(0.2))

	_rect(Rect2(lx_a, -leg_h, leg_w, leg_h - 2), colors["pants"], ol)
	_rect(Rect2(lx_a - 1, -2, leg_w + 2, 2), colors["shoes"])
	if not side:
		_rect(Rect2(lx_b, -leg_h, leg_w, leg_h - 2), colors["pants"], ol)
		_rect(Rect2(lx_b + swing, -2, leg_w + 1, 2), colors["shoes"])

	# ---- 몸통
	var body_y := -leg_h - body_h + bob
	_rect(Rect2(-w / 2, body_y, w, body_h), colors["shirt"], ol)

	if facing != Facing.UP:
		# 넥타이/포인트 색. 뒤를 보고 있으면 안 보인다. (§6.7)
		var tie_x := -1 + (dir if side else 0)
		_rect(Rect2(tie_x, body_y + 1, 2, int(body_h * 0.6)), colors["accent"])

	if has_coat:
		# §6.7 윤세라 — 각진 실루엣의 긴 코트. 무릎 아래까지 내려온다.
		var coat_h := body_h + int(leg_h * 0.62)
		_rect(Rect2(-w / 2 - 1, body_y, 2, coat_h), colors["accent"], ol)
		_rect(Rect2(w / 2 - 1, body_y, 2, coat_h), colors["accent"], ol)
		_rect(Rect2(-w / 2 - 1, body_y + coat_h - 1, w + 2, 1), colors["accent"].darkened(0.3))

	if has_ruler:
		# §6.7 윤세라 — 허리의 금속 자
		var ruler_x := (w / 2 - 1) if dir > 0 else (-w / 2 - 1)
		_rect(Rect2(ruler_x, body_y + body_h - 2, 1, 7), Color.html("#8f9a8c"))

	if has_bag:
		# §6.7 한개미 — 낡은 직장인 가방. 걸을 때 반박자 늦게 흔들린다.
		var bag_dx := -1 if p["arm"] < 0 else 0
		_rect(Rect2(w / 2 - 1 + bag_dx, body_y + 3, 4, 5), colors["accent"], ol)

	# ---- 팔. 다리와 반대로 흔들린다.
	var arm_len := int(body_h * 0.8)
	var arm: int = p["arm"]
	_draw_arm(-w / 2 - 2, body_y + 1 + (arm if side else 0), 2, arm_len, ol)
	_draw_arm(w / 2, body_y + 1 - (arm if side else 0), 2, arm_len, ol)

	# ---- 머리
	var head_y := body_y - head_h
	_rect(Rect2(-head_w / 2, head_y, head_w, head_h), colors["skin"], ol)

	_draw_hair(head_y, head_w, head_h, side, dir)
	_draw_face(head_y, head_w, head_h, side, dir, int(p["mouth"]), ol)


## 소매를 걷었으면 팔 아래쪽이 살색이다. (§6.7 한개미)
func _draw_arm(x: int, y: int, w: int, length: int, ol: Color) -> void:
	if not rolled_sleeves:
		_rect(Rect2(x, y, w, length), colors["shirt"], ol)
		return
	var upper := int(length * 0.55)
	_rect(Rect2(x, y, w, upper), colors["shirt"], ol)
	_rect(Rect2(x, y + upper, w, length - upper), colors["skin"], ol)


func _draw_hair(head_y: int, head_w: int, head_h: int, side: bool, dir: int) -> void:
	match hair_style:
		"long_wave":
			# §6.7 윤세라 — 긴 갈색 웨이브. 어깨 아래까지 내려온다 (2026-08-17 목업 채택).
			# 단발(bob)과 실루엣이 갈려야 한다 — 그게 이 자리표시자의 유일한 일이다.
			_rect(Rect2(-head_w / 2 - 1, head_y - 2, head_w + 2, int(head_h * 0.5)), colors["hair"])
			var fall := head_h + 4
			_rect(Rect2(-head_w / 2 - 2, head_y, 3, fall), colors["hair"])
			_rect(Rect2(head_w / 2 - 1, head_y, 3, fall), colors["hair"])
			if side:
				var back2 := (-head_w / 2 - 3) if dir > 0 else (head_w / 2 + 1)
				_rect(Rect2(back2, head_y, 2, fall + 1), colors["hair"])
			# 금 귀걸이 — accent 는 장신구 색이다
			_rect(Rect2(head_w / 2 - 1, head_y + int(head_h * 0.55), 1, 2), colors["accent"])
		"bob":
			# §6.7 옛 윤세라 규격. 다른 인물이 쓸 수 있어 남긴다.
			_rect(Rect2(-head_w / 2 - 1, head_y - 1, head_w + 2, int(head_h * 0.55)), colors["hair"])
			_rect(Rect2(-head_w / 2 - 1, head_y, 2, head_h), colors["hair"])
			_rect(Rect2(head_w / 2 - 1, head_y, 2, head_h), colors["hair"])
			if side:
				var back := (-head_w / 2 - 2) if dir > 0 else (head_w / 2)
				_rect(Rect2(back, head_y, 2, head_h + 1), colors["hair"])
		"bald":
			_rect(Rect2(-head_w / 2, head_y, head_w, 1), colors["hair"])
			_rect(Rect2(-head_w / 2 - 1, head_y + 2, 1, int(head_h * 0.4)), colors["hair"])
			_rect(Rect2(head_w / 2, head_y + 2, 1, int(head_h * 0.4)), colors["hair"])
		"slick":
			_rect(Rect2(-head_w / 2, head_y - 1, head_w, int(head_h * 0.35)), colors["hair"])
			_rect(Rect2(-head_w / 2, head_y - 1, head_w, 1), colors["hair"].lightened(0.25))
		_:
			# messy — §6.7 한개미, 약간 헝클어진 머리
			_rect(Rect2(-head_w / 2 - 1, head_y - 2, head_w + 2, int(head_h * 0.42)), colors["hair"])
			_rect(Rect2(-head_w / 2 - 1, head_y - 3, 2, 2), colors["hair"])
			_rect(Rect2(head_w / 2 - 2, head_y - 3, 3, 2), colors["hair"])


func _draw_face(head_y: int, head_w: int, head_h: int, side: bool, dir: int,
		mouth: int, ol: Color) -> void:
	# 뒤를 보고 있으면 얼굴이 없다. 이게 방향을 알려 주는 가장 확실한 신호다.
	if facing == Facing.UP:
		return
	var eye_y := head_y + int(head_h * 0.5)
	if side:
		# 옆모습 — 눈 하나, 코 한 픽셀
		_rect(Rect2(dir, eye_y, 1, 1), ol)
		_rect(Rect2(dir * (head_w / 2), eye_y + 1, 1, 1), colors["skin"].darkened(0.3))
		if mouth > 0:
			_rect(Rect2(dir, head_y + head_h - 3, 2, 2), ol)
		return

	_rect(Rect2(-2, eye_y, 1, 1), ol)
	_rect(Rect2(1, eye_y, 1, 1), ol)
	if mouth > 0:
		_rect(Rect2(-1, head_y + head_h - 3, 2, 2), ol)
	elif is_talking:
		_rect(Rect2(-1, head_y + head_h - 3, 2, 1), ol)


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
