extends Node
## 런타임 게임 상태. (autoload: GameState)
##
## 명세서 §17 저장 항목, §12.2 관계 변수, §16.4 퍼즐 상태.
##
## [설계 규약]
##  - 인벤토리에는 버리기/삭제 공개 API가 없다. §11.2 "한 번 놓치면 진행 불가" 원천 차단.
##    아이템 소모는 퍼즐이 정의한 consume 만 가능하며, 그 경우 반드시 대체 아이템을 준다.
##  - 관계는 단일 호감도 숫자가 아니라 4축이다. §12.2.
##  - 퍼즐 상태는 데이터에 선언된 순서 배열을 따라 단조 증가만 한다. 역행 불가 → 상태 꼬임 방지.

signal flag_changed(flag: String, value: Variant)
signal inventory_changed()
signal puzzle_state_changed(puzzle_id: String, state: String)
signal relation_changed(vars: Dictionary)
signal chapter_changed(chapter_id: String)

## §12.2 — 단일 호감도로 단순화하지 않는다.
const RELATION_KEYS := ["sera_trust", "sera_respect", "sera_openness", "sera_irritation"]

var chapter_id: String = ""
var scene_id: String = ""
var player_position: Vector2 = Vector2.ZERO

var flags: Dictionary = {}            ## String -> Variant (bool / int / String)
var inventory: Array[String] = []     ## item_id 순서 보존
var puzzle_states: Dictionary = {}    ## puzzle_id -> state name
var dialogue_seen: Dictionary = {}    ## "dialogue_id/node_id" -> true (한 번만 나오는 선택지 처리)
var battle_results: Dictionary = {}   ## battle_id -> Dictionary (챕터1부터 사용)
var npc_states: Dictionary = {}       ## npc_id -> Dictionary
var relation: Dictionary = {}         ## §12.2
var ending_vars: Dictionary = {}      ## 엔딩 조건 누적치 (§15)
var play_time_sec: float = 0.0

## 장면별 런타임 오버라이드. { scene_id: { "hotspots": {id:bool}, "exits": {id:bool} } }
var scene_overrides: Dictionary = {}

var _paused_timer := false


func _ready() -> void:
	reset()
	set_process(true)


func _process(delta: float) -> void:
	if _paused_timer:
		return
	play_time_sec += delta


func set_timer_paused(v: bool) -> void:
	_paused_timer = v


func reset() -> void:
	chapter_id = ""
	scene_id = ""
	player_position = Vector2.ZERO
	flags.clear()
	inventory.clear()
	puzzle_states.clear()
	dialogue_seen.clear()
	battle_results.clear()
	npc_states.clear()
	ending_vars.clear()
	scene_overrides.clear()
	play_time_sec = 0.0
	relation = {}
	for k in RELATION_KEYS:
		relation[k] = 0
	# 데이터에 선언된 모든 퍼즐을 초기 상태로.
	for pid in GameData.puzzles.keys():
		var p: Dictionary = GameData.puzzles[pid]
		var states: Array = p.get("states", [])
		puzzle_states[pid] = str(states[0]) if states.size() > 0 else "not_started"


# ---------------------------------------------------------------- 플래그

func get_flag(flag: String, default_value: Variant = false) -> Variant:
	return flags.get(flag, default_value)


func has_flag(flag: String) -> bool:
	var v = flags.get(flag, false)
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return not str(v).is_empty()


func set_flag(flag: String, value: Variant = true) -> void:
	if flags.get(flag, null) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)


func add_flag(flag: String, delta: int) -> void:
	var cur = flags.get(flag, 0)
	var base := int(cur) if (cur is int or cur is float) else 0
	set_flag(flag, base + delta)


# ---------------------------------------------------------------- 인벤토리
# 공개 API에 remove/drop 이 없다는 점이 중요하다. (§11.2, §21)

func has_item(id: String) -> bool:
	return inventory.has(id)


func has_all_items(ids: Array) -> bool:
	for i in ids:
		if not inventory.has(str(i)):
			return false
	return true


func give_item(id: String) -> bool:
	if id.is_empty() or inventory.has(id):
		return false
	if not GameData.items.has(id):
		push_warning("[GameState] 정의되지 않은 아이템 지급: %s" % id)
	inventory.append(id)
	inventory_changed.emit()
	return true


## 퍼즐 진행에 의한 소모만 허용. 데이터에서 take 로 지정된 경우에만 호출된다.
## 필수 아이템은 항상 결과물 아이템으로 대체되므로 진행 불가가 생기지 않는다.
func consume_item(id: String) -> bool:
	var idx := inventory.find(id)
	if idx < 0:
		return false
	inventory.remove_at(idx)
	inventory_changed.emit()
	return true


# ---------------------------------------------------------------- 퍼즐

func puzzle_state(puzzle_id: String) -> String:
	return str(puzzle_states.get(puzzle_id, "not_started"))


func is_puzzle_at_least(puzzle_id: String, state: String) -> bool:
	var order: Array = GameData.puzzle(puzzle_id).get("states", [])
	var cur := order.find(puzzle_state(puzzle_id))
	var want := order.find(state)
	if cur < 0 or want < 0:
		return puzzle_state(puzzle_id) == state
	return cur >= want


