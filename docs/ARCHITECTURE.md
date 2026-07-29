# 아키텍처와 데이터 스키마

명세서 §21 이 요구한 다섯 가지를 이 문서가 대신한다.
(폴더 구조는 [README](../README.md), 구현 순서는 §20)

---

## 1. 설계 원칙 세 가지

### 원칙 1 — 콘텐츠는 코드에 들어가지 않는다

> §21 "하드코딩된 장면별 if문이 늘어나지 않도록 InteractionResolver 또는 동등한 중앙 처리 구조를 설계하라."

`scripts/` 안의 어떤 파일에도 `if scene_id == "office_pantry"` 같은 분기가 없다.
장면·아이템·대사·퍼즐·상호작용은 전부 `data/*.json` 이고, 코드는 그 스키마를 해석할 뿐이다.

챕터 2를 추가한다는 것은 JSON 파일 몇 개와 `manifest.json` 한 줄을 추가하는 일이다.

### 원칙 2 — 진행 불가 상태를 API 레벨에서 막는다

> §11.2 "한 번 놓치면 진행 불가", §21 "필수 아이템 삭제 기능은 구현하지 않는다."

- `GameState` 에 `drop_item` / `remove_item` 공개 API가 **없다**. `consume_item` 은 퍼즐이
  데이터에서 `take` 로 지정한 경우에만 호출되고, 그 룰은 항상 `give` 로 결과물을 돌려준다.
- 퍼즐 상태는 `states` 배열 순서로 **단조 증가만** 한다. `advance_puzzle` 은 역행 요청을 무시한다.
- 대화 선택지가 전부 소진되면 대화가 자연스럽게 끝난다(`_run_choices` → `"end"`).
- 잠긴 문은 핫스폿을 **숨기지 않고** 룰 + `on_fail` 로 막는다. 플레이어는 항상 왜 못 가는지 안다.

### 원칙 3 — "아무 반응 없는 클릭"이 존재할 수 없다

6단계 폴백 체인(아래 §3)의 마지막이 전역 동사 폴백이므로, 어떤 (동사, 대상) 조합이든
반드시 문장이 하나 나온다. §19.2 "선택지마다 캐릭터성이 있는가"의 최소 보장선이다.

---

## 2. 런타임 구조

```
Autoload (project.godot, 이 순서로 초기화됨)
  Theming        한글 SystemFont 폴백 + 전역 Theme, 폰트 3단계 (§18)
  GameData       manifest 기반 JSON 로드 + 상호작용 룰 인덱스
  Loc            키 → 문장. 누락 키는 ⟪key⟫ 로 표시 (§21)
  GameState      플래그/인벤/퍼즐/관계/플레이타임 (§17)
  SaveManager    슬롯 10 + 자동 3 순환, 도트 썸네일, 설정 (§17, §18)
  AudioDirector  펄스파 런타임 합성 효과음, 파일 있으면 파일 우선 (§7.3)
  SceneDirector  장면 전환 + 계단식 암전 + 전환 시 자동 저장

Main (scenes/core/Main.tscn — 유일한 .tscn)
├── World (Node2D)              ← SceneDirector 가 LocationView 를 붙인다
└── UI (CanvasLayer)
    ├── CommandPanel            하단 25%: 문장 라인 + 동사 8개 + 인벤 16칸 (§5.1)
    ├── SubtitleLayer           화자 머리 위 자막, 화자별 색 (§5.1, §18)
    ├── ChoiceBox               선택지 최대 4개 (§5.4)
    ├── TitleScreen / MenuList(일시정지) / MenuList(설정) / SaveSlotMenu
    ├── LogView                 대화 기록 (§18, §23)
    ├── CardView                컷신 카드 (§3.2)
    ├── DebugPanel              F1 (§21)
    └── GameCursor              십자 커서 (§5.3)
```

`Main` 이 하는 일은 **클릭이 무슨 뜻인지 판정해서 넘기는 것뿐**이다.
`(action, target, item)` 을 만들어 `InteractionResolver` 에 주고, 돌아온 `result` 를
`ResultRunner` 에 넘긴다.

---

## 3. 상호작용 해석 — 6단계 폴백 체인

`InteractionResolver.resolve(action_id, target_id, item_id)` → `InteractionResult`

