#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""톤 보정 — 기획서 §23 R6.

받은 그림의 «채도»를 앵커에 맞춘다. 색상(hue)과 구도는 건드리지 않는다.

    python3 tools/tone_match.py docs/art/received/05_subway_night.png
    python3 tools/tone_match.py <파일> --target 0.427 --out <저장경로>

명도(밝기)는 기본적으로 건드리지 않는다 — 밤 장면이 어두운 것은 «어긋남»이 아니라
그 장면의 성격이다. 채도만 맞춰도 톤 거리의 대부분이 잡힌다.

이 도구는 «작은 어긋남»을 위한 것이다. 크게 벗어난 그림은 보정하지 말고 다시 뽑아라 —
보정은 없던 색을 만들어 내지 못한다.

tests/check_assets.py 와 달리 PIL 을 쓴다 (tools/ 는 의존성을 허용한다).
"""
import argparse
import colorsys
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "tests"))
import check_assets as ca  # noqa: E402

try:
    from PIL import Image
except ImportError:
    sys.exit("PIL 이 필요하다:  python3 -m pip install --user pillow")

ROOT = pathlib.Path(__file__).resolve().parent.parent


def mean_sat(im: Image.Image, step: int = 4) -> float:
    px = im.load()
    w, h = im.size
    tot = n = 0.0
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b = px[x, y][:3]
            mx, mn = max(r, g, b), min(r, g, b)
            tot += 0.0 if mx == 0 else (mx - mn) / mx
            n += 1
    return tot / max(1.0, n)


def apply_sat(im: Image.Image, factor: float) -> Image.Image:
    out = im.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            r, g, b = p[0] / 255, p[1] / 255, p[2] / 255
            hh, s, v = colorsys.rgb_to_hsv(r, g, b)
            s = min(1.0, s * factor)
            r, g, b = colorsys.hsv_to_rgb(hh, s, v)
            px[x, y] = (round(r * 255), round(g * 255), round(b * 255)) + tuple(p[3:])
    return out


def solve_factor(im: Image.Image, target: float) -> float:
    """평균 채도가 target 이 되는 배율을 이분 탐색으로 찾는다 (클리핑 때문에 선형이 아니다)."""
    lo, hi = 1.0, 6.0
    if mean_sat(im) >= target:
        lo, hi = 0.2, 1.0
    for _ in range(12):
        mid = (lo + hi) / 2
        if mean_sat(apply_sat(im.resize((im.width // 4, im.height // 4))), mid) < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--target", type=float, default=None, help="목표 평균 채도 (기본: 가장 가까운 앵커)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    src = pathlib.Path(a.file)
    m = ca.measure(src)

    anchors = [(p, ca.measure(p)) for p in ca.collect(ca.ANCHOR_DIR)
               if p.stem not in ca.NON_ANCHOR]
    near, dist = ca.nearest_anchor(m, anchors)
    target = a.target if a.target is not None else dict(anchors)[near]["sat"]

    print(f"{src.name}")
    print(f"  현재  채도 {m['sat']:.3f} · 명도 {m['val']:.3f} · 톤 거리 {dist:.3f} ({near.stem})")
    print(f"  목표  채도 {target:.3f}  ← {near.stem}")

    im = Image.open(src).convert("RGBA")
    f = solve_factor(im, target)
    print(f"  채도 배율 ×{f:.2f} 적용 중… (명도는 건드리지 않는다)")
    out_im = apply_sat(im, f)

    out = pathlib.Path(a.out) if a.out else src.with_name(src.stem + "_toned.png")
    out_im.save(out)

    m2 = ca.measure(out)
    _, dist2 = ca.nearest_anchor(m2, anchors)
    print(f"  결과  채도 {m2['sat']:.3f} · 명도 {m2['val']:.3f} · 톤 거리 {dist2:.3f}")
    print(f"  → {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}")
    if dist2 >= dist:
        print("  ※ 보정해도 가까워지지 않았다. 채도 말고 다른 것이 어긋난 것이다 — 다시 뽑아라")
    return 0


if __name__ == "__main__":
    sys.exit(main())
