class_name Conditions
extends RefCounted
## 전제조건 평가기. 명세서 §21 "preconditions".
##
## 상호작용 룰과 대화 선택지가 같은 스키마를 공유한다.
##
## 예:
## "preconditions": {
##   "flags":      ["knows_boss_caffeine"],       # 참이어야 하는 플래그
##   "not_flags":  ["boss_left"],                 # 거짓이어야 하는 플래그
##   "items":      ["decaf_pack"],                # 소지해야 하는 아이템
##   "not_items":  ["disguised_cup"],
##   "puzzle_at_least": {"decaf_swap": "observed_mug"},
##   "puzzle_is":       {"decaf_swap": "cup_brewed"},
##   "puzzle_not":      {"decaf_swap": "completed"},
##   "relation_min":    {"sera_trust": 3},
##   "scene": "office_pantry",
##   "not_seen": "boss_first_talk/n001"
## }


static func evaluate(pre: Variant) -> bool:
	if pre == null:
		return true
	if not (pre is Dictionary):
		return true
	var p: Dictionary = pre

	for f in _arr(p, "flags"):
		if not GameState.has_flag(str(f)):
			return false
	for f in _arr(p, "not_flags"):
		if GameState.has_flag(str(f)):
			return false
	for i in _arr(p, "items"):
		if not GameState.has_item(str(i)):
			return false
	for i in _arr(p, "not_items"):
		if GameState.has_item(str(i)):
			return false

	var at_least: Dictionary = _dict(p, "puzzle_at_least")
	for pid in at_least.keys():
		if not GameState.is_puzzle_at_least(str(pid), str(at_least[pid])):
			return false

	var is_state: Dictionary = _dict(p, "puzzle_is")
	for pid in is_state.keys():
		if GameState.puzzle_state(str(pid)) != str(is_state[pid]):
			return false

	var not_state: Dictionary = _dict(p, "puzzle_not")
	for pid in not_state.keys():
		if GameState.puzzle_state(str(pid)) == str(not_state[pid]):
			return false

	var rel_min: Dictionary = _dict(p, "relation_min")
	for k in rel_min.keys():
		if int(GameState.relation.get(str(k), 0)) < int(rel_min[k]):
			return false

	var rel_max: Dictionary = _dict(p, "relation_max")
	for k in rel_max.keys():
		if int(GameState.relation.get(str(k), 0)) > int(rel_max[k]):
			return false

	var want_scene := str(p.get("scene", ""))
	if not want_scene.is_empty() and GameState.scene_id != want_scene:
		return false

	var not_seen := str(p.get("not_seen", ""))
	if not not_seen.is_empty() and GameState.dialogue_seen.has(not_seen):
		return false

	var seen := str(p.get("seen", ""))
	if not seen.is_empty() and not GameState.dialogue_seen.has(seen):
		return false

	return true


## 어떤 조건 때문에 실패했는지 반환한다. 디버그 패널과 QA 용.
static func explain(pre: Variant) -> String:
	if not (pre is Dictionary):
		return ""
	var p: Dictionary = pre
	for f in _arr(p, "flags"):
		if not GameState.has_flag(str(f)):
			return "flag 미충족: %s" % f
	for f in _arr(p, "not_flags"):
		if GameState.has_flag(str(f)):
			return "flag 이미 설정됨: %s" % f
	for i in _arr(p, "items"):
		if not GameState.has_item(str(i)):
			return "아이템 없음: %s" % i
	var at_least: Dictionary = _dict(p, "puzzle_at_least")
	for pid in at_least.keys():
		if not GameState.is_puzzle_at_least(str(pid), str(at_least[pid])):
			return "퍼즐 진행 부족: %s < %s (현재 %s)" % [pid, at_least[pid], GameState.puzzle_state(str(pid))]
	return "조건 미충족"


static func _arr(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var v = d.get(key, {})
	return v if v is Dictionary else {}
