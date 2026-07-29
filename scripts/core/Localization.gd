extends Node
## 로컬라이징. (autoload: Loc)
##
## 명세서 §21 "한국어 로컬라이징 키 기반".
## 코드와 데이터에는 문자열 리터럴 대신 키만 쓴다. 실제 문장은 data/localization/*.json.

const MISSING_PREFIX := "⟪"
const MISSING_SUFFIX := "⟫"

var missing_keys: Dictionary = {}


## 키를 문장으로. 없는 키는 ⟪key⟫ 로 표시해 QA 에서 바로 눈에 띄게 한다.
func t(key: String, args: Dictionary = {}) -> String:
	if key.is_empty():
		return ""
	var raw = GameData.strings.get(key, null)
	if raw == null:
		if not missing_keys.has(key):
			missing_keys[key] = true
			push_warning("[Loc] 누락된 키: %s" % key)
		return MISSING_PREFIX + key + MISSING_SUFFIX
	var text := str(raw)
	for k in args.keys():
		text = text.replace("{%s}" % str(k), str(args[k]))
	return text


func has(key: String) -> bool:
	return GameData.strings.has(key)


## 키가 있으면 번역, 없으면 fallback 키. 선택적 대사 처리용.
func t_or(key: String, fallback_key: String, args: Dictionary = {}) -> String:
	return t(key, args) if has(key) else t(fallback_key, args)


## 배열 키(무작위 변형 대사)에서 하나 고른다. 없으면 단일 키로 처리.
func t_variant(key: String, index: int) -> String:
	var raw = GameData.strings.get(key, null)
	if raw is Array and (raw as Array).size() > 0:
		var arr: Array = raw
		return str(arr[posmod(index, arr.size())])
	return t(key)
