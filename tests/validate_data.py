#!/usr/bin/env python3
"""데이터 무결성 검사기.

명세서 §19 QA 체크리스트 중 자동으로 확인할 수 있는 항목을 검사한다.
Godot 없이 돌아가므로 커밋 전/CI 에서 그대로 쓸 수 있다.

    python3 tests/validate_data.py

검사 항목
  1. 모든 JSON 파일이 파싱되는가
  2. 데이터가 참조하는 로컬라이징 키가 전부 ko.json 에 있는가        (§19.2)
  3. GDScript 안의 Loc.t("...") 키가 전부 존재하는가
  4. 상호작용 룰의 target 이 실제 핫스폿/출구/아이템인가
  5. 룰의 item, give, take 가 실제 아이템인가
  6. 대화의 next 가 존재하는 노드인가 (막다른 분기 = 진행 불가)      (§19.1)
  7. result 의 dialogue / goto / puzzle 상태가 실재하는가
  8. 출구의 entry 가 대상 장면의 spawn_points 에 있는가
  9. 핫스폿/출구/장면/아이템에 name_key 가 있는가
 10. 퍼즐의 모든 상태에 힌트가 2단계 이상 있는가                     (§19.1)
 11. 필수 아이템을 되돌릴 수 없이 잃는 경로가 있는가 (take 후 give 확인)
 12. 쓰이지 않는 로컬라이징 키 (경고)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def res_path(p: str) -> Path:
    return ROOT / p.replace("res://", "")


def load(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        err(f"파일 없음: {path.relative_to(ROOT)}")
    except json.JSONDecodeError as e:
        err(f"JSON 파싱 실패: {path.relative_to(ROOT)}:{e.lineno} {e.msg}")
    return {}


def entries(doc: dict, id_field: str) -> dict:
    out = {}
    for e in doc.get("entries", []):
        if isinstance(e, dict) and id_field in e:
            out[e[id_field]] = e
    return out


# ---------------------------------------------------------------- 로드

manifest = load(DATA / "manifest.json")

strings: dict = {}
for p in manifest.get("localization", []):
    strings.update({k: v for k, v in load(res_path(p)).items() if not k.startswith("_")})

items = {}
for p in manifest.get("items", []):
    items.update(entries(load(res_path(p)), "item_id"))

characters = {}
for p in manifest.get("characters", []):
    characters.update(entries(load(res_path(p)), "character_id"))

scenes = {}
for p in manifest.get("scenes", []):
    doc = load(res_path(p))
    if doc.get("scene_id"):
        scenes[doc["scene_id"]] = doc

dialogues = {}
for p in manifest.get("dialogues", []):
    dialogues.update(entries(load(res_path(p)), "dialogue_id"))

puzzles = {}
for p in manifest.get("puzzles", []):
    puzzles.update(entries(load(res_path(p)), "puzzle_id"))

chapters = {}
for p in manifest.get("chapters", []):
    chapters.update(entries(load(res_path(p)), "chapter_id"))

battles = {}
for p in manifest.get("battles", []):
    battles.update(entries(load(res_path(p)), "battle_id"))

rules = []
for p in manifest.get("interactions", []):
    rules.extend(load(res_path(p)).get("rules", []))

if errors:
    print("\n".join("✗ " + e for e in errors))
    sys.exit(1)

used_keys: set[str] = set()


def use_key(key: str, where: str) -> None:
    if not key:
        return
    used_keys.add(key)
    if key not in strings:
        err(f"[{where}] 로컬라이징 키 없음: {key}")


# ---------------------------------------------------------------- 2. 장면

hotspot_ids: set[str] = set()
exit_ids: set[str] = set()

for sid, sc in scenes.items():
    use_key(sc.get("name_key", ""), f"scene {sid}")
    if not sc.get("walkbox"):
        err(f"[scene {sid}] walkbox 가 없다. 플레이어가 움직일 수 없다.")
    if "default" not in sc.get("spawn_points", {}):
        err(f"[scene {sid}] spawn_points 에 'default' 가 없다.")

    for h in sc.get("hotspots", []):
        hid = h.get("id", "")
        if not hid:
            err(f"[scene {sid}] id 없는 핫스폿")
            continue
        hotspot_ids.add(hid)
        use_key(h.get("name_key", ""), f"scene {sid} hotspot {hid}")
        if not h.get("rect"):
            err(f"[scene {sid}/{hid}] rect 가 없다.")
        for verb, key in (h.get("defaults") or {}).items():
            use_key(key, f"scene {sid}/{hid} defaults.{verb}")
        ch = h.get("character")
        if ch and ch not in characters:
            err(f"[scene {sid}/{hid}] 없는 캐릭터: {ch}")

    for e in sc.get("exits", []):
        eid = e.get("id", "")
        if not eid:
            err(f"[scene {sid}] id 없는 출구")
            continue
        exit_ids.add(eid)
        use_key(e.get("name_key", ""), f"scene {sid} exit {eid}")
        for verb, key in (e.get("defaults") or {}).items():
            use_key(key, f"scene {sid}/{eid} defaults.{verb}")
        target = e.get("target", "")
        if target not in scenes:
            err(f"[scene {sid}/{eid}] 없는 대상 장면: {target}")
        else:
            entry = e.get("entry", "default")
            if entry not in scenes[target].get("spawn_points", {}):
                err(f"[scene {sid}/{eid}] 대상 장면 {target} 에 spawn_point '{entry}' 가 없다.")

    # blocks 가 참조하는 hotspot 이 실재하는지
    for b in sc.get("blocks", []):
        bh = b.get("hotspot")
        if bh and bh not in [h.get("id") for h in sc.get("hotspots", [])] + [x.get("id") for x in sc.get("exits", [])]:
            err(f"[scene {sid}] block 이 없는 핫스폿을 참조: {bh}")


# ---------------------------------------------------------------- 2b. 기하 검사
# 명세서 §5.1 게임 장면은 상단 320x135. 하단 45px 은 명령 패널이라 클릭이 안 간다.

VIEW_W, VIEW_H = 320, 135


def in_rects(pt, rects) -> bool:
    x, y = pt
    return any(rx <= x <= rx + rw and ry <= y <= ry + rh for rx, ry, rw, rh in rects)


for sid, sc in scenes.items():
    boxes = sc.get("walkbox", [])
    boxes = boxes if boxes and isinstance(boxes[0], list) else [boxes]
    boxes = [b for b in boxes if len(b) >= 4]

    for b in boxes:
        if b[1] + b[3] > VIEW_H:
            err(f"[scene {sid}] walkbox 가 명령 패널 영역(y>{VIEW_H})까지 내려온다: {b}")

    # 스폰 지점은 walkbox 안이어야 한다
    for key, pt in sc.get("spawn_points", {}).items():
        if len(pt) >= 2 and not in_rects(pt, boxes):
            err(f"[scene {sid}] spawn_point '{key}' {pt} 가 walkbox 밖이다.")

    for h in sc.get("hotspots", []) + sc.get("exits", []):
        hid = h.get("id", "?")
        r = h.get("rect", [])
        if len(r) >= 4:
            if r[0] < 0 or r[1] < 0 or r[0] + r[2] > VIEW_W or r[1] + r[3] > VIEW_H:
                err(f"[scene {sid}/{hid}] rect 가 장면 영역(320x{VIEW_H}) 밖으로 나간다: {r}")
        # walk_to 는 walkbox 안이어야 한다. 밖이면 캐릭터가 엉뚱한 데 서서 대사한다.
        w = h.get("walk_to", [])
        if len(w) >= 2 and boxes and not in_rects(w, boxes):
            err(f"[scene {sid}/{hid}] walk_to {w} 가 walkbox 밖이다.")
        dv = h.get("default_verb")
        if dv and dv not in {"walk", "look", "talk", "pickup", "use", "open", "close", "push", "pull"}:
            err(f"[scene {sid}/{hid}] 알 수 없는 default_verb: {dv}")

    # 핫스폿끼리 겹치면 작은 쪽이 이긴다. 넓이가 비슷한데 겹치면 어느 쪽이 잡힐지 헷갈린다.
    picks = [h for h in sc.get("hotspots", []) + sc.get("exits", []) if len(h.get("rect", [])) >= 4]
    for i in range(len(picks)):
        for j in range(i + 1, len(picks)):
            a, b = picks[i]["rect"], picks[j]["rect"]
            ox = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
            oy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
            if ox <= 0 or oy <= 0:
                continue
            area_a, area_b = a[2] * a[3], b[2] * b[3]
            small = min(area_a, area_b)
            # 작은 쪽의 절반 이상이 가려지면 큰 쪽을 못 고르는 구간이 생긴다
            if ox * oy > small * 0.5 and 0.5 < area_a / area_b < 2.0:
                warn(f"[scene {sid}] 핫스폿 '{picks[i]['id']}' 와 '{picks[j]['id']}' 가 "
                     f"크게 겹친다 ({ox}x{oy}). 어느 쪽이 잡힐지 애매하다.")


# ---------------------------------------------------------------- 3. 아이템

for iid, it in items.items():
    use_key(it.get("name_key", ""), f"item {iid}")
    use_key(it.get("description_key", ""), f"item {iid}")
    use_key(it.get("fail_key", ""), f"item {iid}")


# ---------------------------------------------------------------- 4. 퍼즐

for pid, pz in puzzles.items():
    use_key(pz.get("name_key", ""), f"puzzle {pid}")
    states = pz.get("states", [])
    if len(states) < 2:
        err(f"[puzzle {pid}] states 가 2개 미만이다.")
    hints = pz.get("hints", {})
    for st in states:
        hs = hints.get(st, [])
        # §19.1 "모든 퍼즐이 최소 두 가지 힌트를 가지는가?"
        if len(hs) < 2:
            err(f"[puzzle {pid}] 상태 '{st}' 의 힌트가 {len(hs)}개다. 최소 2단계 필요. (§19.1)")
        for h in hs:
            key = h.get("key", "") if isinstance(h, dict) else str(h)
            use_key(key, f"puzzle {pid} hint {st}")
    for st in hints:
        if st not in states:
            err(f"[puzzle {pid}] 힌트가 정의되지 않은 상태를 가리킨다: {st}")


# ---------------------------------------------------------------- 5. 챕터

for cid, ch in chapters.items():
    use_key(ch.get("name_key", ""), f"chapter {cid}")
    for k in ch.get("intro_card", []):
        use_key(k, f"chapter {cid} intro_card")
    if ch.get("start_scene") not in scenes:
        err(f"[chapter {cid}] 없는 시작 장면: {ch.get('start_scene')}")
    od = ch.get("opening_dialogue", "")
    if od and od not in dialogues:
        err(f"[chapter {cid}] 없는 오프닝 대화: {od}")
    for i in ch.get("starting_items", []):
        if i not in items:
            err(f"[chapter {cid}] 없는 시작 아이템: {i}")


# ---------------------------------------------------------------- 6. result op 공통 검사

def check_result(r: dict, where: str) -> None:
    if not isinstance(r, dict):
        return
    for field in ("lines", "lines_pre"):
        for line in r.get(field, []):
            if isinstance(line, str):
                use_key(line, where)
            elif isinstance(line, dict):
                use_key(line.get("key", ""), where)
    for i in r.get("give", []) + r.get("take", []):
        if i not in items:
            err(f"[{where}] 없는 아이템: {i}")
    for pid, state in (r.get("puzzle") or {}).items():
        if pid not in puzzles:
            err(f"[{where}] 없는 퍼즐: {pid}")
        elif state not in puzzles[pid].get("states", []):
            err(f"[{where}] 퍼즐 {pid} 에 없는 상태: {state}")
    d = r.get("dialogue", "")
    if d and d not in dialogues:
        err(f"[{where}] 없는 대화: {d}")
    goto = r.get("goto")
    if isinstance(goto, str) and goto and goto not in scenes:
        err(f"[{where}] 없는 goto 장면: {goto}")
    if isinstance(goto, dict) and goto.get("scene") not in scenes:
        err(f"[{where}] 없는 goto 장면: {goto.get('scene')}")
    for hid in (r.get("hotspots") or {}):
        base = hid.split("/")[-1]
        if base not in hotspot_ids and base not in exit_ids:
            err(f"[{where}] 없는 핫스폿 토글: {hid}")
    for eid in (r.get("exits") or {}):
        base = eid.split("/")[-1]
        if base not in exit_ids and base not in hotspot_ids:
            err(f"[{where}] 없는 출구 토글: {eid}")


# Conditions 의 feature / not_feature 가 받는 값. Godot 의 OS.has_feature 이름이다.
# "touch" 는 Conditions 가 DisplayServer.is_touchscreen_available() 로 따로 처리한다.
KNOWN_FEATURES = {"web", "mobile", "pc", "editor", "debug", "release", "touch"}


def check_conditions(pre, where: str) -> None:
    if not isinstance(pre, dict):
        return
    for i in pre.get("items", []) + pre.get("not_items", []):
        if i not in items:
            err(f"[{where}] 전제조건이 없는 아이템을 참조: {i}")
    for group in ("puzzle_at_least", "puzzle_is", "puzzle_not"):
        for pid, st in (pre.get(group) or {}).items():
            if pid not in puzzles:
                err(f"[{where}] 전제조건이 없는 퍼즐을 참조: {pid}")
            elif st not in puzzles[pid].get("states", []):
                err(f"[{where}] 전제조건이 퍼즐 {pid} 의 없는 상태를 참조: {st}")
    sc = pre.get("scene")
    if sc and sc not in scenes:
        err(f"[{where}] 전제조건이 없는 장면을 참조: {sc}")
    # OS.has_feature 로 평가되는 플랫폼 분기. 오타를 잡을 수 있게 목록을 고정한다.
    for group in ("feature", "not_feature"):
        f = pre.get(group)
        if f and f not in KNOWN_FEATURES:
            err(f"[{where}] 알 수 없는 feature: {f} (아는 값: {sorted(KNOWN_FEATURES)})")


# ---------------------------------------------------------------- 7. 상호작용 룰

VALID_ACTIONS = {"walk", "look", "talk", "pickup", "use", "open", "close", "push", "pull"}
rule_ids: set[str] = set()

for r in rules:
    rid = r.get("id", "<익명>")
    where = f"rule {rid}"
    if rid in rule_ids:
        err(f"[{where}] 중복된 룰 id")
    rule_ids.add(rid)

    acts = r.get("action", [])
    acts = acts if isinstance(acts, list) else [acts]
    for a in acts:
        if a not in VALID_ACTIONS:
            err(f"[{where}] 알 수 없는 동사: {a}")

    tgts = r.get("target", [])
    tgts = tgts if isinstance(tgts, list) else [tgts]
    for t in tgts:
        if t not in hotspot_ids and t not in exit_ids and t not in items:
            err(f"[{where}] target 이 핫스폿/출구/아이템 어디에도 없다: {t}")

    itm = r.get("item")
    for i in (itm if isinstance(itm, list) else [itm] if itm else []):
        if i not in items:
            err(f"[{where}] 없는 아이템: {i}")

    check_conditions(r.get("preconditions"), where)
    check_result(r.get("result"), where)

    of = r.get("on_fail")
    if isinstance(of, str):
        use_key(of, where + " on_fail")
    elif isinstance(of, dict):
        check_result(of, where + " on_fail")


# §21 전제조건이 있는 룰에는 고유 실패 대사가 있어야 한다.
# 단, 같은 (action,target,item) 에 전제조건 없는 형제 룰이 있으면
# '조건이 안 맞으면 그쪽으로 흘러가는' 의도된 구성이므로 경고하지 않는다.
def rule_keys(r: dict) -> set[tuple]:
    acts = r.get("action", [])
    acts = acts if isinstance(acts, list) else [acts]
    tgts = r.get("target", [])
    tgts = tgts if isinstance(tgts, list) else [tgts]
    itm = r.get("item")
    itms = itm if isinstance(itm, list) else [itm if itm else ""]
    return {(a, t, i) for a in acts for t in tgts for i in itms}


unconditional_keys: set[tuple] = set()
for r in rules:
    if not r.get("preconditions"):
        unconditional_keys |= rule_keys(r)

for r in rules:
    if not r.get("preconditions") or r.get("on_fail"):
        continue
    if rule_keys(r) & unconditional_keys:
        continue  # 전제조건 실패 시 형제 룰이 받아 준다
    warn(f"[rule {r.get('id', '<익명>')}] preconditions 는 있는데 on_fail 도, 대체 룰도 없다. "
         f"전제조건 실패 시 일반 폴백 대사가 나온다.")


# ---------------------------------------------------------------- 8. 대화 그래프

for did, dlg in dialogues.items():
    nodes = dlg.get("nodes", {})
    start = dlg.get("start_node", "")
    if start not in nodes:
        err(f"[dialogue {did}] start_node '{start}' 가 없다.")

    reachable = set()
    stack = [start] if start in nodes else []
    while stack:
        nid = stack.pop()
        if nid in reachable or nid == "end" or nid not in nodes:
            continue
        reachable.add(nid)
        node = nodes[nid]
        where = f"dialogue {did}/{nid}"
        use_key(node.get("text_key", ""), where)
        check_result(node.get("result"), where)

        nexts = []
        if node.get("next"):
            nexts.append(node["next"])
        for b in node.get("branches", []):
            check_conditions(b.get("if"), where + " branch")
            nexts.append(b.get("next", "end"))
        for c in node.get("choices", []):
            use_key(c.get("text_key", ""), where + " choice")
            if c.get("say_key"):
                use_key(c["say_key"], where + " choice say")
            check_conditions(c.get("requires"), where + " choice")
            check_result(c.get("result"), where + " choice")
            nexts.append(c.get("next", "end"))
            # §12.2 effects 는 관계 변수만 허용
            for k in (c.get("effects") or {}):
                if not k.startswith("sera_"):
                    err(f"[{where}] choice.effects 는 관계 변수만 받는다. 상태 변경은 result 를 쓸 것: {k}")

        if not nexts and not node.get("choices"):
            err(f"[{where}] next 도 choices 도 없다. 대화가 끊긴다.")
        for n in nexts:
            if n != "end" and n not in nodes:
                err(f"[{where}] 없는 노드로 이어짐: {n}")
            stack.append(n)

    for nid in nodes:
        # "_" 로 시작하는 키는 주석이다 (GameData 와 같은 규약)
        if nid.startswith("_"):
            continue
        if nid not in reachable:
            warn(f"[dialogue {did}] 도달할 수 없는 노드: {nid}")


# ---------------------------------------------------------------- 8b. 대화 배틀 (§9)

# §9.3 약점 유형 10종
WEAKNESS_TYPES = {
    "hypocrisy", "hindsight", "authority", "vagueness", "fear",
    "greed", "peer_pressure", "conspiracy", "sunk_cost", "self_contradiction",
}
QUALITIES = {"best", "good", "weak", "wrong"}


def battle_lines(lines, where: str) -> None:
    for line in lines or []:
        if isinstance(line, dict):
            use_key(line.get("key", ""), where)
            check_conditions(line.get("if"), where)


for bid, b in battles.items():
    where = f"battle {bid}"
    use_key(b.get("name_key", ""), where)

    opp = b.get("opponent", "")
    if opp and opp not in characters:
        err(f"[{where}] 없는 상대 캐릭터: {opp}")
    ally = b.get("ally", "")
    if ally and ally not in characters:
        err(f"[{where}] 없는 동행 캐릭터: {ally}")

    wt = b.get("weakness_type", "")
    if wt and wt not in WEAKNESS_TYPES:
        err(f"[{where}] §9.3 에 없는 약점 유형: {wt}")

    support = b.get("support_line", 30)
    if not (0 < support < b.get("confidence", 100)):
        err(f"[{where}] 지지선({support})이 초기 자신감({b.get('confidence', 100)}) 안에 있어야 한다.")

    battle_lines(b.get("intro"), where + " intro")

    phases = b.get("phases", [])
    if not phases:
        err(f"[{where}] phases 가 없다.")
    phase_ids = set()

    for ph in phases:
        pid = ph.get("id", "")
        pwhere = f"{where}/{pid}"
        if not pid:
            err(f"[{where}] id 없는 페이즈")
        elif pid in phase_ids:
            err(f"[{where}] 중복된 페이즈 id: {pid}")
        phase_ids.add(pid)

        battle_lines(ph.get("claim"), pwhere + " claim")
        opts = ph.get("options", [])
        # §9.4-2 "플레이어 선택지 3~4개"
        if not 3 <= len(opts) <= 4:
            err(f"[{pwhere}] 선택지가 {len(opts)}개다. §9.4 는 3~4개를 요구한다.")

        # 조건 없이 항상 보이는 선택지만 세도 3개는 돼야 조건부 선택지가 잠겨도 성립한다.
        unconditional = [o for o in opts if not o.get("requires")]
        if len(unconditional) < 3:
            err(f"[{pwhere}] 조건 없는 선택지가 {len(unconditional)}개다. "
                f"requires 가 전부 막히면 선택지가 부족해진다.")

        # §9.4-7 이길 수 있는 페이즈인가 — 자신감을 깎는 선택지가 하나는 있어야 한다.
        if not any(o.get("confidence", 0) < 0 for o in opts):
            err(f"[{pwhere}] 자신감을 깎는 선택지가 없다. 이 페이즈는 이길 수 없다.")

        for i, o in enumerate(opts):
            owhere = f"{pwhere} option{i}"
            use_key(o.get("text_key", ""), owhere)
            if o.get("say_key"):
                use_key(o["say_key"], owhere + " say")
            use_key(o.get("crowd_line", ""), owhere + " crowd")
            check_conditions(o.get("requires"), owhere)
            battle_lines(o.get("reply"), owhere + " reply")
            q = o.get("quality", "")
            if q not in QUALITIES:
                err(f"[{owhere}] 알 수 없는 quality: {q}")

    # §9.5 오답에 힌트가 붙는가
    hints = b.get("hints", {})
    for pid, key in hints.items():
        if pid not in phase_ids:
            err(f"[{where}] 힌트가 없는 페이즈를 가리킨다: {pid}")
        use_key(key, where + " hint")
    if ally:
        missing = phase_ids - set(hints)
        if missing:
            warn(f"[{where}] 동행자가 있는데 힌트가 없는 페이즈: {sorted(missing)} (§9.5)")

    # §9.5 "즉시 패배하지 않는다" — 이겨도 져도 같은 자리로 진행돼야 한다.
    for branch in ("on_win", "on_lose"):
        o = b.get(branch, {})
        if not o:
            err(f"[{where}] {branch} 가 없다. 승패 중 한쪽에서 진행이 멈춘다.")
            continue
        battle_lines(o.get("lines"), f"{where} {branch}")
        check_result(o.get("result"), f"{where} {branch}")

    win_pz = (b.get("on_win", {}).get("result") or {}).get("puzzle", {})
    lose_pz = (b.get("on_lose", {}).get("result") or {}).get("puzzle", {})
    if win_pz != lose_pz:
        err(f"[{where}] 승패에 따라 퍼즐 전진이 다르다. §9.5 대로라면 져도 같은 지점으로 나아가야 한다. "
            f"(승 {win_pz} / 패 {lose_pz})")


# ---------------------------------------------------------------- 9. GDScript 안의 키

KEY_RE = re.compile(r'Loc\.t(?:_or|_variant)?\(\s*"([^"]+)"')
for gd in sorted((ROOT / "scripts").rglob("*.gd")):
    text = gd.read_text(encoding="utf-8")
    for m in KEY_RE.finditer(text):
        use_key(m.group(1), f"code {gd.relative_to(ROOT)}")

# Loc.t() 를 거치지 않고 테이블/배열 리터럴로 넘기는 키
# (Main.SETTING_ROWS, MenuList.open(title_key), CardView.show_card 등)
LITERAL_RE = re.compile(
    r'"((?:ui|card|hint|verb|speaker|fallback|item|hotspot|scene|chapter|puzzle|battle)'
    r'\.[a-z0-9_.]+)"')
for gd in sorted((ROOT / "scripts").rglob("*.gd")):
    for m in LITERAL_RE.finditer(gd.read_text(encoding="utf-8")):
        use_key(m.group(1), f"code {gd.relative_to(ROOT)}")

# 코드가 문자열 조합으로 만드는 키는 정적으로 못 잡으므로 직접 확인한다.
for verb in VALID_ACTIONS:
    use_key(f"verb.{verb}", "code Actions.label_key")
    use_key(f"fallback.verb.{verb}", "code InteractionResolver")
    # 간소화 UI 로 바꾼 뒤에도 이전에 고른 동사가 문장 라인에 남을 수 있으므로
    # verb.simple.* 는 8개 동사 전부 필요하다.
    use_key(f"verb.simple.{verb}", "code Actions.label_key")
use_key("fallback.use_item", "code InteractionResolver")

# 화자 이름표(§5.1 자막, §18 대화 기록)는 데이터가 speaker 로 지정한 값에서 나온다.
# 하드코딩한 목록을 두면 새 인물을 넣을 때마다 여기도 고쳐야 하므로 데이터에서 모은다.
speakers: set[str] = {"player", "narrator", "system", "hint"}   # 코드가 직접 쓰는 화자


def collect_speakers(node) -> None:
    if isinstance(node, dict):
        sp = node.get("speaker")
        if isinstance(sp, str) and sp:
            speakers.add(sp)
        for v in node.values():
            collect_speakers(v)
    elif isinstance(node, list):
        for v in node:
            collect_speakers(v)


for doc in (dialogues, puzzles, scenes, chapters, battles):
    collect_speakers(doc)
collect_speakers(rules)

for sp in sorted(speakers):
    use_key(f"speaker.{sp}", "data speaker")
    if sp not in characters and sp not in ("player", "narrator", "system", "hint"):
        warn(f"화자 '{sp}' 에 대응하는 캐릭터 정의가 없다. 초상화가 임시 도트로 나온다. (§5.4)")


# ---------------------------------------------------------------- 10. 미사용 키

for k in sorted(strings):
    if k.startswith("_"):
        continue
    if k not in used_keys:
        warn(f"쓰이지 않는 로컬라이징 키: {k}")


# ---------------------------------------------------------------- 결과

print(f"장면 {len(scenes)} · 핫스폿 {len(hotspot_ids)} · 출구 {len(exit_ids)} · 아이템 {len(items)} "
      f"· 대화 {len(dialogues)} · 퍼즐 {len(puzzles)} · 배틀 {len(battles)} · 룰 {len(rules)} "
      f"· 문자열 {len(strings)}")

for w in warnings:
    print("△ " + w)
for e in errors:
    print("✗ " + e)

if errors:
    print(f"\n실패: 오류 {len(errors)}건, 경고 {len(warnings)}건")
    sys.exit(1)

print(f"\n통과: 오류 0건, 경고 {len(warnings)}건")
