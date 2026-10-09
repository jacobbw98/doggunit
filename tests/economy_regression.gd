extends SceneTree

class FakeRoom extends Node3D:
	var room_id: int = 1
	var room_type: int = RoomTypes.Type.ITEM
	var radius: float = 20.0
	var graph_visible: bool = true
	var position_4d := Vector4D.zero()

class FakePlayer extends Node3D:
	var position_4d := Vector4D.zero()

class FakeRun extends Node:
	var player: Node3D
	var current_room_id: int = 1
	var current_floor: int = 1
	var loading: bool = false
	var bones: int = 0
	var bombs: int = 0
	var keys: int = 0
	var active_item: Dictionary = {}
	var acquired: Array[String] = []
	var reject_item: bool = false
	var _rng := RandomNumberGenerator.new()
	func add_bones(amount: int) -> void:
		bones += amount
	func spend_bones(amount: int) -> bool:
		if amount < 0 or bones < amount:
			return false
		bones -= amount
		return true
	func acquire_item(item: Dictionary) -> bool:
		if reject_item:
			return false
		acquired.append(str(item.id))
		if PetItems.is_active(item):
			active_item = item.duplicate(true)
		elif PetItems.is_consumable(item):
			if item.consumable == "bomb":
				bombs += 1
			else:
				keys += 1
		return true
	func get_bone_pull_multiplier() -> float:
		return 1.0
	func get_item_count(_id: String, _gun_id: int = -1) -> int:
		return 0

class FakeEnemy extends Node3D:
	var archetype: int = Enemy4D.Archetype.GRUNT
	var max_health: int = 45

var failures: Array[String] = []
var room: FakeRoom
var run: FakeRun

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	room = FakeRoom.new()
	root.add_child(room)
	run = FakeRun.new()
	run._rng.seed = 271828
	root.add_child(run)
	run.player = FakePlayer.new()
	root.add_child(run.player)
	run.player.position = Vector3(0, -18.8, 0)
	_test_choice()
	await process_frame
	_test_auto_pickup()
	await process_frame
	_test_shop_transactions()
	await process_frame
	_test_active_swap()
	await process_frame
	_test_bones()
	await process_frame
	_test_slot()
	await process_frame
	_test_room_population()
	await process_frame
	if failures.is_empty():
		print("ECONOMY PASSED: linked choices, shop atomicity, active swaps, denomination visuals, room containment, difficulty payouts, slot odds and duplicate guards")
	else:
		print("ECONOMY FAILED: ", failures)
	quit(0 if failures.is_empty() else 1)

func _test_choice() -> void:
	var choices := RoomEconomy.spawn_reward(run, room, 2, true)
	check(choices.size() == 2 and choices[0].item.id != choices[1].item.id, "Item room presents two distinct items")
	check(choices[0].choice_token == choices[1].choice_token and not choices[0].choice_token.is_empty(), "Item room choices share one selection")
	var first: ItemPedestal = choices[0]
	var sibling: ItemPedestal = choices[1]
	run.player.global_position = first.global_position + first.global_basis.y * 0.8
	check(first.global_basis.y.dot((room.global_position - first.global_position).normalized()) > 0.99, "Pedestals stand upright on the sphere interior")
	check(first.interact(run), "A free pedestal can be picked up")
	check(not sibling.available and not sibling.interact(run), "Picking one immediately disables its sibling")
	check(run.acquired.size() == 1 and not paused, "World pickup acquires exactly one item without pausing")
	# If the random reward was an active item, the following tests start cleanly.
	run.active_item.clear()

func _pedestal(id: String, price: int = 0) -> ItemPedestal:
	var pedestal := ItemPedestal.new()
	pedestal.configure(run, room, PetItems.find_item(id), price)
	room.add_child(pedestal)
	RoomEconomy.place_on_surface(pedestal, room, Vector3.DOWN, Vector3(0, -1, -0.1).normalized())
	run.player.global_position = pedestal.global_position + pedestal.global_basis.y * 0.8
	return pedestal