func is_puzzle_complete(puzzle_id: String) -> bool:
	var order: Array = GameData.puzzle(puzzle_id).get("states", [])
	if order.is_empty():
		return false
	return puzzle_state(puzzle_id) == str(order[order.size() - 1])


## 단조 증가만 허용. 뒤로 가는 요청은 무시한다.
func advance_puzzle(puzzle_id: String, state: String) -> bool:
	var order: Array = GameData.puzzle(puzzle_id).get("states", [])
	var cur_idx := order.find(puzzle_state(puzzle_id))
	var new_idx := order.find(state)
	if new_idx < 0:
		push_warning("[GameState] 퍼즐 '%s' 에 정의되지 않은 상태: %s" % [puzzle_id, state])
		return false
	if new_idx <= cur_idx:
		return false
	puzzle_states[puzzle_id] = state
	puzzle_state_changed.emit(puzzle_id, state)
	return true


# ---------------------------------------------------------------- 관계 (§12.2)

func adjust_relation(changes: Dictionary) -> void:
	var touched := false
	for k in changes.keys():
		var key := str(k)
		if not RELATION_KEYS.has(key):
			push_warning("[GameState] 알 수 없는 관계 변수: %s" % key)
			continue
		relation[key] = int(relation.get(key, 0)) + int(changes[k])
		touched = true
	if touched:
		relation_changed.emit(relation)


# ---------------------------------------------------------------- 장면 오버라이드

func set_hotspot_enabled(p_scene_id: String, hotspot_id: String, enabled: bool) -> void:
	_scene_override(p_scene_id, "hotspots")[hotspot_id] = enabled


func set_exit_enabled(p_scene_id: String, exit_id: String, enabled: bool) -> void:
	_scene_override(p_scene_id, "exits")[exit_id] = enabled


func is_hotspot_enabled(p_scene_id: String, hotspot_id: String, default_value: bool) -> bool:
	return bool(_scene_override(p_scene_id, "hotspots").get(hotspot_id, default_value))


func is_exit_enabled(p_scene_id: String, exit_id: String, default_value: bool) -> bool:
	return bool(_scene_override(p_scene_id, "exits").get(exit_id, default_value))


func _scene_override(p_scene_id: String, kind: String) -> Dictionary:
	if not scene_overrides.has(p_scene_id):
		scene_overrides[p_scene_id] = {}
	var d: Dictionary = scene_overrides[p_scene_id]
	if not d.has(kind):
		d[kind] = {}
	return d[kind]


# ---------------------------------------------------------------- 대화 기록

func mark_seen(dialogue_id: String, node_id: String) -> void:
	dialogue_seen["%s/%s" % [dialogue_id, node_id]] = true


func was_seen(dialogue_id: String, node_id: String) -> bool:
	return dialogue_seen.has("%s/%s" % [dialogue_id, node_id])


# ---------------------------------------------------------------- 직렬화 (§17)

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"chapter_id": chapter_id,
		"scene_id": scene_id,
		"player_position": [player_position.x, player_position.y],
		"flags": flags.duplicate(true),
		"inventory": inventory.duplicate(),
		"puzzle_states": puzzle_states.duplicate(true),
		"dialogue_seen": dialogue_seen.duplicate(true),
		"battle_results": battle_results.duplicate(true),
		"npc_states": npc_states.duplicate(true),
		"relation": relation.duplicate(true),
		"ending_vars": ending_vars.duplicate(true),
		"scene_overrides": scene_overrides.duplicate(true),
		"play_time_sec": play_time_sec,
	}


func from_dict(d: Dictionary) -> void:
	reset()
	chapter_id = str(d.get("chapter_id", ""))
	scene_id = str(d.get("scene_id", ""))
	var pos = d.get("player_position", [0, 0])
	if pos is Array and (pos as Array).size() >= 2:
		player_position = Vector2(float(pos[0]), float(pos[1]))
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	inventory.clear()
	for i in d.get("inventory", []):
		inventory.append(str(i))
	# 저장 이후 새 퍼즐이 추가돼도 초기값이 유지되도록 merge 한다.
	for k in (d.get("puzzle_states", {}) as Dictionary).keys():
		puzzle_states[str(k)] = str(d["puzzle_states"][k])
	dialogue_seen = (d.get("dialogue_seen", {}) as Dictionary).duplicate(true)
	battle_results = (d.get("battle_results", {}) as Dictionary).duplicate(true)
	npc_states = (d.get("npc_states", {}) as Dictionary).duplicate(true)
	for k in RELATION_KEYS:
		relation[k] = int((d.get("relation", {}) as Dictionary).get(k, 0))
	ending_vars = (d.get("ending_vars", {}) as Dictionary).duplicate(true)
	scene_overrides = (d.get("scene_overrides", {}) as Dictionary).duplicate(true)
	play_time_sec = float(d.get("play_time_sec", 0.0))

	inventory_changed.emit()
	relation_changed.emit(relation)


func formatted_play_time() -> String:
	var total := int(play_time_sec)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
