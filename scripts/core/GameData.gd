extends Node
## 정적 게임 데이터 로더. (autoload: GameData)
##
## 명세서 §16 "데이터 설계", §21 "JSON 또는 Godot Resource 기반 데이터 분리".
##
## 모든 콘텐츠(장면/아이템/대화/퍼즐/상호작용 룰)는 코드가 아니라 data/*.json 에 있다.
## 코드는 데이터를 해석만 하고, 장면별 if 문을 갖지 않는다.
##
## res:// 아래 .json 은 익스포트 시 폴더 스캔이 불안정하므로
## data/manifest.json 에 명시된 파일만 읽는다.

const MANIFEST_PATH := "res://data/manifest.json"

var items: Dictionary = {}          ## item_id -> Dictionary
var characters: Dictionary = {}     ## character_id -> Dictionary (§6.7)
var scenes: Dictionary = {}         ## scene_id -> Dictionary
var dialogues: Dictionary = {}      ## dialogue_id -> Dictionary
var puzzles: Dictionary = {}        ## puzzle_id -> Dictionary
var chapters: Dictionary = {}       ## chapter_id -> Dictionary
var interactions: Array = []        ## 상호작용 룰 원본
var strings: Dictionary = {}        ## 로컬라이징 키 -> 문자열 (Localization 이 가져간다)

var load_errors: PackedStringArray = []

## "action|target" -> Array[rule]. InteractionResolver 가 쓰는 조회 인덱스.
var _rule_index: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	items.clear()
	characters.clear()
	scenes.clear()
	dialogues.clear()
	puzzles.clear()
	chapters.clear()
	interactions.clear()
	strings.clear()
	_rule_index.clear()
	load_errors.clear()

	var manifest := _read_json(MANIFEST_PATH)
	if manifest.is_empty():
		_err("manifest 를 읽지 못했습니다: %s" % MANIFEST_PATH)
		return

	for path in _list(manifest, "localization"):
		_merge_flat(strings, _read_json(path), path)
	for path in _list(manifest, "items"):
		_merge_keyed(items, _read_json(path), "item_id", path)
	for path in _list(manifest, "characters"):
		_merge_keyed(characters, _read_json(path), "character_id", path)
	for path in _list(manifest, "scenes"):
		_merge_keyed(scenes, _read_json(path), "scene_id", path)
	for path in _list(manifest, "dialogues"):
		_merge_keyed(dialogues, _read_json(path), "dialogue_id", path)
	for path in _list(manifest, "puzzles"):
		_merge_keyed(puzzles, _read_json(path), "puzzle_id", path)
	for path in _list(manifest, "chapters"):
		_merge_keyed(chapters, _read_json(path), "chapter_id", path)
	for path in _list(manifest, "interactions"):
		_load_interactions(path)

	_build_rule_index()

	if not load_errors.is_empty():
		for e in load_errors:
			push_error("[GameData] " + e)


# ---------------------------------------------------------------- 조회 API

func item(id: String) -> Dictionary:
	return items.get(id, {})


func scene(id: String) -> Dictionary:
	return scenes.get(id, {})


func dialogue(id: String) -> Dictionary:
	return dialogues.get(id, {})


func puzzle(id: String) -> Dictionary:
	return puzzles.get(id, {})


## action/target 조합에 해당하는 룰 목록. 구체적인 룰(아이템 지정)이 앞에 온다.
func rules_for(action: String, target: String) -> Array:
	return _rule_index.get("%s|%s" % [action, target], [])


## 장면 안에서 핫스폿/출구 정의를 찾는다.
func hotspot_def(scene_id: String, hotspot_id: String) -> Dictionary:
	var sc := scene(scene_id)
	for h in sc.get("hotspots", []):
		if h.get("id", "") == hotspot_id:
			return h
	for e in sc.get("exits", []):
		if e.get("id", "") == hotspot_id:
			return e
	return {}


# ---------------------------------------------------------------- 내부

