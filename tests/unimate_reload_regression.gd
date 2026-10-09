extends SceneTree

const MOTION := preload("res://scripts/weapons/dog_reload_motion.gd")
const MOTION_PATH := "res://assets/dogs/animations/reload_motion.json"

class CosmeticRun:
	extends Node
	func get_item_count(id: String, _gun_id: int = -1) -> int:
		return 2 if id in ["tennis", "tag"] else 0
	func get_stat_bonus(_stat: String, _type: int = -1, _gun_id: int = -1) -> float:
		return 0.0
	func get_stat_multiplier(_stat: String, _type: int = -1, _gun_id: int = -1) -> float:
		return 1.0
	func get_all_stats_factor(_gun_id: int = -1) -> float:
		return 1.0

var failures: Array[String] = []
var clips: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	check(FileAccess.file_exists(MOTION_PATH), "Offline UniMate motion is bundled with the game")
	if not FileAccess.file_exists(MOTION_PATH):
		quit(1)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
	check(data is Dictionary, "Motion artifact parses as a JSON document")
	if not data is Dictionary:
		quit(1)
		return
	_test_source_data(data)
	_test_sampler()
	var run := CosmeticRun.new()
	root.add_child(run)
	run.add_to_group("run_manager")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1729
	for definition in DogBreeds.CATALOG:
		var stats := DogBreeds.create_stats(rng, definition.id)
		await _test_native_reload(stats, definition.id == "xoloitzcuintli")
	for mascot in [true, false]:
		var stats := GunStats.new()
		stats.gun_name = "Mappo" if mascot else "Freezing Pup"
		stats.mascot_visual = mascot
		await _test_native_reload(stats, false)
	_test_cosmetic_refresh_during_reload(rng)
	run.free()
	print("UNIMATE RELOAD: %d failures; source provenance/hashes, 180 finite frames, interpolation, all 20 breed heads, two starter models, following stacked cosmetics, paused progress and neutral completion/refill" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _test_source_data(data: Dictionary) -> void:
	check(data.get("format", "") == "doggunit-unimate-reload/1", "Motion artifact declares its retargeted data format")
	var provenance: Dictionary = data.get("provenance", {})
	check(provenance.get("generator", "") == "UniMate", "Motion identifies its actual generator")
	for field in ["repository", "checkpoint", "checkpoint_url", "inference_device", "source_rig", "retarget", "runtime", "code_license", "checkpoint_license"]:
		check(not String(provenance.get(field, "")).is_empty(), "Motion provenance includes " + field)
	check(FileAccess.file_exists("res://assets/dogs/animations/source/generation_manifests.json"), "Original inference manifests accompany the motion")
	check(FileAccess.file_exists("res://assets/dogs/animations/source/retarget_unimate.py"), "Editable retargeting source accompanies the motion")
	clips = data.get("clips", [data] if data.has("frames") else [])
	check(clips.size() == 3, "Three independently prompted source motions are bundled")
	for clip in clips:
		var source: Dictionary = clip.get("source", {})
		check(not String(source.get("prompt", "")).is_empty() and source.has("seed"), "Each clip preserves its inference prompt and seed: " + clip.id)
		var source_path := "res://assets/dogs/animations/" + String(source.get("source_file", ""))
		check(FileAccess.file_exists(source_path), "Original generated NumPy motion is preserved: " + clip.id)
		if FileAccess.file_exists(source_path):
			check(FileAccess.get_sha256(source_path) == source.get("sha256", ""), "Preserved generated source matches its SHA256: " + clip.id)
		var frames: Array = clip.get("frames", [])
		check(frames.size() == 60 and int(clip.get("fps", 0)) == 30 and is_equal_approx(float(clip.get("duration_seconds", 0.0)), 2.0), "Generated motion has 60 frames at 30 fps: " + clip.id)
		var peak := 0.0
		for i in range(frames.size()):
			var frame: Dictionary = frames[i]
			check(is_equal_approx(float(frame.time), float(i) / 59.0), "Frame time advances from zero to one: %s/%d" % [clip.id, i])
			for field in ["head_rotation", "body_rotation"]:
				var rotation: Array = frame.get(field, [])
				check(rotation.size() == 3, "Motion rotation contains three components: %s/%s/%d" % [clip.id, field, i])
				for component in rotation:
					check(is_finite(float(component)), "Motion components remain finite: %s/%s/%d" % [clip.id, field, i])
				if rotation.size() == 3:
					peak = maxf(peak, _vector(rotation).length())
		check(peak > 0.1, "Generated clip contains substantial motion: " + clip.id)
		if not frames.is_empty():
			check(_vector(frames[0].head_rotation).is_zero_approx() and _vector(frames[0].body_rotation).is_zero_approx(), "Retargeted source begins at neutral pose: " + clip.id)

func _test_sampler() -> void:
	if clips.is_empty():
		return
	for definition in DogBreeds.CATALOG:
		var id: String = definition.id
		var clip: Dictionary = clips[abs(hash(id)) % clips.size()]
		var progress := 1.0 / 3.0
		var index := progress * 59.0
		var left := floori(index)
		var right := ceili(index)
		var sample := MOTION.sample(progress, id)
		check(not sample.is_empty(), "Bundled motion samples without Python or a checkpoint: " + id)
		if sample.is_empty():
			continue
		for field in ["head_rotation", "body_rotation"]:
			var expected := _vector(clip.frames[left][field]).lerp(_vector(clip.frames[right][field]), index - left)
			check(sample[field].is_equal_approx(expected), "Adapter interpolates actual source frames: %s/%s" % [id, field])
		check(not MOTION.sample(0.15, id).head_rotation.is_equal_approx(MOTION.sample(0.65, id).head_rotation), "Normalized reload progress samples different generated poses: " + id)

func _test_native_reload(stats: GunStats, test_pause: bool) -> void:
	stats.reload_seconds = 1.2
	var gun := Gun.new()
	gun.stats = stats
	gun.transform = Transform3D(Basis.from_euler(Vector3(0.05, -0.07, 0.03)), Vector3(0.12, -0.16, -0.3))
	root.add_child(gun)
	gun.set_process(false)
	var baseline := gun.transform
	var head := gun.breed_model.find_child("HeadRoot", true, false) as Node3D if is_instance_valid(gun.breed_model) else null
	var head_basis := head.basis if head else Basis.IDENTITY
	var attachment_baselines: Array[Dictionary] = []
	for attachment in gun.get_node("ItemAttachments").get_children():
		if head and (str(attachment.name).begins_with("MouthBall_") or str(attachment.name).begins_with("Glasses_")):
			attachment_baselines.append({"node":attachment, "transform":attachment.transform, "head_relative":head.global_transform.affine_inverse() * attachment.global_transform})
	gun.current_ammo = 1
	gun.reload()
	gun._process(0.4)
	var id := stats.breed_id if not stats.breed_id.is_empty() else stats.gun_name
	var sample := MOTION.sample(1.0 / 3.0, id)
	var envelope := sin(PI / 3.0)
	check(not gun.transform.is_equal_approx(baseline) and gun.current_ammo == 1, "Native timed reload animates without granting ammo early: " + id)
	if not sample.is_empty():
		var expected_pitch: float = sample.body_rotation.x * envelope
		if head:
			check(head.basis.is_equal_approx(head_basis * Basis.from_euler(sample.head_rotation * envelope)) and not head.basis.is_equal_approx(head_basis), "Native breed head consumes the generated pose: " + id)
		else:
			expected_pitch += sample.head_rotation.x * envelope
		var actual_pitch := (baseline.basis.inverse() * gun.basis).get_euler().x
		check(is_equal_approx(actual_pitch, expected_pitch), "Native held body consumes generated bow pitch: " + id)
	for fixture in attachment_baselines:
		check(not fixture.node.transform.is_equal_approx(fixture.transform) and (head.global_transform.affine_inverse() * fixture.node.global_transform).is_equal_approx(fixture.head_relative), "Stacked mouth/glasses cosmetics follow animated head: %s/%s" % [id, fixture.node.name])
	if test_pause:
		gun.set_process(true)
		await process_frame
		paused = true
		var remaining := gun.reload_remaining
		var pose := gun.transform
		var head_pose := head.basis
		for frame in range(3):
			await process_frame
		check(is_equal_approx(gun.reload_remaining, remaining) and gun.transform.is_equal_approx(pose) and head.basis.is_equal_approx(head_pose), "SceneTree pause freezes sampled head/body pose and reload progress")
		gun.set_process(false)
		paused = false
	gun._process(gun.reload_remaining)
	_check_neutral(gun, baseline, head, head_basis, attachment_baselines, "completion")
	gun.current_ammo = 1
	gun.reload()
	gun._process(0.6)
	gun.refill_magazine()
	_check_neutral(gun, baseline, head, head_basis, attachment_baselines, "refill")
	gun.free()

func _check_neutral(gun: Gun, baseline: Transform3D, head: Node3D, head_basis: Basis, attachments: Array[Dictionary], event: String) -> void:
	check(not gun.is_reloading and gun.current_ammo == gun.get_magazine_size() and gun.transform.is_equal_approx(baseline), "Reload %s restores full magazine and exact held baseline: %s" % [event, gun.stats.gun_name])
	if head:
		check(head.basis.is_equal_approx(head_basis), "Reload %s returns the animated head to neutral: %s" % [event, gun.stats.breed_id])
	for fixture in attachments:
		check(fixture.node.transform.is_equal_approx(fixture.transform), "Reload %s restores attachment baseline: %s/%s" % [event, gun.stats.breed_id, fixture.node.name])

func _test_cosmetic_refresh_during_reload(rng: RandomNumberGenerator) -> void:
	# Picking up items or transferring a breed through a drop stand rebuilds its
	# cosmetics while the existing dog's ammo and reload timer keep running.
	var gun := Gun.new()
	gun.stats = DogBreeds.create_stats(rng, "xoloitzcuintli")
	gun.stats.reload_seconds = 1.2
	root.add_child(gun)
	gun.set_process(false)
	var head := gun.breed_model.find_child("HeadRoot", true, false) as Node3D
	var neutral: Dictionary = {}
	for part in gun.get_node("ItemAttachments").get_children():
		neutral[str(part.name)] = part.transform
	gun.current_ammo = 1
	gun.reload()
	gun._process(0.4)
	gun.refresh_item_visuals()
	var refreshed: Array[Dictionary] = []
	for part in gun.get_node("ItemAttachments").get_children():
		refreshed.append({"node":part, "head_relative":head.global_transform.affine_inverse() * part.global_transform})
	gun._process(0.1)
	for fixture in refreshed:
		check((head.global_transform.affine_inverse() * fixture.node.global_transform).is_equal_approx(fixture.head_relative), "Rebuilt cosmetics continue following an active reload: " + str(fixture.node.name))
	gun._process(gun.reload_remaining)
	for fixture in refreshed:
		check(fixture.node.transform.is_equal_approx(neutral[str(fixture.node.name)]), "Rebuilt cosmetics finish at their neutral anchor: " + str(fixture.node.name))
	gun.free()
