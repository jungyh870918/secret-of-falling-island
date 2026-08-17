class_name LocationView
extends Node2D
## 한 장면(방)의 시각 표현과 공간 질의. 명세서 §5.1, §16.1.
##
## 이 스크립트에는 특정 장면 고유의 분기가 없다. 전부 data/scenes/*.json 을 해석한다.
##
## [최종 에셋 교체 지점]
##   장면 데이터의 "background" 경로에 PNG 가 있으면 blocks 대신 그 그림을 그린다.
##   blocks 는 그 전까지 쓰는 임시 도트다. (§21 "단색 픽셀 블록")

## 월드 층 선 두께. §06 「테두리 = 1 게임픽셀 × UI 배율」.
## 월드는 942 폭이라 1.0 으로 그으면 머리카락이 된다.
const LINE := float(Layout.UI_SCALE)

const DITHER_2X2 := [[1, 0], [0, 1]]
const DITHER_4X4 := [
	[1, 0, 0, 0],
	[0, 0, 1, 0],
	[0, 1, 0, 0],
	[0, 0, 0, 1],
]

var scene_id := ""
var data: Dictionary = {}
var player: Actor = null

var _background: Texture2D = null
var _actors: Dictionary = {}      ## hotspot_id -> Actor
var _walkboxes: Array[Rect2] = []
var _time := 0.0
var _hover_id := ""


func setup(p_scene_id: String, entry: String = "default") -> void:
	scene_id = p_scene_id
	data = GameData.scene(scene_id)
	z_index = 0

	var bg_path := str(data.get("background", ""))
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		var res := ResourceLoader.load(bg_path)
		if res is Texture2D:
			_background = res

	_walkboxes.clear()
	var k := _scale_of(data)
	for r in _rect_list(data.get("walkbox", [])):
		_walkboxes.append(Rect2(r.position * k, r.size * k))

	_spawn_actors()
	_spawn_player(entry)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	# 환경 애니메이션(§6.6)과 핫스폿 점멸(§6.5)이 있으므로 매 프레임 다시 그린다.
	queue_redraw()


# ---------------------------------------------------------------- 배치

func _spawn_player(entry: String) -> void:
	var char_def: Dictionary = GameData.characters.get("han_gaemi", {})
	player = Actor.new()
	player.name = "Player"
	add_child(player)
	player.setup(char_def)
	player.set_walk_clamp(Callable(self, "clamp_to_walkbox"))
	player.place(spawn_point(entry))
	_actors["player"] = player


func _spawn_actors() -> void:
	for h in data.get("hotspots", []):
		if not (h is Dictionary):
			continue
		var hd: Dictionary = h
		var actor_id := str(hd.get("character", ""))
		if actor_id.is_empty():
			continue
		if not is_hotspot_visible(hd):
			continue
		var a := Actor.new()
		a.name = "Actor_" + str(hd.get("id", actor_id))
		add_child(a)
		var def: Dictionary = GameData.characters.get(actor_id, {}).duplicate(true)
		if hd.has("facing"):
			def["facing"] = hd["facing"]
		a.setup(def)
		var pos = hd.get("stand_at", null)
		if pos is Array and (pos as Array).size() >= 2:
			a.place(_pt(pos))
		_actors[str(hd.get("id", actor_id))] = a


func actor(id: String) -> Actor:
	var a = _actors.get(id, null)
	return a if a is Actor and is_instance_valid(a) else null


## 핫스폿이 사라졌을 때(예: 부장 퇴장) 배우도 함께 치운다.
func refresh_actors() -> void:
	for h in data.get("hotspots", []):
		if not (h is Dictionary):
			continue
		var hd: Dictionary = h
		var id := str(hd.get("id", ""))
		var a := actor(id)
		var visible_now := is_hotspot_visible(hd)
		if a != null and not visible_now:
			a.queue_free()
			_actors.erase(id)
		elif a == null and visible_now and not str(hd.get("character", "")).is_empty():
			_spawn_actors()
			return


