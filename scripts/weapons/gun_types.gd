# Gun Types - Rock Paper Scissors System
# Implosive beats Explosive, Freezing beats Implosive, 
# Accelerating beats Freezing, Explosive beats Accelerating
class_name GunTypes
extends RefCounted

enum Type {
	EXPLOSIVE,    # Kinetic stat - damage and size
	IMPLOSIVE,    # Potential stat - knockback and speed
	FREEZING,     # Entropy stat - projectile count and crit damage
	ACCELERATING  # Order stat - accuracy, precision, crit ratio
}

enum Rarity {
	POOR,
	MID,
	OK,
	EPIC,
	LEGENDARY,
	PEAK
}

# Rarity stat multipliers
const RARITY_MULTIPLIERS := {
	Rarity.POOR: 0.5,
	Rarity.MID: 0.75,
	Rarity.OK: 1.0,
	Rarity.EPIC: 1.5,
	Rarity.LEGENDARY: 2.0,
	Rarity.PEAK: 3.0
}

# Rarity colors for UI
const RARITY_COLORS := {
	Rarity.POOR: Color(0.5, 0.5, 0.5),      # Gray
	Rarity.MID: Color(0.8, 0.8, 0.8),       # Light gray
	Rarity.OK: Color(0.2, 0.8, 0.2),        # Green
	Rarity.EPIC: Color(0.6, 0.2, 0.8),      # Purple
	Rarity.LEGENDARY: Color(1.0, 0.8, 0.0), # Gold
	Rarity.PEAK: Color(1.0, 0.2, 0.4)       # Red/Pink
}

# Type effectiveness - returns damage multiplier
static func get_effectiveness(attacker_type: Type, defender_type: Type) -> float:
	# Same type = neutral
	if attacker_type == defender_type:
		return 1.0
	
	# Check if attacker beats defender
	match attacker_type:
		Type.IMPLOSIVE:
			if defender_type == Type.EXPLOSIVE:
				return 1.5  # Super effective
		Type.FREEZING:
			if defender_type == Type.IMPLOSIVE:
				return 1.5
		Type.ACCELERATING:
			if defender_type == Type.FREEZING:
				return 1.5
		Type.EXPLOSIVE:
			if defender_type == Type.ACCELERATING:
				return 1.5
	
	# Check if defender resists attacker (reverse matchup)
	match defender_type:
		Type.IMPLOSIVE:
			if attacker_type == Type.EXPLOSIVE:
				return 0.5  # Not very effective
		Type.FREEZING:
			if attacker_type == Type.IMPLOSIVE:
				return 0.5
		Type.ACCELERATING:
			if attacker_type == Type.FREEZING:
				return 0.5
		Type.EXPLOSIVE:
			if attacker_type == Type.ACCELERATING:
				return 0.5
	
	return 1.0  # Neutral

static func get_type_name(type: Type) -> String:
	match type:
		Type.EXPLOSIVE: return "Explosive"
		Type.IMPLOSIVE: return "Implosive"
		Type.FREEZING: return "Freezing"
		Type.ACCELERATING: return "Accelerating"
	return "Unknown"

static func get_rarity_name(rarity: Rarity) -> String:
	match rarity:
		Rarity.POOR: return "Poor"
		Rarity.MID: return "Mid"
		Rarity.OK: return "Ok"
		Rarity.EPIC: return "Epic"
		Rarity.LEGENDARY: return "Legendary"
		Rarity.PEAK: return "Peak"
	return "Unknown"
