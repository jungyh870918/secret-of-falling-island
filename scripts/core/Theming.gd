extends Node
## 전역 UI 테마. (autoload: Theming)
##
## 명세서 §6.1 "안티앨리어싱 금지", §18 "폰트 크기 3단계".
##
## [핵심 규칙 — 픽셀 폰트는 설계 크기로만 써야 한다]
## Galmuri 는 각 두께가 특정 픽셀 크기에 맞춰 설계된 도트 폰트다.
## Galmuri11 을 9px 로 줄이면 글리프가 리샘플링되면서 도트가 뭉개진다.
## 그래서 크기 단계마다 그 크기로 설계된 폰트를 따로 쓴다.
##
##   작게 = Galmuri9  @  9px
##   보통 = Galmuri11 @ 11px
##   크게 = Galmuri14 @ 14px
##
## 하나를 골라 배율만 바꾸는 방식은 쓰지 않는다.
##
## 폰트 출처: Galmuri (Lee Minseo), SIL Open Font License 1.1
##            assets/fonts/Galmuri-LICENSE.txt — 재배포 시 반드시 동봉한다.
##            원본 15MB 를 tools/subset_font.py 로 5MB 로 줄여 넣었다.

const FONT_DIR := "res://assets/fonts"

## §18 폰트 크기 3단계. [파일 이름, 설계 픽셀 크기]
const FONT_SPECS := [
	["Galmuri9", 9],
	["Galmuri11", 11],
	["Galmuri14", 14],
]
const FONT_SIZE_LABELS := ["ui.settings.font_small", "ui.settings.font_medium", "ui.settings.font_large"]

## Galmuri 가 없을 때(에셋 미포함 빌드) 쓰는 OS 한글 폰트 후보.
## 도트 느낌은 안 나지만 두부(□)는 피할 수 있다.
const SYSTEM_FONT_CANDIDATES := [
	"Apple SD Gothic Neo", "AppleGothic",
	"Malgun Gothic", "Noto Sans KR", "Noto Sans CJK KR",
	"NanumGothic", "Nanum Gothic", "Sans-Serif",
]
const FALLBACK_SIZES := [9, 10, 12]

signal font_size_changed(px: int)

var theme: Theme
## 현재 단계의 본문 폰트
var base_font: Font
## 한 단계 작은 폰트. 동사 버튼·각주처럼 좁은 칸에 쓴다.
## 이것도 반드시 설계 크기로 쓴다.
var small_font: Font

var _fonts: Array[Font] = []
var _using_pixel_font := false
var _size_index := 1


func _ready() -> void:
	_load_fonts()
	theme = Theme.new()
	_apply_index(_size_index)
	# Window.theme 를 지정하면 트리 전체 Control 에 상속된다.
	get_tree().root.theme = theme


func _load_fonts() -> void:
	_fonts.clear()
	var all_present := true
	for spec in FONT_SPECS:
		var path := "%s/%s.ttf" % [FONT_DIR, str(spec[0])]
		if not ResourceLoader.exists(path):
			all_present = false
			break

	if all_present:
		for spec in FONT_SPECS:
			var res := ResourceLoader.load("%s/%s.ttf" % [FONT_DIR, str(spec[0])])
			if res is FontFile:
				_fonts.append(_configure_pixel_font(res as FontFile))
			else:
				all_present = false
				break

	if all_present and _fonts.size() == FONT_SPECS.size():
		_using_pixel_font = true
		return

	# 폴백: OS 한글 폰트 하나로 세 단계를 모두 처리한다.
	push_warning("[Theming] Galmuri 픽셀 폰트를 찾지 못해 시스템 폰트로 대체합니다.")
	_using_pixel_font = false
	_fonts.clear()
	var sf := _make_system_font()
	for i in FONT_SPECS.size():
		_fonts.append(sf)


## 도트 폰트 렌더링 설정. 하나라도 켜지면 글자가 흐려진다.
func _configure_pixel_font(f: FontFile) -> FontFile:
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE      # §6.1
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.hinting = TextServer.HINTING_NONE                     # 이미 격자에 맞춰 설계됨
	f.force_autohinter = false                              # 자동 힌팅은 도트를 망친다
	f.multichannel_signed_distance_field = false            # MSDF 는 곡선 보간용
	f.allow_system_fallback = true                          # 빠진 글자만 OS 폰트로
	f.oversampling = 1.0                                    # 초과 샘플링 금지
	return f


func _make_system_font() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(SYSTEM_FONT_CANDIDATES)
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	sf.hinting = TextServer.HINTING_NONE
	sf.allow_system_fallback = true
	sf.multichannel_signed_distance_field = false
	return sf


func _apply_index(idx: int) -> void:
	_size_index = clampi(idx, 0, FONT_SPECS.size() - 1)
	var small_idx: int = maxi(0, _size_index - 1)

	base_font = _fonts[_size_index]
	small_font = _fonts[small_idx]

	theme.default_font = base_font
	theme.default_font_size = font_size()


func set_font_size_index(idx: int) -> void:
	if _size_index == clampi(idx, 0, FONT_SPECS.size() - 1) and base_font != null:
		return
	_apply_index(idx)
	font_size_changed.emit(font_size())


func get_font_size_index() -> int:
	return _size_index


## 본문 크기. 픽셀 폰트를 쓸 때는 반드시 그 폰트의 설계 크기다.
func font_size() -> int:
	if _using_pixel_font:
		return int(FONT_SPECS[_size_index][1])
	return int(FALLBACK_SIZES[_size_index])


## 작은 라벨 크기. small_font 와 짝을 이룬다 — 둘을 섞어 쓰면 도트가 깨진다.
func small_font_size() -> int:
	var small_idx: int = maxi(0, _size_index - 1)
	if _using_pixel_font:
		return int(FONT_SPECS[small_idx][1])
	return int(FALLBACK_SIZES[small_idx])


func using_pixel_font() -> bool:
	return _using_pixel_font