func spawn_point(entry: String) -> Vector2:
	var sp = data.get("spawn_points", {})
	if sp is Dictionary:
		var d: Dictionary = sp
		for key in [entry, "default", "player"]:
			var v = d.get(key, null)
			if v is Array and (v as Array).size() >= 2:
				return _pt(v)
	if not _walkboxes.is_empty():
		return _walkboxes[0].get_center()
	return Vector2(Layout.WORLD_SIZE) * 0.5


func place_player(pos: Vector2) -> void:
	if player != null:
		player.place(clamp_to_walkbox(pos))


# ---------------------------------------------------------------- 공간 질의

## 걸을 수 있는 영역 안으로 밀어 넣는다. (§11.2 "픽셀 하나짜리 오브젝트 찾기" 금지와 별개로,
## 클릭이 살짝 빗나가도 이동이 되게 하려는 목적)
func clamp_to_walkbox(p: Vector2) -> Vector2:
	if _walkboxes.is_empty():
		return p
	for r in _walkboxes:
		if r.has_point(p):
			return p
	var best := p
	var best_d := INF
	for r in _walkboxes:
		var c := Vector2(
			clampf(p.x, r.position.x, r.position.x + r.size.x),
			clampf(p.y, r.position.y, r.position.y + r.size.y))
		var d := c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


## 커서 아래의 핫스폿/출구. 위에 있는 것(작은 것)부터 우선.
## 판정에 더할 여유 픽셀. 터치 기기에서 Main 이 올린다 —
## 손가락은 커서보다 뭉툭해서 320×180 격자에서는 정확히 짚기 어렵다. (§20 Phase 2 P2-1)
## 넓이 비교는 원래 크기로 하므로 "겹치면 작은 쪽이 이긴다" 규칙은 그대로다.
static var hit_padding := 0.0


## p 는 **화면 좌표**다. 월드 로컬로 바꿔서 판정한다 (세로 셸)
func hotspot_at(screen_p: Vector2) -> Dictionary:
	if not Layout.in_view(screen_p):
		return {}
	var p := Layout.to_world(screen_p)
	var best: Dictionary = {}
	var best_area := INF
	for h in data.get("hotspots", []):
		if not (h is Dictionary):
			continue
		if not is_hotspot_visible(h):
			continue
		var r := _rect_of(h)
		if r.has_area() and r.grow(hit_padding).has_point(p) and r.get_area() < best_area:
			best = h
			best_area = r.get_area()
	for e in data.get("exits", []):
		if not (e is Dictionary):
			continue
		if not is_exit_enabled(e):
			continue
		var r2 := _rect_of(e)
		if r2.has_area() and r2.grow(hit_padding).has_point(p) and r2.get_area() < best_area:
			best = e
			best_area = r2.get_area()
	return best


func is_hotspot_visible(h: Dictionary) -> bool:
	var default_on := bool(h.get("enabled", true))
	if not GameState.is_hotspot_enabled(scene_id, str(h.get("id", "")), default_on):
		return false
	return Conditions.evaluate(h.get("visible_if", null))


func is_exit_enabled(e: Dictionary) -> bool:
	var default_on := bool(e.get("enabled", true))
	if not GameState.is_exit_enabled(scene_id, str(e.get("id", "")), default_on):
		return false
	return Conditions.evaluate(e.get("visible_if", null))


func is_exit(h: Dictionary) -> bool:
	return h.has("target")


## 상호작용 전 걸어갈 좌표.
func walk_to_of(h: Dictionary) -> Vector2:
	var w = h.get("walk_to", null)
	if w is Array and (w as Array).size() >= 2:
		return _pt(w)
	var r := _rect_of(h)
	return clamp_to_walkbox(Vector2(r.get_center().x, r.position.y + r.size.y))


func set_hover(id: String) -> void:
	_hover_id = id


# ---------------------------------------------------------------- 그리기

