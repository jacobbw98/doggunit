class_name RoomEconomy
extends RefCounted

const INTERACTION_DISTANCE := 4.5
const PICKUP_RADIUS := 1.35
const COMMERCE_ENTRY_DISTANCE := 14.0
const COMMERCE_PORTAL_CLEARANCE := 10.0
const COMMERCE_FOOTPRINT := 1.4

## World rewards belong to the generated room, including its changing W slice.
static func populate_room(run: Node, room: Node3D) -> void:
	if room.has_meta("economy_populated"):
		return
	room.set_meta("economy_populated", true)
	match int(room.get("room_type")):
		RoomTypes.Type.ITEM:
			spawn_reward(run, room, 2, true)
		RoomTypes.Type.SHOP:
			_populate_shop(run, room)
		RoomTypes.Type.GAMBLING:
			var machine := SlotMachine.new()
			machine.configure(run, room)
			room.add_child(machine)
			place_on_surface(machine, room, _commerce_direction(run, room, [0.0]), _entry_direction(run, room))

static func spawn_reward(run: Node, room: Node3D, count: int = 1, choice_group: bool = true) -> Array:
	var choices: Array = PetItems.CATALOG.duplicate(true)
	var spawned: Array = []
	var rng := _rng(run)
	var anchor := _display_direction(run, room)
	var right := _surface_right(anchor)
	var token := "%d:%d" % [room.get_instance_id(), rng.randi()] if choice_group and count > 1 else ""
	for index in range(mini(count, choices.size())):
		var item: Dictionary = choices.pop_at(PetItems.pick_index(choices, rng))
		var pedestal := ItemPedestal.new()
		pedestal.configure(run, room, item, 0, token)
		room.add_child(pedestal)
		var lateral: float = (index - (count - 1) * 0.5) * 3.2 / maxf(float(room.get("radius")), 1.0)
		var direction := (anchor + right * lateral).normalized()
		place_on_surface(pedestal, room, direction, _entry_direction(run, room))
		spawned.append(pedestal)
	return spawned

static func _populate_shop(run: Node, room: Node3D) -> void:
	var rng := _rng(run)
	var count := rng.randi_range(1, 3)
	var choices: Array = PetItems.CATALOG.duplicate(true)
	choices.append_array(PetItems.CONSUMABLES.duplicate(true))
	var anchor := _commerce_direction(run, room, [-3.2, 0.0, 3.2, 5.0])
	var right := _surface_right(anchor)
	var entry := _entry_direction(run, room)
	for index in range(count):
		var item: Dictionary = choices.pop_at(PetItems.pick_index(choices, rng))
		var pedestal := ItemPedestal.new()
		pedestal.configure(run, room, item, int(item.get("shop_price", 15)))
		room.add_child(pedestal)
		var lateral: float = (index - (count - 1) * 0.5) * 3.2 / float(room.get("radius"))
		place_on_surface(pedestal, room, (anchor + right * lateral).normalized(), entry)
	# Mildred's three-box perch stays beside the stock, leaving each offer reachable.
	var counter: Node3D = load("res://scripts/items/mildred_shopkeeper.gd").new()
	counter.configure(run, room)
	room.add_child(counter)
	place_on_surface(counter, room, (anchor + right * (5.0 / float(room.get("radius")))).normalized(), entry)

static func drop_enemy_bones(run: Node, enemy: Node3D, room: Node3D) -> Array:
	if not is_instance_valid(enemy) or not is_instance_valid(room) or enemy.has_meta("bones_dropped"):
		return []
	enemy.set_meta("bones_dropped", true)
	var limits := enemy_drop_range(enemy, int(run.get("current_floor")))
	var amount := _rng(run).randi_range(limits.x, limits.y)
	return spawn_bones(run, room, enemy.global_position, amount)

static func enemy_drop_range(enemy: Node, floor_number: int = 1) -> Vector2i:
	var kind = enemy.get("archetype")
	var health = enemy.get("max_health")
	var minimum := 1
	var maximum := 3
	if kind == Enemy4D.Archetype.BOSS or (health != null and int(health) >= 300):
		minimum = 20
		maximum = 35
	elif kind == Enemy4D.Archetype.BRUTE or (health != null and int(health) >= 100):
		minimum = 5
		maximum = 9
	elif kind == Enemy4D.Archetype.SNIPER or (health != null and int(health) >= 65):
		minimum = 3
		maximum = 6
	# Later floors increase payouts in proportion to the tougher encounters.
	var scale_factor := 1.0 + maxi(0, floor_number - 1) * 0.3
	return Vector2i(maxi(1, roundi(minimum * scale_factor)), maxi(1, roundi(maximum * scale_factor)))

