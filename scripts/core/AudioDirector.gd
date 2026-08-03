extends Node
## 사운드. (autoload: AudioDirector)
##
## 명세서 §7. 최종적으로는 FM/AdLib 감성의 MIDI 계열 음원을 쓴다.
## 프로토타입 단계에서는 **런타임에 펄스파를 합성**해 임시 효과음을 만든다.
## (PC 스피커/AdLib 톤에 가깝고, 바이너리 에셋 없이도 소리가 난다)
##
## [최종 에셋 교체 지점]
##   res://assets/audio/sfx/<이름>.wav  가 있으면 합성 대신 그 파일을 쓴다.
##   res://assets/audio/music/<이름>.ogg 가 있으면 BGM 으로 재생한다.

const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_DIR := "res://assets/audio/music"
const MIX_RATE := 22050

## §7.3 효과음 정의. 이름 -> 합성 파라미터
## kind: "pulse"(구형파) | "noise" | "sweep"
const SFX_RECIPES := {
	# 아이템 획득: 동전이 아니라 짧은 '체결음'
	"pickup":   [{"kind": "pulse", "f0": 880, "f1": 1320, "ms": 40, "duty": 0.5, "vol": 0.35},
				 {"kind": "pulse", "f0": 1320, "f1": 1320, "ms": 60, "duty": 0.25, "vol": 0.3}],
	# 잘못된 조합: 주문 거부음
	"fail":     [{"kind": "pulse", "f0": 220, "f1": 160, "ms": 90, "duty": 0.5, "vol": 0.3},
				 {"kind": "pulse", "f0": 160, "f1": 110, "ms": 110, "duty": 0.5, "vol": 0.25}],
	# UI 선택: 짧은 키보드 클릭
	"click":    [{"kind": "noise", "ms": 12, "vol": 0.18}],
	# 저장: 플로피 디스크 모터음
	"save":     [{"kind": "noise", "ms": 60, "vol": 0.10},
				 {"kind": "pulse", "f0": 70, "f1": 62, "ms": 220, "duty": 0.5, "vol": 0.12},
				 {"kind": "noise", "ms": 40, "vol": 0.08}],
	# 새 정보 획득: 뉴스 속보 벨
	"news":     [{"kind": "pulse", "f0": 1046, "f1": 1046, "ms": 90, "duty": 0.5, "vol": 0.25},
				 {"kind": "pulse", "f0": 784, "f1": 784, "ms": 160, "duty": 0.5, "vol": 0.22}],
	# 문 여닫기
	"door":     [{"kind": "noise", "ms": 90, "vol": 0.16},
				 {"kind": "pulse", "f0": 120, "f1": 80, "ms": 70, "duty": 0.5, "vol": 0.14}],
	# 주가 급락: 낮은 피치의 하강음
	"crash":    [{"kind": "sweep", "f0": 520, "f1": 90, "ms": 420, "duty": 0.5, "vol": 0.22}],
	# 대화 진행
	"blip":     [{"kind": "pulse", "f0": 620, "f1": 620, "ms": 18, "duty": 0.3, "vol": 0.10}],
	# 장면 전환
	"whoosh":   [{"kind": "noise", "ms": 140, "vol": 0.12}],
	# §7.3 대화 배틀 타격: 종이 찢김 + 캔들 붕괴음
	"hit_paper": [{"kind": "noise", "ms": 70, "vol": 0.22},
				  {"kind": "sweep", "f0": 700, "f1": 240, "ms": 130, "duty": 0.25, "vol": 0.20}],
	# §7.3 멘탈 지지선 이탈: 금속 기둥 파손음
	"support_break": [{"kind": "pulse", "f0": 330, "f1": 330, "ms": 60, "duty": 0.5, "vol": 0.26},
					  {"kind": "noise", "ms": 90, "vol": 0.20},
					  {"kind": "sweep", "f0": 420, "f1": 70, "ms": 520, "duty": 0.5, "vol": 0.24}],
}

var _cache: Dictionary = {}
var _music_cache: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_music := ""
var _next_player := 0


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	apply_volumes()


