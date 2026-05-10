# RoomDecorator - Places 3D model decorations on the interior surface of sphere rooms
# Uses a dead-simple approach: place model, look_at center, rotate so Y=up toward center.
class_name RoomDecorator
extends RefCounted

class ModelEntry:
	var path: String
	var min_scale: float
	var max_scale: float
	var weight: float
	var categories: Array
	func _init(p: String, min_s: float, max_s: float, w: float, cats: Array) -> void:
		path = p; min_scale = min_s; max_scale = max_s; weight = w; categories = cats

var model_catalog: Array = []
var _scene_cache: Dictionary = {}

const ROOM_NORMAL := 0
const ROOM_BOSS := 1
const ROOM_ITEM := 2
const ROOM_SHOP := 3
const ROOM_GAMBLING := 4
const ROOM_SPECIAL := 5

var decoration_profiles: Dictionary = {
	ROOM_NORMAL: { "density": 1.0, "categories": ["tree", "rock", "structure"], "structure_chance": 0.15 },
	ROOM_BOSS: { "density": 0.3, "categories": ["rock"], "structure_chance": 0.0 },
	ROOM_ITEM: { "density": 0.5, "categories": ["rock", "structure"], "structure_chance": 0.8 },
	ROOM_SHOP: { "density": 0.6, "categories": ["structure", "rock"], "structure_chance": 0.9 },
	ROOM_GAMBLING: { "density": 0.4, "categories": ["rock"], "structure_chance": 0.3 },
	ROOM_SPECIAL: { "density": 2.0, "categories": ["tree", "rock"], "structure_chance": 0.05 },
}

const MIN_DECORATION_SPACING: float = 3.0
const MIN_PORTAL_DISTANCE: float = 6.0

## How far inside the wall to place model origins (units from wall toward center)
const WALL_INSET: float = 1.0

func _init() -> void:
	_build_model_catalog()

func _build_model_catalog() -> void:
	# Scale = target visual height in game units (auto-calculated from room radius later)
	# These are relative weights - actual scale is computed per-room
	model_catalog = [
		ModelEntry.new("res://resources/Models/oaktree.glb", 0.15, 0.3, 3.0, ["tree", "nature"]),
		ModelEntry.new("res://resources/Models/pinetree.glb", 0.15, 0.3, 3.0, ["tree", "nature"]),
		ModelEntry.new("res://resources/Models/minipinetree.glb", 0.1, 0.2, 4.0, ["tree", "nature"]),
		ModelEntry.new("res://resources/Models/single rock.glb", 0.05, 0.12, 5.0, ["rock", "nature"]),
		ModelEntry.new("res://resources/Models/small rock cluster.glb", 0.05, 0.12, 3.0, ["rock", "nature"]),
		ModelEntry.new("res://resources/Models/big rock cluster.glb", 0.08, 0.15, 2.0, ["rock", "nature"]),
		ModelEntry.new("res://resources/Models/House1.1.glb", 0.1, 0.2, 1.5, ["structure"]),
		ModelEntry.new("res://resources/Models/house2.2.glb", 0.1, 0.2, 1.5, ["structure"]),
		ModelEntry.new("res://resources/Models/well.glb", 0.05, 0.1, 2.0, ["structure"]),
	]

func _get_model_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var resource = load(path)
	if resource == null or not resource is PackedScene:
		push_warning("[RoomDecorator] Failed to load: %s" % path)
		return null
	_scene_cache[path] = resource
	return resource

