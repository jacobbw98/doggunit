extends RefCounted

static func _clear(parent: Node, name_value: String) -> void:
	var old := parent.get_node_or_null(name_value)
	if old:
		parent.remove_child(old)
		old.queue_free()

static func refresh_player(run: RunManager) -> void:
	_clear(run.player, "StackedCones")
	var root := Node3D.new()
	root.name = "StackedCones"
	run.player.add_child(root)
	for i in range(run.get_item_count("cone")):
		var cone := RoomEconomy.make_model("cone", 0.45)
		cone.position.y = run.player.camera.position.y + 0.22 + float(i) * 0.28
		root.add_child(cone)

static func refresh_gun(gun: Gun) -> void:
	_clear(gun, "ItemAttachments")
	var root := Node3D.new()
	root.name = "ItemAttachments"
	gun.add_child(root)
	var spring_count := gun._bonus_count("spring")
	var head_offset := float(spring_count) * 0.06
	# Move the regular pup's separate head parts above a visible spring neck.
	for part in gun.get_children():
		if part is MeshInstance3D and part.name != "Collar":
			if not part.has_meta("base_position"):
				part.set_meta("base_position", part.position)
			part.position = part.get_meta("base_position") + Vector3.UP * head_offset
	if is_instance_valid(gun.mascot_model):
		gun.mascot_model.set_neck_extension(float(spring_count) * 0.18)
	var mappo := is_instance_valid(gun.mascot_model)
	var breed := is_instance_valid(gun.breed_model)
	if breed:
		var head := gun.breed_model.find_child("HeadRoot", true, false) as Node3D
		if head:
			if not head.has_meta("base_position"):
				head.set_meta("base_position", head.position)
			var parent := head.get_parent() as Node3D
			# Imported breeds have different dimensions. Convert the same held
			# neck extension into their local head space, leaving their feet still.
			head.position = head.get_meta("base_position") + parent.global_basis.inverse() * gun.global_basis.y * head_offset
	var mouth := Vector3(-0.02, -0.08 + head_offset, -0.57) if mappo else Vector3(0, -0.06 + head_offset, -0.19)
	if breed:
		mouth = gun.get_breed_anchor("MouthAnchor")
	for i in range(gun._bonus_count("tennis")):
		var ball := RoomEconomy.make_model("tennis", 0.09)
		ball.name = "MouthBall_%d" % i
		ball.position = mouth + Vector3(float(i % 3 - 1) * 0.055, float(i / 3) * 0.055, -0.025 * float(i % 2))
		root.add_child(ball)
	for i in range(gun._bonus_count("tag")):
		var glasses := RoomEconomy.make_model("tag", 0.055)
		glasses.name = "Glasses_%d" % i
		glasses.scale *= Vector3(2.5, 1, 1)
		glasses.position = gun.get_breed_anchor("GlassesAnchor") + Vector3.UP * (i * 0.018) if breed else mouth + Vector3(0, 0.09 + i * 0.018, 0.07)
		root.add_child(glasses)
	for i in range(spring_count):
		var spring := RoomEconomy.make_model("spring", 0.08)
		spring.name = "SpringNeck_%d" % i
		spring.position = gun.get_breed_anchor("CollarAnchor") + Vector3.UP * (i * 0.06) if breed else (Vector3(-0.02, -0.16 + i * 0.06, -0.37) if mappo else Vector3(0, -0.09 + i * 0.06, 0.0))
		root.add_child(spring)
	# Each copy stays visible on the actual dog receiving the upgrade. Imported
	# breed anchors let cosmetics survive slot swaps, Walkies and dropped guns.
	var mount := gun.get_breed_anchor("CollarAnchor") if breed else (Vector3(-0.02, -0.14, -0.37) if mappo else Vector3(0, -0.09, 0.0))
	for i in range(gun._bonus_count("bounce")):
		var chicken := RoomEconomy.make_model("bounce", 0.14)
		chicken.name = "BouncyChicken_%d" % i
		chicken.position = mount + Vector3(-0.095 - float(i % 3) * 0.044, 0.015 + float(i / 3) * 0.07, -0.02)
		chicken.rotation.z = 0.18
		root.add_child(chicken)
	for i in range(gun._bonus_count("homing")):
		var spoon := RoomEconomy.make_model("homing", 0.14)
		spoon.name = "BentSpoon_%d" % i
		spoon.position = mount + Vector3(0.09 + float(i % 3) * 0.04, 0.01 + float(i / 3) * 0.06, 0.025)
		spoon.rotation.z = -0.25
		root.add_child(spoon)
	for i in range(gun._bonus_count("cubensis")):
		var mushroom := RoomEconomy.make_model("cubensis", 0.12)
		mushroom.name = "MagicMushroom_%d" % i
		mushroom.position = mount + Vector3(-0.07 - float(i % 3) * 0.04, 0.06 + float(i / 3) * 0.06, 0.10)
		root.add_child(mushroom)
	for i in range(gun._bonus_count("lazer")):
		var pointer := RoomEconomy.make_model("lazer", 0.13)
		pointer.name = "LaserPointer_%d" % i
		pointer.position = mount + Vector3(0.085 + float(i % 3) * 0.032, -0.015 + float(i / 3) * 0.04, -0.06)
		pointer.rotation.x = -PI * 0.5
		root.add_child(pointer)
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mappo or breed:
			mesh.layers = Gun.MAPPO_RENDER_LAYER

static func decorate_projectile(projectile: Projectile, count: int) -> void:
	if count <= 0:
		return
	var root := Node3D.new()
	root.name = "Flagella"
	root.set_script(load("res://scripts/items/flagella_animation.gd"))
	projectile.add_child(root)
	for i in range(count):
		var strand := RoomEconomy.make_model("flagellum", 0.5)
		strand.name = "Flagellum_%d" % i
		strand.rotation = Vector3(0.6 * sin(i * 2.4), i * 2.4, 0.6 * cos(i * 2.4))
		root.add_child(strand)
