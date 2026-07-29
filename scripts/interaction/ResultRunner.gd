class_name ResultRunner
extends Node
## 결과(op 묶음) 실행기.
##
## 상호작용 룰의 result 와 대화 노드의 effects/result 가 **같은 스키마**를 쓴다.
## 덕분에 "대사를 띄우고 아이템을 주고 퍼즐을 전진시키는" 로직이 한 군데에만 있다.
##
## [지원 op]
##   lines_pre : [{speaker, key, args}]  상태 변경 전에 출력할 대사
##   sfx       : "pickup"
##   give      : ["item_id", ...]
##   take      : ["item_id", ...]        퍼즐이 명시한 소모만. 항상 대체물을 함께 준다.
##   flags     : {"flag": true, "count": 3}
##   flags_add : {"counter": 1}
##   puzzle    : {"puzzle_id": "state"}  단조 증가만
##   relation  : {"sera_trust": 1}       §12.2
##   hotspots  : {"hotspot_id": false}   현재 장면 기준 (scene 지정 가능: "scene_id/hotspot_id")
##   exits     : {"exit_id": true}
##   lines     : [{speaker, key, args}]  상태 변경 후 출력할 대사
##   dialogue  : "dialogue_id"           분기 대화 시작 (끝까지 await)
##   goto      : {"scene": "id", "entry": "spawn_key"} 또는 "scene_id"
##   event     : "prologue_end"          Main 이 처리하는 특수 연출
##   autosave  : true                    §17 자동 저장 시점

signal event_requested(event_name: String)
signal line_shown(speaker: String, text: String)

var subtitles: Node          ## SubtitleLayer — say(speaker, text) 코루틴 제공
var dialogue_runner: Node    ## DialogueRunner — play(dialogue_id) 코루틴 제공

## event op 처리기. 시그널만 쓰면 emit 이 핸들러를 기다려 주지 않아서,
## 컷신이 뜬 상태로 결과 실행이 끝나 버린다(= 조작 잠금이 풀린다).
## 그래서 이벤트는 await 가능한 Callable 로 넘긴다.
var event_handler: Callable = Callable()

var _running := false


func is_running() -> bool:
	return _running


## result 딕셔너리를 순서대로 실행한다. 코루틴이므로 await 로 호출한다.
func run(result: Dictionary) -> void:
	if result.is_empty():
		return
	_running = true
	await _run_inner(result)
	_running = false


func _run_inner(result: Dictionary) -> void:
	await _say_lines(result.get("lines_pre", []))

	var sfx := str(result.get("sfx", ""))
	if not sfx.is_empty():
		AudioDirector.play_sfx(sfx)

	for id in _arr(result, "take"):
		GameState.consume_item(str(id))
	for id in _arr(result, "give"):
		if GameState.give_item(str(id)):
			if sfx.is_empty():
				AudioDirector.play_sfx("pickup")

	var flags: Dictionary = _dict(result, "flags")
	for k in flags.keys():
		GameState.set_flag(str(k), flags[k])
	var flags_add: Dictionary = _dict(result, "flags_add")
	for k in flags_add.keys():
		GameState.add_flag(str(k), int(flags_add[k]))

	var puzzle: Dictionary = _dict(result, "puzzle")
	for pid in puzzle.keys():
		GameState.advance_puzzle(str(pid), str(puzzle[pid]))

	var relation: Dictionary = _dict(result, "relation")
	if not relation.is_empty():
		GameState.adjust_relation(relation)

	var hotspots: Dictionary = _dict(result, "hotspots")
	for k in hotspots.keys():
		var sc_id := GameState.scene_id
		var hs_id := str(k)
		if hs_id.contains("/"):
			var parts := hs_id.split("/", false, 2)
			sc_id = parts[0]
			hs_id = parts[1]
		GameState.set_hotspot_enabled(sc_id, hs_id, bool(hotspots[k]))

	var exits: Dictionary = _dict(result, "exits")
	for k in exits.keys():
		var sc_id2 := GameState.scene_id
		var ex_id := str(k)
		if ex_id.contains("/"):
			var parts2 := ex_id.split("/", false, 2)
			sc_id2 = parts2[0]
			ex_id = parts2[1]
		GameState.set_exit_enabled(sc_id2, ex_id, bool(exits[k]))

	await _say_lines(result.get("lines", []))

	var dlg := str(result.get("dialogue", ""))
	if not dlg.is_empty() and dialogue_runner != null:
		await dialogue_runner.play(dlg)

	var ev := str(result.get("event", ""))
	if not ev.is_empty():
		event_requested.emit(ev)
		if event_handler.is_valid():
			await event_handler.call(ev)

	var goto = result.get("goto", null)
	if goto != null:
		var target := ""
		var entry := "default"
		if goto is String:
			target = goto
		elif goto is Dictionary:
			target = str((goto as Dictionary).get("scene", ""))
			entry = str((goto as Dictionary).get("entry", "default"))
		if not target.is_empty():
			await SceneDirector.change_scene(target, entry)

	if bool(result.get("autosave", false)):
		SaveManager.autosave()


func _say_lines(lines: Variant) -> void:
	if not (lines is Array):
		return
	for l in lines:
		var speaker := "player"
		var key := ""
		var args := {}
		if l is String:
			key = l
		elif l is Dictionary:
			speaker = str((l as Dictionary).get("speaker", "player"))
			key = str((l as Dictionary).get("key", ""))
			var a = (l as Dictionary).get("args", {})
			if a is Dictionary:
				args = a
			# 조건부 대사
			if not Conditions.evaluate((l as Dictionary).get("if", null)):
				continue
		if key.is_empty():
			continue
		var text := Loc.t(key, args)
		line_shown.emit(speaker, text)
		if subtitles != null:
			await subtitles.say(speaker, text)


static func _arr(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var v = d.get(key, {})
	return v if v is Dictionary else {}
