class_name SaveSlotMenu
extends MenuList
## 저장/불러오기 슬롯 화면. 명세서 §17.
##   - 수동 슬롯 10개 + 자동 저장 3개
##   - "저장 화면에 현재 장면의 작은 도트 썸네일 표시"

enum Mode { SAVE, LOAD }

signal slot_chosen(slot: String, mode: int)

const THUMB_BOX := Rect2i(218, 42, 64, 27)

var mode: int = Mode.SAVE
var _slots: Array[String] = []
var _thumb_cache: Dictionary = {}


func open_for(p_mode: int) -> void:
	mode = p_mode
	box = Rect2i(12, 4, 192, 174)
	row_h = 11
	_thumb_cache.clear()
	_slots.clear()
	var rows: Array = []

	for i in SaveManager.MANUAL_SLOTS:
		var slot := SaveManager.manual_slot(i)
		_slots.append(slot)
		rows.append(_row_for(slot, Loc.t("ui.save.slot", {"n": i + 1})))

	for i in SaveManager.AUTO_SLOTS:
		var slot := SaveManager.auto_slot(i)
		_slots.append(slot)
		var r := _row_for(slot, Loc.t("ui.save.autoslot", {"n": i + 1}))
		# 자동 저장 슬롯에는 덮어쓰기를 하지 않는다.
		if mode == Mode.SAVE:
			r["enabled"] = false
		rows.append(r)

	var title := "ui.save.title" if mode == Mode.SAVE else "ui.load.title"
	open(title, rows, "ui.save.footer")


func _row_for(slot: String, label: String) -> Dictionary:
	var s := SaveManager.slot_summary(slot)
	if s.is_empty():
		return {
			"label": label,
			"value": Loc.t("ui.save.empty"),
			"enabled": mode == Mode.SAVE,
		}
	return {"label": label, "value": str(s.get("play_time", "")), "enabled": true}


func selected_slot() -> String:
	if selected < 0 or selected >= _slots.size():
		return ""
	return _slots[selected]


func choose() -> void:
	var slot := selected_slot()
	if slot.is_empty():
		return
	slot_chosen.emit(slot, mode)


func _draw() -> void:
	if not visible:
		return
	super._draw()

	var font := Theming.base_font
	var size := Theming.small_font_size()
	var slot := selected_slot()

	draw_rect(Rect2(THUMB_BOX).grow(2), Palette.ui("panel"), true)
	draw_rect(Rect2(THUMB_BOX).grow(2), Palette.ui("outline"), false, 1.0)

	var tex := _thumb(slot)
	if tex != null:
		draw_texture_rect(tex, Rect2(THUMB_BOX), false)
	else:
		draw_rect(Rect2(THUMB_BOX), Palette.ui("panel_dark"), true)
		var t := Loc.t("ui.save.no_preview")
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(roundf(THUMB_BOX.position.x + (THUMB_BOX.size.x - w) / 2.0),
			THUMB_BOX.position.y + THUMB_BOX.size.y / 2.0),
			t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ui("text_dim"))

	var s := SaveManager.slot_summary(slot)
	var y := THUMB_BOX.position.y + THUMB_BOX.size.y + 8
	if s.is_empty():
		return
	var scene_key := str(s.get("scene_name_key", ""))
	if not scene_key.is_empty():
		draw_string(font, Vector2(THUMB_BOX.position.x, y), Loc.t(scene_key),
			HORIZONTAL_ALIGNMENT_LEFT, THUMB_BOX.size.x + 4, size, Palette.ui("text"))
	draw_string(font, Vector2(THUMB_BOX.position.x, y + 10), str(s.get("saved_at_text", "")),
		HORIZONTAL_ALIGNMENT_LEFT, THUMB_BOX.size.x + 4, size, Palette.ui("text_dim"))


func _thumb(slot: String) -> Texture2D:
	if slot.is_empty():
		return null
	if _thumb_cache.has(slot):
		return _thumb_cache[slot]
	var t := SaveManager.slot_thumbnail(slot)
	_thumb_cache[slot] = t
	return t
