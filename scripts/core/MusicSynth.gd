class_name MusicSynth
extends RefCounted
## 배경음악 런타임 합성. 명세서 §7.1 / §7.2.
##
## §7.1 "MIDI 또는 FM 신시사이저 기반 / AdLib·사운드블라스터 감성 / 짧고 기억하기 쉬운 멜로디
## / 장면별 루프 60~120초 / 멜로디 악기는 FM 피아노, 클라리넷 유사음, 브라스, 칩 베이스
## / 드럼은 과하지 않게."
##
## 효과음과 같은 이유로 파일 대신 런타임 합성을 쓴다 — 저장소에 바이너리를 넣지 않고도
## 소리가 나고, 나중에 assets/audio/music/<이름>.ogg 를 넣으면 AudioDirector 가 그쪽을 먼저 쓴다.
##
## 11025Hz 모노는 절약이 아니라 선택이다. AdLib 시절의 대역폭이 그 정도였고,
## 320x180 도트에 맞는 소리도 그쪽이다.

const RATE := 11025

## 곡 정의. seq 는 16분음표 슬롯 배열이고 step 은 슬롯 하나의 길이(16분음표 개수)다.
## 음 높이는 MIDI 번호, -1 은 쉼표.
const SONGS := {
	# §7.2 기관성 — "박자감이 거의 없는 미니멀 루프. 프린터, 키보드, 팩스 소리를 리듬으로."
	# 회사·지하철·원룸이 모두 이 곡을 쓴다. 같은 밤의 세 장소이기 때문이다.
	"office_night": {
		"bpm": 64,
		"loop_sec": 64.0,
		"tracks": [
			{ "inst": "fm_piano", "vol": 0.115, "step": 4, "gate": 3.4,
			  "seq": [57, -1, 60, -1,  55, -1, -1, 57,  62, -1, 60, -1,  55, -1, -1, -1] },
			{ "inst": "clarinet", "vol": 0.062, "step": 16, "gate": 14.0,
			  "seq": [64, -1, 62, -1, 60, -1, 59, -1] },
			{ "inst": "bass", "vol": 0.085, "step": 16, "gate": 15.0,
			  "seq": [33, 33, 29, 31] },
			{ "_": "키보드 타건 — 드럼 대신 사무실 소리를 리듬으로 쓴다",
			  "inst": "key", "vol": 0.030, "step": 3, "gate": 1.0,
			  "seq": [1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0] },
			{ "_": "프린터 — 아주 가끔",
			  "inst": "printer", "vol": 0.028, "step": 64, "gate": 6.0,
			  "seq": [1, 0, 0, 1] }
		]
	},

	# §7.2 황소항 — "경쾌하지만 불안한 스윙 리듬. 중간중간 음이 반음씩 미끄러져
	# '뭔가 잘못된 번영' 을 표현한다." 미끄러지는 음은 seq 안에 반음 어긋난 값으로 박아 뒀다.
	"bull_harbor": {
		"bpm": 126,
		"swing": 0.16,
		"loop_sec": 64.0,
		"tracks": [
			{ "inst": "brass", "vol": 0.105, "step": 2, "gate": 1.7,
			  "seq": [60, 64, 67, 64,  65, 64, 62, -1,  60, 63, 67, 66,  69, 67, 64, -1,
					  60, 64, 67, 71,  70, 67, 64, -1,  58, 62, 65, 64,  62, -1, -1, -1] },
			{ "inst": "clarinet", "vol": 0.055, "step": 8, "gate": 7.0,
			  "seq": [72, 71, 75, 74, 72, 70, 67, 68] },
			{ "inst": "bass", "vol": 0.095, "step": 4, "gate": 3.6,
			  "seq": [36, 43, 38, 45,  36, 43, 39, 46] },
			{ "inst": "hat", "vol": 0.030, "step": 2, "gate": 1.0,
			  "seq": [1, 0, 1, 1, 0, 1, 1, 0] },
			{ "inst": "kick", "vol": 0.048, "step": 8, "gate": 2.0,
			  "seq": [1, 0, 1, 0, 1, 0, 1, 1] }
		]
	},

	# §7.2 윤세라 — "짧은 피아노 또는 FM 벨 모티프. 낮은 베이스 위에 날카로운 세 음이 반복된다."
	# 세 음은 76-79-83. 다른 어떤 곡에도 이 세 음을 쓰지 않는다.
	"sera": {
		"bpm": 84,
		"loop_sec": 60.0,
		"tracks": [
			{ "inst": "fm_bell", "vol": 0.115, "step": 6, "gate": 5.0,
			  "seq": [76, 79, 83, -1,  -1, -1, 76, 79,  83, -1, -1, -1,
					  74, 78, 81, -1,  -1, -1, -1, -1] },
			{ "inst": "bass", "vol": 0.090, "step": 32, "gate": 30.0,
			  "seq": [28, 31, 26, 28] },
			{ "inst": "fm_piano", "vol": 0.045, "step": 16, "gate": 12.0,
			  "seq": [64, -1, 62, -1, 59, -1, 62, -1] }
		]
	},

	# 타이틀 — 세라 모티프를 아직 모르는 상태의 곡. 세 음 중 마지막이 빠져 있다.
	"title": {
		"bpm": 72,
		"loop_sec": 60.0,
		"tracks": [
			{ "inst": "fm_piano", "vol": 0.100, "step": 8, "gate": 7.0,
			  "seq": [52, 55, 59, 55,  57, 60, 55, -1] },
			{ "inst": "bass", "vol": 0.080, "step": 32, "gate": 30.0,
			  "seq": [28, 33, 31, 28] },
			{ "inst": "clarinet", "vol": 0.050, "step": 16, "gate": 13.0,
			  "seq": [76, 79, -1, 74] }
		]
	}
}


