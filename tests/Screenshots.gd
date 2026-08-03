extends Node
## 화면 캡처 도구. 헤드리스가 아닌 실제 렌더링으로 320×180 프레임을 PNG 로 뽑는다.
##
##   godot --path . tests/Screenshots.tscn
##
## §19.3 아트 체크리스트와 §18 가독성을 눈으로 확인하기 위한 것이다.
## 특히 한글이 9~12px 에서 읽히는지, 자막이 화면 밖으로 나가지 않는지.
##
## 결과: docs/screenshots/NN_<이름>.png (320×180 원본 해상도)

const MAIN_SCENE := "res://scenes/core/Main.tscn"
const OUT_DIR := "res://docs/screenshots"
const TIME_SCALE := 4.0

var main: Node
var _shot := 0


func _ready() -> void:
	_hide_window()
	Engine.time_scale = TIME_SCALE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveManager.set_setting("text_speed", 3)
	SaveManager.set_setting("verb_ui", "classic")
	SaveManager.set_setting("font_size_index", 1)
	await get_tree().process_frame

	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await settle(20)

	await capture("title", "타이틀 화면")

	main.call("_open_settings")
	await settle(10)
	await capture("settings", "설정 12항목이 박스 안에 들어가는지")
	main.call("_close_settings")
	await settle(10)

	# --- 새 게임: 인트로 카드가 실제로 뜰 때까지 기다렸다가 찍는다 ---
	main.call("_start_new_game")
	if await wait_until(func(): return bool(main.card.is_active())):
		await settle(6)
		await capture("card_intro", "§3.2 인트로 컷신 카드")
		await dismiss_card()

	# 오프닝 내레이션 자막
	if await wait_until(func(): return bool(main.subtitles.is_active())):
		await settle(4)
		await capture("subtitle_narration", "내레이션 자막 — 화자색 + 1px 외곽선")
	await auto_advance()

	await capture("room_meeting", "§8.1 회의실 — 하단 25% 명령 패널")

	# 마우스오버 포커스 — 실제 커서를 핫스폿 위로 옮겨서 확인한다.
	# (수동으로 set_hover 만 하면 _update_hover 가 매 프레임 덮어쓴다)
	await hover_over("boss_mug")
	await capture("hover_focus", "마우스오버 포커스 + §5.3 문장 라인 (보다 → 부장의 머그컵)")

	# 아이템을 든 상태의 3단 문장 라인
	main.held_item = "id_card"
	main.panel.set_held_item("id_card")
	main.current_verb = Actions.Verb.USE
	main.panel.set_verb(Actions.Verb.USE)
	await hover_over("boss")
	await capture("sentence_use_item", "§5.3 사용하다 → 사원증 → 부장")
	main.held_item = ""
	main.panel.set_held_item("")
	main.current_verb = Actions.Verb.LOOK
	main.panel.set_verb(Actions.Verb.LOOK)
	await unhover()

	# --- 부장 대화: 대사 한 장, 선택지 한 장 ---
	main.call("_interact", "boss", Actions.Verb.TALK)
	if await wait_until(func(): return bool(main.subtitles.is_active())):
		await settle(4)
		await capture("dialogue_line", "부장 대사 — 화자색 구분")
	if await wait_until(func(): return bool(main.choice_box.is_active()), 2400,
			func(): if bool(main.subtitles.is_active()): main.subtitles.advance()):
		await settle(4)
		await capture("dialogue_choices", "§5.4 선택지 4개")
	await auto_advance()

	# §5.2 간소화 UI
	SaveManager.set_setting("verb_ui", "simple")
	main.panel.queue_redraw()
	await settle(6)
	await capture("panel_simple", "§5.2 간소화 UI — 조사/대화/사용/이동")
	SaveManager.set_setting("verb_ui", "classic")
	main.panel.queue_redraw()
	await settle(4)

	# --- 복도 ---
	main.call("_interact", "door_corridor", Actions.Verb.WALK)
	await auto_advance()
	await capture("room_corridor", "복도 — 사훈 액자 · 정수기 · 엘리베이터")

	# 강조를 끈 상태 — 임시 아트만으로 뭐가 상호작용 가능한지 알 수 있나?
	SaveManager.set_setting("high_contrast_hotspots", false)
	SaveManager.set_setting("show_exit_markers", false)
	await settle(8)
	await capture("highlight_off", "핫스폿 강조 OFF — 대비용. 뭐가 클릭 가능한지 알 수 없다")

	SaveManager.set_setting("high_contrast_hotspots", true)
	SaveManager.set_setting("show_exit_markers", true)
	await settle(8)
	await capture("highlight_on", "§18 강조 ON (프로토타입 기본값) + 출구 삼각 마커")
	SaveManager.set_setting("show_exit_markers", false)
	await settle(4)

	# --- 탕비실 + 인벤토리 ---
	main.call("_interact", "door_pantry", Actions.Verb.WALK)
	await auto_advance()
	await capture("room_pantry_before", "탕비실 (집기 전) — 커피 봉지 두 개가 강조되는지")

	main.call("_interact", "decaf_shelf", Actions.Verb.PICKUP)
	await auto_advance()
	main.call("_interact", "strong_shelf", Actions.Verb.PICKUP)
	await auto_advance()
	await capture("room_pantry", "탕비실 (집은 뒤) — 인벤토리 4칸, 봉지 핫스폿 소멸")

	# 실패 대사 한 장 (§21)
	main.held_item = "id_card"
	main.call("_interact", "coffee_machine", Actions.Verb.USE)
	if await wait_until(func(): return bool(main.subtitles.is_active())):
		await settle(4)
		await capture("fail_line", "§21 고유 실패 대사")
	await auto_advance()

	# --- 대화 기록 ---
	main.log_view.open()
	await settle(8)
	await capture("log", "§18 대화 기록")
	main.log_view.close()
	await settle(4)

	# --- 저장 화면 ---
	SaveManager.save_to(SaveManager.manual_slot(0))
	await settle(6)
	main.call("_open_save_menu", 0)
	await settle(8)
	await capture("save_menu", "§17 저장 화면 — 도트 썸네일")
	main.call("_close_save_menu")
	await settle(8)
	main.call("_resume")
	await settle(4)

	# --- 디버그 패널 ---
	main.debug_panel.toggle()
	await settle(6)
	await capture("debug", "§21 디버그 패널")
	main.debug_panel.toggle()
	await settle(4)

	# --- 폰트 크게 ---
	SaveManager.set_setting("font_size_index", 2)
	main.call("_apply_settings")
	await settle(8)
	await capture("font_large", "§18 글자 크게 — 레이아웃 유지 확인")
	SaveManager.set_setting("font_size_index", 1)
	main.call("_apply_settings")
	await settle(6)

	await _phase2_shots()

	print("\n총 %d장 저장: %s" % [_shot, ProjectSettings.globalize_path(OUT_DIR)])
	get_tree().quit()


