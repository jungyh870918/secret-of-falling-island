class_name Layout
extends RefCounted
## 화면 배치 상수. 명세서 §5.1 / §6.2.
##
##  0 ─────────────────────────── 320
##  0 ┌──────────────────────────┐
##    │  상단 75% : 게임 장면      │
##135 ├──────────────────────────┤
##    │  하단 25% : 명령 + 인벤토리 │
##180 └──────────────────────────┘

const SCREEN := Vector2i(320, 180)

## 게임 장면 영역 (상단 75%)
const VIEW_HEIGHT := 135
const VIEW_RECT := Rect2i(0, 0, 320, 135)

## 명령 패널 영역 (하단 25%)
const PANEL_Y := 135
const PANEL_HEIGHT := 45
const PANEL_RECT := Rect2i(0, 135, 320, 45)

## §5.3 문장 라인 — "사용하다 → 금속 자 → 금이 간 지지선"
const SENTENCE_RECT := Rect2i(3, 135, 314, 12)

## §5.1 왼쪽 동사 버튼 (2행 4열)
const VERB_ORIGIN := Vector2i(3, 148)
const VERB_CELL := Vector2i(38, 14)
const VERB_GAP := Vector2i(1, 1)
const VERB_COLS := 4
const VERB_ROWS := 2

## §5.1 오른쪽 인벤토리 슬롯 (2행 6열 = 12칸)
const INV_ORIGIN := Vector2i(162, 148)
const INV_CELL := Vector2i(25, 14)
const INV_GAP := Vector2i(1, 1)
const INV_COLS := 6
const INV_ROWS := 2
const INV_VISIBLE := 12

## §5.4 대화 선택지 — 최대 4개, 패널 영역을 덮는다
const CHOICE_RECT := Rect2i(2, 134, 316, 45)
const CHOICE_MAX := 4

## §5.4 초상화 대화 / §6.2 초상화 96×96.
## 장면 영역 아래쪽 모서리에 붙인다. 말하는 배우가 그 모서리에 서 있으면
## 반대쪽으로 옮겨 화자를 가리지 않게 한다.
const PORTRAIT_SIZE := 96
const PORTRAIT_MARGIN := 3


static func portrait_rect(on_left: bool) -> Rect2i:
	var x := PORTRAIT_MARGIN if on_left else SCREEN.x - PORTRAIT_SIZE - PORTRAIT_MARGIN
	return Rect2i(x, VIEW_HEIGHT - PORTRAIT_SIZE - PORTRAIT_MARGIN, PORTRAIT_SIZE, PORTRAIT_SIZE)


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


static func in_view(p: Vector2) -> bool:
	return Rect2(VIEW_RECT).has_point(p)