## 배경을 «늘리지 않고» 월드 밴드를 채운 뒤 남는 쪽을 잘라낸다.
## 늘리면 8% 가로로 뚱뚱해진다 (1024×1536 → 942×1305). 아트 기준: 넉넉히 그리고 화면이 잘라 쓴다.
## 자르는 위치는 장면의 "bg_anchor" [x, y] 로 조절한다. 기본 0.5 = 가운데.
func _background_src() -> Rect2:
	var dst := Vector2(Layout.VIEW_RECT.size)
	var ts := Vector2(_background.get_size())
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2(Vector2.ZERO, ts)
	var k := maxf(dst.x / ts.x, dst.y / ts.y)
	var src_size := (dst / k).min(ts)
	var a := Vector2(0.5, 0.5)
	var av = data.get("bg_anchor", null)
	if av is Array and (av as Array).size() >= 2:
		a = Vector2(clampf(float(av[0]), 0.0, 1.0), clampf(float(av[1]), 0.0, 1.0))
	return Rect2((ts - src_size) * a, src_size)


func _draw() -> void:
	if _background != null:
		draw_texture_rect_region(_background, Rect2(Vector2.ZERO, Vector2(Layout.VIEW_RECT.size)),
			_background_src())
	else:
		_draw_blocks()

	if bool(SaveManager.get_setting("high_contrast_hotspots", false)):
		_draw_hotspot_outlines()
	if bool(SaveManager.get_setting("show_exit_markers", false)):
		_draw_exit_markers()
	_draw_hover_outline()


func _draw_blocks() -> void:
	for b in data.get("blocks", []):
		if not (b is Dictionary):
			continue
		var bd: Dictionary = b
		if not Conditions.evaluate(bd.get("visible_if", null)):
			continue
		var hs_id := str(bd.get("hotspot", ""))
		if not hs_id.is_empty():
			var hd := GameData.hotspot_def(scene_id, hs_id)
			if not hd.is_empty() and not (is_hotspot_visible(hd) or is_exit_enabled(hd)):
				continue

		var r := _rect_of(bd)
		var c := Palette.parse(bd.get("color", "#ff00ff"))
		var anim := str(bd.get("anim", ""))
		match anim:
			# §6.6 "주가 전광판 숫자가 불규칙하게 바뀜", "HTS 화면에서 캔들이 오르내림"
			"flicker":
				if fposmod(_time * 7.0 + r.position.x, 3.0) < 0.5:
					c = c.lightened(0.25)
			"blink":
				if fposmod(_time * 1.6 + r.position.y * 0.1, 2.0) < 1.0:
					c = c.darkened(0.35)
			"ticker":
				# 캔들이 오르내리는 느낌 — 높이를 흔든다
				var k := int(fposmod(_time * 4.0 + r.position.x * 0.7, 4.0))
				r.position.y += k - 1
				r.size.y = maxf(1.0, r.size.y - (k - 1))

		var dither := str(bd.get("dither", ""))
		if dither.is_empty():
			draw_rect(r, c, true)
		else:
			# §6.4 그라데이션 대신 디더링
			var c2 := Palette.parse(bd.get("color2", "#000000"), c.darkened(0.3))
			_draw_dithered(r, c, c2, DITHER_4X4 if dither == "4x4" else DITHER_2X2)

		var outline = bd.get("outline", null)
		if outline != null:
			draw_rect(r, Palette.parse(outline), false, 1.0)


func _draw_dithered(r: Rect2, a: Color, b: Color, pattern: Array) -> void:
	draw_rect(r, a, true)
	var n: int = pattern.size()
	var x0 := int(r.position.x)
	var y0 := int(r.position.y)
	for y in int(r.size.y):
		var row: Array = pattern[y % n]
		for x in int(r.size.x):
			if int(row[x % n]) == 1:
				draw_rect(Rect2(x0 + x, y0 + y, 1, 1), b, true)


