#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""아트 에셋 규격 확인 — 기획서 §23 R7.

**그림의 좋고 나쁨은 판정하지 않는다.** 화풍·톤·분위기는 사람이 눈으로 본다.
이 도구는 «눈으로 보면 놓치는 객관적인 것»만 본다 — 크기, 알파, 가장자리 잔여물.

    python3 tests/check_assets.py                 # assets/ 아래 PNG 전부
    python3 tests/check_assets.py docs/art/received
    python3 tests/check_assets.py --tone          # 톤 수치도 같이 (참고용, 판정 아님)

쓰고 싶을 때만 쓰면 되는 도구다. 이걸 통과해야 그림을 쓸 수 있는 것이 아니다.

의존성이 없다 — 다른 검증기와 같은 규약이다. PNG 는 zlib 로 직접 푼다.
(PIL 을 쓰지 않는 이유: tests/check_project.py · validate_data.py 가 의존성 없이 도는데
 여기만 설치를 요구하면 «검증을 돌릴 수 없는 환경»이 생긴다)

한때 톤 거리로 합격선을 두고 그림을 «불합격» 시켰다. 그 공정은 걷어냈다 —
좋은 그림이 숫자 때문에 버려진다. 톤 수치는 `--tone` 으로 볼 수 있지만
그것으로 무엇을 버릴지 정하지 않는다.
"""
from __future__ import annotations

import math
import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ANCHOR_DIR = ROOT / "docs" / "mockups"

# 톤 앵커에서 빼는 목업.
#
# 04_notebook 은 풀스크린 UI 오버레이라 «월드 그림»이 거의 없다. 그림을 판정하는
# 기준으로 쓰면 두 가지가 어긋난다 — 합격선이 부풀고(0.147 → 0.279), 어두운 그림이
# «UI 화면과 닮았다»는 이유로 통과한다. 실제로 지하철 배경이 그렇게 통과할 뻔했다.
# UI 작업의 참고 자료로는 그대로 쓰되, 톤 앵커에서는 뺀다.
NON_ANCHOR = {"04_notebook"}

# 기준 캔버스가 정해지면 여기에 규격을 넣는다 (§23 «사람이 결정해야 하는 것»)
SPEC: dict[str, dict] = {
    # "assets/backgrounds/*.png": {"size": (1080, 1500)},
}

# 합격선은 상수가 아니라 «앵커끼리 떨어진 최대 거리»에서 나온다 (main 참고)


# ── PNG 디코드 (8비트, 비인터레이스) ──────────────────────────────────

def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path: pathlib.Path):
    """→ (width, height, [(r,g,b,a), ...])  실패하면 ValueError."""
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("PNG 가 아니다")
    pos, idat, pal, trns = 8, bytearray(), None, None
    w = h = depth = ctype = interlace = 0
    while pos < len(raw):
        (ln,) = struct.unpack(">I", raw[pos:pos + 4])
        typ = raw[pos + 4:pos + 8]
        body = raw[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif typ == b"PLTE":
            pal = body
        elif typ == b"tRNS":
            trns = body
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        pos += 12 + ln
    if depth != 8:
        raise ValueError(f"비트 심도 {depth} 는 지원하지 않는다 (8비트만)")
    if interlace:
        raise ValueError("인터레이스 PNG 는 지원하지 않는다")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if channels is None:
        raise ValueError(f"알 수 없는 컬러 타입 {ctype}")

    data = zlib.decompress(bytes(idat))
    stride = w * channels
    out, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        f = data[p]
        line = bytearray(data[p + 1:p + 1 + stride])
        p += 1 + stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                c = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 0xFF
        elif f != 0:
            raise ValueError(f"알 수 없는 필터 {f}")
        prev = line
        out.append(bytes(line))

    px = []
    for line in out:
        for x in range(w):
            o = x * channels
            if ctype == 6:
                px.append((line[o], line[o + 1], line[o + 2], line[o + 3]))
            elif ctype == 2:
                px.append((line[o], line[o + 1], line[o + 2], 255))
            elif ctype == 0:
                g = line[o]
                px.append((g, g, g, 255))
            elif ctype == 4:
                g = line[o]
                px.append((g, g, g, line[o + 1]))
            else:  # palette
                i = line[o]
                px.append((pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2],
                           trns[i] if trns and i < len(trns) else 255))
    return w, h, px


# ── 측정 ─────────────────────────────────────────────────────────────

def _rgb_to_hsv(r: int, g: int, b: int):
    r, g, b = r / 255, g / 255, b / 255
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        hh = 0.0
    elif mx == r:
        hh = ((g - b) / d % 6) / 6
    elif mx == g:
        hh = ((b - r) / d + 2) / 6
    else:
        hh = ((r - g) / d + 4) / 6
    return hh, (0.0 if mx == 0 else d / mx), mx


def _run_gcd(vals) -> int:
    if len(vals) < 2:
        return 0
    runs, cur = [], 1
    for i in range(1, len(vals)):
        if vals[i] == vals[i - 1]:
            cur += 1
        else:
            runs.append(cur)
            cur = 1
    runs.append(cur)
    if len(runs) > 2:
        runs = runs[1:-1]          # 양 끝은 잘린 구간일 수 있다
    g = 0
    for r in runs:
        g = math.gcd(g, r)
    return g


HUE_BINS = 12


def measure(path: pathlib.Path) -> dict:
    w, h, px = read_png(path)
    opaque = [p for p in px if p[3] > 8]
    semi = sum(1 for p in px if p[3] not in (0, 255))
    colors = {p[:3] for p in opaque}

    # 톤 — 불투명 픽셀의 평균 채도·명도 + 색상 «분포»
    #
    # 색상을 원형 평균(벡터)으로 재면 여러 색이 섞인 그림에서 서로 상쇄되어
    # 0 에 가까워진다. 파란 하늘 + 녹슨 철 + 붉은 간판이 있는 그림과
    # 무채색 그림이 같은 값을 낸다. 그래서 «분포»(히스토그램)로 잰다.
    hist = [0.0] * HUE_BINS
    ss = sv = 0.0
    for r, g, b, _ in opaque:
        hh, s_, v_ = _rgb_to_hsv(r, g, b)
        # 채도·명도로 가중 — 어둡거나 회색인 픽셀이 색상을 좌우하지 않게
        hist[min(HUE_BINS - 1, int(hh * HUE_BINS))] += s_ * v_
        ss += s_
        sv += v_
    tot = sum(hist) or 1.0
    hist = [v / tot for v in hist]
    n = max(1, len(opaque))

    # 업스케일 배수 — 여러 줄에서 재고 최빈값
    from collections import Counter
    gx = Counter()
    for y in range(0, h, max(1, h // 24)):
        g = _run_gcd([px[y * w + x] for x in range(w)])
        if g:
            gx[g] += 1

    # 가장자리에 남은 배경색 (부품일 때만 의미 있다)
    edge = []
    if h and w:
        edge = [px[x] for x in range(w)] + [px[(h - 1) * w + x] for x in range(w)]
    edge_opaque = sum(1 for p in edge if p[3] > 8) / max(1, len(edge))

    return {
        "size": (w, h),
        "ratio": w / h if h else 0,
        "colors": len(colors),
        "semi": semi,
        "upscale": gx.most_common(1)[0][0] if gx else 0,
        "hue_hist": hist,
        "sat": ss / n,
        "val": sv / n,
        "edge_opaque": edge_opaque,
        "transparent": len(px) - len(opaque),
        "px_total": len(px),
    }


def tone_distance(a: dict, b: dict) -> float:
    """두 그림의 톤 거리. 0 이면 같고 1 이면 완전히 다르다.

    색상은 히스토그램 교집합으로 잰다 — 겹치는 만큼이 닮은 정도다.
    """
    overlap = sum(min(x, y) for x, y in zip(a["hue_hist"], b["hue_hist"]))
    dh = 1.0 - overlap
    ds = abs(a["sat"] - b["sat"])
    dv = abs(a["val"] - b["val"])
    return dh * 0.5 + ds * 0.25 + dv * 0.25


def nearest_anchor(m: dict, anchors: list) -> tuple:
    """가장 가까운 앵커와 그 거리.

    앵커 4장은 서로 다른 «종류»의 장면이다(실측: 서로 최대 0.279 떨어져 있다).
    그 평균은 어느 장면도 아닌 유령 값이라, 평균과 비교하면
    앵커 자신도 통과하지 못하는 기준이 된다. 그래서 «가장 가까운 앵커»와 잰다.
    """
    best = min(anchors, key=lambda t: tone_distance(m, t[1]))
    return best[0], tone_distance(m, best[1])


# ── 실행 ─────────────────────────────────────────────────────────────

def collect(target: pathlib.Path) -> list[pathlib.Path]:
    if target.is_file():
        return [target]
    return sorted(p for p in target.rglob("*.png") if not p.name.startswith("."))


def main(argv: list[str]) -> int:
    show_tone = "--tone" in argv
    args = [a for a in argv if not a.startswith("--")]
    target = ROOT / (args[0] if args else "assets")

    files = collect(target)
    rel_t = target.relative_to(ROOT) if target.is_relative_to(ROOT) else target
    print(f"검사 대상 {len(files)}장 — {rel_t}")
    if not files:
        print("  그림이 아직 없다. 자리표시자 폴백이 있으므로 이 상태에서도 게임은 돈다.")
        return 0

    anchors = []
    if show_tone:
        anchors = [(p_, measure(p_)) for p_ in collect(ANCHOR_DIR) if p_.stem not in NON_ANCHOR]

    problems = []
    print()
    head = f"{'파일':<30}{'크기':>12}{'고유색':>9}{'반투명':>8}"
    if show_tone:
        head += f"{'톤(참고)':>10}"
    print(head + "   확인")
    for p_ in files:
        rel = p_.relative_to(ROOT) if p_.is_relative_to(ROOT) else p_
        try:
            m = measure(p_)
        except ValueError as e:
            problems.append(f"{rel}: {e}")
            print(f"{p_.name[:30]:<30}{'읽기 실패':>12}")
            continue

        notes = []
        # 부품인데 가장자리가 불투명하면 배경이 남은 것이다 — 객관적으로 잘못된 것
        if m["transparent"] > 0 and m["edge_opaque"] > 0.9:
            notes.append("부품인데 가장자리가 불투명 — 배경이 남았나?")
            problems.append(f"{rel}: 가장자리 배경 잔여 의심")
        for pat, spec in SPEC.items():
            if rel.match(pat) and "size" in spec and m["size"] != tuple(spec["size"]):
                notes.append(f"크기 {m['size']} ≠ 규격 {tuple(spec['size'])}")
                problems.append(f"{rel}: 크기 불일치")

        row = (f"{p_.name[:30]:<30}{m['size'][0]:>5}×{m['size'][1]:<6}"
               f"{m['colors']:>9}{m['semi']:>8}")
        if show_tone:
            near, d = nearest_anchor(m, anchors) if anchors else (None, 0.0)
            row += f"{d:>10.3f}"
        print(row + "   " + (" · ".join(notes) or "—"))

    print()
    for x in problems:
        print(f"  확인 필요  {x}")
    print(f"\n확인 필요 {len(problems)}건")
    if show_tone:
        print("※ 톤 수치는 참고용이다. 이 숫자로 그림을 버리지 않는다 — 판정은 눈으로 한다.")
    if not SPEC:
        print("※ 기준 캔버스가 미정이라 크기 검사는 아직 비어 있다 (§23).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
