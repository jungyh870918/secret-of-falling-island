extends Node
## 저장/불러오기. (autoload: SaveManager)
##
## 명세서 §17.
##   - 수동 슬롯 10개, 자동 저장 3개 순환
##   - 자동 저장 시점: 장면 전환 / 퍼즐 완료 / 대화 배틀 종료 / 챕터 시작 / 중요 선택 직후
##   - 저장 화면에 현재 장면의 작은 도트 썸네일
##
## §23 "게임 재실행 후 이어하기 가능" 을 만족하기 위해 마지막 저장 위치를 별도로 기록한다.

signal saved(slot: String)
signal loaded(slot: String)

const SAVE_DIR := "user://saves"
const SETTINGS_PATH := "user://settings.json"
const MANUAL_SLOTS := 10
const AUTO_SLOTS := 3
## 게임 장면(320x135)의 1/5 축소. 명령 패널은 제외한다.
const THUMB_SIZE := Vector2i(64, 27)

## §17 "저장 화면에 현재 장면의 작은 도트 썸네일".
## 뷰포트 텍스처는 프레임 렌더 직후에만 안전하게 읽을 수 있으므로,
## Main 이 주기적으로 (frame_post_draw 이후) 최신 화면을 여기에 넣어 둔다.
var last_frame: Image = null

var settings: Dictionary = {}
## 사용자가 실제로 고른 적이 있는 설정 키. settings 에는 기본값도 전부 들어 있어서
## 그것만으로는 "고른 적 있음" 을 알 수 없다. 기기별 기본값(터치 → 간소화 UI)을
## 적용할 때 사용자의 선택을 덮지 않으려면 이 구분이 필요하다.
var _user_set: Dictionary = {}

var _auto_cursor := 0

## 저장 순서를 가리는 단조 증가 카운터.
## 유닉스 시각은 초 단위라 자동 저장이 연달아 일어나면 순서를 구분하지 못한다
## (장면 전환 + 퍼즐 진행이 같은 초에 겹치면 §23-13 '이어하기' 가 옛 저장을 연다).
var _save_counter := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_settings()
	_auto_cursor = int(settings.get("_auto_cursor", 0))
	_save_counter = int(settings.get("_save_counter", 0))


# ---------------------------------------------------------------- 슬롯 이름

static func manual_slot(i: int) -> String:
	return "manual_%02d" % i


static func auto_slot(i: int) -> String:
	return "auto_%d" % i


func _path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


func _thumb_path(slot: String) -> String:
	return "%s/%s.png" % [SAVE_DIR, slot]


# ---------------------------------------------------------------- 저장

func save_to(slot: String) -> bool:
	_save_counter += 1
	var payload := {
		"slot": slot,
		"save_index": _save_counter,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"saved_at_text": Time.get_datetime_string_from_system(false, true),
		"scene_name_key": GameData.scene(GameState.scene_id).get("name_key", ""),
		"play_time": GameState.formatted_play_time(),
		"state": GameState.to_dict(),
	}
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 저장 실패: %s" % slot)
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

	_write_thumbnail(slot)

	settings["_last_slot"] = slot
	settings["_save_counter"] = _save_counter
	_save_settings()
	AudioDirector.play_sfx("save")
	saved.emit(slot)
	return true


## §17 자동 저장 3개 순환.
func autosave() -> void:
	var slot := auto_slot(_auto_cursor)
	_auto_cursor = (_auto_cursor + 1) % AUTO_SLOTS
	settings["_auto_cursor"] = _auto_cursor
	save_to(slot)


# ---------------------------------------------------------------- 불러오기

func load_from(slot: String) -> bool:
	var d := read_slot(slot)
	if d.is_empty():
		return false
	var state = d.get("state", {})
	if not (state is Dictionary):
		return false
	GameState.from_dict(state)
	settings["_last_slot"] = slot
	_save_settings()
	loaded.emit(slot)
	return true


func read_slot(slot: String) -> Dictionary:
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func slot_exists(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))


func has_any_save() -> bool:
	for i in AUTO_SLOTS:
		if slot_exists(auto_slot(i)):
			return true
	for i in MANUAL_SLOTS:
		if slot_exists(manual_slot(i)):
			return true
	return false


