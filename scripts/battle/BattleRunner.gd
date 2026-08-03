class_name BattleRunner
extends Node
## 대화 배틀 진행기. 명세서 §9.
##
## §9.1 "상대의 체력을 깎는 시스템이 아니다. 논리 구조를 파악하고 모순을 찔러
## 멘탈 차트를 붕괴시키는 시스템이다." — 그래서 이 러너에는 HP 도, 턴 제한도 없다.
##
## §9.4 기본 흐름을 그대로 코드로 옮긴다.
##   1 상대 주장 → 2 선택지 3~4개 → 3 선택 결과 → 4 군중 반응
##   → 5 모순 카드 획득 → 6 다음 페이즈 → 7 지지선 이탈 시 승리
##
## §9.5 실패 처리 — 오답을 골라도 즉시 패배하지 않는다.
##   상대 자신감 상승 / 군중 지지 증가 / 동행자의 짧은 힌트 / 재시도 가능.
##   그래서 이 파일에도 '게임 오버' 로 가는 경로가 없다. 최악의 결과는 '졌지만 진행된다' 다.
##
## 배틀 정의는 전부 data/battles/*.json 에 있고, 여기에는 배틀별 분기가 없다.

signal battle_started(battle_id: String)
signal battle_finished(battle_id: String, won: bool)

## 한 페이즈에서 오답을 이만큼 고르면 다음 페이즈로 넘어간다.
## 무한히 붙잡아 두면 §9.5 "재도전 가능" 이 아니라 벽이 된다.
const MAX_ATTEMPTS := 3

var subtitles: SubtitleLayer
var choice_box: ChoiceBox
var result_runner: ResultRunner
var view: BattleView
var portraits: PortraitView

var _active := false


func is_active() -> bool:
	return _active


## 배틀 하나를 끝까지 진행하고 승패를 돌려준다. (코루틴)
func play(battle_id: String) -> bool:
	var def := GameData.battle(battle_id)
	if def.is_empty():
		push_error("[BattleRunner] 없는 배틀: %s" % battle_id)
		return false

	var phases: Array = def.get("phases", []) if def.get("phases", null) is Array else []
	if phases.is_empty():
		push_error("[BattleRunner] 페이즈가 없는 배틀: %s" % battle_id)
		return false

	_active = true
	battle_started.emit(battle_id)

	var opponent := str(def.get("opponent", ""))
	var ally := str(def.get("ally", ""))

	view.open(int(def.get("confidence", 100)), int(def.get("crowd_support", 50)),
		int(def.get("support_line", 30)))
	if portraits != null:
		portraits.set_enabled(true)
		portraits.pin(opponent)

	var prev_music := AudioDirector.current_music()
	var music := str(def.get("music", ""))
	if not music.is_empty():
		AudioDirector.play_music(music)

	await _say_lines(def.get("intro", []))

	var attempts_total := 0
	for i in phases.size():
		var phase: Dictionary = phases[i]
		attempts_total += await _run_phase(battle_id, def, phase, ally)
		# §9.4-7 지지선을 이탈하면 남은 페이즈를 건너뛴다. 이긴 싸움을 계속 시키지 않는다.
		if view.is_broken():
			break

	var won := view.is_broken()
	var outcome: Dictionary = def.get("on_win" if won else "on_lose", {})
	if outcome is Dictionary:
		AudioDirector.play_sfx("support_break" if won else "fail")
		await _say_lines(outcome.get("lines", []))

	GameState.battle_results[battle_id] = {
		"won": won,
		"confidence": view.confidence,
		"crowd": view.crowd,
		"cards": view.cards.duplicate(),
		"attempts": attempts_total,
	}

	if portraits != null:
		portraits.unpin()
		portraits.set_enabled(false)
	view.close()
	if not music.is_empty():
		AudioDirector.play_music(prev_music)

	# 결과 op(플래그·퍼즐 전진·보상)는 데이터가 정한다. 여기에 배틀별 분기를 두지 않는다.
	if outcome is Dictionary and outcome.get("result", null) is Dictionary:
		await result_runner.run(outcome["result"])

	_active = false
	battle_finished.emit(battle_id, won)
	return won


## 페이즈 하나. 정답을 고르거나 시도 횟수를 다 쓰면 끝난다. 시도 횟수를 돌려준다.
func _run_phase(battle_id: String, def: Dictionary, phase: Dictionary, ally: String) -> int:
	var phase_id := str(phase.get("id", "?"))
	await _say_lines(phase.get("claim", []))

	var used: Dictionary = {}      ## 이미 고른 선택지 인덱스
	var attempts := 0

	while attempts < MAX_ATTEMPTS:
		var options := _available_options(phase, used)
		if options.is_empty():
			break

		var picked: int = await choice_box.present(options.map(func(o):
			return {"text": Loc.t(str(o["data"].get("text_key", ""))), "seen": false}))
		if picked < 0 or picked >= options.size():
			break

		var chosen: Dictionary = options[picked]["data"]
		used[options[picked]["index"]] = true
		attempts += 1

		DialogueLog.add("player", "→ " + Loc.t(str(chosen.get("text_key", ""))), "choice")
		var say_key := str(chosen.get("say_key", chosen.get("text_key", "")))
		if not say_key.is_empty():
			await subtitles.say("player", Loc.t(say_key))

		var quality := str(chosen.get("quality", "weak"))
		var good := quality in ["best", "good"]
		AudioDirector.play_sfx("hit_paper" if good else "fail")

		view.apply(int(chosen.get("confidence", 0)), int(chosen.get("crowd", 0)),
			str(chosen.get("card", "")))

		await _say_lines(chosen.get("reply", []))

		var crowd_line := str(chosen.get("crowd_line", ""))
		if not crowd_line.is_empty():
			await subtitles.say("narrator", Loc.t(crowd_line))

		if view.is_broken():
			return attempts
		if quality == "best":
			return attempts

		# §9.5 오답이면 동행자가 짧은 힌트를 준다. 힌트를 끈 사람에게는 주지 않는다(§18).
		if not good and not ally.is_empty() and int(SaveManager.get_setting("hint_level", 3)) > 0:
			var hints: Dictionary = def.get("hints", {}) if def.get("hints", null) is Dictionary else {}
			var hint_key := str(hints.get(phase_id, ""))
			if not hint_key.is_empty():
				await subtitles.say(ally, Loc.t(hint_key))

	return attempts


## §9.4-2 "선택지 3~4개". requires 로 조건부 선택지를 열 수 있다 —
## 경고문을 읽고 온 플레이어에게는 한 장이 더 있다.
func _available_options(phase: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	var raw: Array = phase.get("options", []) if phase.get("options", null) is Array else []
	for i in raw.size():
		if used.has(i):
			continue
		var o = raw[i]
		if not (o is Dictionary):
			continue
		if not Conditions.evaluate((o as Dictionary).get("requires", null)):
			continue
		out.append({"data": o, "index": i})
		if out.size() >= Layout.CHOICE_MAX:
			break
	return out


func _say_lines(lines: Variant) -> void:
	if not (lines is Array):
		return
	for l in lines:
		if not (l is Dictionary):
			continue
		var d: Dictionary = l
		if not Conditions.evaluate(d.get("if", null)):
			continue
		var key := str(d.get("key", ""))
		if key.is_empty():
			continue
		await subtitles.say(str(d.get("speaker", "narrator")), Loc.t(key))
