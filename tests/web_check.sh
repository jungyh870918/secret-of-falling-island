#!/usr/bin/env bash
#
# 웹 빌드를 익스포트하고 실제 브라우저에서 검사한다.
# docs/WEB_BUILD_HANDOFF.md 의 P1-2 / P1-3 / P1-4 / P1-5 를 자동으로 확인한다.
#
#   tests/web_check.sh
#
# 필요한 것
#   - Godot 4 (웹 익스포트 템플릿 설치됨)
#   - Google Chrome
#   - Node 22+ (내장 WebSocket 을 쓴다)
#   - python3 (로컬 정적 서버)
#
# 데스크톱 검증은 tests/SmokeTest.tscn 이 한다. 이 스크립트는 브라우저에서만
# 드러나는 것 — autoplay 정책, IndexedDB 세이브, 브라우저 예약 키 — 만 본다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/../build/web}"
OUT="${OUT_DIR:-$(mktemp -d)}"
PORT="${PORT:-8917}"
CDP_PORT="${CDP_PORT:-9222}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
GODOT="${GODOT:-godot}"

[[ -x "$CHROME" ]] || { echo "Chrome 을 찾을 수 없습니다. CHROME 으로 경로를 지정하세요." >&2; exit 1; }

mkdir -p "$OUT"
PROFILE="$(mktemp -d)"      # 매번 새 프로필 — 이전 세이브가 남아 있으면 P1-5 검사가 무의미하다
cleanup() {
	[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
	[[ -n "${CHROME_PID:-}" ]] && kill "$CHROME_PID" 2>/dev/null || true
	# Chrome 이 프로필에 쓰기를 끝낸 뒤에 지운다. 바로 지우면 "Directory not empty" 가 난다.
	sleep 1
	rm -rf "$PROFILE" 2>/dev/null || true
}
trap cleanup EXIT

echo "[1/3] 웹 익스포트"
mkdir -p "$BUILD"
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$BUILD/index.html" >/dev/null
ls -la "$BUILD/index.wasm" | awk '{printf "      wasm %.1f MB\n", $5/1048576}'

echo "[2/3] 로컬 서버(:$PORT)와 헤드리스 Chrome 기동"
python3 -m http.server "$PORT" --directory "$BUILD" >/dev/null 2>&1 &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null || true   # 종료할 때 "Terminated" 잡 메시지를 남기지 않는다

# --autoplay-policy 를 강제해야 실제 브라우저의 "조작 전 무음" 정책이 재현된다.
# 이걸 빼면 헤드리스가 소리를 그냥 틀어 버려서 P1-4 검사가 의미를 잃는다.
"$CHROME" --headless=new \
	--remote-debugging-port="$CDP_PORT" \
	--user-data-dir="$PROFILE" \
	--autoplay-policy=document-user-activation-required \
	--enable-unsafe-swiftshader \
	--no-first-run --no-default-browser-check \
	--window-size=1280,720 about:blank >/dev/null 2>&1 &
CHROME_PID=$!
disown "$CHROME_PID" 2>/dev/null || true
sleep 4

echo "[3/3] 검사"
CDP_PORT="$CDP_PORT" node "$ROOT/tests/web_check.mjs" "http://127.0.0.1:$PORT/index.html" "$OUT"
status=$?
echo "캡처: $OUT"
exit $status
