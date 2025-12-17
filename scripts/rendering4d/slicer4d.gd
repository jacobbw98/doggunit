# Slicer4D - Controls the 3D slice plane through 4D space
# Manages which W-coordinate we're viewing and updates all 4D objects
class_name Slicer4D
extends Node

## Current W-coordinate of the slice plane (smoothed)
@export var slice_w: float = 0.0:
	set(value):
		slice_w = value
		_update_all_slices()

## Target W-coordinate (where we're scrolling toward)
var target_w: float = 0.0

## W movement speed when using scroll wheel in debug mode
@export var scroll_speed: float = 0.5  # Smaller for finer control

## Smoothing time (seconds to reach target - higher = smoother)
@export var smooth_time: float = 0.3

## Enable scroll wheel W movement (set by debug console "4d" command)
var scroll_4d_enabled: bool = false

## Enable dynamic W limits based on objects
@export var use_dynamic_limits: bool = true

## Padding beyond object bounds
@export var limit_padding: float = 2.0

## All tracked 4D objects
var objects_4d: Array[Object4D] = []

## Accumulated scroll input (for smoothing notched scroll wheels)
var _scroll_accumulator: float = 0.0

## Time since last scroll (for accumulator decay)
var _time_since_scroll: float = 0.0

## Scroll accumulator decay time
const SCROLL_DECAY_TIME: float = 0.15

## Dynamic W limits (updated when objects change)
var _min_w: float = -100.0
var _max_w: float = 100.0

signal slice_changed(new_w: float)

func _ready() -> void:
	add_to_group("slicer_4d")
	set_process(true)
	# Find all 4D objects in scene
	call_deferred("_find_all_objects")

func _find_all_objects() -> void:
	objects_4d.clear()
	for node in get_tree().get_nodes_in_group("objects_4d"):
		if node is Object4D:
			objects_4d.append(node)
			node.update_slice(slice_w)
	_update_w_limits()
	print("[Slicer4D] Found %d 4D objects, W range: [%.1f, %.1f]" % [objects_4d.size(), _min_w, _max_w])

func _process(delta: float) -> void:
	if not scroll_4d_enabled:
		return
	
	# Process accumulated scroll input
	_time_since_scroll += delta
	
	# Apply accumulated scroll to target after a small delay
	# This groups rapid scroll events together
	if abs(_scroll_accumulator) > 0.01 and _time_since_scroll > SCROLL_DECAY_TIME:
		var new_target: float = target_w + _scroll_accumulator * scroll_speed
		
		# Apply dynamic limits
		if use_dynamic_limits:
			new_target = clamp(new_target, _min_w, _max_w)
		
		target_w = new_target
		_scroll_accumulator = 0.0
		print("[Slicer4D] W = %.2f (range: %.1f to %.1f)" % [target_w, _min_w, _max_w])
	
	# Smooth interpolation toward target
	var diff: float = target_w - slice_w
	if abs(diff) > 0.0001:
		# Exponential smoothing (framerate independent)
		var t: float = 1.0 - exp(-delta / smooth_time)
		var new_w: float = slice_w + diff * t
		slice_w = new_w
		slice_changed.emit(slice_w)

func _input(event: InputEvent) -> void:
	if not scroll_4d_enabled:
		return
	
	# Mouse wheel accumulates scroll input (handles notched wheels)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_accumulator += 1.0
			_time_since_scroll = 0.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_accumulator -= 1.0
			_time_since_scroll = 0.0

func _update_all_slices() -> void:
	for obj in objects_4d:
		if obj and is_instance_valid(obj):
			obj.update_slice(slice_w)

## Public method to update all 4D objects (used by portals for W-sync)
func update_all_objects() -> void:
	_update_all_slices()

## Calculate W limits based on all objects
func _update_w_limits() -> void:
	if objects_4d.is_empty():
		_min_w = -10.0
		_max_w = 10.0
		return
	
	_min_w = INF
	_max_w = -INF
	
	for obj in objects_4d:
		if not obj or not is_instance_valid(obj):
			continue
		
		var obj_w: float = obj.position_4d.w
		var obj_extent: float = obj.slice_threshold
		
		# For hyperspheres, use radius as extent
		if obj is Hypersphere4D:
			obj_extent = (obj as Hypersphere4D).radius
		elif obj is KleinBottle4D:
			var klein: KleinBottle4D = obj as KleinBottle4D
			obj_extent = klein.major_radius + klein.tube_radius
		
		_min_w = min(_min_w, obj_w - obj_extent - limit_padding)
		_max_w = max(_max_w, obj_w + obj_extent + limit_padding)
	
	# Ensure minimum range
	if _max_w - _min_w < 1.0:
		var center: float = (_min_w + _max_w) / 2.0
		_min_w = center - 5.0
		_max_w = center + 5.0

## Register a new 4D object
func register_object(obj: Object4D) -> void:
	if obj and not objects_4d.has(obj):
		objects_4d.append(obj)
		obj.update_slice(slice_w)
		_update_w_limits()
		print("[Slicer4D] Registered %s, new W range: [%.1f, %.1f]" % [obj.name, _min_w, _max_w])

## Unregister a 4D object
func unregister_object(obj: Object4D) -> void:
	objects_4d.erase(obj)
	_update_w_limits()

## Set scroll mode (called by debug console)
func set_scroll_4d_mode(enabled: bool) -> void:
	scroll_4d_enabled = enabled
	if enabled:
		target_w = slice_w  # Reset target to current position
		_scroll_accumulator = 0.0
		_update_w_limits()

## Get current slice W coordinate
func get_slice_w() -> float:
	return slice_w

## Get W limits
func get_w_limits() -> Vector2:
	return Vector2(_min_w, _max_w)

## Move slider to a specific W value (with smooth transition)
func set_slice_w(w: float) -> void:
	if use_dynamic_limits:
		w = clamp(w, _min_w, _max_w)
	target_w = w

## Teleport to W value immediately (no smoothing)
func teleport_to_w(w: float) -> void:
	if use_dynamic_limits:
		w = clamp(w, _min_w, _max_w)
	slice_w = w
	target_w = w
	_scroll_accumulator = 0.0
