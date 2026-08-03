# 웹 빌드 인수인계

이 게임이 웹으로 익스포트되어 개인 게임 사이트 **JUNG ARCADE** 안에 임베드되었다.
이 문서는 그 작업의 내용과, **게임 저장소 쪽에서 이어서 해야 할 일**을 정리한 것이다.

- 공개 주소: https://web-production-f5ce4.up.railway.app/games/secret-of-falling-island
- 사이트 저장소: `jung-arcade` (Next.js) — 이 게임의 소개 페이지와 실행 영역이 거기 있다
- 최초 작업 일자: 2026-08-03 / 대상 커밋 `030a099`
- P1 처리 일자: 2026-08-03 / Phase 2 수직 슬라이스(`3a74e91`) 이후

> **이 문서를 세션 프롬프트로 쓰려면** 아래 한 줄이면 된다.
>
> ```
> docs/WEB_BUILD_HANDOFF.md 를 읽고, "해야 할 일" 의 P1 항목부터 처리해 줘.
> ```

---

## 1. 무슨 작업이 있었나

Godot 4 프로젝트를 **HTML5(WebAssembly)로 익스포트**해서, 사이트의 게임 상세
페이지 안에 iframe 으로 넣었다. 게임 코드는 **한 줄도 고치지 않았다.**
익스포트 설정만 새로 만들었다.

### 확인된 것 (실측)

| 항목 | 결과 |
|---|---|
| Godot 4.7.1 에서 열리는가 | ✅ 4.2 대상 프로젝트지만 그대로 열린다. 프로젝트 파일 변경 없음 |
| 기존 테스트 | ✅ `tests/SmokeTest.tscn` **82건 전부 통과** (4.7.1 기준) |
| 웹 렌더링 | ✅ `gl_compatibility` → WebGL 2.0 정상 |
| iframe 임베드 | ✅ 16:9 컨테이너 안에서 정상 구동 |
| 실제 플레이 | ✅ 타이틀 → 「새 게임」 → 프롤로그 진입까지 확인 |
| 전송량 | wasm 37.6MB → **gzip 10.2MB** |
| 화면 비율 | 내부 해상도 320×180 → **16:9** |

### 핵심 결정 — 스레드를 껐다

Godot 웹 빌드의 가장 큰 함정은 **SharedArrayBuffer** 다.
스레드를 켜고 빌드하면 브라우저가 cross-origin isolation 을 요구하고,
서버가 이런 헤더를 보내야 한다.

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

이 헤더를 켜면 **그 사이트 전체에서 다른 출처의 리소스가 전부 막히고**,
iframe 으로 품고 있는 부모 페이지까지 같이 isolate 되어야 한다.
사이트에 이미 올라가 있는 다른 게임까지 깨질 수 있었다.

그래서 `variant/thread_support=false` 로 빌드했다. 빌드 로그가 그 증거다.

```
Build configuration: Emscripten 4.0.20, single-threaded, no GDExtension support.
```

**이 설정을 되돌리지 말 것.** 단일 스레드라 로딩이 조금 느려지지만,
이 게임 규모에서는 체감 차이가 없고 대신 어디서든 헤더 설정 없이 돌아간다.

### 익스포트 설정

`export_presets.cfg` 를 새로 만들었다. **이 파일은 현재 `.gitignore` 에 걸려
있어 커밋되지 않았다** (아래 P1-1 참고). 전체 내용은
사이트 저장소의 `docs/godot-web-export.md` 에 그대로 적어 두었다. 요점만:

```ini
[preset.0]
name="Web"
platform="Web"
export_filter="all_resources"
exclude_filter="tests/*, docs/*, tools/*"   # pck 를 줄인다
export_path="../build/web/index.html"

[preset.0.options]
variant/thread_support=false                # ★ 절대 true 로 바꾸지 말 것
variant/extensions_support=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/head_include="<meta name=\"robots\" content=\"noindex, follow\">
<link rel=\"canonical\" href=\"https://web-production-f5ce4.up.railway.app/games/secret-of-falling-island\">"
progressive_web_app/enabled=false
```

`html/head_include` 는 검색엔진이 **게임 실행 페이지 대신 소개 페이지를 색인**
하게 만든다. 실행 페이지는 캔버스뿐이라 본문 텍스트가 없어서 단독으로는
검색 가치가 없고, 그대로 두면 소개 페이지와 같은 검색어를 두고 경쟁한다.

---

