extends Node
## 헤드리스 통합 테스트. 프롤로그 전체를 코드로 플레이하고 §23 완료 기준을 검증한다.
##
##   godot --headless --path . tests/SmokeTest.tscn
##
## 실제 Main 을 띄우고, 사람이 하는 것과 같은 순서로 상호작용을 발생시킨다.
## 입력 이벤트를 흉내 내는 대신 Main 의 상호작용 진입점을 직접 부른다 —
## 검증 대상은 "클릭이 좌표에 맞는가"가 아니라 "게임 로직이 맞는가"다.

const MAIN_SCENE := "res://scenes/core/Main.tscn"
const TIME_SCALE := 50.0     ## 대사 홀드/페이드 타이머를 빠르게 감는다
const PUMP_LIMIT := 20000

## Main.Mode 와 같은 순서. 인스턴스를 통한 enum 접근을 피한다.
const MODE_TITLE := 0
const MODE_PLAY := 1

var main: Node
var failures: Array[String] = []
var checks := 0
var _choice_queue: Array[int] = []


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	# 자동 진행을 위해 텍스트 즉시 표시
	SaveManager.set_setting("text_speed", 3)
	await get_tree().process_frame

	main = load(MAIN_SCENE).instantiate()
	add_child(main)
	await get_tree().process_frame

	await _run()

	print("\n" + "=".repeat(60))
	if failures.is_empty():
		print("스모크 테스트 통과 — 검증 %d건, 실패 0건" % checks)
	else:
		print("스모크 테스트 실패 — 검증 %d건, 실패 %d건" % [checks, failures.size()])
		for f in failures:
			print("  ✗ " + f)
	print("=".repeat(60))
	get_tree().quit(0 if failures.is_empty() else 1)


# ---------------------------------------------------------------- 단언

func check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("  ✓ " + label)
	else:
		failures.append(label)
		print("  ✗ " + label)
	return ok


func section(title: String) -> void:
	print("\n[%s]" % title)


# ---------------------------------------------------------------- 진행 도우미

## 대사/컷신/선택지를 자동으로 넘기며 게임이 멈출 때까지 프레임을 돌린다.
func pump() -> void:
	var frames := 0
	var settled := 0
	while frames < PUMP_LIMIT:
		frames += 1
		await get_tree().process_frame

		if bool(main.card.is_active()):
			main.card.dismiss()
		if bool(main.choice_box.is_active()):
			main.choice_box.select_index(_next_choice())
		if bool(main.subtitles.is_active()):
			main.subtitles.advance()

		var idle: bool = not bool(main.busy) \
			and not SceneDirector.is_changing() \
			and not bool(main.dialogue_runner.is_active()) \
			and not bool(main.card.is_active()) \
			and not bool(main.subtitles.is_active()) \
			and not bool(main.choice_box.is_active())
		if idle:
			settled += 1
			if settled >= 4:
				return
		else:
			settled = 0
	failures.append("pump 이 %d 프레임 안에 끝나지 않았다 (무한 대기 의심)" % PUMP_LIMIT)


func _next_choice() -> int:
	if _choice_queue.is_empty():
		return 0
	return _choice_queue.pop_front()


func queue_choices(indices: Array) -> void:
	_choice_queue.clear()
	for i in indices:
		_choice_queue.append(int(i))


## 상호작용 하나를 발생시키고 끝날 때까지 기다린다.
func act(target: String, verb: int, item: String = "") -> void:
	main.held_item = item
	main.call("_interact", target, verb)
	await pump()


func goto(scene_id: String, entry: String = "default") -> void:
	SceneDirector.change_scene(scene_id, entry)
	await pump()


func log_tail(n: int = 1) -> String:
	var e := DialogueLog.entries()
	if e.is_empty():
		return ""
	var out := ""
	for i in range(maxi(0, e.size() - n), e.size()):
		out += str(e[i].get("text", "")) + " "
	return out


func log_contains(fragment: String) -> bool:
	for e in DialogueLog.entries():
		if str(e.get("text", "")).contains(fragment):
			return true
	return false


# ---------------------------------------------------------------- 시나리오

func _run() -> void:
	await _t_data_load()
	await _t_title()
	await _t_new_game()
	await _t_boss_dialogue()
	await _t_navigation()
	await _t_puzzle_chain()
	await _t_unique_failures()
	await _t_observation_and_solve()
	await _t_new_exit_and_end()
	await _t_save_load()
	await _t_no_silent_clicks()
	await _t_missing_keys()


