class_name DialogueLog
extends RefCounted
## 대화 기록. 명세서 §18 "대화 기록", §23 "대화 로그 확인 가능".
##
## 세션 한정 기록이다(§17 저장 항목에 없음). 정적 저장소를 쓴다.

const MAX_ENTRIES := 300

static var _entries: Array = []          ## [{speaker, text, kind}]
static var _listeners: Array[Callable] = []

## kind: "line" | "choice" | "system"
static func add(speaker: String, text: String, kind: String = "line") -> void:
	if text.is_empty():
		return
	_entries.append({"speaker": speaker, "text": text, "kind": kind})
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	for c in _listeners:
		if c.is_valid():
			c.call()


static func entries() -> Array:
	return _entries


static func clear() -> void:
	_entries.clear()


static func subscribe(c: Callable) -> void:
	if not _listeners.has(c):
		_listeners.append(c)