## Phase 2 구간 — 지하철·원룸·황소항, 초상화, 대화 배틀.
## 퍼즐을 실제로 풀지 않고 상태를 직접 세워 장면만 확인한다.
func _phase2_shots() -> void:
	GameState.set_flag("boss_left", true)
	GameState.advance_puzzle("decaf_swap", "completed")

	await jump("subway_night", "from_office")
	await capture("room_subway", "§8.1 심야 지하철 — 광고판 · 노선도 · 바닥의 전단지")

	main.call("_interact", "subway_window", Actions.Verb.LOOK)
	if await wait_until(func(): return bool(main.subtitles.is_active())):
		await settle(4)
		await capture("subway_reflection", "창문 반사 — §8.1 '결핍 제시'")
	await auto_advance()

	await jump("studio_room", "from_subway")
	await capture("room_studio", "§8.1 한개미의 원룸 — 노트북 · 냉장고 · 매트리스")

	# §5.4 초상화 대화 — 박프로 방송
	GameState.give_item("last_chance_flyer")
	main.held_item = "last_chance_flyer"
	main.call("_interact", "laptop", Actions.Verb.USE)
	if await wait_until(func(): return bool(main.portraits.speaker == "park"), 2400,
			func(): if bool(main.subtitles.is_active()) and main.portraits.speaker != "park":
				main.subtitles.advance()):
		await settle(6)
		await capture("portrait_park", "§5.4 초상화 대화 — 박프로 방송")
	if await wait_until(func(): return bool(main.choice_box.is_active()), 2400,
			func(): if bool(main.subtitles.is_active()): main.subtitles.advance()):
		await settle(4)
		await capture("portrait_choices", "§5.4 초상화 + 선택지 4개")
	await auto_advance()

	await jump("bull_harbor_entrance", "from_city")
	await capture("room_harbor", "§8.1 황소항 입구 — 황소 동상 · 전광판 · 환전소")

	# 세라 등장 상태
	GameState.set_flag("scam_done", true)
	GameState.advance_puzzle("first_scam", "scammed")
	GameState.give_item("loss_receipt")
	await jump("bull_harbor_entrance", "from_city")
	await capture("harbor_sera", "§8.1 윤세라 첫 등장 — 코트 실루엣과 금속 자")

	main.call("_interact", "sera", Actions.Verb.TALK)
	if await wait_until(func(): return bool(main.portraits.speaker == "sera"), 2400,
			func(): if bool(main.subtitles.is_active()) and main.portraits.speaker != "sera":
				main.subtitles.advance()):
		await settle(6)
		await capture("portrait_sera", "§5.4 초상화 대화 — 윤세라")
	await auto_advance()

	# §9 대화 배틀 — 첫 페이즈의 선택지 화면과 멘탈 차트
	GameState.advance_puzzle("first_scam", "met_sera")
	main.call("_interact", "exchange_booth", Actions.Verb.TALK)
	if await wait_until(func(): return bool(main.choice_box.is_active()), 3000,
			func(): if bool(main.subtitles.is_active()): main.subtitles.advance()):
		await settle(6)
		await capture("battle_start", "§9 대화 배틀 — 상대 초상 · 멘탈 차트 · 군중")
	# 결정타 하나를 넣어 캔들이 떨어진 차트를 찍는다
	if bool(main.choice_box.is_active()):
		main.choice_box.select_index(0)
	if await wait_until(func(): return bool(main.choice_box.is_active()), 3000,
			func(): if bool(main.subtitles.is_active()): main.subtitles.advance()):
		await settle(6)
		await capture("battle_chart", "§9.4 모순 카드 획득 후 — 캔들이 지지선으로 내려간다")
	await auto_advance()


