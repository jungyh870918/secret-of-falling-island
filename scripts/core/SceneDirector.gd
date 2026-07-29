extends Node
## 장면 전환 담당. (autoload: SceneDirector)
##
## 명세서 §17 "자동 저장 시점: 장면 전환".
## 화면 전환은 DOS 시절 감성에 맞춰 부드러운 페이드가 아니라 짧은 계단식 암전을 쓴다.

signal scene_will_change(from_id: String, to_id: String)
signal scene_changed(scene_id: String)

const FADE_STEPS := 6
const FADE_STEP_SEC := 0.022

## Main 이 주입한다. LocationView 가 붙을 부모 노드.
var world_root: Node2D = null
## 현재 LocationView 인스턴스
var current_view: LocationView = null

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _changing := false


func _ready() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)


func is_changing() -> bool:
	return _changing


## entry: 도착 장면의 spawn_points 키. 없으면 "default".
func change_scene(scene_id: String, entry: String = "default") -> void:
	if _changing:
		return
	if not GameData.scenes.has(scene_id):
		push_error("[SceneDirector] 없는 장면: %s" % scene_id)
		return
	_changing = true

	var from_id := GameState.scene_id
	scene_will_change.emit(from_id, scene_id)
	AudioDirector.play_sfx("whoosh")

	await _fade(0.0, 1.0)

	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
		current_view = null
	# queue_free 는 프레임 끝에 처리되므로 한 프레임 넘긴다.
	await get_tree().process_frame

	GameState.scene_id = scene_id
	var view := LocationView.new()
	view.name = "LocationView"
	if world_root != null:
		world_root.add_child(view)
	else:
		add_child(view)
	current_view = view
	view.setup(scene_id, entry)

	AudioDirector.play_music(str(GameData.scene(scene_id).get("music", "")))

	scene_changed.emit(scene_id)

	await _fade(1.0, 0.0)
	_changing = false

	# §17 자동 저장 시점 — 장면 전환
	SaveManager.autosave()


## 저장 불러오기 직후처럼 페이드 없이 즉시 세우는 경우.
func enter_scene_immediate(scene_id: String, entry: String = "default", position: Vector2 = Vector2.ZERO) -> void:
	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
		current_view = null
		await get_tree().process_frame

	GameState.scene_id = scene_id
	var view := LocationView.new()
	view.name = "LocationView"
	if world_root != null:
		world_root.add_child(view)
	else:
		add_child(view)
	current_view = view
	view.setup(scene_id, entry)
	if position != Vector2.ZERO:
		view.place_player(position)
	AudioDirector.play_music(str(GameData.scene(scene_id).get("music", "")))
	_fade_rect.color = Color(0, 0, 0, 0)
	scene_changed.emit(scene_id)


func _fade(from_a: float, to_a: float) -> void:
	# 계단식 암전 — 8단계 딜레이. §6.1 "과도한 현대식 광원 금지" 정서에 맞춘다.
	for i in range(FADE_STEPS + 1):
		var a: float = lerpf(from_a, to_a, float(i) / float(FADE_STEPS))
		_fade_rect.color = Color(0, 0, 0, snappedf(a, 1.0 / FADE_STEPS))
		await get_tree().create_timer(FADE_STEP_SEC).timeout
	_fade_rect.color = Color(0, 0, 0, to_a)