func _t_data_load() -> void:
	section("데이터 로드")
	check(GameData.load_errors.is_empty(),
		"GameData 로드 오류 없음 (%s)" % ", ".join(GameData.load_errors))
	check(GameData.scenes.size() == 3, "장면 3개 (실제 %d)" % GameData.scenes.size())
	check(GameData.items.size() == 7, "아이템 7개 (실제 %d)" % GameData.items.size())
	check(GameData.dialogues.size() == 4, "대화 4개 (실제 %d)" % GameData.dialogues.size())
	check(GameData.interactions.size() >= 40, "상호작용 룰 %d개" % GameData.interactions.size())
	check(GameData.strings.size() > 300, "로컬라이징 %d줄" % GameData.strings.size())


func _t_title() -> void:
	section("§23-1 타이틀 화면")
	check(int(main.mode) == MODE_TITLE, "실행 직후 타이틀 모드")
	check(bool(main.title_screen.visible), "타이틀 화면이 보인다")
	check(int(main.title_screen.rows.size()) == 5, "타이틀 항목 5개")
	check(not bool(main.panel.visible), "타이틀에서는 명령 패널이 숨겨진다")


func _t_new_game() -> void:
	section("§23-2 새 게임 + 컷신")
	queue_choices([])
	main.call("_start_new_game")
	await pump()

	check(int(main.mode) == MODE_PLAY, "플레이 모드 진입")
	check(GameState.scene_id == "office_meeting_room", "회의실에서 시작 (실제 %s)" % GameState.scene_id)
	check(bool(main.panel.visible), "명령 패널이 보인다")

	var view: LocationView = SceneDirector.current_view
	check(view != null and view.player != null, "§23-3 한개미가 배치됨")
	if view != null and view.player != null:
		check(view.clamp_to_walkbox(view.player.position) == view.player.position,
			"플레이어가 walkbox 안에 있다 %s" % str(view.player.position))
		check(view.actor("boss") != null, "부장이 배치됨")

	check(GameState.has_item("id_card") and GameState.has_item("phone"),
		"시작 소지품 2개 지급 (%s)" % ", ".join(GameState.inventory))
	check(log_contains("월급의 끝") or log_contains("목요일 밤"), "인트로 컷신이 재생됨")
	check(log_contains("부장님이 안 가면"), "오프닝 내레이션이 재생됨")
	check(log_contains("동작을 고르고"), "조작 안내 1이 출력됨")
	check(log_contains("힌트에 벌점"), "조작 안내 2가 출력됨")


func _t_boss_dialogue() -> void:
	section("§23-4 부장 대화")
	# 명세서 §8.1 선택지 4개. 각 분기를 따로 확인한다.
	for pick in range(4):
		GameState.dialogue_seen.clear()
		GameState.set_flag("talked_to_boss", false)
		DialogueLog.clear()
		queue_choices([pick, 0])
		await act("boss", Actions.Verb.TALK)
		var reached := log_contains("자네는 참 안정적이야")
		check(reached, "선택지 %d 분기가 '자네는 참 안정적이야' 로 합류한다" % (pick + 1))

	check(GameState.has_flag("talked_to_boss"), "대화 종료 시 talked_to_boss 플래그")
	check(log_contains("사람들은 안정이라는 말을"), "§8.1 내레이션 출력")

	# 재대화는 idle 대화로 넘어가야 한다
	DialogueLog.clear()
	queue_choices([3])
	await act("boss", Actions.Verb.TALK)
	check(log_contains("아직 안 갔나?"), "두 번째 대화는 boss_idle 로 분기")


func _t_navigation() -> void:
	section("§23-5 장면 이동")
	await act("door_corridor", Actions.Verb.WALK)
	check(GameState.scene_id == "office_corridor", "회의실 → 복도 (실제 %s)" % GameState.scene_id)

	await act("door_pantry", Actions.Verb.WALK)
	check(GameState.scene_id == "office_pantry", "복도 → 탕비실 (실제 %s)" % GameState.scene_id)

	var view: LocationView = SceneDirector.current_view
	check(view != null and view.player != null
			and view.clamp_to_walkbox(view.player.position) == view.player.position,
		"도착 지점이 walkbox 안")


