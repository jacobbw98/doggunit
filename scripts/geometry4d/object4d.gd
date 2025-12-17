# Object4D - Base class for all 4D objects
# Extends Node3D for scene integration but tracks 4D position/rotation
class_name Object4D
extends Node3D

## 4D position of this object
@export var position_4d: Vector4 = Vector4.ZERO:
	set(value):
		position_4d = value
		_position_4d = Vector4D.from_vector4(value)
		_sync_to_3d()

## 4D scale of this object
@export var scale_4d: Vector4 = Vector4.ONE:
	set(value):
		scale_4d = value
		_scale_4d = Vector4D.from_vector4(value)

## Internal Vector4D representation
var _position_4d: Vector4D = Vector4D.zero()
var _rotation_4d: Isocline = Isocline.identity()
var _scale_4d: Vector4D = Vector4D.one()

## The current W-slice coordinate for rendering
var current_slice_w: float = 0.0

## If true, object is visible in current slice
var is_in_slice: bool = true

## Ghost projection mode (shows transparent ghost when off-slice)
var ghost_enabled: bool = false
var ghost_mesh: MeshInstance3D = null

## Slice visibility threshold (how close to slice to be visible)
@export var slice_threshold: float = 0.5

signal slice_visibility_changed(is_visible: bool)
signal position_4d_changed(new_pos: Vector4D)

func _ready() -> void:
	_position_4d = Vector4D.from_vector4(position_4d)
	_scale_4d = Vector4D.from_vector4(scale_4d)
	add_to_group("objects_4d")
	
	# Auto-register with any Slicer4D in the scene
	call_deferred("_register_with_slicer")
	
	# Check global ghost mode from debug console
	call_deferred("_check_global_ghost_mode")

## Check if ghost mode is globally enabled and apply it
func _check_global_ghost_mode() -> void:
	var console = get_tree().get_first_node_in_group("debug_console")
	if console and console.get("ghost_enabled"):
		set_ghost_mode(true)

# Get 4D position as Vector4D
func get_position_4d() -> Vector4D:
	return _position_4d

# Set 4D position
func set_position_4d(pos: Vector4D) -> void:
	_position_4d = pos
	position_4d = pos.to_vector4()
	_sync_to_3d()
	position_4d_changed.emit(pos)

# Get 4D rotation
func get_rotation_4d() -> Isocline:
	return _rotation_4d

# Set 4D rotation
func set_rotation_4d(rot: Isocline) -> void:
	_rotation_4d = rot
	_sync_to_3d()

# Get 4D scale
func get_scale_4d() -> Vector4D:
	return _scale_4d

# Set 4D scale
func set_scale_4d(s: Vector4D) -> void:
	_scale_4d = s
	scale_4d = s.to_vector4()

# Get full 4D transform
func get_transform_4d() -> Transform4D:
	return Transform4D.from_rotation_translation_scale(
		_rotation_4d.to_matrix(),
		_position_4d,
		_scale_4d
	)

# Update slice visibility
func update_slice(slice_w: float) -> void:
	current_slice_w = slice_w
	var w_distance: float = abs(_position_4d.w - slice_w)
	var was_visible: bool = is_in_slice
	is_in_slice = w_distance <= slice_threshold
	
	if is_in_slice != was_visible:
		slice_visibility_changed.emit(is_in_slice)
		_update_visibility()
	
	# Update ghost projection
	_update_ghost_visibility(w_distance)

# Sync 4D position to 3D representation
func _sync_to_3d() -> void:
	# Project 4D position to 3D (XYZ components)
	global_position = _position_4d.to_vector3()
	
	# Update visibility based on W distance from current slice
	_update_visibility()

func _update_visibility() -> void:
	# Main mesh visibility based on W-slice intersection
	visible = is_in_slice

## Set ghost projection mode - called by debug console
func set_ghost_mode(enabled: bool) -> void:
	ghost_enabled = enabled
	if not ghost_enabled and ghost_mesh:
		ghost_mesh.visible = false
	# Force visibility update
	var w_distance: float = abs(_position_4d.w - current_slice_w)
	_update_ghost_visibility(w_distance)

## Update ghost mesh visibility when object is off-slice
func _update_ghost_visibility(w_distance: float) -> void:
	if not ghost_enabled:
		if ghost_mesh:
			ghost_mesh.visible = false
		return
	
	# Show ghost when object is at least partially outside slice
	# Ghost fades in as the real object fades out
	var ghost_threshold := slice_threshold * 0.3  # Start showing ghost earlier
	
	if w_distance < ghost_threshold:
		# Object is mostly in slice - hide ghost
		if ghost_mesh:
			ghost_mesh.visible = false
	else:
		# Object is partially or fully off-slice - show ghost projection
		if not ghost_mesh:
			_create_ghost_mesh()
		if ghost_mesh:
			ghost_mesh.visible = true
			# Ghost shows at full size regardless of W-distance
			ghost_mesh.global_position = _position_4d.to_vector3()
			
			# Adjust ghost opacity based on how far off-slice
			var alpha: float = clamp((w_distance - ghost_threshold) / (slice_threshold - ghost_threshold), 0.1, 0.4)
			var mat: StandardMaterial3D = ghost_mesh.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = alpha

## Create ghost mesh (transparent wireframe-like version)
## Subclasses should override this to create a proper full-shape ghost projection
func _create_ghost_mesh() -> void:
	# Default implementation: try to copy child mesh
	# Subclasses should override to create full-shape projection meshes
	for child in get_children():
		if child is MeshInstance3D and child != ghost_mesh:
			ghost_mesh = MeshInstance3D.new()
			# Duplicate the mesh to avoid sharing with the original
			if child.mesh:
				ghost_mesh.mesh = child.mesh.duplicate()
			ghost_mesh.name = "GhostMesh_" + name
			_apply_ghost_material(ghost_mesh)
			
			# Add to scene root instead of as child, so hiding parent doesn't hide ghost
			if get_tree() and get_tree().root:
				get_tree().root.add_child(ghost_mesh)
			break

## Apply the standard ghost material to a mesh instance
func _apply_ghost_material(mesh_inst: MeshInstance3D) -> void:
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.5)  # Blue ghost color
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_mat.no_depth_test = true  # Always visible through geometry
	mesh_inst.material_override = ghost_mat

# Get signed distance from this object's center to a point in 4D
# Override in subclasses for specific shapes
func get_signed_distance(point: Vector4D) -> float:
	return Vector4D.distance(point, _position_4d)

# Get surface normal at a point (for collision/gravity)
# Override in subclasses
func get_surface_normal(point: Vector4D) -> Vector4D:
	return point.subtract(_position_4d).normalized()

# Project a point onto this object's surface
# Override in subclasses
func project_to_surface(point: Vector4D) -> Vector4D:
	return _position_4d

# Register with any Slicer4D in the scene
func _register_with_slicer() -> void:
	var slicer: Node = null
	
	# Find existing Slicer4D
	var slicers = get_tree().get_nodes_in_group("slicer_4d")
	if slicers.size() > 0:
		slicer = slicers[0]
	
	# If no slicer exists, create one
	if not slicer:
		slicer = Slicer4D.new()
		slicer.name = "AutoSlicer4D"
		get_tree().current_scene.add_child(slicer)
		print("[Object4D] Created Slicer4D automatically")
	
	# Register this object
	if slicer.has_method("register_object"):
		slicer.register_object(self)
		print("[Object4D] Registered %s with Slicer4D" % name)
