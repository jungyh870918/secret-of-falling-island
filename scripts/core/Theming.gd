extends Node
## 전역 UI 테마. (autoload: Theming)
##
## 명세서 §6.1 "안티앨리어싱 금지", §18 "폰트 크기 3단계".
##
## Godot 기본 폰트에는 한글 글리프가 없어 대사가 두부(□)로 표시된다.
## 따라서 SystemFont 폴백을 사용한다.
##
## [최종 에셋 교체 지점]
##   res://assets/fonts/pixel_ko.ttf 파일을 넣으면 자동으로 그 폰트를 사용한다.
##   (DOS풍 한글 비트맵 폰트를 확보하면 여기에 넣기만 하면 됨)

const FONT_PATH := "res://assets/fonts/pixel_ko.ttf"

## 플랫폼별 한글 시스템 폰트 후보. 위에서부터 먼저 찾은 것을 쓴다.
const SYSTEM_FONT_CANDIDATES := [
	"Apple SD Gothic Neo",  # macOS
	"AppleGothic",          # macOS (구)
	"Malgun Gothic",        # Windows
	"Noto Sans KR",
	"Noto Sans CJK KR",     # Linux
	"NanumGothic",
	"Nanum Gothic",
	"Sans-Serif",
]

## §18 폰트 크기 3단계
const FONT_SIZES := [9, 10, 12]
const FONT_SIZE_LABELS := ["ui.settings.font_small", "ui.settings.font_medium", "ui.settings.font_large"]

signal font_size_changed(px: int)

var theme: Theme
var base_font: Font
var _size_index := 1


func _ready() -> void:
	base_font = _make_font()
	theme = Theme.new()
	theme.default_font = base_font
	theme.default_font_size = FONT_SIZES[_size_index]
	# Window.theme 를 지정하면 트리 전체 Control 에 상속된다.
	get_tree().root.theme = theme


func set_font_size_index(idx: int) -> void:
	_size_index = clampi(idx, 0, FONT_SIZES.size() - 1)
	theme.default_font_size = FONT_SIZES[_size_index]
	font_size_changed.emit(FONT_SIZES[_size_index])


func get_font_size_index() -> int:
	return _size_index


func font_size() -> int:
	return FONT_SIZES[_size_index]


## 작은 라벨용. 본문보다 항상 한 단계 작되 8px 밑으로는 안 내려간다(한글 가독성).
func small_font_size() -> int:
	return maxi(9, FONT_SIZES[_size_index] - 1)


func _make_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var res := ResourceLoader.load(FONT_PATH)
		if res is FontFile:
			var ff := res as FontFile
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.hinting = TextServer.HINTING_NONE
			ff.allow_system_fallback = true
			return ff

	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(SYSTEM_FONT_CANDIDATES)
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	sf.hinting = TextServer.HINTING_NONE
	sf.allow_system_fallback = true
	sf.multichannel_signed_distance_field = false
	return sf