static func has_song(song_name: String) -> bool:
	return SONGS.has(song_name)


## 곡 하나를 이음매 없이 반복되는 스트림으로 만든다.
static func render(song_name: String) -> AudioStreamWAV:
	if not SONGS.has(song_name):
		return null
	var song: Dictionary = SONGS[song_name]

	var bpm := float(song.get("bpm", 96))
	var sixteenth := 60.0 / bpm / 4.0                 # 16분음표 한 칸의 초
	var swing := float(song.get("swing", 0.0))        # 8분음표 뒷박을 뒤로 미는 비율
	var total := int(float(song.get("loop_sec", 60.0)) * RATE)

	var buf := PackedFloat32Array()
	buf.resize(total)
	buf.fill(0.0)

	var steps := int(ceil(float(song.get("loop_sec", 60.0)) / sixteenth))
	for t in song.get("tracks", []):
		if not (t is Dictionary):
			continue
		_render_track(buf, t, steps, sixteenth, swing, total)

	return _to_stream(buf)


static func _render_track(buf: PackedFloat32Array, track: Dictionary, steps: int,
		sixteenth: float, swing: float, total: int) -> void:
	var seq: Array = track.get("seq", []) if track.get("seq", null) is Array else []
	if seq.is_empty():
		return
	var step_len := maxi(1, int(track.get("step", 4)))
	var inst := str(track.get("inst", "fm_piano"))
	var vol := float(track.get("vol", 0.1))
	var gate := float(track.get("gate", float(step_len) * 0.9))

	var slot := 0
	while slot * step_len < steps:
		var value = seq[slot % seq.size()]
		slot += 1
		var note := int(value)
		if note < 0:
			continue

		var step_index := (slot - 1) * step_len
		var t0 := step_index * sixteenth
		# 스윙 — 8분음표 뒷박만 뒤로 민다. §7.2 황소항의 "경쾌하지만 불안한" 느낌.
		if swing > 0.0 and (step_index / 2) % 2 == 1:
			t0 += sixteenth * swing

		var start := int(t0 * RATE)
		if start >= total:
			break
		var dur := gate * sixteenth
		_render_note(buf, inst, note, start, dur, vol, total)


