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

	# §5.3 문장 라인
	main.held_item = "id_card"
	main.panel.set_held_item("id_card")
	main.panel.set_sentence(Actions.sentence(
		Actions.Verb.USE, false, Loc.t("hotspot.boss"), Loc.t("item.id_card.name")))
	await settle(4)
	await capture("sentence_line", "§5.3 사용하다 → 사원증 → 부장")
	main.held_item = ""
	main.panel.set_held_item("")
	await settle(2)

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

	SaveManager.set_setting("high_contrast_hotspots", true)
	SaveManager.set_setting("show_exit_markers", true)
	await settle(8)
	await capture("accessibility", "§18 고대비 핫스폿 + 출구 삼각 마커")
	SaveManager.set_setting("high_contrast_hotspots", false)
	SaveManager.set_setting("show_exit_markers", false)
	await settle(4)

	# --- 탕비실 + 인벤토리 ---
	main.call("_interact", "door_pantry", Actions.Verb.WALK)
	await auto_advance()
	main.call("_interact", "decaf_shelf", Actions.Verb.PICKUP)
	await auto_advance()
	main.call("_interact", "strong_shelf", Actions.Verb.PICKUP)
	await auto_advance()
	await capture("room_pantry", "탕비실 — 인벤토리 4칸")

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

	print("\n총 %d장 저장: %s" % [_shot, ProjectSettings.globalize_path(OUT_DIR)])
	get_tree().quit()


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