| # | 조건 | 결과 종류 |
|---|---|---|
| 1 | `(action, target, item)` 룰 일치 + 전제조건 충족 | `SUCCESS` |
| 2 | 룰은 일치하나 전제조건 실패 → 그 룰의 `on_fail` | `PRECONDITION_FAIL` |
| 3 | 아이템 무관 룰의 `on_fail` | `PRECONDITION_FAIL` |
| 4 | 핫스폿 데이터의 `defaults[action]` (아이템을 들었으면 `defaults["use_item"]` 우선) | `DEFAULT_LINE` |
| 5 | 손에 든 아이템의 `fail_key` | `DEFAULT_LINE` |
| 6 | 전역 `fallback.verb.<action>` / `fallback.use_item` | `DEFAULT_LINE` |

**2단계가 §21의 "잘못된 조합에는 고유한 실패 대사를 제공한다"를 구조적으로 보장한다.**
전제조건을 붙인 룰의 작성자는 `on_fail` 을 같이 쓸 수밖에 없고,
안 쓰면 `tests/validate_data.py` 가 경고한다.

### 룰 정렬 규칙

같은 `(action, target)` 에 룰이 여러 개면 `GameData._build_rule_index` 가 정렬한다.

1. `item` 을 지정한 룰이 먼저 (더 구체적)
2. 그다음 전제조건 개수가 많은 룰이 먼저

이 규칙에서 **관용구 하나가 나온다.**

```jsonc
// 이미 본 뒤의 짧은 반복 대사 — 전제조건이 있으므로 자동으로 먼저 검사된다
{ "id": "look_boss_mug_repeat", "action": "look", "target": "boss_mug",
  "preconditions": { "flags": ["knows_boss_caffeine"] },
  "result": { "lines": [ ... ] } },

// 첫 관찰 — 전제조건이 없으므로 위 룰이 안 걸릴 때만 실행된다
{ "id": "look_boss_mug_first", "action": "look", "target": "boss_mug",
  "result": { "flags": { "knows_boss_caffeine": true }, "lines": [ ... ] } }
```

"처음 볼 때 / 다시 볼 때"를 코드 분기 없이 데이터만으로 표현한다.

### 아이템 조합은 대칭이다

`use A on B` 가 안 걸리면 `use B on A` 로 한 번 더 시도한다(§16.3).
플레이어가 어느 쪽을 먼저 집었는지 신경 쓸 필요가 없다.

---

## 4. 데이터 스키마

### 4.1 상호작용 룰 (`data/interactions/*.json`)

```jsonc
{
  "id": "use_disguised_on_boss",     // 고유. 검증기가 중복을 잡는다
  "action": "use",                   // 문자열 또는 배열 ["walk","open","use"]
  "target": "boss",                  // 핫스폿 id / 출구 id / 아이템 id. 배열 가능
  "item": "disguised_cup",           // 손에 든 아이템. 없으면 맨손 전용
  "any_item": false,                 // true 면 아무 아이템이나 받는다
  "once": true,                      // 한 번만. 이후엔 다음 순위 룰로
  "preconditions": { ... },          // §4.3
  "result":  { ... },                // §4.2
  "on_fail": { ... }                 // 전제조건 실패 시. 문자열(대사 키)도 가능
}
```

### 4.2 result op — 상호작용과 대화 노드가 **같은 스키마**를 쓴다

`ResultRunner` 하나가 둘 다 실행한다. 실행 순서는 아래 표 순서.

| op | 형태 | 뜻 |
|---|---|---|
| `lines_pre` | `[{speaker, key, args, if}]` | 상태 변경 **전** 대사 |
| `sfx` | `"pickup"` | §7.3 효과음 |
| `take` | `["item_id"]` | 소모. 반드시 `give` 와 함께 |
| `give` | `["item_id"]` | 지급 |
| `flags` / `flags_add` | `{"flag": true}` / `{"count": 1}` | 플래그 |
| `puzzle` | `{"decaf_swap": "cup_brewed"}` | 단조 증가 전진 |
| `relation` | `{"sera_trust": 1}` | §12.2 관계 4축 |
| `hotspots` / `exits` | `{"boss": false}` | 켜기/끄기. `"scene_id/id"` 로 타 장면 지정 |
| `lines` | 위와 같음 | 상태 변경 **후** 대사 |
| `dialogue` | `"boss_leaving"` | 분기 대화 시작 (끝까지 await) |
| `event` | `"prologue_end"` | Main 의 특수 연출 (await 가능) |
| `goto` | `"scene_id"` 또는 `{scene, entry}` | 장면 이동 |
| `autosave` | `true` | §17 자동 저장 시점 |