## 2. 사이트 쪽에서 이미 처리한 것 (중복 작업 금지)

게임 저장소에서 다시 할 필요가 없는 것들이다.

- 게임 소개, 특징, 조작법, FAQ, 스크린샷 페이지
- **모바일 안내** — 마우스·키보드가 필요한 게임이라 모바일에서는 실행 버튼 대신
  「PC 전용」 안내를 띄운다. 눌러도 안 되는 버튼을 보여주지 않는다
- 「전체 화면」 버튼과 「새 창에서 열기」 링크 (페이지 쪽 UI)
- 클릭하기 전에는 iframe 을 만들지 않는 지연 로딩
- 투자 권유가 아니라는 고지 (명세서 §0 원칙 9·10 반영)
- 스크린샷은 `docs/screenshots/` 의 320×180 원본을 **nearest 4배 확대**해서 썼다.
  정수 배율이라 픽셀이 뭉개지지 않는다. 새 스크린샷을 추가하면 사이트에도
  반영할 수 있다

---

## 3. 해야 할 일

우선순위 순. 각 항목에 근거가 되는 파일과 줄 번호를 적었다.

### P1 — 전부 처리됨 (2026-08-03)

실측 결과는 `tests/web_check.sh` 로 재현할 수 있다. 아래 표의 "확인 방법"이
그 스크립트가 실제로 하는 일이다.

| | 항목 | 결과 |
|---|---|---|
| P1-1 | `export_presets.cfg` 저장소 포함 | ✅ `.gitignore` 에서 제외를 풀고 커밋했다 |
| P1-2 | 웹 F 키 충돌 | ✅ 브라우저 예약 키를 바인딩하지 않는다 |
| P1-3 | 웹에서 「종료」 숨기기 | ✅ 숨겼고, 메뉴 분기를 인덱스 → id 로 바꿨다 |
| P1-4 | 웹에서 소리가 나는가 | ✅ **난다.** 다만 첫 조작 전까지는 안 난다 (아래) |
| P1-5 | 세이브가 실제로 남는가 | ✅ **남는다.** 탭을 닫았다 다시 열어도 이어하기가 활성화된다 |

#### P1-1. `export_presets.cfg` — 완료

`.gitignore` 에서 제외를 풀고 프리셋을 커밋했다. 이제 클론만 하면 웹 빌드를
그대로 재현할 수 있다. 안드로이드 keystore 처럼 비밀값이 들어가는 프리셋을
추가할 때 다시 분리하라는 주석을 `.gitignore` 에 남겨 뒀다.

#### P1-2. 웹 F 키 충돌 — 완료

**액션은 등록하고 키만 비운다.** `scripts/core/Main.gd` 의 `_add_action` 이
웹에서 `BROWSER_RESERVED_KEYS`(F1·F2·F3·F5·F9·F11)를 걸러 낸다.

액션 자체를 등록하지 않는 방법도 있었지만 그러면 `is_action_pressed("game_quicksave")`
호출부가 매 프레임 오류를 낸다. 키만 비우면 호출부는 그대로 두고 안전해진다 —
액션은 존재하되 영원히 걸리지 않는다.

> **원래 문서가 남긴 질문 — "실제로 가로채지는가" 에 대한 답:**
> 이제 확인할 필요가 없어졌다. 게임이 그 키를 아예 받지 않는다.
> 검사는 F5 = 빠른 저장이라는 점을 이용한다. 캔버스에 F5 를 넣고
> IndexedDB 에 `manual_00.json` 이 생기지 않으면 게임이 키를 안 받은 것이다.
> **실측: 생기지 않았다.**

대체 경로는 ESC 일시정지 메뉴다. 웹에서는 이것이 유일한 저장 경로이므로,
오프닝에서 한 번 알려 준다 — `dlg.open.tutorial.web` "저장과 불러오기는 ESC 메뉴에 있습니다."
이 줄은 웹에서만 나온다.

#### P1-3. 웹에서 「종료」 숨기기 — 완료

타이틀 메뉴가 웹에서 4줄(새 게임 · 이어하기 · 불러오기 · 설정)이 된다.

문서가 지적한 인덱스 문제도 같이 고쳤다. **타이틀과 일시정지 메뉴가 이제
인덱스가 아니라 id 로 분기한다** (`Main._row_id`). 행을 넣고 빼도 분기가 밀리지 않는다.