func _list(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_err("파일 없음: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_err("열 수 없음: %s (err %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()

	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		_err("JSON 파싱 실패: %s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not (parser.data is Dictionary):
		_err("최상위가 오브젝트가 아님: %s" % path)
		return {}
	return parser.data


func _merge_flat(into: Dictionary, src: Dictionary, path: String) -> void:
	for k in src.keys():
		if into.has(k):
			_err("중복 키 '%s' (%s)" % [k, path])
		into[k] = src[k]


## 세 가지 형태를 모두 받는다.
##   1) 문서 자체가 항목 하나        { "scene_id": "office_pantry", ... }   ← 장면 파일
##   2) 항목 배열                    { "entries": [ {..}, {..} ] }
##   3) id 를 키로 쓴 맵             { "<id>": {..}, "<id>": {..} }
## "_" 로 시작하는 키는 주석이므로 무시한다.
func _merge_keyed(into: Dictionary, src: Dictionary, id_field: String, path: String) -> void:
	# 형태 1
	if src.get(id_field, null) is String:
		var single_id := str(src[id_field])
		if into.has(single_id):
			_err("중복 %s '%s' (%s)" % [id_field, single_id, path])
		into[single_id] = src
		return

	# 형태 2
	if src.has("entries") and src["entries"] is Array:
		for e in src["entries"]:
			if not (e is Dictionary):
				continue
			var id: String = e.get(id_field, "")
			if id.is_empty():
				_err("'%s' 필드가 없는 항목 (%s)" % [id_field, path])
				continue
			if into.has(id):
				_err("중복 %s '%s' (%s)" % [id_field, id, path])
			into[id] = e
		return

	# 형태 3
	for k in src.keys():
		if str(k).begins_with("_") or not (src[k] is Dictionary):
			continue
		var entry: Dictionary = src[k]
		entry[id_field] = k
		if into.has(k):
			_err("중복 %s '%s' (%s)" % [id_field, k, path])
		into[k] = entry


func _load_interactions(path: String) -> void:
	var d := _read_json(path)
	var arr = d.get("rules", [])
	if not (arr is Array):
		_err("'rules' 배열이 없음: %s" % path)
		return
	for r in arr:
		if r is Dictionary:
			r["_source"] = path
			interactions.append(r)


func _build_rule_index() -> void:
	for r in interactions:
		# action 과 target 모두 문자열 또는 배열을 받는다.
		var actions: Array = _as_string_list(r.get("action", ""))
		var targets: Array = _as_string_list(r.get("target", ""))
		if actions.is_empty():
			_err("action 이 없는 룰: %s" % str(r.get("id", "?")))
			continue
		if targets.is_empty():
			_err("target 이 없는 룰: %s" % str(r.get("id", "?")))
			continue

		for action in actions:
			for target in targets:
				var key := "%s|%s" % [action, target]
				if not _rule_index.has(key):
					_rule_index[key] = []
				_rule_index[key].append(r)

	# 아이템을 지정한 구체적인 룰이 먼저 검사되도록 정렬한다.
	for key in _rule_index.keys():
		var list: Array = _rule_index[key]
		list.sort_custom(func(a, b):
			var ai := 1 if str(a.get("item", "")).is_empty() else 0
			var bi := 1 if str(b.get("item", "")).is_empty() else 0
			if ai != bi:
				return ai < bi
			# 전제조건이 많은 룰을 먼저 (더 구체적)
			return _precond_weight(a) > _precond_weight(b))


static func _as_string_list(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for e in v:
			var s := str(e)
			if not s.is_empty():
				out.append(s)
	elif v is String and not (v as String).is_empty():
		out.append(str(v))
	return out


static func _precond_weight(rule: Dictionary) -> int:
	var p = rule.get("preconditions", {})
	if not (p is Dictionary):
		return 0
	var w := 0
	for k in (p as Dictionary).keys():
		var v = p[k]
		w += (v as Array).size() if v is Array else 1
	return w


func _err(msg: String) -> void:
	load_errors.append(msg)