static func denominations(amount: int) -> Array[int]:
	var values: Array[int] = []
	var remainder := maxi(0, amount)
	for value in [10, 5, 1]:
		while remainder >= value:
			values.append(value)
			remainder -= value
	return values

static func spawn_bones(run: Node, room: Node3D, world_position: Vector3, amount: int) -> Array:
	var spawned: Array = []
	var rng := _rng(run)
	var outward := (world_position - room.global_position).normalized()
	if outward.is_zero_approx():
		outward = Vector3.DOWN
	var up := -outward
	var right := _surface_right(outward)
	var forward := up.cross(right).normalized()
	for value in denominations(amount):
		var bone := BonePickup.new()
		bone.configure(run, room, value, rng.randi_range(0, 3))
		room.add_child(bone)
		bone.global_position = world_position + up * 0.5
		bone.velocity = room.global_basis.inverse() * (up * rng.randf_range(2.8, 4.4) + right * rng.randf_range(-2.8, 2.8) + forward * rng.randf_range(-2.8, 2.8))
		bone.constrain_to_room()
		spawned.append(bone)
	return spawned

static func room_visible(run: Node, room: Node3D) -> bool:
	if not is_instance_valid(run) or not is_instance_valid(room):
		return false
	if room.get("graph_visible") == false:
		return false
	var player = run.get("player")
	if not is_instance_valid(player):
		return false
	var point = player.get("position_4d")
	var room_point = room.get("position_4d")
	return point == null or room_point == null or absf(point.w - room_point.w) < float(room.get("radius"))

static func room_active(run: Node, room: Node3D) -> bool:
	if not room_visible(run, room) or run.get("loading") == true or int(run.get("current_room_id")) != int(room.get("room_id")):
		return false
	var player: Node3D = run.get("player")
	var point = player.get("position_4d")
	var room_point = room.get("position_4d")
	return point == null or room_point == null or absf(point.w - room_point.w) < 1.0

static func can_interact(run: Node, room: Node3D, actor: Node3D) -> bool:
	if not room_active(run, room) or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return false
	var player: Node3D = run.get("player")
	var camera = player.get("camera")
	var eye: Vector3 = camera.global_position if camera is Camera3D else player.global_position + player.global_basis.y * 1.6
	return eye.distance_to(interaction_position(actor)) <= INTERACTION_DISTANCE

static func interaction_position(actor: Node3D) -> Vector3:
	if actor.has_method("get_interaction_position"):
		return actor.get_interaction_position()
	return actor.global_position + actor.global_basis.y * 1.8

static func in_pickup_range(run: Node, room: Node3D, actor: Node3D) -> bool:
	if not room_active(run, room) or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return false
	var player: Node3D = run.get("player")
	var offset := player.global_position - actor.global_position
	var up := actor.global_basis.y.normalized()
	# The grounded CharacterBody centre is two metres above this surface.
	# Floor distance works on walls and ceilings as well as the bottom of a room.
	return absf(offset.dot(up)) <= 3.2 and offset.slide(up).length() <= PICKUP_RADIUS

static func place_on_surface(node: Node3D, room: Node3D, outward: Vector3, facing_outward: Vector3) -> void:
	var up := -outward.normalized()
	var forward := (facing_outward - outward).slide(up).normalized()
	if forward.is_zero_approx():
		forward = _surface_right(outward).cross(up).normalized()
	node.global_position = room.global_position + outward.normalized() * (float(room.get("radius")) - 0.04)
	node.global_basis = Basis.looking_at(forward, up)

static func _entry_direction(run: Node, room: Node3D) -> Vector3:
	var player: Node3D = run.get("player")
	var direction := (player.global_position - room.global_position).normalized()
	return direction if not direction.is_zero_approx() else Vector3.DOWN

static func _display_direction(run: Node, room: Node3D) -> Vector3:
	var entry := _entry_direction(run, room)
	var player: Node3D = run.get("player")
	var tangent := (-player.global_basis.z).slide(entry).normalized()
	if tangent.is_zero_approx():
		tangent = _surface_right(entry).cross(-entry).normalized()
	# Four metres ahead is visible on entry and reachable without crossing the room.
	var angle := 4.0 / maxf(float(room.get("radius")), 1.0)
	return (entry * cos(angle) + tangent * sin(angle)).normalized()