캡처로 확인하다가 딸려 나온 문제 하나 — 일시정지 메뉴 상자가 100px 이라
마지막 행 「타이틀로」와 하단 안내문 「ESC 로 돌아갑니다」가 맞닿아 글자가
겹쳐 보였다. 상자를 110px 로 넓혔다. 웹과 무관한 기존 버그다.

#### P1-4. 웹 오디오 — 확인함, 그리고 고침

**실측 (헤드리스 Chrome + `--autoplay-policy=document-user-activation-required`):**

| 시점 | AudioContext | 파형 |
|---|---|---|
| 페이지 로드 직후 | `suspended` | 없음 |
| 캔버스 클릭 후 | `running` | 최대 진폭 13/128 |

우려가 근거 있었다는 뜻이다 — **캔버스 안에서 조작이 일어나기 전까지 소리가 나지 않는다.**
사이트의 「게임 시작」 버튼은 iframe 바깥이라 이 조작에 해당하지 않는다.

`AudioContext.state` 가 `running` 인 것과 실제로 소리가 나는 것은 다르므로,
검사는 destination 으로 가는 연결에 아날라이저를 물려 **파형을 직접 잰다.**

고친 것: `AudioDirector.wake()` 를 두고 캔버스 안 첫 입력에 곡을 **처음부터 다시** 튼다.
안 그러면 정지 상태 동안 재생 위치만 흘러가서, 조작을 시작하면 곡 중간부터
들리거나 아예 안 들린다. 데스크톱에서는 아무 일도 하지 않는다.

#### P1-5. 세이브 영속성 — 확인함

**실측:** 새 프로필로 열어 새 게임 → 자동 저장 → **탭을 완전히 닫음** →
다시 열기. IndexedDB 에 파일이 그대로 있었다.

```
/userfs/godot/app_userdata/떡락섬의 비밀/saves/auto_0.json
/userfs/godot/app_userdata/떡락섬의 비밀/saves/auto_1.json
/userfs/godot/app_userdata/떡락섬의 비밀/saves/auto_1.png
```

타이틀 화면의 「이어하기」 글자색도 같이 확인했다.

| | 「이어하기」 글자 평균 밝기 | 팔레트 |
|---|---|---|
| 새 프로필 (세이브 없음) | 139.3 | `text_dim` `#8a8296` = 139.3 |
| 탭 닫았다 다시 염 | 205.3 | `text` `#d8d0c0` = 205.3 |

정확히 일치한다. 비활성 → 활성으로 바뀌었다. **`SaveManager` 에 추가로 손댈 것은 없다.**

### 재현 방법

```bash
tests/web_check.sh
```

익스포트 → 로컬 서버 → 헤드리스 Chrome → **11건** 검사까지 한 번에 한다.
데스크톱 검증(`tests/SmokeTest.tscn`)으로는 잡히지 않는 것만 본다.
`--autoplay-policy` 를 강제해서 띄우므로 헤드리스가 소리를 그냥 틀어 버리지 않는다.

이것으로 **P2-4(웹 빌드 자동 점검)도 함께 처리됐다.**

뷰포트는 **정확히 16:9 로 고정**한다. 캔버스 비율이 게임 비율과 다르면 게임이
캔버스 안에서 다시 레터박스되어, 좌표가 화면 가운데는 맞고 가장자리는 빗나간다.
이 오차 때문에 처음에 P2-1·P2-2 를 잘못 실패로 읽었다.

### P2 — 전부 처리됨 (2026-08-03)

| | 항목 | 결과 |
|---|---|---|
| P2-1 | 터치 지원 여부 결정 | ✅ **지원한다.** 길게 누르기 = 우클릭, 타겟 확대, 간소화 UI 기본값 |
| P2-2 | 전체 화면을 게임 안에서 | ✅ 설정 메뉴에서 켜진다. 다음 pointerup 에 얹는 방식 |
| P2-3 | 빌드 크기 | ✅ 측정함. **문서의 가정이 틀렸다** — 아래 |
| P2-4 | 웹 빌드 자동 점검 | ✅ `tests/web_check.sh` (P1 절 참고) |

#### P2-1. 터치 지원 — 넣기로 했다

모바일 유입이 크다는 판단은 문서 그대로다. 세 가지로 메웠다.

