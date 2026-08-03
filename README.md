# 떡락섬의 비밀 (코드명 RED_CANDLE)

1990년대 DOS VGA 어드벤처 감성의 2D 포인트 앤 클릭 게임.
이 저장소는 [통합 제작 명세서](떡락섬의_비밀_DOS_2D_어드벤처_통합제작명세서.md) **§20 Phase 2 — 수직 슬라이스** 구현이다.

- 엔진: Godot 4.2+ / GDScript
- 내부 해상도: 320×180, 정수 배율, nearest 필터, 안티앨리어싱 없음 (§6.2, §21)
- 현재 범위: **프롤로그 전체** — 회의실 · 복도 · 탕비실 · 심야 지하철 · 원룸 · 황소항 입구 (§8.1)
  - 디카페인 커피 퍼즐, 투자 방송 장면, 첫 사기 피해, 윤세라 첫 등장
  - §9 대화 배틀 1개 (환전소), §5.4 초상화 대화, §7.2 배경음악 3곡

---

## 실행

```bash
# Godot 4.2 이상에서 이 폴더를 프로젝트로 열고 F5
godot --path .
```

Godot 편집기에서 처음 열면 `.godot/` 캐시가 생성된다. `scenes/core/Main.tscn` 이 메인 씬이다.

### 검증

```bash
# Godot 없이 — 의존성 없는 파이썬 스크립트
python3 tests/check_project.py                    # 구조 / class_name 충돌 / 경로 / 들여쓰기
python3 tests/validate_data.py                    # JSON · 대사 키 · 룰 · 대화 그래프 · 좌표

# Godot 필요
godot --headless --path . tests/SmokeTest.tscn    # 프롤로그 전체 자동 플레이, 135건 검증
godot --path . tests/Screenshots.tscn             # docs/screenshots/ 에 30장 캡처
```

```bash
# 웹 빌드 — 브라우저에서만 드러나는 것(오디오 정책·IndexedDB 세이브·예약 키)
tests/web_check.sh
```

`SmokeTest` 는 `--headless` 라 창이 뜨지 않는다.
`Screenshots` 는 실제 렌더링이 필요해 창을 만들지만(헤드리스는 더미 렌더러라 이미지가
안 나온다), **포커스를 뺏지 않고 화면 밖에서 돌기 때문에 작업을 가리지 않는다.**
눈으로 보려면 `godot --path . tests/Screenshots.tscn -- visible`.

`SmokeTest` 는 §23 완료 기준 16개 중 15개를 자동으로 확인하고,
회의실부터 황소항 대화 배틀까지 프롤로그 전 구간을 실제로 플레이한다.
그 뒤 6개 장면 × 35개 대상 × 8동사 × 아이템 조합 **4368가지가 전부 대사를 내는지** 훑는다.

현재 상태: **전부 통과**. 자세한 내용은 [docs/PROTOTYPE_QA.md](docs/PROTOTYPE_QA.md).

---

## 조작

| 입력 | 동작 |
|---|---|
| 좌클릭 (장면) | 선택한 동사로 상호작용 / 빈 바닥은 이동 |
| **우클릭 (장면)** | 그 대상에게 **가장 자연스러운 동작** (문이면 이동, 사람이면 대화) |
| **길게 누르기 (터치)** | 우클릭과 같다. 터치 기기에서는 동사 UI 가 간소화 4개로 시작한다 |
| 좌클릭 (인벤토리) | `사용하다` 상태면 아이템을 손에 든다. 다른 아이템에 다시 쓰면 조합 |
| 우클릭 (인벤토리) | 아이템 살펴보기 |
| 방향키 / WASD | 걷기 |
| 숫자 1–8 | 동사 선택 (대화 중에는 선택지 선택) |
| Space / Enter | 대사 넘기기, 메뉴 확정 |
| H 또는 좌하단 `?` | 힌트 (페널티 없음, §11.3) |
| TAB 또는 L | 대화 기록 (§18) |
| ESC | 일시정지 메뉴 |
| F5 / F9 | 빠른 저장 / 빠른 불러오기 |
| F11 | 전체 화면 |
| **F1** | 디버그 패널 (F2 페이지 전환, F3 데이터 리로드) |

문 앞에서 `열다`를 못 찾아 헤매지 않도록 **우클릭 = 기본 동작**을 넣었다.
각 핫스폿의 기본 동작은 장면 데이터의 `default_verb` 로 지정한다.

---

## 폴더 구조

```
red-candle/
├─ project.godot            Godot 설정 (autoload, 320×180, integer scaling)
├─ scenes/core/Main.tscn    유일한 .tscn — 나머지 노드는 전부 코드로 구성
├─ docs/ARCHITECTURE.md     아키텍처와 데이터 스키마
├─ data/                    ★ 콘텐츠는 전부 여기. 코드 수정 없이 늘어난다
│  ├─ manifest.json         읽어들일 파일 목록 (새 파일 추가 시 여기도 한 줄)
│  ├─ localization/ko*.json 모든 문장. 코드/데이터에는 키만 있다
│  ├─ scenes/               배경 블록, 핫스폿, 출구, walkbox
│  ├─ interactions/         ★ 상호작용 룰 테이블
│  ├─ dialogues/            분기 대화 그래프
│  ├─ items/ puzzles/ chapters/ characters/
│  └─ battles/              ★ §9 대화 배틀 정의 (페이즈 · 선택지 · 모순 카드)
├─ scripts/
│  ├─ core/                 Autoload, Main, Palette, Layout
│  ├─ interaction/          Actions, Conditions, InteractionResolver, ResultRunner
│  ├─ dialogue/             DialogueRunner, DialogueLog, HintSystem
│  ├─ battle/               BattleRunner, BattleView (§9)
│  ├─ locations/            LocationView, Actor
│  ├─ ui/  save/  debug/
├─ assets/                  ★ 지금은 비어 있다. 넣으면 자동으로 임시 도트를 대체
└─ tests/                   Godot 없이 도는 검증 스크립트
```