## Shops and gambling displays occupy an open part of the sphere, with a wide
## walking corridor around every doorway, including undiscovered secret doors.
static func _commerce_direction(run: Node, room: Node3D, offsets: Array[float]) -> Vector3:
	var entry := _entry_direction(run, room)
	var player: Node3D = run.get("player")
	var tangent := (-player.global_basis.z).slide(entry).normalized()
	if tangent.is_zero_approx():
		tangent = _surface_right(entry).cross(-entry).normalized()
	var radius := maxf(float(room.get("radius")), 1.0)
	var first_angle := minf(COMMERCE_ENTRY_DISTANCE / radius, PI)
	var preferred := (entry * cos(first_angle) + tangent * sin(first_angle)).normalized()
	if _commerce_clearance(room, preferred, offsets) >= COMMERCE_PORTAL_CLEARANCE:
		return preferred
	var sideways := entry.cross(tangent).normalized()
	var best := preferred
	var best_score := INF
	var fallback := preferred
	var fallback_clearance := _commerce_clearance(room, preferred, offsets)
	# A deterministic scan keeps decoration independent of inventory/drop RNG.
	var ring_count := maxi(1, ceili((PI * radius - COMMERCE_ENTRY_DISTANCE) / 2.0))
	for ring in range(ring_count + 1):
		var angle := minf((COMMERCE_ENTRY_DISTANCE + ring * 2.0) / radius, PI)
		for bearing_index in range(32):
			var bearing := TAU * bearing_index / 32.0
			var direction := (entry * cos(angle) + (tangent * cos(bearing) + sideways * sin(bearing)) * sin(angle)).normalized()
			var clearance := _commerce_clearance(room, direction, offsets)
			if clearance > fallback_clearance:
				fallback = direction
				fallback_clearance = clearance
			if clearance < COMMERCE_PORTAL_CLEARANCE:
				continue
			var score := preferred.angle_to(direction) * radius
			if score < best_score:
				best = direction
				best_score = score
	return best if best_score < INF else fallback

static func _commerce_clearance(room: Node3D, anchor: Vector3, offsets: Array[float]) -> float:
	var portals = room.get("portals")
	if not portals is Array or portals.is_empty():
		return INF
	var radius := maxf(float(room.get("radius")), 1.0)
	var right := _surface_right(anchor)
	var clearance := INF
	for offset in offsets:
		var direction := (anchor + right * offset / radius).normalized()
		for portal in portals:
			if not is_instance_valid(portal) or not portal is Node3D:
				continue
			var portal_direction: Vector3 = (portal.global_position - room.global_position).normalized()
			if portal_direction.is_zero_approx():
				continue
			var portal_size = portal.get("portal_radius")
			var portal_radius: float = float(portal_size) if portal_size != null else 2.0
			clearance = minf(clearance, direction.angle_to(portal_direction) * radius - portal_radius - COMMERCE_FOOTPRINT)
	return clearance

static func _surface_right(outward: Vector3) -> Vector3:
	var reference := Vector3.FORWARD
	if absf(outward.dot(reference)) > 0.9:
		reference = Vector3.RIGHT
	return (-outward).cross(reference).normalized()

static func _rng(run: Node) -> RandomNumberGenerator:
	var rng = run.get("_rng")
	if rng is RandomNumberGenerator:
		return rng
	var fallback := RandomNumberGenerator.new()
	fallback.randomize()
	return fallback

static func make_label(text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 24
	label.pixel_size = 0.0035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 3
	return label

static func make_model(id: String, size: float, by_height: bool = false) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.name = id.to_pascal_case() + "Model"
	var path := "res://assets/items/%s.glb" % id
	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			var imported = packed.instantiate()
			if imported is Node3D:
				wrapper.add_child(imported)
				var bounds := model_bounds(wrapper)
				var reference := bounds.size.y if by_height else maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
				var scale_factor := size / maxf(reference, 0.001)
				wrapper.scale = Vector3.ONE * scale_factor
				imported.position += Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
				return wrapper
	# This also keeps save files playable if an asset is temporarily being reimported.
	var placeholder := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	placeholder.mesh = mesh
	placeholder.position.y = size * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.70, 0.40)
	material.roughness = 1.0
	placeholder.material_override = material
	wrapper.add_child(placeholder)
	return wrapper

static func model_bounds(node: Node, transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var total := AABB()
	var found := false
	var pending: Array = [[node, transform]]
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		var current: Node = entry[0]
		var accumulated: Transform3D = entry[1]
		if current is MeshInstance3D and current.mesh:
			var bounds: AABB = accumulated * current.mesh.get_aabb()
			total = total.merge(bounds) if found else bounds
			found = true
		for child in current.get_children():
			pending.append([child, accumulated * child.transform if child is Node3D else accumulated])
	return total
