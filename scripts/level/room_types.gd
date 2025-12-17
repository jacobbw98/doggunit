# RoomTypes - Enum and data for room types in procedural levels
class_name RoomTypes
extends RefCounted

## Room type enumeration
enum Type {
	NORMAL,     # Combat encounter
	BOSS,       # Boss fight (2x size)
	ITEM,       # Free item reward
	SHOP,       # Buy items with currency
	GAMBLING,   # Risk/reward mechanics
	SPECIAL     # Unique encounter
}

## Room colors by type
const ROOM_COLORS: Dictionary = {
	Type.NORMAL: Color(0.2, 0.8, 1.0, 1.0),   # Cyan
	Type.BOSS: Color(1.0, 0.2, 0.2, 1.0),     # Red
	Type.ITEM: Color(1.0, 0.85, 0.2, 1.0),    # Gold
	Type.SHOP: Color(1.0, 0.6, 0.2, 1.0),     # Orange
	Type.GAMBLING: Color(0.6, 0.2, 1.0, 1.0), # Purple
	Type.SPECIAL: Color(0.2, 0.4, 1.0, 1.0)   # Blue
}

## Room size multipliers
const ROOM_SIZES: Dictionary = {
	Type.NORMAL: 1.0,    # Base size (some can be 1.5x, set separately)
	Type.BOSS: 2.0,      # Boss rooms are 2x size
	Type.ITEM: 1.0,
	Type.SHOP: 1.0,
	Type.GAMBLING: 1.0,
	Type.SPECIAL: 1.0
}

## Room display names
const ROOM_NAMES: Dictionary = {
	Type.NORMAL: "Combat Room",
	Type.BOSS: "Boss Room",
	Type.ITEM: "Item Room",
	Type.SHOP: "Shop",
	Type.GAMBLING: "Gambling Room",
	Type.SPECIAL: "??? Room"
}

## Get color for room type
static func get_color(type: Type) -> Color:
	return ROOM_COLORS.get(type, Color.WHITE)

## Get size multiplier for room type
static func get_size_multiplier(type: Type) -> float:
	return ROOM_SIZES.get(type, 1.0)

## Get display name for room type
static func get_name(type: Type) -> String:
	return ROOM_NAMES.get(type, "Unknown")

## Get random normal size (some are 1.5x)
static func get_random_normal_size() -> float:
	# 30% chance for a large normal room
	return 1.5 if randf() < 0.3 else 1.0