static func _render_note(buf: PackedFloat32Array, inst: String, note: int,
		start: int, dur: float, vol: float, total: int) -> void:
	var count := int(dur * RATE)
	if count <= 0:
		return
	var freq := 440.0 * pow(2.0, (note - 69) / 12.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d" % [inst, note, start])

	var phase := 0.0
	var mod_phase := 0.0
	for i in count:
		var idx := start + i
		if idx >= total:
			break
		var t := float(i) / float(count)          # 0..1 노트 진행
		var secs := float(i) / float(RATE)
		var v := 0.0

		match inst:
			"fm_piano":
				# 2-op FM. 변조 지수가 빠르게 죽으면서 어택만 밝다. FM 피아노의 기본형.
				var index: float = 2.6 * exp(-secs * 9.0)
				mod_phase += freq / RATE
				phase += freq / RATE
				v = sin(TAU * phase + index * sin(TAU * mod_phase)) * exp(-secs * 3.2)
			"fm_bell":
				# 변조 비율을 정수가 아닌 값으로 두면 금속성 배음이 된다.
				var index_b: float = 3.4 * exp(-secs * 2.2)
				mod_phase += freq * 1.41 / RATE
				phase += freq / RATE
				v = sin(TAU * phase + index_b * sin(TAU * mod_phase)) * exp(-secs * 1.9)
			"clarinet":
				# 홀수 배음만 — 사각파에 가깝지만 듀티를 좁혀 목관 느낌을 낸다.
				phase += freq / RATE
				phase = fposmod(phase, 1.0)
				var env_c: float = minf(1.0, secs * 12.0) * (1.0 - t * 0.55)
				v = (1.0 if phase < 0.34 else -1.0) * env_c * 0.55
			"brass":
				# 살짝 흔들리는 펄스. §7.1 "브라스"
				var vib: float = 1.0 + sin(TAU * 5.5 * secs) * 0.006
				phase += freq * vib / RATE
				phase = fposmod(phase, 1.0)
				var env_br: float = minf(1.0, secs * 26.0) * (1.0 - t * 0.7)
				v = (1.0 if phase < 0.26 else -1.0) * env_br * 0.6
			"bass":
				# 칩 베이스. 저역은 사각파가 제일 또렷하다.
				phase += freq / RATE
				phase = fposmod(phase, 1.0)
				var env_bs: float = minf(1.0, secs * 40.0) * (1.0 - t * 0.35)
				v = (1.0 if phase < 0.5 else -1.0) * env_bs * 0.5
			"key":
				# 키보드 타건 — 아주 짧은 노이즈. §7.2 기관성의 '리듬'
				v = rng.randf_range(-1.0, 1.0) * exp(-secs * 90.0)
			"printer":
				# 프린터 — 노이즈를 일정 간격으로 끊어 낸다
				var on: bool = fmod(secs, 0.045) < 0.020
				v = (rng.randf_range(-1.0, 1.0) if on else 0.0) * exp(-secs * 1.6)
			"hat":
				v = rng.randf_range(-1.0, 1.0) * exp(-secs * 120.0)
			"kick":
				var f_k: float = lerpf(120.0, 45.0, minf(1.0, secs * 18.0))
				phase += f_k / RATE
				phase = fposmod(phase, 1.0)
				v = (1.0 if phase < 0.5 else -1.0) * exp(-secs * 22.0)
			_:
				phase += freq / RATE
				phase = fposmod(phase, 1.0)
				v = (1.0 if phase < 0.5 else -1.0) * (1.0 - t)

		buf[idx] = buf[idx] + v * vol


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		# 소프트 클리핑 — 트랙이 겹쳐 1.0 을 넘어도 딱딱하게 잘리지 않게 한다.
		var s: float = buf[i]
		s = s / (1.0 + absf(s) * 0.6)
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	# 이음매 없는 반복. 루프 길이를 마디에 맞춰 잡았으므로 그대로 이어 붙으면 된다.
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()
	return wav
