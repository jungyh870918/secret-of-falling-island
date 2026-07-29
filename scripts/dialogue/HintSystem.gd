class_name HintSystem
extends RefCounted
## 힌트. 명세서 §11.3.
##
##   1단계: 한개미 혼잣말
##   2단계: 세라의 관찰   (프롤로그처럼 세라가 없는 구간에서는 내레이션이 대신한다)
##   3단계: 구체적 지시
##
## §11.3 "힌트 사용에 페널티를 주지 않는다." — 점수도 플래그도 남기지 않는다.

const DEFAULT_SPEAKERS := ["player", "sera", "hint"]

static var _stage := 0
static var _context := ""


## 지금 화면/진행 상황에 맞는 다음 힌트를 반환한다.
## 반환: {"speaker": String, "key": String} — 힌트가 없으면 빈 Dictionary.
static func next_hint() -> Dictionary:
	var pid := active_puzzle_id()
	if pid.is_empty():
		return {"speaker": "player", "key": "hint.none"}

	var state := GameState.puzzle_state(pid)
	var ctx := "%s/%s" % [pid, state]
	if ctx != _context:
		_context = ctx
		_stage = 0

	var entries := hints_for(pid, state)
	if entries.is_empty():
		return {"speaker": "player", "key": "hint.none"}

	var max_stage := mini(entries.size(), int(SaveManager.get_setting("hint_level", 3)))
	if max_stage <= 0:
		return {}
	var idx: int = mini(_stage, max_stage - 1)
	_stage = mini(_stage + 1, max_stage - 1)

	var e = entries[idx]
	if e is String:
		return {"speaker": DEFAULT_SPEAKERS[mini(idx, 2)], "key": str(e)}
	if e is Dictionary:
		var d: Dictionary = e
		return {
			"speaker": str(d.get("speaker", DEFAULT_SPEAKERS[mini(idx, 2)])),
			"key": str(d.get("key", "")),
		}
	return {}


static func hints_for(puzzle_id: String, state: String) -> Array:
	var p := GameData.puzzle(puzzle_id)
	var hints = p.get("hints", {})
	if not (hints is Dictionary):
		return []
	var v = (hints as Dictionary).get(state, [])
	return v if v is Array else []


## 현재 장면이 선언한 퍼즐 중 아직 안 끝난 첫 번째.
static func active_puzzle_id() -> String:
	var sc := GameData.scene(GameState.scene_id)
	var list = sc.get("active_puzzles", [])
	if list is Array:
		for pid in list:
			if not GameState.is_puzzle_complete(str(pid)):
				return str(pid)
	# 장면이 지정하지 않았으면 전체에서 찾는다.
	for pid in GameData.puzzles.keys():
		if not GameState.is_puzzle_complete(str(pid)):
			return str(pid)
	return ""


static func reset() -> void:
	_stage = 0
	_context = ""