대사 줄에는 `"if": {...}` 로 조건을 달 수 있다. 조건이 안 맞으면 그 줄만 건너뛴다.

### 4.3 preconditions (`Conditions.gd`)

```jsonc
{
  "flags": ["knows_boss_caffeine"],   "not_flags": ["boss_left"],
  "items": ["decaf_pack"],            "not_items": ["disguised_cup"],
  "puzzle_at_least": { "decaf_swap": "cup_brewed" },
  "puzzle_is":       { "decaf_swap": "disguised" },
  "puzzle_not":      { "decaf_swap": "completed" },
  "relation_min":    { "sera_trust": 3 },
  "relation_max":    { "sera_irritation": 2 },
  "scene": "office_pantry",
  "seen": "boss_first_talk/n050",     "not_seen": "boss_first_talk/n001"
}
```

핫스폿의 `visible_if`, 블록의 `visible_if`, 대화 선택지의 `requires`,
대사 줄의 `if` 가 모두 같은 스키마를 쓴다.

### 4.4 장면 (`data/scenes/*.json`)

좌표계는 **320×135** (하단 45px 은 명령 패널).

```jsonc
{
  "scene_id": "office_pantry",
  "name_key": "scene.office_pantry",
  "background": "res://assets/backgrounds/office_pantry.png",  // 있으면 blocks 대신 사용
  "music": "office_night",
  "active_puzzles": ["decaf_swap"],        // 힌트 시스템이 참조
  "walkbox": [20, 98, 284, 30],            // 사각형 하나 또는 사각형 배열
  "spawn_points": { "default": [60,116], "from_corridor": [46,116] },

  "blocks": [                              // 임시 도트. 뒤에서 앞 순서로 그린다
    { "rect": [0,0,320,90], "color": "#6f7a6a" },
    { "rect": [0,56,320,34], "color": "#8f9a8c", "dither": "2x2", "color2": "#6f7a6a" },
    { "hotspot": "decaf_shelf", "rect": [152,52,20,26], "color": "#6f9a63",
      "visible_if": { "not_flags": ["took_decaf"] } },
    { "rect": [109,46,10,2], "color": "#8fd48a", "anim": "flicker" }
  ],

  "hotspots": [{
    "id": "coffee_machine",
    "name_key": "hotspot.coffee_machine",
    "default_verb": "use",                 // 우클릭 시 쓸 동사
    "character": "boss",                   // 있으면 Actor 를 세운다
    "stand_at": [162, 118],
    "rect": [102, 38, 36, 42],
    "walk_to": [120, 106],                 // 상호작용 전 걸어갈 곳
    "visible_if": { ... },
    "defaults": { "talk": "fail.machine.talk", "use_item": "..." }
  }],

  "exits": [{
    "id": "door_corridor", "name_key": "...", "default_verb": "walk",
    "rect": [...], "walk_to": [...],
    "target": "office_corridor", "entry": "from_pantry"
  }]
}
```

`blocks[].anim` — `flicker`(전광판·모니터), `blink`(경고등), `ticker`(캔들 오르내림). §6.6
`blocks[].dither` — `2x2` / `4x4`. 그라데이션 대신 쓴다. §6.4
`blocks[].hotspot` — 그 핫스폿이 꺼지면 이 블록도 사라진다.

**출구는 룰이 없으면 자동으로 이동한다.** 룰(`walk`/`open`/`use`/`push`)을 걸면 그쪽이
항상 우선하므로, 잠긴 문은 룰 + `on_fail` 로 표현한다.

### 4.5 대화 (`data/dialogues/*.json`) — §16.2

```jsonc
{
  "dialogue_id": "boss_first_talk",
  "start_node": "n001",
  "nodes": {
    "n001": { "speaker": "boss", "text_key": "dlg.boss1.n001", "next": "n002" },
    "n002": { "speaker": "player", "choices": [
      { "text_key": "dlg.boss1.c001", "say_key": "...", "next": "n010",
        "requires": { ... }, "once": true, "silent": false,
        "effects": { "sera_respect": 1 },   // 관계 변수 전용
        "result":  { ... } }                // 그 외 상태 변경은 전부 여기
    ]},
    "n003": { "branches": [ { "if": {...}, "next": "n010" } ], "next": "n011" },
    "n004": { "result": { "flags": {...}, "autosave": true }, "next": "end" }
  }
}
```

