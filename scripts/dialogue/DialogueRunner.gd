class_name DialogueRunner
extends Node
## 분기 대화 진행기. 명세서 §16.2 데이터 스키마 기반.
##
## 노드 형태
##   {"speaker":"sera", "text_key":"...", "next":"n002"}
##   {"speaker":"player", "choices":[ {...} ]}
##   {"result": { ... ResultRunner op ... }, "next":"n003"}
##   {"branches":[{"if":{...},"next":"n010"}], "next":"n011"}   조건 분기
##
## 선택지 형태
##   {"text_key":"...", "say_key":"...", "next":"n003",
##    "effects":{"sera_respect":1},        # §12.2 관계 변수 축약 표기
##    "result":{ ... },                    # 전체 op 도 가능
##    "requires":{...}, "once":true}
##
## §0-7 "플레이어가 틀린 선택을 해도 즉시 게임 오버시키지 않는다" —
## 이 러너에는 실패/사망 개념이 없다. 모든 선택은 어떤 노드로든 이어진다.

signal dialogue_started(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)

var subtitles: SubtitleLayer
var choice_box: ChoiceBox
var result_runner: ResultRunner

var _active := false
var _current_id := ""


func is_active() -> bool:
	return _active


func play(dialogue_id: String) -> void:
	var dlg := GameData.dialogue(dialogue_id)
	if dlg.is_empty():
		push_error("[DialogueRunner] 없는 대화: %s" % dialogue_id)
		return
	var nodes = dlg.get("nodes", {})
	if not (nodes is Dictionary):
		push_error("[DialogueRunner] nodes 없음: %s" % dialogue_id)
		return

	_active = true
	_current_id = dialogue_id
	dialogue_started.emit(dialogue_id)

	var node_id := str(dlg.get("start_node", ""))
	var guard := 0
	while not node_id.is_empty() and node_id != "end" and guard < 500:
		guard += 1
		if not (nodes as Dictionary).has(node_id):
			push_error("[DialogueRunner] %s: 없는 노드 %s" % [dialogue_id, node_id])
			break
		var node: Dictionary = nodes[node_id]
		GameState.mark_seen(dialogue_id, node_id)
		node_id = await _run_node(dialogue_id, node_id, node)

	if guard >= 500:
		push_error("[DialogueRunner] %s: 무한 루프 방지로 중단" % dialogue_id)

	_active = false
	dialogue_finished.emit(dialogue_id)


func _run_node(dialogue_id: String, node_id: String, node: Dictionary) -> String:
	# 1. 대사
	var text_key := str(node.get("text_key", ""))
	if not text_key.is_empty():
		var speaker := str(node.get("speaker", "narrator"))
		await subtitles.say(speaker, Loc.t(text_key, _args(node)))

	# 2. 결과 op
	var result = node.get("result", null)
	if result is Dictionary and result_runner != null:
		await result_runner.run(result)

	# 3. 선택지
	var choices = node.get("choices", null)
	if choices is Array and not (choices as Array).is_empty():
		return await _run_choices(dialogue_id, node_id, choices)

	# 4. 조건 분기
	for b in _arr(node, "branches"):
		if b is Dictionary and Conditions.evaluate((b as Dictionary).get("if", null)):
			return str((b as Dictionary).get("next", "end"))

	return str(node.get("next", "end"))


func _run_choices(dialogue_id: String, node_id: String, choices: Array) -> String:
	var available: Array = []
	for i in choices.size():
		var c = choices[i]
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		if not Conditions.evaluate(cd.get("requires", null)):
			continue
		var seen_key := "%s/%s#%d" % [dialogue_id, node_id, i]
		if bool(cd.get("once", false)) and GameState.dialogue_seen.has(seen_key):
			continue
		available.append({"data": cd, "index": i, "seen_key": seen_key})
		if available.size() >= Layout.CHOICE_MAX:
			break

	if available.is_empty():
		# 모든 선택지가 소진된 경우 대화를 자연스럽게 닫는다. (진행 불가 방지)
		return "end"

	var options: Array = []
	for a in available:
		var cd: Dictionary = a["data"]
		options.append({
			"text": Loc.t(str(cd.get("text_key", ""))),
			"seen": GameState.dialogue_seen.has(a["seen_key"]),
		})

	var picked: int = await choice_box.present(options)
	if picked < 0 or picked >= available.size():
		return "end"

	var chosen: Dictionary = available[picked]["data"]
	GameState.dialogue_seen[available[picked]["seen_key"]] = true
	DialogueLog.add("player", "→ " + str(options[picked]["text"]), "choice")

	# 고른 선택지를 한개미가 실제로 말한다. say_key 로 다른 문장을 지정할 수 있다.
	var say_key := str(chosen.get("say_key", chosen.get("text_key", "")))
	if not say_key.is_empty() and not bool(chosen.get("silent", false)):
		await subtitles.say(str(chosen.get("speaker", "player")), Loc.t(say_key))

	# §12.2 관계 변수 축약 표기
	var effects = chosen.get("effects", null)
	if effects is Dictionary and not (effects as Dictionary).is_empty():
		GameState.adjust_relation(effects)

	var result = chosen.get("result", null)
	if result is Dictionary and result_runner != null:
		await result_runner.run(result)

	return str(chosen.get("next", "end"))


static func _args(node: Dictionary) -> Dictionary:
	var a = node.get("args", {})
	return a if a is Dictionary else {}


static func _arr(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []
