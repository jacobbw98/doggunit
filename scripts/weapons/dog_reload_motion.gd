extends RefCounted
## Offline UniMate motion is sampled at normalized reload progress. Runtime
## playback needs no Python, GPU, checkpoint, network or model inference.
const MOTION_PATH := "res://assets/dogs/animations/reload_motion.json"
const MOTION_DATA := preload("res://assets/dogs/animations/reload_motion_data.gd")
static var _clips: Array = []
static var _loaded := false

static func _load_clips() -> void:
	if _loaded:
		return
	_loaded = true
	var data = JSON.parse_string(MOTION_DATA.JSON_TEXT)
	if data is Dictionary:
		if data.has("clips"):
			_clips = data.clips
		elif data.has("frames"):
			_clips = [data]

static func sample(progress: float, dog_id: String) -> Dictionary:
	_load_clips()
	if _clips.is_empty():
		return {}
	var clip: Dictionary = _clips[abs(hash(dog_id)) % _clips.size()]
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		return {}
	var index := clampf(progress, 0.0, 1.0) * (frames.size() - 1)
	var left := floori(index)
	var right := mini(left + 1, frames.size() - 1)
	var result := {}
	for key in ["head_rotation", "body_rotation"]:
		var a: Array = frames[left].get(key, [0.0, 0.0, 0.0])
		var b: Array = frames[right].get(key, [0.0, 0.0, 0.0])
		result[key] = Vector3(float(a[0]), float(a[1]), float(a[2])).lerp(Vector3(float(b[0]), float(b[1]), float(b[2])), index - left)
	return result
