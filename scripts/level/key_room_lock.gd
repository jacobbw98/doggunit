## An F interaction at the entrance, using the existing item prompt selection.
extends Node3D

var portal: PortalDoor
var room_id: int = -1
var _busy: bool = false

func configure(door: PortalDoor) -> void:
	portal = door
	if is_instance_valid(door.source_room):
		room_id = int(door.source_room.get("room_id"))
	set_meta("room_id", room_id)

func _ready() -> void:
	name = "KeyRoomInteraction"
	add_to_group("item_interactables")

func requires_interaction() -> bool:
	return true

func get_interaction_position() -> Vector3:
	return portal.to_global(Vector3(0, 0, 0.20)) if is_instance_valid(portal) else global_position

func _can_reach(actor_run: Node) -> bool:
	return is_instance_valid(portal) and portal.key_locked and portal.available and RoomEconomy.can_interact(actor_run, portal.source_room, self)

func get_interaction_text(actor_run: Node) -> String:
	if _busy or not _can_reach(actor_run):
		return ""
	if portal.combat_locked:
		return "Clear the room before unlocking"
	var locked_room := portal.get_key_locked_room()
	if not is_instance_valid(locked_room):
		return ""
	var room_name: String = RoomTypes.ROOM_NAMES.get(int(locked_room.get("room_type")), "Room")
	return "Unlock %s · 1 key%s" % [room_name, " (no keys)" if int(actor_run.get("keys")) < 1 else ""]

func interact(actor_run: Node) -> bool:
	if _busy or not _can_reach(actor_run) or portal.combat_locked:
		return false
	var locked_room := portal.get_key_locked_room()
	if not is_instance_valid(locked_room) or not locked_room.has_method("unlock_with_key"):
		return false
	_busy = true
	var unlocked: bool = locked_room.unlock_with_key(actor_run)
	_busy = false
	return unlocked