## §18 고대비 핫스폿 모드
func _draw_hotspot_outlines() -> void:
	for h in data.get("hotspots", []):
		if h is Dictionary and is_hotspot_visible(h):
			draw_rect(_rect_of(h), Palette.ui("text_hot"), false, LINE)


## §18 길 찾기용 출구 표시 옵션
func _draw_exit_markers() -> void:
	for e in data.get("exits", []):
		if not (e is Dictionary) or not is_exit_enabled(e):
			continue
		var r := _rect_of(e)
		var cx := r.get_center().x
		var top := r.position.y - 4
		# 색만이 아니라 모양으로도 알 수 있게 삼각형 마커 (§18)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 3, top), Vector2(cx + 3, top), Vector2(cx, top + 4)]),
			Palette.ui("text_hot"))


## 마우스오버 포커스. §6.5 "발광 대신 1px 테두리".
## 점멸시키지 않는다 — 커서를 올린 순간 바로, 계속 보여야 한다.
## (점멸은 눈이 아프고 '지금 반응이 없는 건가' 하는 착각을 준다)
func _draw_hover_outline() -> void:
	if _hover_id.is_empty():
		return
	var h := GameData.hotspot_def(scene_id, _hover_id)
	if h.is_empty():
		return
	var r := _rect_of(h)
	# 어두운 배경에도, 밝은 배경에도 읽히도록 안쪽에 어두운 선을 한 겹 깐다.
	draw_rect(r.grow(LINE), Palette.ui("outline"), false, LINE)
	draw_rect(r, Palette.ui("text_hot"), false, LINE)


# ---------------------------------------------------------------- 유틸

## 장면 좌표 → 월드 로컬 픽셀.
##
## 장면에 `"coord_space": "norm"` 이 있으면 rect 는 0~1 비율이고 밴드 크기를 곱한다.
## 없으면 옛 320×135 픽셀 공간이라 **균일 배율로** 밴드에 맞춘다 —
## 찌그러뜨리지 않는다. 화면을 다 못 채울 뿐이다.
## (기준 캔버스 D1 이 아직 뒤집힐 수 있어 픽셀을 데이터에 박지 않는다)
## 장면 좌표의 «점» → 월드 로컬 픽셀. rect 와 같은 배율을 쓴다
func _pt(v: Variant) -> Vector2:
	if not (v is Array) or (v as Array).size() < 2:
		return Vector2.ZERO
	var k := _scale_of(data)
	return Vector2(float(v[0]) * k.x, float(v[1]) * k.y)


static func _scale_of(scene: Dictionary) -> Vector2:
	if str(scene.get("coord_space", "")) == "norm":
		return Vector2(Layout.WORLD_SIZE)
	# 아직 안 옮긴 옛 장면(320×135 픽셀)은 «축마다 따로» 늘려 월드 밴드를 채운다.
	# 균일 배율로 맞추면 세로 셸의 아래 2/3 가 빈 채로 남는다.
	# 자리표시자 blocks 와 핫스폿이 같은 배율을 타므로 서로 어긋나지 않는다.
	return Vector2(float(Layout.WORLD_SIZE.x) / 320.0, float(Layout.WORLD_SIZE.y) / 135.0)


func _rect_of(d: Dictionary) -> Rect2:
	return _rect_in(data, d)


static func _rect_in(scene: Dictionary, d: Dictionary) -> Rect2:
	var r = d.get("rect", null)
	if not (r is Array) or (r as Array).size() < 4:
		return Rect2()
	var k := _scale_of(scene)
	return Rect2(float(r[0]) * k.x, float(r[1]) * k.y,
		float(r[2]) * k.x, float(r[3]) * k.y)


static func _rect_list(v: Variant) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not (v is Array) or (v as Array).is_empty():
		return out
	var arr: Array = v
	if arr[0] is Array:
		for e in arr:
			if e is Array and (e as Array).size() >= 4:
				out.append(Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])))
	elif arr.size() >= 4:
		out.append(Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3])))
	return out
