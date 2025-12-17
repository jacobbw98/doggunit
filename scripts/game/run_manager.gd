# Run Manager - Handles roguelike progression
class_name RunManager
extends Node

signal floor_changed(floor_number: int)
signal item_acquired(item_name: String)

var current_floor: int = 1
var max_floors: int = 10

# Items/modifiers collected during this run
var run_modifiers: Array[Dictionary] = []

func _ready() -> void:
	pass

func start_new_run() -> void:
	current_floor = 1
	run_modifiers.clear()
	floor_changed.emit(current_floor)

func advance_floor() -> void:
	current_floor += 1
	floor_changed.emit(current_floor)
	
	if current_floor > max_floors:
		GameManager.end_run(true)

func add_modifier(modifier: Dictionary) -> void:
	# Modifier format:
	# {
	#   "name": "Fire Rate Up",
	#   "stat": "fire_rate",
	#   "multiplier": 0.9,  # 10% faster
	#   "type_restriction": GunTypes.Type.EXPLOSIVE  # Optional, -1 for all
	# }
	run_modifiers.append(modifier)
	item_acquired.emit(modifier.name)

func get_stat_multiplier(stat_name: String, gun_type: GunTypes.Type) -> float:
	var multiplier = 1.0
	
	for mod in run_modifiers:
		if mod.stat == stat_name:
			# Check if modifier applies to this gun type
			if mod.has("type_restriction") and mod.type_restriction >= 0:
				if mod.type_restriction != gun_type:
					continue
			
			multiplier *= mod.multiplier
	
	return multiplier

func get_floor_difficulty_multiplier() -> float:
	# Enemies get stronger each floor
	return 1.0 + (current_floor - 1) * 0.2
