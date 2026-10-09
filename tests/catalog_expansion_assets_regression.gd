extends SceneTree

class VisualRun:
	extends Node
	var counts := {"bounce": 2, "homing": 2, "cubensis": 2, "lazer": 3}
	func get_item_count(id: String, _gun_id: int = -1) -> int:
		return int(counts.get(id, 0))
	func get_stat_bonus(_stat: String, _type: int = -1, _gun_id: int = -1) -> float:
		return 0.0
	func get_stat_multiplier(_stat: String, _type: int = -1, _gun_id: int = -1) -> float:
		return 1.0
	func get_all_stats_factor(_gun_id: int = -1) -> float:
		return 1.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

func _csv(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	var headers := file.get_csv_line()
	headers[0] = headers[0].trim_prefix("\uFEFF")
	var rows: Array[Dictionary] = []
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() == 0 or cells[0].is_empty():
			continue
		var row := {}
		for i in range(mini(headers.size(), cells.size())):
			row[headers[i]] = cells[i]
		rows.append(row)
	return rows

func _run() -> void:
	var item_rows := _csv("res://data/items.csv")
	check(item_rows.size() == PetItems.CATALOG.size(), "Every CSV permanent item reaches native catalog")
	for row in item_rows:
		var item := PetItems.find_item(row.item_id)
		check(not item.is_empty(), "Item ID is available: " + row.item_id)
		for mapping in [["item_name", "name"], ["what_it_does", "description"], ["flavor_text", "flavor_text"], ["model_description", "model_description"], ["notes", "notes"]]:
			check(String(item.get(mapping[1], "")) == String(row[mapping[0]]), "Item CSV text preserved: %s/%s" % [row.item_id, mapping[0]])
		check(int(item.get("shop_price", 0)) == int(row.shop_price_bones), "CSV item shop price preserved: " + row.item_id)
	var dog_rows := _csv("res://data/dogs_guns.csv")
	for row in dog_rows:
		var definition := DogBreeds.get_definition(row.item_id)
		if row.category == "starter_weapon":
			for starter in PetItems.STARTER_DOGS:
				if starter.id == row.item_id:
					definition = starter
		check(not definition.is_empty(), "Dog CSV ID is available: " + row.item_id)
		for mapping in [["item_name", "name"], ["what_it_does", "description"], ["flavor_text", "flavor_text"], ["model_description", "model_description"], ["notes", "notes"]]:
			check(String(definition.get(mapping[1], "")) == String(row[mapping[0]]), "Dog CSV text preserved: %s/%s" % [row.item_id, mapping[0]])
		for mapping in [["damage", "damage"], ["shot_interval_seconds", "fire_rate"], ["projectile_speed", "projectile_speed"], ["magazine_capacity", "max_ammo"], ["reload_seconds", "reload_seconds"]]:
			check(is_equal_approx(float(definition.get(mapping[1], -1.0)), float(row[mapping[0]])), "Dog CSV combat value reaches catalog: %s/%s" % [row.item_id, mapping[0]])
		check(is_equal_approx(float(row.sustained_dps), 44.0), "Dog CSV documents equal expected baseline DPS: " + row.item_id)
	check(PetItems.rarity_weight({"rarity": "legendary"}) < PetItems.rarity_weight({"rarity": "rare"}), "Legendary items are rarer than rare items")
	check(PetItems.rarity_weight({"rarity": "rare"}) < PetItems.rarity_weight({"rarity": "uncommon"}), "Rare items are rarer than uncommon items")
	for id in ["boneswarm", "bounce", "homing", "flesh", "tofu", "aminita", "cubensis", "lazer"]:
		var model := load("res://assets/items/%s.glb" % id) as PackedScene
		check(model != null, "New native item model imports: " + id)
		if model:
			var instance := model.instantiate()
			check(not instance.find_children("*", "MeshInstance3D", true, false).is_empty(), "New item contains meshes: " + id)
			instance.free()
	var run := VisualRun.new()
	root.add_child(run)
	run.add_to_group("run_manager")
	var rng := RandomNumberGenerator.new()
	rng.seed = 55210
	for id in ["brussels_griffon", "otterhound"]:
		var gun := Gun.new()
		gun.stats = DogBreeds.create_stats(rng, id)
		root.add_child(gun)
		check(is_instance_valid(gun.breed_model), "Edited breed model loads on held gun: " + id)
		for anchor in ["HeadRoot", "MouthAnchor", "GlassesAnchor", "CollarAnchor"]:
			check(gun.breed_model.find_child(anchor, true, false) != null, "Edited breed keeps anchor: %s/%s" % [id, anchor])
		var attachments := gun.get_node("ItemAttachments")
		for fixture in [["BouncyChicken", 2], ["BentSpoon", 2], ["MagicMushroom", 2], ["LaserPointer", 3]]:
			for i in range(int(fixture[1])):
				check(attachments.get_node_or_null("%s_%d" % [fixture[0], i]) != null, "Stacked dog cosmetic exists: %s/%s_%d" % [id, fixture[0], i])
		gun.free()
	run.free()
	if failures.is_empty():
		print("PASS catalog_expansion_assets_regression")
	quit(0 if failures.is_empty() else 1)