func _test_auto_pickup() -> void:
	var game: Node = root.get_node("GameManager")
	var previous_state: int = game.current_state
	game.current_state = game.GameState.PLAYING
	run.active_item.clear()
	var choices := RoomEconomy.spawn_reward(run, room, 2, true)
	var first: ItemPedestal = choices[0]
	var sibling: ItemPedestal = choices[1]
	var acquired_before := run.acquired.size()
	# The live controller holds the player's centre 2 m inside the wall.
	# Surface distance, rather than Euclidean distance to the base, must collect.
	run.player.global_position = first.global_position + first.global_basis.y * 2.0 + first.global_basis.x * 0.9
	first._process(0.016)
	sibling._process(0.016)
	check(not first.available and not sibling.available and run.acquired.size() == acquired_before + 1, "Walking onto a free choice collects exactly one item at the player's actual ground clearance")
	check(not paused, "Automatic world pickups never pause gameplay")
	run.active_item.clear()
	var previous_room_type := room.room_type
	room.room_type = RoomTypes.Type.SHOP
	var shop_stock := _pedestal("med_bowl", 0)
	run.player.global_position = shop_stock.global_position + shop_stock.global_basis.y * 2.0
	shop_stock._process(0.016)
	check(shop_stock.available and shop_stock.requires_interaction() and run.acquired.size() == acquired_before + 1, "Shop items stay manual even when priced zero after an active swap")
	shop_stock.retire()
	room.room_type = previous_room_type
	run.active_item = PetItems.find_item("med_bowl")
	var swap := _pedestal("howl_horn")
	run.player.global_position = swap.global_position + swap.global_basis.y * 2.0
	swap._process(0.016)
	check(run.active_item.id == "howl_horn" and swap.item.id == "med_bowl", "Walking onto a free active item swaps the slot once")
	swap._process(0.016)
	check(run.active_item.id == "howl_horn", "Standing over the returned active cannot trigger a continuous swap loop")
	run.player.global_position += swap.global_basis.x * 3.0
	swap._process(0.016)
	run.player.global_position = swap.global_position + swap.global_basis.y * 2.0
	swap._process(0.016)
	check(run.active_item.id == "med_bowl", "Leaving and returning allows a deliberate automatic swap back")
	swap.retire()
	run.active_item.clear()
	game.current_state = previous_state

func _test_shop_transactions() -> void:
	var pedestal := _pedestal("biscuit", 15)
	var acquired_before := run.acquired.size()
	run.bones = 14
	check(not pedestal.interact(run) and run.bones == 14 and pedestal.available, "Unaffordable shop stock remains available and does not charge")
	run.bones = 15
	check(pedestal.interact(run) and run.bones == 0, "Buying stock costs exactly 15 bones")
	check(not pedestal.interact(run) and run.acquired.size() == acquired_before + 1, "A sold pedestal cannot be purchased twice")
	var rejected := _pedestal("tag", 15)
	run.bones = 15
	run.reject_item = true
	check(not rejected.interact(run) and run.bones == 15 and rejected.available, "Failed acquisition refunds the full price atomically")
	run.reject_item = false
	rejected.retire()
	var bomb := _pedestal("bomb", 15)
	run.bones = 15
	run.active_item = PetItems.find_item("med_bowl")
	check(bomb.interact(run) and run.bombs == 1 and not bomb.available, "Bomb purchases fill a consumable counter and do not duplicate the active item")
	check(run.active_item.id == "med_bowl", "Buying consumables preserves the active slot")
	var key := _pedestal("key", 15)
	run.bones = 15
	check(key.interact(run) and run.keys == 1 and run.bones == 0, "Key purchases fill the future-use key counter")

func _test_active_swap() -> void:
	run.active_item = PetItems.find_item("med_bowl")
	var active := _pedestal("howl_horn", 15)
	run.bones = 20
	check(active.interact(run) and run.active_item.id == "howl_horn" and run.bones == 5, "Buying an active item swaps the single slot and charges once")
	check(active.available and active.item.id == "med_bowl" and active.price == 0, "The replaced active returns to the same pedestal for free")
	check(active.interact(run) and run.active_item.id == "med_bowl" and run.bones == 5, "Swapping back never charges the original shop price again")
	active.retire()
	run.active_item.clear()