func _t_puzzle_chain() -> void:
	section("§23-6~7 퍼즐 재료 수집")
	check(GameState.puzzle_state("decaf_swap") == "not_started", "퍼즐 초기 상태")

	# 좌클릭 기본 동사가 '보다' 인 플레이어가 집기를 발견할 수 있어야 한다
	DialogueLog.clear()
	await act("decaf_shelf", Actions.Verb.LOOK)
	check(log_contains("일단 챙겨 둘까"), "초록 봉지 조사 시 집기를 유도한다")
	DialogueLog.clear()
	await act("strong_shelf", Actions.Verb.LOOK)
	check(log_contains("떼어 갈 수 있을 것 같은데"), "빨간 봉지 조사 시 집기를 유도한다")

	await act("decaf_shelf", Actions.Verb.PICKUP)
	check(GameState.has_item("decaf_pack"), "디카페인 원두 획득")
	check(GameState.puzzle_state("decaf_swap") == "has_decaf", "퍼즐 → has_decaf")

	var view: LocationView = SceneDirector.current_view
	check(view.hotspot_at(Vector2(162, 60)).is_empty(), "집은 뒤 초록 봉지 핫스폿이 사라짐")

	await act("coffee_machine", Actions.Verb.USE, "decaf_pack")
	check(GameState.has_item("decaf_cup"), "종이컵 커피 획득")
	check(not GameState.has_item("decaf_pack"), "원두는 소모됨")
	check(GameState.puzzle_state("decaf_swap") == "cup_brewed", "퍼즐 → cup_brewed")

	await act("strong_shelf", Actions.Verb.PICKUP)
	check(GameState.has_item("strong_label"), "‘더 스트롱’ 라벨 획득")

	# 대칭 조합 — 라벨을 들고 컵에 써도, 컵을 들고 라벨에 써도 걸려야 한다 (§16.3)
	await act("decaf_cup", Actions.Verb.USE, "strong_label")
	check(GameState.has_item("disguised_cup"), "위장한 커피 조합 성공")
	check(GameState.puzzle_state("decaf_swap") == "disguised", "퍼즐 → disguised")
	check(not GameState.has_item("decaf_cup") and not GameState.has_item("strong_label"),
		"재료 두 개가 결과물로 대체됨")


func _t_unique_failures() -> void:
	section("§23-9 고유 실패 대사")
	var before := GameState.inventory.size()

	DialogueLog.clear()
	await act("sink", Actions.Verb.USE, "disguised_cup")
	check(log_contains("손실 확정"), "커피를 싱크대에 버리려 함 → 고유 거부 대사")
	check(GameState.inventory.size() == before, "§11.2 필수 아이템이 사라지지 않음")

	DialogueLog.clear()
	await act("coffee_machine", Actions.Verb.USE, "id_card")
	check(log_contains("사원증으로 되는 일은"), "사원증 → 커피 머신 고유 실패 대사")

	DialogueLog.clear()
	await act("strong_shelf", Actions.Verb.PICKUP)
	check(log_contains("두 번 뗄 수 있으면"), "라벨 재수령 시도 → 고유 대사")

	# 복도로 나가 엘리베이터 잠김 확인
	await act("door_corridor", Actions.Verb.WALK)
	check(GameState.scene_id == "office_corridor", "탕비실 → 복도")

	DialogueLog.clear()
	await act("elevator", Actions.Verb.WALK)
	check(GameState.scene_id == "office_corridor", "부장이 있는 동안 엘리베이터로 나갈 수 없다")
	check(log_contains("부장님이 아직 계신다"), "엘리베이터 잠김 → 이유를 알려주는 대사")

	DialogueLog.clear()
	await act("elevator", Actions.Verb.USE, "id_card")
	check(log_contains("되면 그게 더 이상하지"), "사원증 → 엘리베이터 고유 실패 대사")


func _t_observation_and_solve() -> void:
	section("§23-8, §23-10 관찰 후 퍼즐 해결")
	await act("door_meeting", Actions.Verb.WALK)
	check(GameState.scene_id == "office_meeting_room", "복도 → 회의실")

	# 관찰 전에는 전제조건 실패 → 고유 대사, 아이템 유지
	check(not GameState.has_flag("knows_boss_caffeine"), "아직 컵을 관찰하지 않음")
	DialogueLog.clear()
	await act("boss", Actions.Verb.USE, "disguised_cup")
	check(log_contains("난 이따 내 걸로 마셔"), "관찰 전 사용 → 전제조건 실패 고유 대사")
	check(GameState.has_item("disguised_cup"), "실패해도 커피를 잃지 않음")
	check(not GameState.has_flag("boss_left"), "부장이 아직 있음")

	# 위장 안 한 컵 시나리오도 고유 대사가 있는지 (룰 존재 확인)
	var plain := InteractionResolver.resolve("use", "boss", "decaf_cup")
	check(plain.rule_id == "use_plain_cup_on_boss", "위장 안 한 컵에도 전용 룰이 있다")

	# 관찰
	DialogueLog.clear()
	await act("boss_mug", Actions.Verb.LOOK)
	check(GameState.has_flag("knows_boss_caffeine"), "컵 조사 → knows_boss_caffeine")
	check(GameState.has_flag("knows_boss_brand"), "컵 조사 → knows_boss_brand")
	check(log_contains("카페인 마시면 잠을 못 자거든"), "§8.1 카페인 대사 확인")

	# 재조사는 짧은 대사로
	DialogueLog.clear()
	await act("boss_mug", Actions.Verb.LOOK)
	check(log_contains("이십 년째 같은 거"), "재조사 시 짧은 반복 대사 (룰 우선순위)")

	# 해결
	DialogueLog.clear()
	await act("boss", Actions.Verb.USE, "disguised_cup")
	check(log_contains("오늘은 일찍 자야겠어"), "§8.1 부장 퇴근 대사")
	check(GameState.has_flag("boss_left"), "boss_left 플래그")
	check(GameState.is_puzzle_complete("decaf_swap"), "§23-10 퍼즐 완료")
	check(not GameState.has_item("disguised_cup"), "커피가 소모됨")

	var view: LocationView = SceneDirector.current_view
	check(view.actor("boss") == null, "부장 스프라이트가 사라짐")
	check(view.hotspot_at(Vector2(160, 100)).is_empty(), "부장 핫스폿이 비활성화됨")


