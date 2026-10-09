class_name RoomMinimap
extends Control

var run: RunManager
var visited: Dictionary = {}
var _floor_seed: int = -1
var targeted_room_id: int = -1
const TARGET_COLOR := Color("ffe36b")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(330, 275)
	run = get_tree().get_first_node_in_group("run_manager")

func _process(_delta: float) -> void:
	targeted_room_id = -1
	if run and not run.loading:
		if _floor_seed != run.generator.seed_value:
			_floor_seed = run.generator.seed_value
			visited.clear()
		if run.current_room_id >= 0:
			visited[run.current_room_id] = true
		var camera: Camera3D = run.player.get("camera")
		var room: Node3D = run.generator.get_room(run.current_room_id)
		targeted_room_id = get_targeted_room_id(camera, room)
	queue_redraw()

## Intersect the crosshair ray with the current room's actual doorway discs.
## This remains correct as sphere gravity rotates the camera and portal planes.
func get_targeted_room_id(camera: Camera3D, room: Node3D) -> int:
	if not is_instance_valid(camera) or not is_instance_valid(room):
		return -1
	if not camera.is_inside_tree() or not room.is_visible_in_tree():
		return -1
	var center: Vector2 = camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	var radius: float = room.get("radius") if room.get("radius") != null else 20.0
	var nearest_distance: float = radius * 2.0 + 1.0
	var destination_id := -1
	for portal in room.get_portals():
		if not is_instance_valid(portal) or not portal.is_visible_in_tree():
			continue
		if portal.source_room != room or not portal.available or not is_instance_valid(portal.target_room):
			continue
		# Locks leave a visible door, so they deliberately do not affect aiming.
		var normal: Vector3 = (portal.global_basis.inverse().transposed() * Vector3.BACK).normalized()
		var denominator := ray_direction.dot(normal)
		if absf(denominator) < 0.0001:
			continue
		var distance: float = (portal.global_position - ray_origin).dot(normal) / denominator
		if distance <= 0.0 or distance >= nearest_distance:
			continue
		var local_hit: Vector3 = portal.to_local(ray_origin + ray_direction * distance)
		if Vector2(local_hit.x, local_hit.y).length_squared() > portal.portal_radius * portal.portal_radius:
			continue
		nearest_distance = distance
		destination_id = portal.target_room.room_id
	# An unseen doorway can occlude another target, but never reveal a map node.
	return destination_id if visited.has(destination_id) else -1

func get_map_positions() -> Dictionary:
	var points: Dictionary = {}
	if not run or run.loading:
		return points
	var graph := run.generator.room_graph
	var levels: Dictionary = {}
	var max_depth := 1
	for id in graph:
		if not visited.has(id):
			continue
		var depth: int = graph[id].get("depth", 0)
		max_depth = maxi(max_depth, depth)
		if not levels.has(depth):
			levels[depth] = []
		levels[depth].append(id)
	for depth in levels:
		var ids: Array = levels[depth]
		ids.sort()
		for i in range(ids.size()):
			points[ids[i]] = Vector2(26 + float(depth) / max_depth * (size.x - 52), 65 + (i + 1.0) / (ids.size() + 1.0) * 150)
	return points

func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.085, 0.12, 0.92)
	box.border_color = Color("335361")
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(18, 29), "ROOM MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, KennelUI.CREAM)
	draw_string(font, Vector2(18, size.y - 17), "● YOU   ○ EXPLORED   YELLOW: AIM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, KennelUI.MINT)
	var points := get_map_positions()
	if points.is_empty():
		return
	var graph := run.generator.room_graph
	draw_string(font, Vector2(size.x - 118, 29), "W %+.0f" % run.player.position_4d.w, HORIZONTAL_ALIGNMENT_RIGHT, 100, 15, KennelUI.MINT)
	for id in points:
		for neighbor in graph[id].connections:
			if points.has(neighbor) and id < neighbor:
				draw_line(points[id], points[neighbor], Color("496575"), 2, true)
	for id in points:
		var p: Vector2 = points[id]
		var color: Color = RoomTypes.get_color(graph[id].type)
		var current: bool = id == run.current_room_id
		var targeted: bool = id == targeted_room_id
		if targeted:
			color = TARGET_COLOR
		draw_circle(p, 10 if current else 7, color if visited.has(id) else KennelUI.INK)
		draw_arc(p, 10 if current else 7, 0, TAU, 24, color, 2, true)
		if targeted:
			draw_arc(p, 12, 0, TAU, 28, TARGET_COLOR, 2, true)
		if current:
			draw_arc(p, 15, 0, TAU, 28, KennelUI.CREAM, 2, true)
		if graph[id].type == RoomTypes.Type.BOSS:
			draw_string(font, p + Vector2(-4, -13), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ff7a7a"))