## §23 "게임 재실행 후 이어하기" — 가장 최근 저장 슬롯.
## save_index(단조 증가)를 1순위로 본다. 유닉스 시각은 예전 세이브용 폴백.
func latest_slot() -> String:
	var best := ""
	var best_key := Vector2i(-1, -1)
	var candidates: Array[String] = []
	for i in AUTO_SLOTS:
		candidates.append(auto_slot(i))
	for i in MANUAL_SLOTS:
		candidates.append(manual_slot(i))
	for s in candidates:
		var d := read_slot(s)
		if d.is_empty():
			continue
		var key := Vector2i(int(d.get("save_index", 0)), int(d.get("saved_at_unix", 0)))
		if key.x > best_key.x or (key.x == best_key.x and key.y > best_key.y):
			best_key = key
			best = s
	return best


func load_latest() -> bool:
	var s := latest_slot()
	return load_from(s) if not s.is_empty() else false


func slot_summary(slot: String) -> Dictionary:
	var d := read_slot(slot)
	if d.is_empty():
		return {}
	return {
		"slot": slot,
		"scene_name_key": str(d.get("scene_name_key", "")),
		"play_time": str(d.get("play_time", "00:00:00")),
		"saved_at_text": str(d.get("saved_at_text", "")),
		"saved_at_unix": int(d.get("saved_at_unix", 0)),
	}


func slot_thumbnail(slot: String) -> Texture2D:
	var p := _thumb_path(slot)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	if img.load(p) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _write_thumbnail(slot: String) -> void:
	if last_frame == null:
		return
	var img := last_frame.duplicate() as Image
	# 하단 명령 패널을 잘라내고 장면만 남긴다.
	var view_h: int = mini(img.get_height(), 135)
	img = img.get_region(Rect2i(0, 0, img.get_width(), view_h))
	# §17 "작은 도트 썸네일" — 보간 없이 축소해야 도트가 유지된다.
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_NEAREST)
	img.save_png(_thumb_path(slot))


# ---------------------------------------------------------------- 설정 (§18)

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		settings = default_settings()
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		settings = default_settings()
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	settings = default_settings()
	if parsed is Dictionary:
		for k in (parsed as Dictionary).keys():
			settings[k] = parsed[k]
			if not str(k).begins_with("_"):
				_user_set[str(k)] = true


func default_settings() -> Dictionary:
	return {
		"verb_ui": "classic",        ## §5.2 classic | simple
		"font_size_index": 1,        ## §18 3단계
		"text_speed": 1,             ## 0 느림 / 1 보통 / 2 빠름 / 3 즉시
		"fullscreen": false,
		"high_contrast_hotspots": true,   ## §18 고대비 핫스폿.
		## 프로토타입 기본 ON — 임시 색 블록으로는 무엇이 상호작용 가능한지 알 수 없다.
		## 실제 배경 도트가 들어오면 false 로 되돌린다.
		"show_portraits": true,           ## §5.4 대화 초상화. 화면의 3분의 1을 덮으므로 끌 수 있어야 한다.
		"show_exit_markers": false,       ## §18 출구 표시
		"reduce_shake": false,
		"reduce_flashing": false,
		"hint_level": 3,             ## §11.3 최대 힌트 단계
		"master_volume": 0.8,
		"sfx_volume": 0.9,
		"music_volume": 0.6,
	}


func get_setting(key: String, default_value: Variant = null) -> Variant:
	if settings.has(key):
		return settings[key]
	var d := default_settings()
	return d.get(key, default_value)


## 사용자가 이 항목을 직접 고른 적이 있는가.
## settings.has() 로는 알 수 없다 — 거기에는 기본값이 전부 들어 있다.
func is_user_set(key: String) -> bool:
	return _user_set.has(key)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_user_set[key] = true
	_save_settings()


## 기기 때문에 달라지는 기본값(터치 → 간소화 UI 등).
## 사용자의 선택이 아니므로 파일에 적지 않는다 — 적으면 그 프로필을 다른 기기에서
## 열었을 때까지 따라오고, 나중에 사용자가 고른 값과 구분되지 않는다.
func set_device_default(key: String, value: Variant) -> void:
	settings[key] = value


## **사용자가 고른 값과 내부 카운터만 적는다. 기본값은 적지 않는다.**
##
## 전부 적으면 두 가지가 깨진다.
##  1. 한 번 저장한 뒤로는 모든 키가 "사용자가 고른 값" 으로 보여, 기기별 기본값
##     (터치 → 간소화 UI)을 영영 적용할 수 없다.
##  2. 나중에 기본값을 바꿔도 기존 플레이어에게는 반영되지 않는다.
func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	var out: Dictionary = {}
	for k in settings.keys():
		var key := str(k)
		# "_" 로 시작하는 키는 자동 저장 커서 같은 내부 상태다. 항상 남긴다.
		if key.begins_with("_") or _user_set.has(key):
			out[key] = settings[k]
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