func _test_bones() -> void:
	check(RoomEconomy.denominations(27) == [10, 10, 5, 1, 1], "Bone amounts split into exact gold, silver and white denominations")
	check(RoomEconomy.denominations(0).is_empty() and RoomEconomy.denominations(-2).is_empty(), "Nonpositive drops spawn no currency")
	check(BonePickup.denomination_color(1) == Color.WHITE and BonePickup.denomination_color(5) != BonePickup.denomination_color(10), "All three currency denominations have distinct colors")
	var variants := {}
	var total := 0
	var drops := RoomEconomy.spawn_bones(run, room, Vector3(0, -19.7, 0), 27)
	for bone in drops:
		bone.set_physics_process(false)
		total += bone.amount
	check(total == 27 and drops.size() == 5, "Physical bone values preserve the enemy payout")
	for index in range(4):
		var bone := BonePickup.new()
		bone.configure(run, room, 1, index)
		room.add_child(bone)
		bone.set_physics_process(false)
		variants[bone.variant] = true
		bone.queue_free()
	check(variants.size() == 4, "All four aesthetic model variants accept the same denomination")
	var candidate: BonePickup = drops[0]
	candidate.position = Vector3(0, -21, 0)
	candidate.velocity = Vector3.DOWN * 15
	candidate.constrain_to_room()
	check(candidate.position.length() <= room.radius - 0.279 and candidate.velocity.y > 0, "Burst currency cannot escape the room wall and bounces inward")
	run.current_room_id = 2
	var before := run.bones
	candidate.collect()
	check(run.bones == before and not candidate.collected, "An overlapping room cannot collect another room's currency")
	run.current_room_id = room.room_id
	run.player.position_4d.w = 10.0
	candidate.collect()
	check(run.bones == before and not candidate.collected, "A different W slice cannot collect currency")
	run.player.position_4d.w = 0.0
	room.graph_visible = false
	candidate._physics_process(0.1)
	check(not candidate.visible, "Off-graph bones hide")
	room.graph_visible = true
	run.player.global_position = Vector3(0, -18.8, 0)
	candidate.position = Vector3(0, 19, 0)
	candidate.age = BonePickup.BURST_DELAY
	candidate.velocity = Vector3.ZERO
	for step in range(700):
		candidate._physics_process(1.0 / 60.0)
		check(candidate.position.length() < room.radius, "Attracted bones remain inside their room")
		if candidate.collected:
			break
	check(candidate.collected and run.bones == before + candidate.amount, "Currency reaches the player from the opposite side of a sphere")
	candidate.collect()
	check(run.bones == before + candidate.amount, "A collected bone cannot pay out twice")
	for bone in drops:
		if bone != candidate:
			bone.queue_free()
	var enemy := FakeEnemy.new()
	room.add_child(enemy)
	check(RoomEconomy.enemy_drop_range(enemy) == Vector2i(1, 3), "Cheap enemies drop 1 to 3 bones")
	enemy.archetype = Enemy4D.Archetype.SNIPER
	check(RoomEconomy.enemy_drop_range(enemy) == Vector2i(3, 6), "Higher-threat enemies drop 3 to 6 bones")
	enemy.archetype = Enemy4D.Archetype.BRUTE
	check(RoomEconomy.enemy_drop_range(enemy) == Vector2i(5, 9), "Brutes drop 5 to 9 bones")
	enemy.archetype = Enemy4D.Archetype.BOSS
	check(RoomEconomy.enemy_drop_range(enemy) == Vector2i(20, 35), "Bosses drop 20 to 35 bones")
	check(RoomEconomy.enemy_drop_range(enemy, 3).x > 20, "Later floors scale bone payouts with enemy difficulty")
	var death_drop := RoomEconomy.drop_enemy_bones(run, enemy, room)
	check(not death_drop.is_empty() and RoomEconomy.drop_enemy_bones(run, enemy, room).is_empty(), "Repeated death signals cannot duplicate bone drops")
	for bone in death_drop:
		bone.queue_free()
	enemy.queue_free()

