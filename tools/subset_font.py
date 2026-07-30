#!/usr/bin/env python3
"""Galmuri 한글 픽셀 폰트를 게임에 필요한 글자만 남겨 줄인다.

    python3 tools/subset_font.py <원본_폰트_폴더>

원본(Galmuri9/11/14.ttf)은 각각 4~5MB 로, 셋을 합치면 15MB 다.
한글뿐 아니라 라틴 확장·키릴·그리스·가나·일부 한자까지 담고 있기 때문이다.

**한글은 11,172자를 전부 남긴다.** 여기서 줄이면 새 대사를 쓸 때마다
글자가 빠질 위험이 생기고, 그 위험은 절약되는 몇 MB 보다 비싸다.
대신 이 게임이 쓰지 않는 다른 문자 체계를 덜어내 3분의 1로 줄인다.
(15MB → 5MB)

남기는 것:
  - 한글 음절 11,172자 전체 + 한글 자모
  - ASCII, 일반 구두점, 게임에서 쓰는 기호(→ ✓ ⟪⟫ 등)
  - data/**/*.json 에 실제로 등장하는 모든 문자 (혹시 모를 누락 방지)

그래도 빠진 글자가 있으면 Theming 의 allow_system_fallback 이 OS 폰트로
대체하므로 두부(□)가 되지는 않는다. 그 글자만 도트 느낌이 사라진다.

의존성: pip install fonttools
"""

from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "fonts"
FACES = ["Galmuri9", "Galmuri11", "Galmuri14"]

# 한글 음절 11,172자를 조합 규칙(초성×중성×종성)으로 만든다.
# 코드포인트 목록을 하드코딩하지 않기 위한 방식이다.
CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
JONG = "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"

EXTRA = (
    " !\"#$%&'()*+,-./0123456789:;<=>?@"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
    "abcdefghijklmnopqrstuvwxyz{|}~"
    "→←↑↓●○◆■□▲▼✓✗△⟪⟫…·‥、。「」『』"
    "‘’“”—–₩％×÷±°"
    + CHO + JUNG + JONG
)


def hangul_syllables() -> set[str]:
    """한글 음절 11,172자 전체. 초성 19 × 중성 21 × 종성 28.
    줄이지 않는다 — 위 설명 참고."""
    out: set[str] = set()
    for ci, c in enumerate(CHO):
        for vi, v in enumerate(JUNG):
            # 종성 없음
            out.add(chr(0xAC00 + (ci * 21 + vi) * 28))
            for ti in range(1, 28):
                out.add(chr(0xAC00 + (ci * 21 + vi) * 28 + ti))
    return {s for s in out if unicodedata.category(s) == "Lo"}


def chars_in_game_text() -> set[str]:
    """실제 대사에 쓰인 문자는 무조건 포함한다."""
    out: set[str] = set()
    for p in (ROOT / "data").rglob("*.json"):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        stack = [data]
        while stack:
            v = stack.pop()
            if isinstance(v, str):
                out.update(v)
            elif isinstance(v, dict):
                stack.extend(v.values())
            elif isinstance(v, list):
                stack.extend(v)
    return out


def main() -> int:
    try:
        from fontTools import subset
    except ImportError:
        print("fonttools 가 필요합니다:  python3 -m pip install --user fonttools")
        return 1

    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src_dir = Path(sys.argv[1])

    keep = hangul_syllables() | set(EXTRA) | chars_in_game_text()
    print(f"남길 글자 수: {len(keep)}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for face in FACES:
        matches = list(src_dir.rglob(f"{face}.ttf"))
        if not matches:
            print(f"  ! {face}.ttf 를 찾지 못했습니다")
            continue
        src = matches[0]
        dst = OUT_DIR / f"{face}.ttf"

        opts = subset.Options()
        opts.desubroutinize = True
        opts.recalc_bounds = True
        opts.drop_tables += ["DSIG"]
        opts.layout_features = ["*"]        # 한글 조합 관련 기능 유지
        opts.name_IDs = ["*"]
        opts.notdef_outline = True

        font = subset.load_font(str(src), opts)
        subsetter = subset.Subsetter(options=opts)
        subsetter.populate(text="".join(sorted(keep)))
        subsetter.subset(font)
        subset.save_font(font, str(dst), opts)

        before = src.stat().st_size / 1024
        after = dst.stat().st_size / 1024
        print(f"  {face}.ttf  {before:>7.0f} KB → {after:>6.0f} KB  ({after / before * 100:.0f}%)")

    # 라이선스는 반드시 함께 배포해야 한다 (OFL 1.1)
    lic = list(src_dir.rglob("LICENSE.txt"))
    if lic:
        (OUT_DIR / "Galmuri-LICENSE.txt").write_text(
            lic[0].read_text(encoding="utf-8"), encoding="utf-8")
        print("  Galmuri-LICENSE.txt 복사 (OFL 1.1 — 재배포 시 필수)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
