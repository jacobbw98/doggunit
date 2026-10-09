class_name DogGunPickup
extends Node3D

var run: Node
var room: Node3D
var room_id: int = -1
var gun: Gun
var available := true
var _busy := false
var _label: Label3D
var _stand: Node3D
var _age := 0.0
var _gun_base_y := 1.05
var _visual_center := Vector3.ZERO

func configure(owner_run: Node, owning_room: Node3D, dropped_gun: Gun) -> void:
	run = owner_run
	room = owning_room
	room_id = int(room.get("room_id"))
	gun = dropped_gun
	set_meta("room_id", room_id)

func _ready() -> void:
	name = "DroppedDogGun"
	add_to_group("dog_gun_pickups")
	add_to_group("item_interactables")
	_stand = RoomEconomy.make_model("pedestal", 0.9, true)
	add_child(_stand)
	_label = RoomEconomy.make_label("", Color.WHITE)
	_label.position.y = 2.0
	add_child(_label)
	_show_gun()

func _process(delta: float) -> void:
	visible = available and RoomEconomy.room_visible(run, room)
	_age += delta
	if is_instance_valid(gun) and not gun.is_reloading:
		gun.position.y = _gun_base_y + sin(_age * 2.0) * 0.06

func requires_interaction() -> bool:
	return true

func get_interaction_position() -> Vector3:
	return gun.to_global(_visual_center) if is_instance_valid(gun) else to_global(Vector3(0.0, 1.1, 0.0))

func get_interaction_text(actor_run: Node) -> String:
	if not available or _busy or not is_instance_valid(gun) or not RoomEconomy.can_interact(actor_run, room, self):
		return ""
	var inventory: WeaponManager = actor_run.get("player").weapon_manager
	var action := "Swap held dog for" if inventory.is_inventory_full() else "Pick up"
	return "%s %s" % [action, gun.stats.get_display_name()]

func interact(actor_run: Node) -> bool:
	if not available or _busy or not is_instance_valid(gun) or not RoomEconomy.can_interact(actor_run, room, self):
		return false
	var inventory: WeaponManager = actor_run.get("player").weapon_manager
	var selected: Gun = inventory.get_current_gun()
	if inventory.is_inventory_full() and (not is_instance_valid(selected) or selected.get_meta("on_walkies", false)):
		return false
	_busy = true
	var acquired := gun
	remove_child(acquired)
	acquired.transform = Transform3D.IDENTITY
	var previous: Gun = inventory.pickup_gun(acquired)
	acquired.refresh_item_visuals()
	actor_run.pickup_message.emit("Picked up " + acquired.stats.get_display_name())
	actor_run.status_changed.emit()
	if is_instance_valid(previous):
		# Retain the same object, ammo, and item bindings when a full pack swaps.
		gun = previous
		_show_gun()
		_busy = false
	else:
		gun = null
		available = false
		remove_from_group("dog_gun_pickups")
		remove_from_group("item_interactables")
		queue_free()
	return true

func _show_gun() -> void:
	if not is_instance_valid(gun):
		return
	if gun.get_parent() != self:
		add_child(gun)
	gun.transform = Transform3D.IDENTITY
	gun.scale = Vector3.ONE * 3.0
	gun.visible = true
	gun.refresh_item_visuals()
	# Held offsets vary by model. Center the actual visual on its stand rather
	# than burying a whole breed's legs inside the pedestal when scaled up.
	var bounds := RoomEconomy.model_bounds(gun)
	_visual_center = bounds.get_center()
	_gun_base_y = 0.95 - bounds.position.y * 3.0
	gun.position = Vector3(-_visual_center.x * 3.0, _gun_base_y, -_visual_center.z * 3.0)
	gun.rebase_reload_animation(gun.transform)
	_label.position.y = maxf(2.0, 0.95 + bounds.size.y * 3.0 + 0.2)
	_label.text = "%s\n%s · %s\n%.0f damage · %.2fs · %d/%d ammo" % [gun.stats.gun_name, GunTypes.get_rarity_name(gun.stats.rarity), GunTypes.get_type_name(gun.stats.gun_type), gun.stats.get_scaled_damage(), gun.stats.fire_rate, gun.current_ammo, gun.get_magazine_size()]
	_label.modulate = GunTypes.RARITY_COLORS[gun.stats.rarity]
