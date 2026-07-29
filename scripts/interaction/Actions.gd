class_name Actions
extends RefCounted
## 동사 정의. 명세서 §5.2.
##
## §21 "동사는 ... 내부적으로 Action enum 또는 명확한 상수로 관리하라."
## 데이터(JSON)에서는 문자열 id 로 쓰고, 코드에서는 enum 으로 다룬다.

enum Verb {
	WALK,    ## UI에는 없지만 내부적으로 필요 (빈 바닥 클릭)
	LOOK,    ## 보다
	TALK,    ## 말하다
	PICKUP,  ## 집다
	USE,     ## 사용하다
	OPEN,    ## 열다
	CLOSE,   ## 닫다
	PUSH,    ## 밀다
	PULL,    ## 당기다
}

## enum -> 데이터 id
const IDS := {
	Verb.WALK: "walk",
	Verb.LOOK: "look",
	Verb.TALK: "talk",
	Verb.PICKUP: "pickup",
	Verb.USE: "use",
	Verb.OPEN: "open",
	Verb.CLOSE: "close",
	Verb.PUSH: "push",
	Verb.PULL: "pull",
}

## §5.2 고전 동사 UI — 8개. 2행 4열.
const CLASSIC_LAYOUT: Array[int] = [
	Verb.LOOK, Verb.TALK, Verb.PICKUP, Verb.USE,
	Verb.OPEN, Verb.CLOSE, Verb.PUSH, Verb.PULL,
]

## §5.2 간소화 UI — 조사 / 대화 / 사용 / 이동.
## '이동'은 WALK 로 매핑되며 출구를 강조 표시한다.
const SIMPLE_LAYOUT: Array[int] = [
	Verb.LOOK, Verb.TALK, Verb.USE, Verb.WALK,
]

## 핫스폿 위에서 우클릭할 때 쓰는 '가장 자연스러운' 동사.
const DEFAULT_VERB := Verb.LOOK


static func id(v: int) -> String:
	return str(IDS.get(v, "look"))


static func from_id(s: String) -> int:
	match s:
		"walk": return Verb.WALK
		"talk": return Verb.TALK
		"pickup": return Verb.PICKUP
		"use": return Verb.USE
		"open": return Verb.OPEN
		"close": return Verb.CLOSE
		"push": return Verb.PUSH
		"pull": return Verb.PULL
		_: return Verb.LOOK


## UI 라벨 로컬라이징 키. 고전/간소화에서 이름이 다르다(보다 vs 조사).
static func label_key(v: int, simple: bool) -> String:
	return "verb.simple.%s" % id(v) if simple else "verb.%s" % id(v)


## §5.3 "사용하다 → 금속 자 → 금이 간 지지선" 형태의 문장 라인.
## 아이템을 든 상태의 USE 는 두 단계로 표시된다.
static func sentence(v: int, simple: bool, target_name: String, held_item_name: String) -> String:
	var verb_text := Loc.t(label_key(v, simple))
	if v == Verb.USE and not held_item_name.is_empty():
		if target_name.is_empty():
			return "%s → %s → …" % [verb_text, held_item_name]
		return "%s → %s → %s" % [verb_text, held_item_name, target_name]
	if target_name.is_empty():
		return verb_text
	return "%s → %s" % [verb_text, target_name]
