#!/usr/bin/env python3
"""프로젝트 구조 점검. Godot 없이 돌아간다.

    python3 tests/check_project.py

  1. project.godot 의 autoload / main_scene 경로가 실재하는가
  2. class_name 이 중복되지 않는가 (Godot 은 전역 등록이라 충돌하면 열리지 않는다)
  3. autoload 스크립트에 class_name 이 붙어 있지 않은가 (이름 충돌 원인)
  4. .tscn 의 ext_resource 경로가 실재하는가
  5. preload()/load() 안의 res:// 경로가 실재하는가
  6. 들여쓰기가 탭으로 통일돼 있는가 (GDScript 는 혼용 시 파싱 오류)
  7. GDScript 파일마다 첫 줄이 class_name 또는 extends 인가
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors: list[str] = []


def err(m: str) -> None:
    errors.append(m)


def res(p: str) -> Path:
    return ROOT / p.replace("res://", "")


# ---------------------------------------------------------------- project.godot

pg = (ROOT / "project.godot").read_text(encoding="utf-8")

main_scene = re.search(r'run/main_scene="([^"]+)"', pg)
if not main_scene:
    err("project.godot 에 run/main_scene 이 없다")
elif not res(main_scene.group(1)).exists():
    err(f"main_scene 파일 없음: {main_scene.group(1)}")

autoload_block = re.search(r"\[autoload\](.*?)(\n\[|\Z)", pg, re.S)
autoloads: dict[str, str] = {}
if autoload_block:
    for name, path in re.findall(r'^(\w+)="\*?(res://[^"]+)"', autoload_block.group(1), re.M):
        autoloads[name] = path
        if not res(path).exists():
            err(f"autoload '{name}' 스크립트 없음: {path}")
if not autoloads:
    err("autoload 가 하나도 등록되지 않았다")


# ---------------------------------------------------------------- GDScript

gd_files = sorted((ROOT / "scripts").rglob("*.gd"))
class_names: dict[str, Path] = {}

for gd in gd_files:
    rel = gd.relative_to(ROOT)
    text = gd.read_text(encoding="utf-8")
    lines = text.split("\n")

    code = [l for l in lines if l.strip() and not l.strip().startswith("#")]
    if not code:
        err(f"{rel}: 빈 스크립트")
        continue
    first = code[0].strip()
    if not (first.startswith("class_name ") or first.startswith("extends ")):
        err(f"{rel}: 첫 줄이 class_name/extends 가 아니다 → '{first[:40]}'")

    m = re.match(r"class_name\s+(\w+)", text, re.M)
    cn = re.search(r"^class_name\s+(\w+)", text, re.M)
    if cn:
        name = cn.group(1)
        if name in class_names:
            err(f"class_name 중복: {name} ({rel} vs {class_names[name]})")
        class_names[name] = rel
        if name in autoloads:
            err(f"{rel}: autoload 이름 '{name}' 과 class_name 이 충돌한다")

    # autoload 스크립트에는 class_name 이 없어야 한다
    if str(rel).replace("\\", "/") in {a.replace("res://", "") for a in autoloads.values()}:
        if cn:
            err(f"{rel}: autoload 스크립트에 class_name 이 있다 ({cn.group(1)})")

    # 들여쓰기 혼용
    for i, line in enumerate(lines, 1):
        stripped = line.lstrip("\t")
        if stripped.startswith(" ") and stripped.strip() and not stripped.lstrip().startswith("#"):
            # 탭 뒤 정렬용 공백은 허용하되, 줄 맨 앞의 스페이스 들여쓰기는 오류
            if line.startswith(" "):
                err(f"{rel}:{i}: 스페이스로 들여쓰기했다 (GDScript 는 탭)")

    # preload / load 경로
    for m2 in re.finditer(r'(?:preload|load)\(\s*"(res://[^"]+)"', text):
        if not res(m2.group(1)).exists():
            err(f"{rel}: 없는 리소스를 preload/load 한다 → {m2.group(1)}")


# ---------------------------------------------------------------- tscn

for tscn in sorted((ROOT / "scenes").rglob("*.tscn")):
    text = tscn.read_text(encoding="utf-8")
    for path in re.findall(r'ext_resource[^\n]*path="(res://[^"]+)"', text):
        if not res(path).exists():
            err(f"{tscn.relative_to(ROOT)}: ext_resource 경로 없음 → {path}")


# ---------------------------------------------------------------- 결과

print(f"GDScript {len(gd_files)}개 · class_name {len(class_names)}개 · autoload {len(autoloads)}개")
for e in errors:
    print("✗ " + e)

if errors:
    print(f"\n실패: {len(errors)}건")
    sys.exit(1)
print("\n통과")