func _t_new_exit_and_end() -> void:
	section("§23-11~12 새 출구 + 자동 저장")
	await act("door_corridor", Actions.Verb.WALK)
	check(GameState.scene_id == "office_corridor", "복도로 이동")

	DialogueLog.clear()
	await act("elevator", Actions.Verb.WALK)
	check(log_contains("오늘은 내가 먼저 나간다"), "§23-11 엘리베이터가 이제 열린다")
	check(log_contains("프롤로그"), "종료 컷신 카드 출력")
	check(int(main.mode) == MODE_TITLE, "프롤로그 종료 후 타이틀로 복귀")
	check(SaveManager.has_any_save(), "§23-12 자동 저장 파일 존재")


func _t_save_load() -> void:
	section("§23-13 이어하기")
	var slot := SaveManager.latest_slot()
	check(not slot.is_empty(), "최근 저장 슬롯 발견 (%s)" % slot)

	var summary := SaveManager.slot_summary(slot)
	check(not summary.is_empty(), "저장 슬롯을 읽을 수 있다")

	# 상태를 완전히 날린 뒤 이어하기
	GameState.reset()
	check(not GameState.has_flag("boss_left"), "리셋 확인")

	main.call("_continue_game")
	await pump()

	check(GameState.has_flag("boss_left"), "저장된 플래그가 복원됨")
	check(GameState.is_puzzle_complete("decaf_swap"), "저장된 퍼즐 상태가 복원됨")
	check(GameState.scene_id == "office_corridor", "저장된 장면이 복원됨 (%s)" % GameState.scene_id)
	check(SceneDirector.current_view != null, "장면이 실제로 세워짐")


## §19.2 — 어떤 (동사, 대상) 조합에도 반응이 있어야 한다.
## 부작용 없는 순수 해석만 하므로 게임 상태를 건드리지 않는다.
func _t_no_silent_clicks() -> void:
	section("§19.2 무반응 클릭 없음 (전수 조사)")
	var verbs := ["look", "talk", "pickup", "use", "open", "close", "push", "pull"]
	var silent: Array[String] = []
	var combos := 0
	var saved_scene := GameState.scene_id

	for sid in GameData.scenes.keys():
		GameState.scene_id = sid
		var sc: Dictionary = GameData.scene(sid)
		var targets: Array = []
		for h in sc.get("hotspots", []):
			targets.append(str(h.get("id", "")))
		for e in sc.get("exits", []):
			targets.append(str(e.get("id", "")))

		for target in targets:
			for v in verbs:
				# 맨손
				combos += 1
				if not _produces_line(v, target, ""):
					silent.append("%s / %s / %s (맨손)" % [sid, target, v])
				# 아이템을 들고
				for item in GameData.items.keys():
					combos += 1
					if not _produces_line("use", target, str(item)):
						silent.append("%s / %s / use+%s" % [sid, target, item])

	GameState.scene_id = saved_scene
	check(silent.is_empty(), "%d개 조합 전부 대사 출력 (무반응 %d개: %s)"
		% [combos, silent.size(), ", ".join(silent.slice(0, 5))])


func _produces_line(action: String, target: String, item: String) -> bool:
	var res := InteractionResolver.resolve(action, target, item)
	var r := res.result
	if not str(r.get("dialogue", "")).is_empty():
		return true
	for field in ["lines", "lines_pre"]:
		for l in r.get(field, []):
			var key := str(l) if l is String else str((l as Dictionary).get("key", ""))
			if not key.is_empty() and Loc.has(key):
				return true
	return false


func _t_missing_keys() -> void:
	section("로컬라이징")
	var missing := Loc.missing_keys.keys()
	check(missing.is_empty(), "플레이 중 누락된 대사 키 없음 (%s)"
		% ", ".join(PackedStringArray(missing.slice(0, 8))))