func decorate_room(room: Node, room_type: int, portal_positions: Array) -> void:
	var room_radius: float = room.radius if room.get("radius") else 20.0
	var room_center: Vector3 = room.global_position
	
	var profile: Dictionary = decoration_profiles.get(room_type, decoration_profiles[ROOM_NORMAL])
	var density: float = profile["density"]
	var allowed_categories: Array = profile["categories"]
	var structure_chance: float = profile["structure_chance"]
	
	var total_count: int = clampi(int(ceil(floor(room_radius / 5.0) * density)), 1, 25)
	
	var available_models: Array = _filter_models(allowed_categories)
	if available_models.is_empty():
		return
	
	var structure_models: Array = _filter_models(["structure"])
	var nature_models: Array = []
	for m in available_models:
		var is_struct := false
		for c in m.categories:
			if c == "structure":
				is_struct = true
				break
		if not is_struct:
			nature_models.append(m)
	
	var placed: Array = []
	var portal_dirs: Array = []
	for pp in portal_positions:
		var d: Vector3 = (pp - room_center)
		if d.length_squared() > 0.01:
			portal_dirs.append(d.normalized())
	
	# Maybe place a structure
	var placed_count: int = 0
	if structure_models.size() > 0 and randf() < structure_chance:
		var pos = _find_surface_point(room_center, room_radius, portal_dirs, placed, 20)
		if pos != Vector3.ZERO:
			_place_model(room, _weighted_pick(structure_models), pos, room_center, room_radius)
			placed.append(pos)
			placed_count += 1
	
	# Place nature decorations
	var models_to_use: Array = nature_models if nature_models.size() > 0 else available_models
	for i in range(total_count - placed_count):
		var pos = _find_surface_point(room_center, room_radius, portal_dirs, placed, 15)
		if pos == Vector3.ZERO:
			continue
		_place_model(room, _weighted_pick(models_to_use), pos, room_center, room_radius)
		placed.append(pos)
	
	print("[RoomDecorator] %s: %d models placed (type=%d)" % [room.name, placed.size(), room_type])

func _find_surface_point(center: Vector3, radius: float, portal_dirs: Array, placed: Array, attempts: int) -> Vector3:
	for _i in range(attempts):
		var dir := Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)).normalized()
		var pt: Vector3 = center + dir * (radius - WALL_INSET)
		
		var blocked := false
		for pd in portal_dirs:
			if dir.angle_to(pd) * radius < MIN_PORTAL_DISTANCE:
				blocked = true
				break
		if blocked:
			continue
		
		for op in placed:
			if pt.distance_to(op) < MIN_DECORATION_SPACING:
				blocked = true
				break
		if blocked:
			continue
		return pt
	return Vector3.ZERO

## Simple placement: wrapper Node3D on surface, Y toward center, model as child.
func _place_model(room: Node, model: ModelEntry, surface_pos: Vector3, room_center: Vector3, room_radius: float) -> void:
	var scene: PackedScene = _get_model_scene(model.path)
	if not scene:
		return
	var instance: Node3D = scene.instantiate()
	if not instance:
		return
	
	var scale_val: float = room_radius * randf_range(model.min_scale, model.max_scale)
	
	# Local position relative to room center (room is the parent node)
	var local_pos: Vector3 = surface_pos - room.global_position
	
	# "Up" = from surface toward center = -local_pos direction
	var up: Vector3 = -local_pos.normalized()
	
	# Build orthonormal basis with Y = up (toward center)
	var ref: Vector3 = Vector3.FORWARD
	if abs(up.dot(ref)) > 0.9:
		ref = Vector3.RIGHT
	var right: Vector3 = up.cross(ref).normalized()
	var forward: Vector3 = right.cross(up).normalized()
	
	# Random spin around Y (toward-center axis)
	var angle: float = randf() * TAU
	var r: Vector3 = right * cos(angle) + forward * sin(angle)
	var f: Vector3 = -right * sin(angle) + forward * cos(angle)
	
	# Wrapper handles position + orientation + scale
	var wrapper := Node3D.new()
	wrapper.name = "Decor_%d" % (randi() % 99999)
	wrapper.position = local_pos
	wrapper.basis = Basis(r, up, -f)
	wrapper.scale = Vector3.ONE * scale_val
	
	# Model as child — reset its root transform so only wrapper controls orientation.
	# Child meshes inside the GLB keep their own relative transforms.
	instance.transform = Transform3D.IDENTITY
	room.add_child(wrapper)
	wrapper.add_child(instance)
	
	print("[RoomDecorator] Placed %s scale=%.1f" % [model.path.get_file(), scale_val])

func _filter_models(categories: Array) -> Array:
	var result: Array = []
	for m in model_catalog:
		for c in m.categories:
			if c in categories:
				result.append(m)
				break
	return result

func _weighted_pick(models: Array) -> ModelEntry:
	if models.is_empty():
		return model_catalog[0]
	var total: float = 0.0
	for m in models:
		total += m.weight
	var roll: float = randf() * total
	var cum: float = 0.0
	for m in models:
		cum += m.weight
		if roll <= cum:
			return m
	return models[models.size() - 1]
