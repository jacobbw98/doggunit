@tool
class_name GeneratedMascot
extends Node3D
## Adapter for an imported mascot. Forward is -Z; paws rest at Y=0.
## Imported geometry and materials are preserved; no procedural substitute is built.

@export var model: PackedScene
@export var model_yaw_degrees: float = 0.0
@export_range(0.01, 10.0, 0.01) var target_height: float = 1.46
## Optional framing adjustment in normalized mascot units, after grounding/centering.
@export var model_offset: Vector3 = Vector3.ZERO
@export var animate: bool = true
@export var idle_strength: float = 1.0
## Optional matte finish for generated PBR assets used as cartoon characters.
@export var cartoon_materials: bool = false

var body_root: Node3D
var imported_model: Node
var source_bounds := AABB()
var normalized_bounds := AABB()
var normalization_scale: float = 1.0
var mesh_count: int = 0
var _has_mesh_bounds: bool = false
var _time: float = 0.0
var _bark_time: float = 0.0
var _shoot_player: AnimationPlayer
var _shoot_animation: StringName
var _neck_extension := 0.0
var _neck_materials: Array = []
const SHOOT_ANIMATION := "Mappo_Shoot"


func _ready() -> void:
	rebuild_model()


## Call after changing the model or its adapter settings on an existing instance.
func rebuild_model() -> void:
	if is_instance_valid(body_root):
		remove_child(body_root)
		body_root.queue_free()
	body_root = Node3D.new()
	body_root.name = "BodyRoot"
	add_child(body_root)
	imported_model = null
	source_bounds = AABB()
	normalized_bounds = AABB()
	normalization_scale = 1.0
	mesh_count = 0
	_has_mesh_bounds = false
	_time = 0.0
	_bark_time = 0.0
	_shoot_player = null
	_shoot_animation = &""
	if model == null:
		return
	var placement := Node3D.new()
	placement.name = "ModelPlacement"
	body_root.add_child(placement)
	var orientation := Node3D.new()
	orientation.name = "ModelOrientation"
	orientation.rotation_degrees.y = model_yaw_degrees
	placement.add_child(orientation)
	imported_model = model.instantiate()
	orientation.add_child(imported_model)
	_find_shoot_animation(imported_model)
	if cartoon_materials:
		_soften_materials(imported_model)
	# Include the imported root transform and every nested transform. Resetting a
	# glTF root can discard its original axis correction, scale, or mesh placement.
	_accumulate_bounds(orientation, Transform3D.IDENTITY)
	if not _has_mesh_bounds or source_bounds.size.y <= 0.00001:
		push_warning("Generated mascot has no mesh bounds with a usable height.")
		return
	normalization_scale = maxf(target_height, 0.01) / source_bounds.size.y
	placement.scale = Vector3.ONE * normalization_scale
	var center := source_bounds.get_center()
	placement.position = -Vector3(center.x, source_bounds.position.y, center.z) * normalization_scale + model_offset
	normalized_bounds = placement.transform * source_bounds


func _soften_materials(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var source := instance.get_active_material(surface)
			if source is StandardMaterial3D:
				# Keep embedded color/normal textures and leave the imported resource
				# intact. Generated metallic values can otherwise make fur look silver.
				var material := source.duplicate() as StandardMaterial3D
				material.metallic = 0.0
				material.metallic_texture = null
				material.metallic_specular = 0.0 if source.resource_name.to_lower().contains("whiskers") else 0.2
				material.roughness = 0.85
				material.roughness_texture = null
				material.normal_scale = 0.35
				instance.set_surface_override_material(surface, material)
	for child in node.get_children():
		_soften_materials(child)


func _accumulate_bounds(node: Node, parent_transform: Transform3D) -> void:
	var relative_transform := parent_transform
	if node is Node3D:
		relative_transform *= (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var bounds := relative_transform * (node as MeshInstance3D).mesh.get_aabb()
		source_bounds = source_bounds.merge(bounds) if _has_mesh_bounds else bounds
		_has_mesh_bounds = true
		mesh_count += 1
	for child in node.get_children():
		_accumulate_bounds(child, relative_transform)


func _find_shoot_animation(node: Node) -> void:
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		for animation_name in player.get_animation_list():
			# Imported clips can be qualified by their AnimationLibrary name.
			if animation_name == SHOOT_ANIMATION or String(animation_name).ends_with("/" + SHOOT_ANIMATION):
				_shoot_player = player
				_shoot_animation = animation_name
				return
	for child in node.get_children():
		_find_shoot_animation(child)
		if is_instance_valid(_shoot_player):
			return


## Gun calls this for every successful shot, including when idle motion is off.
func bark() -> void:
	_bark_time = 0.30
	if is_instance_valid(_shoot_player) and _shoot_player.has_animation(_shoot_animation):
		# Repeated shots restart the jaw cycle instead of resuming a playing clip.
		_shoot_player.stop()
		_shoot_player.play(_shoot_animation, 0.0)
		_shoot_player.advance(0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(body_root):
		return
	_time += delta
	_bark_time = maxf(_bark_time - delta, 0.0)
	var idle := maxf(idle_strength, 0.0) if animate else 0.0
	var pulse := sin((_bark_time / 0.30) * PI) if _bark_time > 0.0 else 0.0
	body_root.scale = Vector3(1.0, 1.0 + sin(_time * 1.9) * 0.006 * idle + pulse * 0.012, 1.0)
	body_root.rotation.x = pulse * 0.025
	for entry in _neck_materials:
		if is_instance_valid(entry[0]):
			entry[1].set_shader_parameter("mesh_to_mascot", global_transform.affine_inverse() * entry[0].global_transform)

func set_neck_extension(amount: float) -> void:
	_neck_extension = amount
	if _neck_materials.is_empty():
		for mesh in body_root.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				var source := mesh.get_active_material(surface) as StandardMaterial3D
				if source == null:
					continue
				var mat := ShaderMaterial.new()
				mat.shader = load("res://resources/shaders/spring_neck.gdshader")
				mat.set_shader_parameter("fur_color", source.albedo_color)
				if source.albedo_texture:
					mat.set_shader_parameter("fur_texture", source.albedo_texture)
				mat.set_shader_parameter("mesh_to_mascot", global_transform.affine_inverse() * mesh.global_transform)
				_neck_materials.append([mesh, mat, source, surface])
	for entry in _neck_materials:
		entry[1].set_shader_parameter("extension", amount)
		entry[0].set_surface_override_material(entry[3], entry[1] if amount > 0.0 else entry[2])