---

## 에셋 교체 지점

프로토타입은 임시 도트(색 블록)와 런타임 합성 사운드로 돌아간다.
효과음도 배경음악도 파일이 아니라 코드가 만든다 — 저장소에 바이너리가 없어도 소리가 난다.
아래 경로에 **파일을 넣기만 하면** 코드 수정 없이 교체된다.

| 넣을 곳 | 규격 | 대체 대상 |
|---|---|---|
| `assets/backgrounds/<scene_id>.png` | 320×135 | 장면의 `blocks` 임시 도트 |
| `assets/sprites/characters/<character_id>.png` | 스프라이트시트, 프레임 32×48 | Actor 의 `_draw()` 임시 캐릭터 |
| `assets/sprites/portraits/<character_id>.png` | 96×96 | PortraitView 의 임시 초상화 (§5.4) |
| `assets/ui/items/<item_id>.png` | 16×16 | 인벤토리 색 블록 아이콘 |
| `assets/ui/title.png` | 320×180 | 타이틀 임시 아트 |
| `assets/ui/command_panel.png` | 320×45 | 하단 명령 패널 배경 |
| `assets/audio/sfx/<이름>.wav` | — | 런타임 합성 효과음 |
| `assets/audio/music/<이름>.ogg` | — | `MusicSynth` 의 런타임 합성 곡 |

### 폰트

**Galmuri** (이민서, SIL Open Font License 1.1) — 한글 도트 폰트를 쓴다.
`assets/fonts/Galmuri-LICENSE.txt` 를 재배포 시 반드시 동봉해야 한다.

도트 폰트는 **설계된 픽셀 크기로만** 써야 뭉개지지 않으므로, §18 의 크기 3단계마다
그 크기로 설계된 폰트를 따로 쓴다. 하나를 골라 배율만 바꾸지 않는다.

| 단계 | 폰트 | 크기 |
|---|---|---|
| 작게 | `Galmuri9.ttf` | 9px |
| 보통 | `Galmuri11.ttf` | 11px |
| 크게 | `Galmuri14.ttf` | 14px |

원본 3개는 15MB(한글 외 라틴 확장·키릴·가나까지 포함)라서
`tools/subset_font.py` 로 이 게임이 쓰는 문자만 남겨 5MB 로 줄였다.
**한글 11,172자는 전부 남긴다** — 여기서 줄이면 새 대사를 쓸 때마다 글자가 빠질
위험이 생기고, 그 위험이 절약되는 몇 MB보다 비싸다.

```bash
python3 -m pip install --user fonttools
python3 tools/subset_font.py <Galmuri_원본_폴더>
```

폰트 파일이 없으면 `Theming` 이 OS 한글 폰트로 자동 폴백한다 — 도트 느낌은
사라지지만 두부(□)는 뜨지 않는다.

---

## 프롤로그 진행 (§8.1)

```
회의실 ─ 디카페인 커피 퍼즐 ─► 복도 ─ 엘리베이터
                                   │
                              심야 지하철  광고판 · 창문 반사 · 노선도(황소항)
                                   │      '마지막 기회' 전단지 획득
                                   ▼
                                 원룸     전단지 + 노트북 → 박프로 투자 방송
                                   │      월급 봉투를 챙겨야 나갈 수 있다
                                   ▼
                            황소항 입구   가짜 환전소 → 첫 사기 피해
                                   │      윤세라 첫 등장 · 첫 만남 대화
                                   │      §9 대화 배틀 — 규정/지정/수수료의 자기모순
                                   ▼
                              프롤로그 종료 컷신 → 챕터 1 예고
```

배틀은 **져도 진행이 막히지 않는다**(§9.5). 이기면 수수료를 돌려받고,
지면 셔터가 내려갈 뿐이다. 어느 쪽이든 세라의 명함을 받고 프롤로그가 끝난다.

---

## 다음 단계 (§20)

- **Phase 3 — 챕터 1**: 투자자 조합 세 시험, 대화 배틀 3개, 퍼즐 6~8개, 챕터 종료 컷신
- **Phase 4**: 챕터 2부터 순차 제작

챕터 1을 붙이려면 `data/` 에 JSON 을 더하고 `manifest.json` 에 줄을 추가하면 된다.
배틀도 마찬가지로 `data/battles/` 에 정의만 넣으면 되고, 상호작용 룰에서
`"event": "battle:<id>"` 로 부른다. `scripts/` 는 건드리지 않는다.

`GameState` 의 관계 변수 4축(§12.2)과 `battle_results` 는 이미 저장 포맷에 들어 있어,
챕터 1을 붙일 때 세이브 호환성이 깨지지 않는다.
