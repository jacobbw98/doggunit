class_name ItemPedestal
extends Node3D

const PEDESTAL_HEIGHT: float = 1.56
const ITEM_SIZE: float = 1.40
const ITEM_BASE_HEIGHT: float = 1.70

var run: Node
var room: Node3D
var room_id: int = -1
var item: Dictionary = {}
var price: int = 0
var choice_token: String = ""
var available: bool = true
var _busy: bool = false
var _item_model: Node3D
var _label: Label3D
var _age: float = 0.0
var _item_center: Vector3 = Vector3.ZERO
var _auto_pickup_armed: bool = true

func configure(run_owner: Node, owning_room: Node3D, offered_item: Dictionary, bone_price: int = 0, linked_choice: String = "") -> void:
	run = run_owner
	room = owning_room
	room_id = int(room.get("room_id"))
	item = offered_item.duplicate(true)
	price = maxi(0, bone_price)
	choice_token = linked_choice
	set_meta("room_id", room_id)

func _ready() -> void:
	add_to_group("item_interactables")
	add_to_group("item_pedestals")
	name = "Pedestal_" + str(item.get("id", "item"))
	add_child(RoomEconomy.make_model("pedestal", PEDESTAL_HEIGHT, true))
	_label = RoomEconomy.make_label("", Color.WHITE)
	_label.position.y = 3.50
	add_child(_label)
	_refresh_display()

func _process(delta: float) -> void:
	visible = available and RoomEconomy.room_visible(run, room)
	_age += delta
	if is_instance_valid(_item_model):
		_item_model.position.y = ITEM_BASE_HEIGHT + sin(_age * 2.1) * 0.08
		_item_model.rotation.y += delta * 0.5
	if not available or requires_interaction() or not RoomEconomy.room_active(run, room):
		return
	if not RoomEconomy.in_pickup_range(run, room, self):
		_auto_pickup_armed = true
	elif _auto_pickup_armed:
		var game: Node = get_tree().root.get_node_or_null("GameManager")
		if is_instance_valid(game) and game.current_state == game.GameState.PLAYING:
			interact(run)

func requires_interaction() -> bool:
	return price > 0 or (is_instance_valid(room) and int(room.get("room_type")) == RoomTypes.Type.SHOP)

func get_interaction_position() -> Vector3:
	if is_instance_valid(_item_model):
		return to_global(_item_model.position + _item_center)
	return to_global(Vector3(0, ITEM_BASE_HEIGHT + ITEM_SIZE * 0.5, 0))

func get_interaction_text(actor_run: Node) -> String:
	if not available or _busy or not RoomEconomy.can_interact(actor_run, room, self):
		return ""
	var text := str(item.get("name", "Item"))
	if price > 0:
		text += " · %d bones" % price
		if int(actor_run.get("bones")) < price:
			return text + " (not enough bones)"
	if PetItems.is_active(item) and not actor_run.get("active_item").is_empty():
		text += " · swap active"
	return text

func interact(actor_run: Node) -> bool:
	if not available or _busy or not RoomEconomy.can_interact(actor_run, room, self):
		return false
	_busy = true
	if price > 0 and not actor_run.spend_bones(price):
		_busy = false
		return false
	var old_active: Dictionary = {}
	if PetItems.is_active(item):
		old_active = actor_run.get("active_item").duplicate(true)
		if not old_active.is_empty():
			old_active["remaining_cooldown_rooms"] = int(actor_run.get("active_cooldown_rooms")) if actor_run.get("active_cooldown_rooms") != null else 0
			old_active["remaining_cooldown"] = float(actor_run.get("active_cooldown")) if actor_run.get("active_cooldown") != null else 0.0
	if not actor_run.acquire_item(item):
		if price > 0:
			actor_run.add_bones(price)
		_busy = false
		return false
	# Disable linked options immediately, before deferred deletion can accept input.
	if not choice_token.is_empty():
		for sibling in get_tree().get_nodes_in_group("item_pedestals"):
			if sibling != self and sibling.room == room and sibling.choice_token == choice_token:
				sibling.retire()
		choice_token = ""
	if not old_active.is_empty():
		item = old_active
		price = 0
		# Walking onto an active swaps once. Leaving its previous item here must
		# not immediately swap the slot back on the next frame.
		_auto_pickup_armed = false
		_refresh_display()
		_busy = false
	else:
		retire()
	return true

func retire() -> void:
	available = false
	visible = false
	remove_from_group("item_interactables")
	remove_from_group("item_pedestals")
	queue_free()

func _refresh_display() -> void:
	if is_instance_valid(_item_model):
		remove_child(_item_model)
		_item_model.queue_free()
	_item_model = RoomEconomy.make_model(str(item.get("id", "biscuit")), ITEM_SIZE)
	_item_model.position.y = ITEM_BASE_HEIGHT
	add_child(_item_model)
	var display_bounds := RoomEconomy.model_bounds(_item_model, Transform3D(_item_model.basis, Vector3.ZERO))
	_item_center = display_bounds.get_center()
	var family := "CONSUMABLE"
	var color := Color(1.0, 0.88, 0.50)
	match int(item.get("category", -1)):
		PetItems.Category.GLOBAL_PASSIVE:
			family = "GLOBAL PASSIVE"
			color = Color(0.55, 0.95, 0.78)
		PetItems.Category.DOG_INCLUSIVE:
			family = "SELECTED DOG"
			color = Color(0.57, 0.78, 1.0)
		PetItems.Category.ACTIVE:
			family = "ACTIVE CONSUMABLE" if PetItems.is_consumable(item) else "ACTIVE"
			color = Color(0.92, 0.68, 1.0)
	_label.text = str(item.get("name", "Item")) + "\n" + family + " · " + str(item.get("rarity", "common")).capitalize() + (" · %d bones" % price if price > 0 else "")
	_label.modulate = color