func _test_slot() -> void:
	var frequencies := [0, 0, 0, 0]
	for roll in range(100):
		frequencies[SlotMachine.outcome_for_roll(roll)] += 1
	check(frequencies == [1, 20, 30, 49], "The slot table has exactly 1% explosion, 20% item, 30% bones and 49% nothing")
	var ordinary := SlotMachine.new()
	ordinary.configure(run, room)
	room.add_child(ordinary)
	ordinary.set_process(false)
	RoomEconomy.place_on_surface(ordinary, room, Vector3.DOWN, Vector3(0, -1, -0.1).normalized())
	run.player.global_position = ordinary.global_position + ordinary.global_basis.y * 0.8
	run.bones = 20
	check(ordinary.interact(run), "An ordinary machine starts an item-winning spin")
	ordinary.pending_roll = 20
	ordinary.resolve_spin()
	var winnings := _stocks(room)
	check(winnings.size() == 1 and winnings[0].price == 0, "Item-winning spins create one free world pedestal")
	if not winnings.is_empty():
		check(winnings[0].global_position.distance_to(ordinary.global_position) < 3.0, "Slot items appear beside the winning machine")
		winnings[0].retire()
	check(ordinary.interact(run), "A completed spin allows the machine to be used again")
	ordinary.pending_roll = 35
	ordinary.resolve_spin()
	var payout := 0
	for bone in get_nodes_in_group("bone_pickups"):
		if not bone.is_queued_for_deletion():
			payout += bone.amount
			bone.queue_free()
	check(payout in [5, 10], "Bone-winning spins spawn a 5 or 10 bone payout")
	check(ordinary.interact(run), "The machine also starts a losing spin")
	var balance := run.bones
	ordinary.pending_roll = 99
	ordinary.resolve_spin()
	check(run.bones == balance and ordinary.last_outcome == SlotMachine.Outcome.NOTHING, "Losing spins produce no extra payout")
	ordinary.queue_free()
	var machine := SlotMachine.new()
	machine.configure(run, room)
	room.add_child(machine)
	machine.set_process(false)
	RoomEconomy.place_on_surface(machine, room, Vector3.DOWN, Vector3(0, -1, -0.1).normalized())
	run.player.global_position = machine.global_position + machine.global_basis.y * 0.8
	run.bones = 2
	check(not machine.interact(run) and run.bones == 2 and not machine.spinning, "Unaffordable spins do not lock or charge")
	run.bones = 20
	check(machine.interact(run) and run.bones == 17, "A spin costs exactly 3 bones")
	check(not machine.interact(run) and run.bones == 17, "Input during spinning cannot charge again")
	machine.pending_roll = 0
	machine.resolve_spin()
	check(machine.broken and run.bones == 117 and not machine.spinning, "Explosion grants exactly 100 bones and destroys the machine")
	machine.resolve_spin()
	check(not machine.interact(run) and run.bones == 117, "Destroyed machines cannot repeat jackpots")
	machine.queue_free()

func _test_room_population() -> void:
	var acquired_before := run.acquired.size()
	var kinds := {}
	var item_room := FakeRoom.new()
	item_room.room_id = 2
	root.add_child(item_room)
	run.current_room_id = 2
	RoomEconomy.populate_room(run, item_room)
	RoomEconomy.populate_room(run, item_room)
	check(_stocks(item_room).size() == 2, "Re-entering an item room cannot duplicate its two choices")
	item_room.queue_free()
	for seed_value in range(12):
		var shop := FakeRoom.new()
		shop.room_type = RoomTypes.Type.SHOP
		shop.room_id = 3
		root.add_child(shop)
		run._rng.seed = seed_value
		RoomEconomy.populate_room(run, shop)
		var stocks := _stocks(shop)
		check(stocks.size() >= 1 and stocks.size() <= 3, "Shops have between one and three offers")
		var ids := {}
		for stock in stocks:
			ids[stock.item.id] = true
			kinds[str(stock.item.get("kind", "passive"))] = true
			check(stock.price == int(stock.item.get("shop_price", 15)), "Shop prices use each item's edited catalog price")
		check(ids.size() == stocks.size(), "Each shop's stock is distinct")
		check(shop.get_node_or_null("MildredsCounter/Mildred") != null, "Mildred appears behind the shop counter")
		shop.queue_free()
	check(kinds.has("passive") and kinds.has("active") and kinds.has("consumable"), "Shop stock can include all item families plus consumables")
	check(run.acquired.size() == acquired_before, "Entering shops never awards free samples")
	run.current_room_id = room.room_id

func _stocks(owning_room: Node) -> Array:
	var stocks: Array = []
	for child in owning_room.get_children():
		if child is ItemPedestal:
			stocks.append(child)
	return stocks
