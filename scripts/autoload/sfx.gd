extends Node
## 音效播放。MVP 只有 2 個音效（GDD 11.3）：shoot、pickup。
##
## 用法：Sfx.play(&"shoot")。檔案放在 res://assets/audio/<name>.wav，不存在時靜默略過。

const VOICES := 8
## 同一個音效在這個間隔內重複觸發只播放一次，避免連射時疊音。
const MIN_INTERVAL := 0.06

var _streams := {}
var _last_played := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: StringName, volume_db := 0.0) -> void:
	var stream := _get_stream(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(sound, -1.0) < MIN_INTERVAL:
		return
	_last_played[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db
	p.play()


func _get_stream(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		var path := "res://assets/audio/%s.wav" % sound
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]
