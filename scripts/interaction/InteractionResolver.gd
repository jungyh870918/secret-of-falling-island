class_name InteractionResolver
extends RefCounted
## 중앙 상호작용 처리기. 명세서 §21.
##
##   "하드코딩된 장면별 if문이 늘어나지 않도록 InteractionResolver 또는
##    동등한 중앙 처리 구조를 설계하라."
##
## 모든 상호작용은 (actor, action, target, item?) 로 표현되고, 룰 테이블에서 조회된다.
## 코드에는 어떤 장면/퍼즐 고유 분기도 없다. 새 콘텐츠는 JSON 추가만으로 늘어난다.
##
## [폴백 체인] — 위에서부터 먼저 걸리는 것을 쓴다.
##   1. (action, target, item) 일치 + 전제조건 충족  → 정상 결과
##   2. (action, target, item) 일치 + 전제조건 실패  → 그 룰의 on_fail (고유 실패 대사)
##   3. (action, target) 일치(아이템 무관) 룰의 on_fail
##   4. 핫스폿 데이터의 defaults[action]
##   5. 사용한 아이템 데이터의 fail_key
##   6. 전역 동사 폴백 fallback.verb.<action>
##
## 3~6단계가 있기 때문에 "반응이 아예 없는 클릭"이 존재할 수 없다. (§19.2)

## action_id: "look"/"use"/... , target_id: 핫스폿 id 또는 아이템 id,
## item_id: 손에 든 인벤토리 아이템 (없으면 "")
static func resolve(action_id: String, target_id: String, item_id: String = "") -> InteractionResult:
	var res := InteractionResult.new()

	# --- 1~3단계: 룰 테이블 -------------------------------------------------
	var attempts: Array = [[target_id, item_id]]
	# 아이템 조합은 대칭이다. (§16.3 combinations)
	if action_id == "use" and not item_id.is_empty() and GameData.items.has(target_id):
		attempts.append([item_id, target_id])

	var precondition_fail: Dictionary = {}
	var precondition_fail_id := ""
	var precondition_note := ""

	for pair in attempts:
		var tgt: String = pair[0]
		var itm: String = pair[1]
		for rule in GameData.rules_for(action_id, tgt):
			if not _item_matches(rule, itm):
				continue
			if _consumed_once(rule):
				continue
			if Conditions.evaluate(rule.get("preconditions", null)):
				res.kind = InteractionResult.Kind.SUCCESS
				res.rule_id = str(rule.get("id", ""))
				res.result = _result_of(rule)
				return res
			# 전제조건 실패 — 가장 구체적인 룰의 on_fail 을 기억해 둔다.
			if precondition_fail.is_empty():
				var of = rule.get("on_fail", null)
				if of != null:
					precondition_fail = _as_result(of)
					precondition_fail_id = str(rule.get("id", ""))
					precondition_note = Conditions.explain(rule.get("preconditions", null))

	if not precondition_fail.is_empty():
		res.kind = InteractionResult.Kind.PRECONDITION_FAIL
		res.rule_id = precondition_fail_id
		res.result = precondition_fail
		res.debug_note = precondition_note
		return res

	# --- 4단계: 핫스폿 기본 대사 -------------------------------------------
	# 아이템을 든 채로 사용하면 "use_item" 키를 먼저 본다.
	# 없으면 5단계에서 아이템 고유 실패 대사를 쓰는 편이 더 구체적이다.
	var hs := GameData.hotspot_def(GameState.scene_id, target_id)
	var defaults: Dictionary = hs.get("defaults", {}) if hs.get("defaults", {}) is Dictionary else {}
	var default_key := action_id
	if action_id == "use" and not item_id.is_empty():
		default_key = "use_item"
	if defaults.has(default_key):
		res.result = _line_result(str(defaults[default_key]), str(hs.get("speaker", "player")))
		res.debug_note = "hotspot default[%s]" % default_key
		return res

	# --- 5단계: 아이템 자체의 실패 대사 -------------------------------------
	if not item_id.is_empty():
		var it := GameData.item(item_id)
		var fk := str(it.get("fail_key", ""))
		if not fk.is_empty():
			res.result = _line_result(fk, "player")
			res.debug_note = "item fail_key"
			return res

	# 아이템을 조사/집기 하는 경우 아이템 설명을 읽어준다.
	if GameData.items.has(target_id):
		var it2 := GameData.item(target_id)
		if action_id == "look" and it2.has("description_key"):
			res.result = _line_result(str(it2["description_key"]), "player")
			res.debug_note = "item description"
			return res

	# --- 6단계: 전역 동사 폴백 ----------------------------------------------
	var key := "fallback.use_item" if (action_id == "use" and not item_id.is_empty()) else "fallback.verb.%s" % action_id
	res.result = _line_result(key, "player")
	res.debug_note = "global verb fallback"
	return res


## 룰의 item 필드와 손에 든 아이템이 맞는지.
static func _item_matches(rule: Dictionary, item_id: String) -> bool:
	var ri = rule.get("item", null)
	if ri == null or (ri is String and (ri as String).is_empty()):
		# 아이템을 지정하지 않은 룰은 '맨손' 상호작용용이다.
		# 단, any_item:true 면 아무 아이템이나 받는다.
		if bool(rule.get("any_item", false)):
			return true
		return item_id.is_empty()
	if ri is Array:
		return (ri as Array).has(item_id)
	return str(ri) == item_id


## "once": true 인 룰이 이미 실행됐는지.
static func _consumed_once(rule: Dictionary) -> bool:
	if not bool(rule.get("once", false)):
		return false
	return GameState.has_flag(once_flag(str(rule.get("id", ""))))


static func once_flag(rule_id: String) -> String:
	return "_once/%s" % rule_id


static func _result_of(rule: Dictionary) -> Dictionary:
	var r := _as_result(rule.get("result", {}))
	if bool(rule.get("once", false)):
		var flags: Dictionary = r.get("flags", {})
		flags = flags.duplicate()
		flags[once_flag(str(rule.get("id", "")))] = true
		r = r.duplicate()
		r["flags"] = flags
	return r


## on_fail 은 문자열(대사 키) 또는 전체 result 오브젝트 둘 다 허용한다.
static func _as_result(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	if v is String:
		return _line_result(str(v), "player")
	if v is Array:
		var lines: Array = []
		for k in v:
			lines.append({"speaker": "player", "key": str(k)})
		return {"lines": lines}
	return {}


static func _line_result(key: String, speaker: String) -> Dictionary:
	return {"lines": [{"speaker": speaker, "key": key}]}