- 고른 선택지는 한개미가 실제로 말한다(`say_key` 로 다른 문장 지정 가능, `silent: true` 로 생략).
- `once` 선택지가 전부 소진되면 대화는 `"end"` 로 끝난다 → 대화 안에서 갇히지 않는다.
- 검증기가 모든 `next` 의 도달 가능성과 고아 노드를 검사한다.

### 4.6 퍼즐 (`data/puzzles/*.json`) — §16.4, §11.3

```jsonc
{
  "puzzle_id": "decaf_swap",
  "states": ["not_started", "has_decaf", "cup_brewed", "disguised", "completed"],
  "fail_safe": { "resettable": true, "lost_items_restored": true },
  "hints": {
    "not_started": [
      { "speaker": "player",   "key": "hint.decaf.0.1" },   // 1단계: 혼잣말
      { "speaker": "narrator", "key": "hint.decaf.0.2" },   // 2단계: 관찰 (세라 부재 시 내레이션)
      { "speaker": "hint",     "key": "hint.decaf.0.3" }    // 3단계: 구체적 지시
    ]
  }
}
```

**순서를 강제하고 싶지 않은 관찰은 상태가 아니라 플래그로 둔다.**
프롤로그에서 "부장의 컵 관찰"은 `knows_boss_caffeine` 플래그다.
디카페인을 먼저 챙기든 컵을 먼저 보든 막히지 않는다.

검증기는 모든 상태에 힌트가 **2단계 이상** 있는지 확인한다(§19.1).

---

## 5. 프롤로그 퍼즐 흐름 (§8.1)

```
                     [관찰 — 순서 무관, 플래그]
  회의실  ─ 보다 → 부장의 머그컵 ──────────────► knows_boss_caffeine
                                                knows_boss_brand
  탕비실  ─ 집다 → 초록 봉지  ──► decaf_pack        puzzle: has_decaf
          ─ 집다 → 빨간 봉지  ──► strong_label      (빈 봉지는 그대로 남는다)
          ─ 사용 → 커피 머신 + decaf_pack ──► decaf_cup    puzzle: cup_brewed
          ─ 사용 → decaf_cup + strong_label ─► disguised_cup  puzzle: disguised

  회의실  ─ 사용 → 부장 + disguised_cup
             ├ knows_boss_caffeine ✓ → boss_leaving 대화 → boss_left
             │                          부장 핫스폿 off, puzzle: completed
             └ ✗ → on_fail: 부장 "됐네. 난 이따 내 걸로 마셔."   ← 고유 실패 대사 = 힌트

  복도    ─ 엘리베이터
             ├ boss_left ✓ → event: prologue_end → 컷신 카드 → 타이틀
             └ ✗ → on_fail: "부장님이 아직 계신다."
```

고유 실패 대사가 세 군데 더 있다(§21):

| 시도 | 반응 |
|---|---|
| 위장 안 한 종이컵을 부장에게 | "그건 자네 컵 아닌가? 난 내 거 마시네." |
| 봉지째 부장에게 | "그걸 나더러 씹으라는 건가?" |
| 커피를 싱크대에 버리기 | "이걸 버리면 다시 만들어야 한다. 그건 손실 확정이다." |

마지막 것이 §11.2 "필수 아이템을 잃을 수 없다"를 **농담으로** 처리한 지점이다.

---

## 6. 아직 비어 있는 자리

| 위치 | 용도 | 명세서 |
|---|---|---|
| `scripts/battle/`, `data/battles/` | 대화 배틀 (멘탈 차트, 모순 카드, 약점 10종) | §9 |
| `GameState.battle_results` | 배틀 결과 — 이미 세이브 포맷에 포함 | §17 |
| `GameState.relation` 4축 | 세라 관계 — 대화 선택지 `effects` 가 이미 연결됨 | §12.2 |
| `GameState.ending_vars` | 엔딩 조건 누적치 | §15 |
| `scenes/cutscenes/`, `assets/sprites/portraits/` | 초상화 대화 (96×96) | §5.4, §6.2 |

챕터 1을 붙일 때 세이브 포맷을 바꾸지 않아도 되도록 미리 넣어 뒀다.