func apply_volumes() -> void:
	var sfx_v := float(SaveManager.get_setting("sfx_volume", 0.9)) * float(SaveManager.get_setting("master_volume", 0.8))
	var mus_v := float(SaveManager.get_setting("music_volume", 0.6)) * float(SaveManager.get_setting("master_volume", 0.8))
	for p in _sfx_players:
		p.volume_db = linear_to_db(maxf(sfx_v, 0.0001))
	_music_player.volume_db = linear_to_db(maxf(mus_v, 0.0001))


func play_sfx(sfx_name: String) -> void:
	if sfx_name.is_empty():
		return
	var stream := _get_sfx(sfx_name)
	if stream == null:
		return
	var p := _sfx_players[_next_player]
	_next_player = (_next_player + 1) % _sfx_players.size()
	p.stream = stream
	p.play()


func current_music() -> String:
	return _current_music


func play_music(music_name: String) -> void:
	if music_name == _current_music:
		return
	_current_music = music_name
	if music_name.is_empty():
		_music_player.stop()
		return

	var stream := _get_music(music_name)
	if stream == null:
		_music_player.stop()
		return
	_music_player.stream = stream
	_music_player.play()


## 파일이 있으면 파일, 없으면 §7.2 정의로 합성한다. 효과음과 같은 규칙이다.
func _get_music(music_name: String) -> AudioStream:
	if _music_cache.has(music_name):
		return _music_cache[music_name]

	var path := "%s/%s.ogg" % [MUSIC_DIR, music_name]
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is AudioStream:
			_music_cache[music_name] = res
			return res

	var synth: AudioStream = MusicSynth.render(music_name)
	if synth == null:
		push_warning("[AudioDirector] 정의되지 않은 곡: %s" % music_name)
	_music_cache[music_name] = synth
	return synth


func stop_music() -> void:
	_current_music = ""
	_music_player.stop()


## 종료 시 재생 중인 스트림을 놓아준다. 안 하면 AudioStreamWAV 가 누수로 보고된다.
func _exit_tree() -> void:
	for p in _sfx_players:
		p.stop()
		p.stream = null
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	_cache.clear()
	_music_cache.clear()


func _get_sfx(sfx_name: String) -> AudioStream:
	if _cache.has(sfx_name):
		return _cache[sfx_name]

	var path := "%s/%s.wav" % [SFX_DIR, sfx_name]
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is AudioStream:
			_cache[sfx_name] = res
			return res

	if not SFX_RECIPES.has(sfx_name):
		_cache[sfx_name] = null
		return null
	var stream := _synthesize(SFX_RECIPES[sfx_name])
	_cache[sfx_name] = stream
	return stream


# ---------------------------------------------------------------- 합성

func _synthesize(segments: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for seg in segments:
		_append_segment(samples, seg)
	# 클릭 노이즈 방지용 페이드아웃
	var fade := mini(samples.size(), 200)
	for i in fade:
		samples[samples.size() - fade + i] *= 1.0 - float(i) / float(fade)

	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _append_segment(out: PackedFloat32Array, seg: Dictionary) -> void:
	var kind := str(seg.get("kind", "pulse"))
	var ms := int(seg.get("ms", 60))
	var count := int(MIX_RATE * ms / 1000.0)
	var vol := float(seg.get("vol", 0.25))
	var f0 := float(seg.get("f0", 440))
	var f1 := float(seg.get("f1", f0))
	var duty := float(seg.get("duty", 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seg))

	var phase := 0.0
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var amp := vol * (1.0 - t * 0.85)   # 감쇠 엔벨로프
		var v := 0.0
		match kind:
			"noise":
				v = rng.randf_range(-1.0, 1.0) * amp
			_:
				var freq: float = lerpf(f0, f1, t if kind == "sweep" else t * t)
				phase += freq / float(MIX_RATE)
				phase = fposmod(phase, 1.0)
				v = (1.0 if phase < duty else -1.0) * amp
		out.append(v)
