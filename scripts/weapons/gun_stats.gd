# Gun Stats Resource
# Stats correspond to gun types:
# - Kinetic (Explosive): damage, projectile size
# - Potential (Implosive): knockback, speed (player & projectiles)
# - Entropy (Freezing): projectile count, crit damage
# - Order (Accelerating): accuracy, precision, crit ratio
class_name GunStats
extends Resource

@export var gun_name: String = "Unnamed Dog"
@export_multiline var description: String = ""
@export_multiline var flavor_text: String = ""
## Breed and elemental type are independent. Empty keeps the original starter visual.
@export var breed_id: String = ""
@export var gun_type: GunTypes.Type = GunTypes.Type.EXPLOSIVE
@export var rarity: GunTypes.Rarity = GunTypes.Rarity.OK
## Opt in for Mappo's personal model; ordinary explosive drops keep their pup visual.
@export var mascot_visual: bool = false

# Base stats (scaled by rarity)
@export_group("Kinetic Stats (Explosive)")
@export var base_damage: float = 10.0
@export var projectile_size: float = 1.0

@export_group("Potential Stats (Implosive)")
@export var knockback_force: float = 5.0
@export var projectile_speed: float = 20.0

@export_group("Entropy Stats (Freezing)")
@export var projectile_count: int = 1
@export var crit_damage_multiplier: float = 2.0

@export_group("Order Stats (Accelerating)")
@export var accuracy: float = 0.9  # 0-1, higher = more accurate
@export var precision: float = 0.8  # Spread reduction
@export var crit_chance: float = 0.1  # 0-1

@export_group("Ammo")
@export var max_ammo: int = 30
@export var fire_rate: float = 0.2  # Seconds between shots
## Negative derives a breed-specific time; a positive CSV value overrides it.
@export var reload_seconds: float = -1.0
const INITIAL_SUSTAINED_DPS: float = 44.0

func get_reload_seconds() -> float:
	if reload_seconds > 0.0:
		return reload_seconds
	# Balance full magazines including the last shot's cooldown, standard crits,
	# and reload. Rarity and acquired items intentionally increase this baseline.
	var expected_hit := base_damage * projectile_count * (1.0 + crit_chance * (crit_damage_multiplier - 1.0))
	return maxf(0.35, max_ammo * expected_hit / INITIAL_SUSTAINED_DPS - max_ammo * fire_rate)

func get_initial_sustained_dps() -> float:
	var expected_hit := base_damage * projectile_count * (1.0 + crit_chance * (crit_damage_multiplier - 1.0))
	return max_ammo * expected_hit / (max_ammo * fire_rate + get_reload_seconds())

# Get damage with rarity scaling
func get_scaled_damage() -> float:
	return base_damage * GunTypes.RARITY_MULTIPLIERS[rarity]

func get_scaled_knockback() -> float:
	return knockback_force * GunTypes.RARITY_MULTIPLIERS[rarity]

func get_scaled_projectile_speed() -> float:
	return projectile_speed * GunTypes.RARITY_MULTIPLIERS[rarity]

func get_scaled_crit_damage() -> float:
	return crit_damage_multiplier * GunTypes.RARITY_MULTIPLIERS[rarity]

func get_scaled_crit_chance() -> float:
	# Crit chance scales at half rate to prevent 100% crit
	return min(crit_chance * (1.0 + (GunTypes.RARITY_MULTIPLIERS[rarity] - 1.0) * 0.5), 0.75)

# Calculate actual projectile count (can increase with rarity for Entropy guns)
func get_projectile_count() -> int:
	if gun_type == GunTypes.Type.FREEZING:
		return projectile_count + int(GunTypes.RARITY_MULTIPLIERS[rarity] - 1)
	return projectile_count

# Check if this shot is a critical hit
func roll_crit() -> bool:
	return randf() < get_scaled_crit_chance()

# Get the primary stat for this gun's type
func get_primary_stat_value() -> float:
	match gun_type:
		GunTypes.Type.EXPLOSIVE:
			return get_scaled_damage()
		GunTypes.Type.IMPLOSIVE:
			return get_scaled_knockback()
		GunTypes.Type.FREEZING:
			return float(get_projectile_count())
		GunTypes.Type.ACCELERATING:
			return accuracy * precision
	return 0.0

func get_display_name() -> String:
	var rarity_name = GunTypes.get_rarity_name(rarity)
	var type_name = GunTypes.get_type_name(gun_type)
	return "[%s] %s (%s)" % [rarity_name, gun_name, type_name]