## 퍼즐을 건너뛰고 장면만 세운다. 스크린샷 전용.
func jump(scene_id: String, entry: String) -> void:
	SceneDirector.change_scene(scene_id, entry)
	await auto_advance()


# ---------------------------------------------------------------- 창 숨기기

## 캡처는 실제 렌더링이 필요하다 — `--headless` 는 더미 렌더러라 이미지가 안 나온다.
## 그래서 창은 떠야 하지만, 작업 중에 앞으로 튀어나와 하던 일을 가리면 안 된다.
## 포커스를 뺏지 않게 하고 화면 밖으로 밀어 둔다. 창은 살아 있으므로 렌더링은 계속된다.
##
##   godot --path . tests/Screenshots.tscn -- visible   ← 눈으로 보고 싶을 때
func _hide_window() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a) == "visible":
			return

	var win := get_window()
	win.set_flag(Window.FLAG_NO_FOCUS, true)
	# 최소화는 macOS 에서 렌더링이 멈출 수 있어 쓰지 않는다. 화면 밖으로 옮기기만 한다.
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	# 위치가 화면 안으로 강제 보정되는 환경이면 최소한 뒤로는 보낸다.
	win.always_on_top = false


# ---------------------------------------------------------------- 대기 도우미

func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## 조건이 참이 될 때까지 기다린다. 매 프레임 each 를 부른다(옵션).
func wait_until(predicate: Callable, max_frames: int = 1800, each: Callable = Callable()) -> bool:
	var f := 0
	while f < max_frames:
		f += 1
		if bool(predicate.call()):
			return true
		if each.is_valid():
			each.call()
		await get_tree().process_frame
	push_warning("wait_until 시간 초과")
	return false


func dismiss_card() -> void:
	var f := 0
	while f < 1800 and bool(main.card.is_active()):
		f += 1
		main.card.dismiss()
		await get_tree().process_frame


func auto_advance(max_frames: int = 4000) -> void:
	var f := 0
	var settled := 0
	while f < max_frames:
		f += 1
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
		if not busy:
			settled += 1
			if settled >= 4:
				return
		else:
			settled = 0


## 창 좌표로 실제 커서를 옮긴다. 내부 해상도 320x180 → 창 1280x720 이므로 4배.
func hover_over(hotspot_id: String) -> void:
	var view: LocationView = SceneDirector.current_view
	var h := GameData.hotspot_def(GameState.scene_id, hotspot_id)
	if view == null or h.is_empty():
		push_warning("호버 대상 없음: %s" % hotspot_id)
		return
	var c := LocationView._rect_of(h).get_center()
	var scale := float(DisplayServer.window_get_size().x) / float(Layout.SCREEN.x)
	Input.warp_mouse(c * scale)
	await settle(8)


func unhover() -> void:
	var scale := float(DisplayServer.window_get_size().x) / float(Layout.SCREEN.x)
	Input.warp_mouse(Vector2(6, 6) * scale)
	await settle(6)

func capture(shot_name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("캡처 실패: %s" % shot_name)
		return
	_shot += 1
	var path := "%s/%02d_%s.png" % [OUT_DIR, _shot, shot_name]
	img.save_png(path)
	print("  [%02d] %-22s %dx%d  %s" % [_shot, shot_name, img.get_width(), img.get_height(), note])
