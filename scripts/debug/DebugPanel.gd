class_name DebugPanel
extends Control
## 디버그 패널. 명세서 §21 "디버그 패널 제공".
##
## F1 토글. QA(§19)에 필요한 정보를 한 화면에 모은다.
##   - 데이터 로드 오류 / 누락된 로컬라이징 키   → §19.2
##   - 퍼즐 상태와 플래그                        → §19.1 진행 불가 점검
##   - 마지막 상호작용의 매칭 결과와 폴백 단계   → 룰이 왜 안 걸렸는지 즉시 확인
##
## 릴리스 빌드에서는 Main 이 이 노드를 만들지 않는다.

const BOX := Rect2i(2, 2, 316, 176)
const LINE_H := 9

var last_interaction := ""
var last_resolution := ""

var _page := 0
const PAGES := ["상태", "플래그", "데이터", "장면"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func toggle() -> void:
	visible = not visible
	queue_redraw()


func next_page() -> void:
	_page = (_page + 1) % PAGES.size()
	queue_redraw()


func note_interaction(action: String, target: String, item: String, res: InteractionResult) -> void:
	last_interaction = "%s(%s%s)" % [action, target, "" if item.is_empty() else " + " + item]
	last_resolution = "%s rule=%s %s" % [
		res.kind_name(), res.rule_id if not res.rule_id.is_empty() else "-", res.debug_note]
	if visible:
		queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(BOX), Color(0.05, 0.04, 0.07, 0.92), true)
	draw_rect(Rect2(BOX), Palette.ui("text_hot"), false, 1.0)

	var lines := PackedStringArray()
	lines.append("[F1 닫기]  [F2 페이지: %s]  [F3 데이터 리로드]" % PAGES[_page])
	lines.append("")

	match _page:
		0: _page_state(lines)
		1: _page_flags(lines)
		2: _page_data(lines)
		3: _page_scene(lines)

	var font := Theming.small_font
	var size := Theming.small_font_size()
	for i in lines.size():
		var y := BOX.position.y + 4 + LINE_H * i + font.get_ascent(size)
		if y > BOX.position.y + BOX.size.y - 2:
			break
		var col := Palette.ui("text")
		var l := lines[i]
		if l.begins_with("["):
			col = Palette.ui("text_hot")
		elif l.begins_with("!"):
			col = Color.html("#ff6b6b")
		elif l.begins_with("#"):
			col = Palette.ui("text_dim")
		draw_string(font, Vector2(BOX.position.x + 4, y), l,
			HORIZONTAL_ALIGNMENT_LEFT, BOX.size.x - 8, size, col)


func _page_state(out: PackedStringArray) -> void:
	out.append("# 장면: %s   챕터: %s   플레이: %s" % [GameState.scene_id, GameState.chapter_id, GameState.formatted_play_time()])
	out.append("# 위치: %s" % str(GameState.player_position))
	out.append("")
	out.append("[퍼즐]")
	for pid in GameData.puzzles.keys():
		var states: Array = GameData.puzzle(str(pid)).get("states", [])
		var cur := GameState.puzzle_state(str(pid))
		out.append("  %s : %s (%d/%d)%s" % [pid, cur, states.find(cur) + 1, states.size(),
			"  ✓" if GameState.is_puzzle_complete(str(pid)) else ""])
	out.append("")
	out.append("[인벤토리 %d]" % GameState.inventory.size())
	out.append("  " + ", ".join(GameState.inventory))
	out.append("")
	out.append("[관계]")
	var rel := ""
	for k in GameState.RELATION_KEYS:
		rel += "%s=%d  " % [k.replace("sera_", ""), int(GameState.relation.get(k, 0))]
	out.append("  " + rel)
	out.append("")
	out.append("[마지막 상호작용]")
	out.append("  " + last_interaction)
	out.append("  " + last_resolution)


func _page_flags(out: PackedStringArray) -> void:
	out.append("[플래그 %d]" % GameState.flags.size())
	var keys := GameState.flags.keys()
	keys.sort()
	for k in keys:
		out.append("  %s = %s" % [k, str(GameState.flags[k])])


func _page_data(out: PackedStringArray) -> void:
	out.append("[데이터] 장면 %d / 아이템 %d / 대화 %d / 퍼즐 %d / 룰 %d" % [
		GameData.scenes.size(), GameData.items.size(),
		GameData.dialogues.size(), GameData.puzzles.size(), GameData.interactions.size()])
	out.append("")
	if GameData.load_errors.is_empty():
		out.append("# 로드 오류 없음")
	else:
		out.append("[로드 오류 %d]" % GameData.load_errors.size())
		for e in GameData.load_errors:
			out.append("! " + e)
	out.append("")
	if Loc.missing_keys.is_empty():
		out.append("# 누락 로컬라이징 키 없음")
	else:
		out.append("[누락 키 %d]" % Loc.missing_keys.size())
		for k in Loc.missing_keys.keys():
			out.append("! " + str(k))


func _page_scene(out: PackedStringArray) -> void:
	var sc := GameData.scene(GameState.scene_id)
	out.append("[핫스폿]")
	for h in sc.get("hotspots", []):
		if h is Dictionary:
			var id := str((h as Dictionary).get("id", ""))
			var on := GameState.is_hotspot_enabled(GameState.scene_id, id, bool((h as Dictionary).get("enabled", true)))
			out.append("  %s %s  %s" % ["●" if on else "○", id, str((h as Dictionary).get("rect", []))])
	out.append("")
	out.append("[출구]")
	for e in sc.get("exits", []):
		if e is Dictionary:
			var id2 := str((e as Dictionary).get("id", ""))
			var on2 := GameState.is_exit_enabled(GameState.scene_id, id2, bool((e as Dictionary).get("enabled", true)))
			out.append("  %s %s → %s" % ["●" if on2 else "○", id2, str((e as Dictionary).get("target", ""))])
	out.append("")
	out.append("[전체 장면]")
	for sid in GameData.scenes.keys():
		out.append("  %s%s" % ["→ " if sid == GameState.scene_id else "  ", sid])