| 없는 것 | 대신 |
|---|---|
| 우클릭(기본 동작) | **길게 누르기 0.45초.** 5px 이상 미끄러지면 끌기로 보고 취소 |
| 마우스오버 | 탭하면 문장 라인이 갱신된다. 커서(십자)는 끄고 OS 커서를 보인다 |
| 정확한 조준 | 핫스폿 판정에 4px 여유(320×180 기준). 넓이 비교는 원래 크기로 하므로 "겹치면 작은 쪽이 이긴다" 규칙은 그대로 |
| 작은 버튼 | 동사 UI 를 §5.2 간소화(4개)로 시작 — 버튼 폭이 두 배가 된다 |

터치에서는 **누른 순간이 아니라 뗀 순간에 행동한다.** 누르고 있는 동안
길게 누르기로 갈아탈 여지를 남겨야 하기 때문이다.

오프닝에 터치 전용 안내 한 줄이 나온다 — "길게 누르면 그 대상에게 알맞은 동작을 합니다."
`Conditions` 에 넣은 `feature: "touch"` 로 분기하며, 세이브에 남지 않는다.

**실측** (헤드리스 Chrome, 터치 에뮬레이션, 720×405 mobile):
회의실에서 복도 문을 0.9초 길게 눌러 `office_meeting_room → office_corridor` 이동 확인.
동사 패널이 4개(조사·대화·사용·이동)로 나오는 것도 캡처로 확인.

##### 여기서 드러난 진짜 버그

터치 기본값이 처음에는 적용되지 않았다. 원인은 터치 감지가 아니라 **설정 저장**이었다.
`_load_settings()` 가 `settings` 에 기본값을 전부 채워 넣어서,
`settings.has("verb_ui")` 로는 "사용자가 고른 값" 과 "기본값" 을 구분할 수 없었다.

고친 방식 —
- `SaveManager.is_user_set(key)` 로 사용자가 실제로 고른 키만 판별한다
- `_save_settings()` 는 **사용자가 고른 값과 내부 카운터만** 적는다.
  전부 적으면 한 번 저장한 뒤로 모든 키가 "사용자 값" 이 되고, 나중에 기본값을
  바꿔도 기존 플레이어에게 반영되지 않는다
- 기기 때문에 달라지는 값은 `set_device_default()` 로 넣고 **파일에 적지 않는다**.
  적으면 그 프로필을 데스크톱에서 열었을 때까지 따라온다

> 참고로 `DisplayServer.is_touchscreen_available()` 은 웹 빌드에서도 제대로 답한다.
> 원래 문서에는 없던 얘기지만, 의심하다 확인했으므로 적어 둔다.

##### 남는 한계 — 세로 화면

이건 게임 저장소에서 풀 수 없다. 세로 폰에서 `index.html` 을 통째로 열면
16:9 게임이 캔버스 안에서 레터박스되어 화면의 3분의 1만 쓴다.
**사이트가 16:9 컨테이너로 감싸므로 실제 배포 환경에서는 문제가 없다.**
다만 컨테이너 폭이 390px 이면 게임은 390×219 로, 명령 패널이 25 CSS px 다.
문서 P2-1 이 언급한 `three-kingdoms` 방식 — 크기를 보장해야 하는 버튼을
스테이지 밖에 실제 픽셀로 두는 것 — 은 여전히 사이트 쪽에서 할 일이다.

#### P2-2. 게임 안 전체 화면 — 켜진다

문서의 우려가 맞았다. `DisplayServer.window_set_mode(FULLSCREEN)` 은
웹에서 **조용히 무시된다.** 브라우저는 requestFullscreen 을 사용자 조작에서
비롯된 호출로만 허용하는데, Godot 의 입력 처리는 requestAnimationFrame 안에서
일어나 그 조건을 만족하지 못한다. (실측: 토글해도 `document.fullscreenElement` 가 null)

대신 **다음 pointerup 한 번에 얹는다** (`Main._apply_fullscreen_web`).
설정을 켠 그 클릭의 뗌 동작이 보통 여기 걸리므로 실제로는 즉시 전환된다 —
실측에서도 "토글과 같은 클릭에서 바로" 켜졌다.

⚠️ iframe 안에서는 부모가 `allow="fullscreen"` 을 줘야 성공한다. 사이트 쪽 몫이다.

#### P2-3. 빌드 크기 — 폰트가 아니라 엔진이다

문서는 폰트(5MB)를 후보로 지목했지만, **측정해 보니 전송량에서 폰트는 이미 작다.**

| | raw | gzip | brotli |
|---|---|---|---|
| `index.wasm` (엔진) | 37.68 MB | 9.68 MB | **6.77 MB** |
| `index.pck` (게임 전체) | 1.98 MB | 1.81 MB | 1.78 MB |
| `index.js` | 0.27 MB | 0.07 MB | 0.06 MB |

