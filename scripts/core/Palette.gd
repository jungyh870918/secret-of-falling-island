class_name Palette
extends RefCounted
## 팔레트. 명세서 §6.3 — 기본 32~48색으로 제한한다.
##
## 데이터(JSON)의 색 지정은 "#rrggbb" 직접 값 또는 "pal.bear_ink" 같은 팔레트 키를 쓴다.
## 팔레트 키를 쓰면 나중에 색 보정을 한 곳에서 할 수 있다.
##
## [최종 에셋 교체 지점] assets/palettes/ 에 .gpl/.hex 를 두고 여기 값을 맞춘다.

## §6.3 상승장 계열
const BULL := {
	"wine":     "#4a1220",
	"brick":    "#8c3327",
	"scarlet":  "#c8352e",
	"ember":    "#e8734a",
	"old_gold": "#b98a3c",
	"ivory":    "#e8d9b8",
}

## §6.3 하락장 계열
const BEAR := {
	"navy":     "#141c2e",
	"ink":      "#1b2430",
	"teal":     "#245a5e",
	"slate":    "#3d5670",
	"violet":   "#3a2c4d",
	"cold":     "#c8d8e4",
}

## §6.3 기관성 계열
const INSTITUTION := {
	"gray":     "#4a4a4c",
	"steel":    "#5f6d78",
	"pale":     "#8f9a8c",
	"green":    "#6f9a63",
	"monitor":  "#8fd48a",
	"paper":    "#c9c6b4",
}

## §6.3 리딩 군도 계열
const LEADING := {
	"gold":     "#e0b23a",
	"magenta":  "#b83a7a",
	"neon":     "#5ce0d0",
	"black":    "#0d0b10",
	"banner":   "#d0231f",
}

## UI 공통 (§5.1 하단 25% 명령 패널)
const UI := {
	"panel":       "#241f2b",
	"panel_light": "#3a3346",
	"panel_dark":  "#161320",
	"text":        "#d8d0c0",
	"text_dim":    "#8a8296",
	"text_hot":    "#e8c06a",
	"outline":     "#0d0b10",
	"select":      "#8c3327",
}

## 화자별 자막 색. §6.7 캐릭터 구분과 짝을 이룬다.
const SPEAKER := {
	"player":   "#e8d9b8",  ## 한개미 — 따뜻한 아이보리
	"sera":     "#9fd8d0",  ## 윤세라 — 차가운 청록
	"boss":     "#c9c6b4",  ## 부장 — 서류색
	"narrator": "#8a8296",  ## 내레이션 — 흐린 회보라
	"system":   "#e8c06a",
	"kim":      "#e0b23a",
	"park":     "#e8734a",
	"oh":       "#8f9a8c",
	"hint":     "#8fd48a",
}

const _TABLES := {
	"bull": BULL, "bear": BEAR, "inst": INSTITUTION, "lead": LEADING, "ui": UI, "speaker": SPEAKER,
}


## "#1b2430" 또는 "pal.bear.ink" / "pal.ui.panel" 형태를 Color 로.
static func parse(v: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if v is Color:
		return v
	var s := str(v)
	if s.is_empty():
		return fallback
	if s.begins_with("#"):
		return Color.html(s) if Color.html_is_valid(s) else fallback
	if s.begins_with("pal."):
		var parts := s.substr(4).split(".")
		if parts.size() == 2 and _TABLES.has(parts[0]):
			var table: Dictionary = _TABLES[parts[0]]
			if table.has(parts[1]):
				return Color.html(str(table[parts[1]]))
	return fallback


static func speaker_color(speaker: String) -> Color:
	return Color.html(str(SPEAKER.get(speaker, SPEAKER["player"])))


static func ui(key: String) -> Color:
	return Color.html(str(UI.get(key, "#ff00ff")))
