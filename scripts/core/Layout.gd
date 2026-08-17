class_name Layout
extends RefCounted
## 화면 배치 상수.
##
## **2026-08-17 세로 전환.** 기준 캔버스 941×1672 (스튜디오 D1) → **942×1674 로 1~2px 조정**했다.
## 이유는 아래 「두 좌표계」. 가로 320×180 은 폐기됐다 — D2 「세로 전용」.
##
## ## 두 좌표계
##
## 기획서 §05 의 세 층 중 **World 만 D1 캔버스에 묶인다.** UI 는 기기 해상도다.
## 그래서 이 파일은 좌표계를 둘 쓴다.
##
## - **화면 좌표** — 뷰포트 942×1674. 월드·핫스폿·마우스가 여기 산다
## - **UI 좌표** — 314×558 «설계 픽셀». UI 캔버스층이 `UI_SCALE` 배로 확대해 그린다
##
## UI 를 확대하는 이유는 Galmuri 가 **도트 폰트**라서다. 설계 크기의 정수 배가 아니면
## 글자가 뭉갠다. 942 = 314×3, 1674 = 558×3 — D1 에서 1~2px 어긋나지만(0.1%)
## 그 대가로 UI 전체가 정수 배로 떨어진다.
##
## 화면 좌표를 UI 노드에 넘길 때는 반드시 `to_ui()` 를 통과시킨다.
##
##   0 ──────────────── 942            UI 좌표로는 314
##   0 ┌────────────────┐
##     │  상단 바        │  147           49
## 147 ├────────────────┤
##     │                │
##     │  월드 1305      │  화면의 78%   435
##     │                │
##1452 ├────────────────┤
##     │  상황 라인·가방  │  222           74
##1674 └────────────────┘

const SCREEN := Vector2i(942, 1674)

## UI 층 확대 배율. 도트 폰트가 뭉개지지 않으려면 **정수**여야 한다
const UI_SCALE := 3
const UI_SIZE := Vector2i(314, 558)

## 상단 바 — 화면 좌표
const TOPBAR_H := 147
const TOPBAR_RECT := Rect2i(0, 0, 942, 147)

## 월드 밴드. **화면 좌표**다 — 월드 노드가 여기로 옮겨진다
const WORLD_ORIGIN := Vector2i(0, 147)
const WORLD_SIZE := Vector2i(942, 1305)
const WORLD_SCREEN_RECT := Rect2i(0, 147, 942, 1305)

## 장면 영역. **월드 로컬 좌표**라 원점이 0 이다 (월드 노드가 이미 내려가 있다)
const VIEW_HEIGHT := 1305
const VIEW_RECT := Rect2i(0, 0, 942, 1305)

# ---------------------------------------------------------------- 여기부터 UI 좌표

## 상단 바 — UI 좌표
const UI_TOPBAR_RECT := Rect2i(0, 0, 314, 49)

## 하단 — 상황 라인 + 가방
const PANEL_Y := 484
const PANEL_HEIGHT := 74
const PANEL_RECT := Rect2i(0, 484, 314, 74)

## §5.3 문장 라인 — "사용하다 → 금속 자 → 금이 간 지지선"
const SENTENCE_RECT := Rect2i(4, 486, 306, 14)

## §5.1 왼쪽 동사 버튼 (2행 4열)
const VERB_ORIGIN := Vector2i(4, 503)
const VERB_CELL := Vector2i(37, 25)
const VERB_GAP := Vector2i(1, 1)
const VERB_COLS := 4
const VERB_ROWS := 2

## §5.1 오른쪽 인벤토리 슬롯 (2행 6열 = 12칸)
const INV_ORIGIN := Vector2i(164, 503)
const INV_CELL := Vector2i(24, 25)
const INV_GAP := Vector2i(1, 1)
const INV_COLS := 6
const INV_ROWS := 2
const INV_VISIBLE := 12

## §5.4 대화 선택지 — 최대 4개, 패널 영역을 덮는다
## 두 줄짜리 선택지 4개가 들어가야 한다 (26×4 = 104). 월드 아래쪽을 조금 덮는다 —
## 목업의 선택지 카드도 월드 위에 얹힌다
const CHOICE_RECT := Rect2i(2, 446, 310, 110)
const CHOICE_MAX := 4

## §5.4 초상화 대화 / §6.2 초상화.
## 스튜디오 P1 규격 188×188 (941 캔버스) → UI 좌표로 63.
## 장면 영역 아래쪽 모서리에 붙인다. 말하는 배우가 그 모서리에 서 있으면
## 반대쪽으로 옮겨 화자를 가리지 않게 한다.
const PORTRAIT_SIZE := 63
const PORTRAIT_MARGIN := 4

## 월드 밴드를 UI 좌표로 본 것. 초상화·자막이 월드 안에 머물러야 할 때 쓴다
const UI_WORLD_RECT := Rect2i(0, 49, 314, 435)


static func portrait_rect(on_left: bool) -> Rect2i:
	var x := PORTRAIT_MARGIN if on_left else UI_SIZE.x - PORTRAIT_SIZE - PORTRAIT_MARGIN
	# 선택지 상자 «위»에 앉힌다. 월드 바닥에 붙이면 선택지 4개가 뜰 때 가려진다
	var y := CHOICE_RECT.position.y - PORTRAIT_SIZE - PORTRAIT_MARGIN
	return Rect2i(x, y, PORTRAIT_SIZE, PORTRAIT_SIZE)


static func verb_cell_rect(index: int) -> Rect2i:
	var col := index % VERB_COLS
	var row := index / VERB_COLS
	return Rect2i(
		VERB_ORIGIN.x + col * (VERB_CELL.x + VERB_GAP.x),
		VERB_ORIGIN.y + row * (VERB_CELL.y + VERB_GAP.y),
		VERB_CELL.x, VERB_CELL.y)


static func inv_cell_rect(index: int) -> Rect2i:
	var col := index % INV_COLS
	var row := index / INV_COLS
	return Rect2i(
		INV_ORIGIN.x + col * (INV_CELL.x + INV_GAP.x),
		INV_ORIGIN.y + row * (INV_CELL.y + INV_GAP.y),
		INV_CELL.x, INV_CELL.y)


## 화면 좌표가 월드 밴드 안인가
static func in_view(p: Vector2) -> bool:
	return Rect2(WORLD_SCREEN_RECT).has_point(p)


## 화면 좌표 → 월드 로컬 좌표
static func to_world(p: Vector2) -> Vector2:
	return p - Vector2(WORLD_ORIGIN)


## 화면 좌표 → UI 설계 좌표. UI 노드에 마우스 위치를 넘길 때 반드시 거친다
static func to_ui(p: Vector2) -> Vector2:
	return p / float(UI_SCALE)


## 월드 로컬 좌표 → UI 설계 좌표. 배우 위치에 초상화·자막을 붙일 때 쓴다
static func world_to_ui(p: Vector2) -> Vector2:
	return (p + Vector2(WORLD_ORIGIN)) / float(UI_SCALE)