폰트 3종은 디스크에서 5.1MB 지만 **pck 전체가 1.98MB** 다 — Godot 이 압축해 담는다.
한글 11,172자를 지키는 판단(README 폰트 절)은 전송량 면에서 비용이 거의 없다.
**줄일 것이 있다면 엔진 wasm 이고, 그건 콘텐츠와 무관하다.**

할 수 있는 것 두 가지.

1. **brotli 로 서빙** — gzip 대비 wasm 이 30% 작아진다(9.68 → 6.77MB).
   호스팅 설정 한 번이면 되고 유지 비용이 없다. **가장 값싼 개선이다.**
2. 커스텀 템플릿을 소스에서 빌드해 안 쓰는 모듈을 뺀다. 절반까지 줄지만
   emscripten + scons 툴체인과 그 유지 부담이 생긴다. 지금 규모에서는 이르다.

저장소 이력에 40MB 가 쌓이는 문제는 그대로다. 자주 다시 빌드하게 되면
별도 호스팅으로 옮기는 편이 낫다 — 사이트는 `data/games.ts` 의 `playUrl`
한 줄만 바꾸면 된다.

## 4. 건드리면 안 되는 것

| 대상 | 이유 |
|---|---|
| `variant/thread_support=false` | true 로 바꾸면 SharedArrayBuffer 가 필요해지고, 사이트 전체에 COOP/COEP 헤더가 걸려 다른 게임까지 깨진다 |
| `html/head_include` 의 noindex·canonical | 지우면 게임 실행 페이지가 소개 페이지와 검색 경쟁을 한다 |
| 내부 해상도 320×180 | 사이트가 16:9 컨테이너로 감싸고 있다. 비율을 바꾸면 `jung-arcade` 의 `data/games.ts` 에서 `aspectRatio` 도 같이 고쳐야 한다 |

**사이트 도메인이 바뀌면** `html/head_include` 의 canonical 도 함께 고쳐야 한다.
사이트 쪽 환경변수만 바꾸는 것으로는 부족하다.

---

## 5. 다시 익스포트해서 사이트에 반영하는 법

```bash
# 1. 익스포트 (export_presets.cfg 가 있어야 한다 — P1-1)
cd /path/to/secret-of-falling-island
godot --headless --path . --export-release "Web" ../build/web/index.html

# 2. 사이트로 복사
cp ../build/web/* /path/to/jung-arcade/public/games/secret-of-falling-island/

# 3. 확인
cd /path/to/jung-arcade
pnpm build && pnpm start
# http://localhost:3000/games/secret-of-falling-island

# 4. 배포
railway up --service web
```

### 익스포트 템플릿이 없다면

공식 배포본은 전 플랫폼이 묶여 **1.2GB** 다. 웹 템플릿만 필요하면
`jung-arcade/scripts/fetch-godot-web-templates.py` 가 zip 범위 요청으로
**84MB** 만 받아 설치한다.

### 테스트할 때 주의

- 헤드리스 Chrome 에서 `--virtual-time-budget` 은 **wasm 컴파일을 기다려 주지
  않는다.** 로딩 화면만 찍히고 게임이 안 뜬 것처럼 보인다. CDP 로 붙어 실시간으로
  기다린 뒤 캡처해야 한다.
- 헤드리스 Chrome 은 macOS 에서 창 폭을 **최소 500px 로 강제**한다. 390px
  모바일 화면을 보려면 그 폭의 iframe 안에 페이지를 넣어 찍어야 한다.

---

## 6. 게임 내용 쪽에서 도움이 되는 것

사이트의 소개 페이지는 지금 프로토타입 범위(프롤로그 회의실 → 복도 → 탕비실)
기준으로 쓰여 있고, 상태는 **「개발 중」** 으로 표시된다.

다음이 갱신되면 사이트에도 반영할 수 있다.

- **Phase 2 수직 슬라이스**가 나오면 → 소개 문구, 플레이 분량, 스크린샷 교체
- **새 스크린샷** (`godot --path . tests/Screenshots.tscn`) → 사이트 카드·갤러리
- **개발 과정 기록** → 사이트에 개발 일지 페이지가 있다. 만들면서 고민한 것을
  글로 남기면 검색 유입에 도움이 된다. 현재 삼국지 게임 것만 올라가 있다
