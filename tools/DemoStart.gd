extends Node
## 데모 진입점 — 원하는 장면에서 바로 시작해 **사람이 조작한다.**
##
##   godot --path . tools/DemoStart.tscn                    황소항 (기본)
##   godot --path . tools/DemoStart.tscn -- subway_night    다른 장면
##   godot --path . tools/DemoStart.tscn -- harbor sera     세라가 나온 뒤 상태
##
## 캡처 도구(`tests/Screenshots.gd`)와 다른 점은 **끝나고 창을 넘겨준다**는 것뿐이다.
## 상태를 억지로 세우므로 퍼즐을 실제로 푼 결과와 다를 수 있다 — 눈으로 보는 용도다.

const MAIN_SCENE := "res://scenes/core/Main.tscn"

## 별칭. 긴 scene_id 를 외우지 않게
const ALIAS := {
	"harbor": "bull_harbor_entrance",
	"subway": "subway_night",
	"studio": "studio_room",
	"meeting": "office_meeting_room",
	"corridor": "office_corridor",
	"pantry": "office_pantry",
}

var main: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var target := "harbor"
	var with_sera := false
	for a in args:
		var s := str(a)
		if s == "sera":
			with_sera = true
		else:
			target = s
	var scene_id: String = ALIAS.get(target, target)

	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await _settle(20)

	main.call("_start_new_game")
	# 새 게임은 «비동기»다 — 인트로 카드 → 회의실 전환이 뒤이어 돌아간다.
	# 여기서 기다리지 않으면 아래 점프를 그 전환이 덮어쓴다 (실제로 회의실이 떴었다)
	await _idle()

	# 프롤로그를 건너뛴다. 실제로 푼 것이 아니라 «그 뒤 상태»를 세우는 것이다
	GameState.set_flag("boss_left", true)
	GameState.advance_puzzle("decaf_swap", "completed")
	GameState.give_item("id_card")
	GameState.give_item("phone")
	GameState.give_item("last_chance_flyer")
	if with_sera:
		GameState.set_flag("scam_done", true)
		GameState.advance_puzzle("first_scam", "scammed")
		GameState.give_item("loss_receipt")

	SceneDirector.change_scene(scene_id, "from_city")
	await _idle()
	if GameState.scene_id != scene_id:
		push_warning("점프 실패: %s 에 있어야 하는데 %s 다" % [scene_id, GameState.scene_id])

	await _show_window()
	print("\n데모 시작 — %s (실제 장면 %s)%s" % [scene_id, GameState.scene_id, "  (세라 등장 상태)" if with_sera else ""])
	print("좌클릭 이동·상호작용 / 우클릭 기본 동사 / TAB 대화 기록 / ESC 메뉴\n")


## 게임이 «완전히 멈출 때까지» 기다린다. 카드·자막·선택지는 넘기면서.
## 조용해진 상태가 몇 프레임 이어져야 끝난 것으로 본다 — 전환 사이에 한 프레임씩
## 조용해지는 순간이 있어서 한 번만 보면 속는다.
func _idle(max_frames: int = 3000) -> void:
	var quiet := 0
	for i in max_frames:
		await get_tree().process_frame
		if bool(main.card.is_active()):
			main.card.dismiss()
		if bool(main.choice_box.is_active()):
			main.choice_box.select_index(0)
		if bool(main.subtitles.is_active()):
			main.subtitles.advance()
		var busy: bool = bool(main.busy) or SceneDirector.is_changing() \
			or bool(main.dialogue_runner.is_active()) or bool(main.card.is_active()) \
			or bool(main.subtitles.is_active()) or bool(main.choice_box.is_active())
		quiet = 0 if busy else quiet + 1
		if quiet >= 20:
			return


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## 창을 «확실히» 사람 앞으로 꺼낸다.
## 그냥 grab_focus 만 하면 터미널 뒤에 숨은 채로 뜬다 — 그래서 안 보였다.
func _show_window() -> void:
	var win := get_window()
	win.set_flag(Window.FLAG_NO_FOCUS, false)
	win.mode = Window.MODE_WINDOWED

	# 화면이 여러 대면 창이 엉뚱한 데 뜬다. 무엇이 어디 있는지 먼저 찍는다
	var n := DisplayServer.get_screen_count()
	var primary := DisplayServer.get_primary_screen()
	for i in n:
		print("  화면 #%d %s%s  usable=%s" % [i, DisplayServer.screen_get_size(i),
			"  ← 주 화면" if i == primary else "", DisplayServer.screen_get_usable_rect(i)])

	# 주 화면 가운데. 인자 없는 usable_rect 는 «창이 이미 있던» 화면을 잡아 안 옮겨진다
	var scr := primary
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("screen="):
			scr = int(str(a).substr(7))
	var r := DisplayServer.screen_get_usable_rect(scr)

	# 창을 화면에 맞는 «정수 배»로 키운다. 기본 472×838 은 4K 화면에서 폭의 12%라
	# 있어도 안 보인다. 정수 배여야 도트가 안 뭉갠다 — Layout 머리말과 같은 이유다.
	var base := Vector2i(Layout.SCREEN) / 2                # 471×837
	# 여유는 «비율»이 아니라 고정값이다. 0.9 를 곱하면 세로가 딱 한 배 모자라 2배가 막힌다
	const MARGIN := 48
	var k: int = clampi(mini((r.size.x - MARGIN) / base.x, (r.size.y - MARGIN) / base.y), 1, 4)
	for a2 in OS.get_cmdline_user_args():
		if str(a2).begins_with("zoom="):
			k = clampi(int(str(a2).substr(5)), 1, 4)
	var size := base * k
	DisplayServer.window_set_size(size)
	var pos := r.position + (r.size - size) / 2

	win.current_screen = scr
	DisplayServer.window_set_position(pos)
	win.always_on_top = true
	DisplayServer.window_move_to_foreground()
	win.grab_focus()
	win.request_attention()
	await get_tree().process_frame

	# 한 번에 안 먹는 환경이 있다. 실제로 갔는지 확인하고 다시 민다
	if DisplayServer.window_get_position().distance_to(Vector2(pos)) > 4.0:
		DisplayServer.window_set_position(pos)
		await get_tree().process_frame

	await get_tree().create_timer(0.6).timeout
	win.always_on_top = false
	win.grab_focus()
	print("창 — 화면 #%d · 위치 %s · 크기 %s (%d배)" % [
		scr, DisplayServer.window_get_position(), size, k])
