# Weapon Manager - Handles 3-gun inventory
class_name WeaponManager
extends Node3D

signal weapon_switched(gun_index: int, gun: Gun)
signal weapon_picked_up(gun: Gun)
signal weapon_dropped(gun: Gun)
signal inventory_full()

const MAX_GUNS := 3

# Gun inventory (max 3)
var guns: Array[Gun] = []
var current_gun_index: int = -1

# Reference to where guns are held
@export var gun_holder: Node3D

func _ready() -> void:
	# Initialize empty slots
	guns.resize(MAX_GUNS)
	
	# Auto-find gun holder if not set
	if not gun_holder:
		gun_holder = get_node_or_null("GunHolder")
	if not gun_holder:
		gun_holder = self  # Use self as fallback
		print("[WeaponManager] Using self as gun_holder")
	else:
		print("[WeaponManager] Gun holder found: %s" % gun_holder.name)

func _process(_delta: float) -> void:
	_handle_weapon_switch_input()

func _handle_weapon_switch_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		switch_to_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_to_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"):
		switch_to_weapon(2)

func switch_to_weapon(index: int) -> void:
	if index < 0 or index >= MAX_GUNS:
		return
	
	if guns[index] == null:
		return
	
	# Hide current gun
	if current_gun_index >= 0 and guns[current_gun_index]:
		guns[current_gun_index].visible = false
	
	# Show new gun
	current_gun_index = index
	guns[current_gun_index].visible = true
	
	weapon_switched.emit(current_gun_index, guns[current_gun_index])

func get_current_gun() -> Gun:
	if current_gun_index < 0 or current_gun_index >= MAX_GUNS:
		return null
	return guns[current_gun_index]

func fire(origin: Vector3, direction: Vector3, w_position: float = 0.0) -> void:
	var gun = get_current_gun()
	if gun:
		print("[WeaponManager] Firing gun at index %d" % current_gun_index)
		gun.fire(origin, direction, w_position)
	else:
		print("[WeaponManager] Cannot fire - no gun equipped (index: %d)" % current_gun_index)

func reload() -> void:
	var gun = get_current_gun()
	if gun:
		gun.reload()

# Pickup a new gun - returns the dropped gun if inventory was full
func pickup_gun(new_gun: Gun) -> Gun:
	print("[WeaponManager] Picking up gun: %s" % (new_gun.stats.get_display_name() if new_gun.stats else "Unknown"))
	
	# Find empty slot
	for i in range(MAX_GUNS):
		if guns[i] == null:
			_add_gun_to_slot(new_gun, i)
			weapon_picked_up.emit(new_gun)
			
			# Auto-switch if this is first gun
			if current_gun_index < 0:
				switch_to_weapon(i)
			print("[WeaponManager] Gun added to slot %d" % i)
			return null
	
	# Inventory full - swap with current gun
	inventory_full.emit()
	return swap_current_gun(new_gun)

func swap_current_gun(new_gun: Gun) -> Gun:
	if current_gun_index < 0:
		return pickup_gun(new_gun)
	
	var old_gun = guns[current_gun_index]
	
	# Remove old gun from holder
	if old_gun and old_gun.get_parent() == gun_holder:
		gun_holder.remove_child(old_gun)
	
	# Add new gun
	_add_gun_to_slot(new_gun, current_gun_index)
	
	weapon_dropped.emit(old_gun)
	weapon_picked_up.emit(new_gun)
	weapon_switched.emit(current_gun_index, new_gun)
	
	return old_gun

func _add_gun_to_slot(gun: Gun, slot: int) -> void:
	guns[slot] = gun
	
	if gun_holder:
		gun_holder.add_child(gun)
		gun.position = Vector3.ZERO
		
		# Hide if not current weapon
		gun.visible = (slot == current_gun_index)

func drop_current_gun() -> Gun:
	if current_gun_index < 0:
		return null
	
	var dropped = guns[current_gun_index]
	
	if dropped and dropped.get_parent() == gun_holder:
		gun_holder.remove_child(dropped)
	
	guns[current_gun_index] = null
	weapon_dropped.emit(dropped)
	
	# Switch to another gun if available
	for i in range(MAX_GUNS):
		if guns[i] != null:
			switch_to_weapon(i)
			return dropped
	
	current_gun_index = -1
	return dropped

func get_gun_count() -> int:
	var count = 0
	for gun in guns:
		if gun != null:
			count += 1
	return count

func is_inventory_full() -> bool:
	return get_gun_count() >= MAX_GUNS
