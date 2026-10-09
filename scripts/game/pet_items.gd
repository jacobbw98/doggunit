class_name PetItems
extends RefCounted

## Each permanent upgrade belongs either to the whole run or one actual pup.
enum Category { GLOBAL_PASSIVE, DOG_INCLUSIVE, ACTIVE }

const CATEGORY_NAMES := {
	Category.GLOBAL_PASSIVE: "GLOBAL PASSIVE",
	Category.DOG_INCLUSIVE: "DOG INCLUSIVE",
	Category.ACTIVE: "ACTIVE"
}

const STARTER_DOGS: Array[Dictionary] = [
	{"id": "mappo", "name": "Mappo", "description": "Fire a heavy explosive bark: 45 base damage per projectile, one shot every 0.9 seconds.", "flavor_text": "Mappo Blappo Holiday Inn", "model_description": "Existing black Mappo mascot with pointed ears, mint collar and blue heart tag.", "notes": "Ok rarity. One projectile. Crit chance 0.1; crit damage multiplier 2. Accuracy 0.9; precision 0.8; knockback stat 5; projectile size 1. Explosion damage falls linearly to zero at radius 12. Damage excludes crits, items and matchup modifiers.", "effect": "explosive", "damage": 45.0, "fire_rate": 0.9, "projectile_speed": 32.0, "max_ammo": 30, "rarity": "Ok", "reload_seconds": 6.750000000000007},
	{"id": "freezing_pup", "name": "Freezing Pup", "description": "Fire freezing projectiles for 10 base damage every 0.2 seconds. Each hit has a 1% freeze chance, increasing by 1% per consecutive hit on that target; each hit refreshes the 0.5-second window. A proc freezes for 2 seconds.", "flavor_text": "Defulat cold cod dog", "model_description": "Existing stylized freezing pup gun.", "notes": "Ok rarity. One projectile. Crit chance 0.1; crit damage multiplier 2. Accuracy 0.9; precision 0.8; knockback stat 5; projectile size 1.", "effect": "freezing", "damage": 10.0, "fire_rate": 0.2, "projectile_speed": 32.0, "max_ammo": 30, "rarity": "Ok", "reload_seconds": 1.5},
	{"id": "implosive_pup", "name": "Implosive Pup", "description": "Fire implosive projectiles for 10 base damage every 0.2 seconds; pull nearby enemies toward impact.", "flavor_text": "Do you believe in gravity", "model_description": "Existing stylized implosive pup gun.", "notes": "Ok rarity. One projectile. Crit chance 0.1; crit damage multiplier 2. Accuracy 0.9; precision 0.8; knockback stat 5; projectile size 1. Impact pull force 15.", "effect": "implosive", "damage": 10.0, "fire_rate": 0.2, "projectile_speed": 32.0, "max_ammo": 30, "rarity": "common", "reload_seconds": 1.5},
]

# Implemented from data/items.csv and data/consumables.csv.
const CATALOG: Array[Dictionary] = [
	{"id": "biscuit", "name": "Treat", "description": "All pups deal 50% more damage.", "flavor_text": "Hungry dungery", "model_description": "dog oreao", "notes": "", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "damage", "multiplier": 1.5},
	{"id": "zoomies", "name": "Zoomies", "description": "Move 12% faster.", "flavor_text": "Sped go fast yes", "model_description": "A bright cartoon lightning bolt", "notes": "", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "speed", "multiplier": 1.12},
	{"id": "squeaker", "name": "Illegal Squeaker", "description": "The selected pup has 18% less time between shots.", "flavor_text": "Banned in seventeen very quiet neighborhoods.", "model_description": "A chocolate duck", "notes": "Multiplier applies to shot interval. 0.82 means about 22% more shots per second.", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "fire_rate", "multiplier": 0.82},
	{"id": "tennis", "name": "Yummy Tennis Ball", "description": "The selected pup fires one extra projectile.", "flavor_text": "Mmmmmm, ball", "model_description": "Lime tennis ball with a white seam and a ghostly offset copy.", "notes": "Adds one projectile per shot; final projectile shot no cap. The dog that recived this item should have the ball in its mouth now with aditional balls joining slightly offset", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "extra_shots", "amount": 1.0},
	{"id": "cone", "name": "Cone?", "description": "Maximum health +25, heal 25.", "flavor_text": "Oh, cone chan", "model_description": "Street cone with an anime girl face", "notes": "This should go on the top of the player, additional ones go on top of the previous", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "health", "amount": 25.0},
	{"id": "flagella", "name": "Flaggela cool", "description": "The selected pup's projectiles travel 30% faster.", "flavor_text": "wiggley Willgly g?", "model_description": "many flaggella wiggling, they all come from a center point and reach outward making a sphere", "notes": "the projectile models gain one flaggella, additional for each item", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "projectile_speed", "multiplier": 1.3},
	{"id": "kibble", "name": "Nutirant Parasite ", "description": "Heal 3 for every defeated enemy.", "flavor_text": "Flesh lost, flesh gained", "model_description": "A small cute tick shpaed parasite", "notes": "", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "heal_on_kill", "amount": 3.0},
	{"id": "tag", "name": "Glasses", "description": "The selected pup gains 10 percentage points of critical chance.", "flavor_text": "Prescription from dr. yes", "model_description": "doggie glasses", "notes": "diminishing returns probability but can stack over 100%; 0.1 means 10 percentage points. Each addition is +99(x/100).", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "crit_chance", "amount": 0.1},
	{"id": "bowl", "name": "Bottomless Water Bowl", "description": "The selected pup gains 12 magazine capacity and 12 ammo.", "flavor_text": "Hydratetion", "model_description": "Blue water bowl with an impossible-looking water surface.", "notes": "", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "ammo", "amount": 12.0},
	{"id": "spring", "name": "Cursed Flea Collar", "description": "Increase jump launch speed by 15%.", "flavor_text": "Funny collar", "model_description": "Spring-shaped cursed collar in the existing cartoon style.", "notes": "Multiplies upward launch velocity, not maximum jump height. Goes on each dog that is equip extending the neck for each additional spring", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "jump", "multiplier": 1.15},
	{"id": "howl_horn", "name": "Sound Stunner", "description": "Blast and stuns nearby enemies for 65 damage. Cooldown: 2 room clears", "flavor_text": "Bwap!", "model_description": "Air horn", "notes": "", "category": Category.ACTIVE, "kind": "active", "rarity": "common", "shop_price": 15, "effect": "howl", "damage": 65.0, "radius": 8.0, "cooldown": 0.0, "cooldown_rooms": 2.0, "stun_duration": 2.0},
	{"id": "med_bowl", "name": "First Aid", "description": "Recover 30 health. Cooldown: 1 room  clear", "flavor_text": "Stich me up", "model_description": "A first aid kit", "notes": "", "category": Category.ACTIVE, "kind": "active", "rarity": "common", "shop_price": 15, "effect": "heal", "amount": 30.0, "cooldown": 0.0, "cooldown_rooms": 1.0},
	{"id": "magnet", "name": "Bone Cactus", "description": "Gives bones spikes that deal current player damage * 0.4", "flavor_text": "Bone hurting juice", "model_description": "A cactus in the shape of a large feemer", "notes": "", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "common", "shop_price": 15, "stat": "bone_stat", "effect": "bone-modifier", "multiplier": 0.4},
	{"id": "leash", "name": "leash", "description": "lets the gun equip walk around and shoot while the player shoot another gun for 12 seconds Cooldown: 4 room clears", "flavor_text": "A short walk", "model_description": "A braided leash with a loop handle and a brass collar clasp.", "notes": "", "category": Category.ACTIVE, "kind": "active", "rarity": "uncommon", "shop_price": 20, "effect": "walkies", "radius": 15.0, "duration": 12.0, "cooldown": 0.0, "cooldown_rooms": 4.0},
	{"id": "boneswarm", "name": "Bone Swarm", "description": "makes it so the bones that come out of enemies swarm towards the nearest enemies dealing 1 damage every time they contact the enemy. The behaviour is that they hone in on the nearest then bounce off after contact and continue to do so until the enemy has died. ", "flavor_text": "Let the bones work for you", "model_description": "swarm of bones", "notes": "synergies with bone cactus: the first time a spikey bone contacts an enemy the bone explods into spines and the spines keep swarming (the bone value the player recives after compleating the room will remain the same)", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "uncommon", "shop_price": 20, "stat": "bone_stat", "effect": "boneswarm", "damage": 1.0},
	{"id": "bounce", "name": "Bouncy", "description": "Makes the pups projectiles bounce off walls and enemys 3 times before stoping", "flavor_text": "Rubber? Yes", "model_description": "A rubber chicken", "notes": "the effect of the projectile goes off for each bounce, a small model is added to the dog gun, each additional one adds another and adds +1 to the max bounces", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "rare", "shop_price": 30, "stat": "projectile_modifier", "effect": "bounce", "amount": 3.0, "stack_increment": 1.0},
	{"id": "homing", "name": "Spoon bender", "description": "projectiles now hone in onto enemies", "flavor_text": "Seems familier somehow", "model_description": "a bent silver spoon", "notes": "every additional spoon adds +1 to projectile speed and whatever the honing acceleration is", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "rare", "shop_price": 30, "stat": "projectile_modifier", "effect": "homing"},
	{"id": "flesh", "name": "Extra Flesh", "description": "increases player health by 1.1 mulitipyer", "flavor_text": "Flesh gained, humanity lost", "model_description": "A cube of flesh", "notes": "each aditional flesh cube adds 0.1 to the multipyer so 2 would be 1.2 and 3 would be 1.3 ect.", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "uncommon", "shop_price": 20, "stat": "health", "multiplier": 1.1, "stack_increment": 0.1},
	{"id": "tofu", "name": "TOFU", "description": "Maximum health +50, heal 50.", "flavor_text": "Vegan addition", "model_description": "A block of tofu", "notes": "aditional tofu increases health stacking, +10 every time", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "uncommon", "shop_price": 20, "stat": "health", "amount": 50.0, "stack_increment": 10.0},
	{"id": "aminita", "name": "Familier Fungus", "description": "doubles the players size and stats", "flavor_text": "Wahooo", "model_description": "An aminita muscari mushroom", "notes": "this item doubles every stat of the player", "category": Category.GLOBAL_PASSIVE, "kind": "passive", "rarity": "legendary", "shop_price": 50, "stat": "all", "multiplier": 2.0},
	{"id": "cubensis", "name": "Magic Mushrrom", "description": "doubles the gun stats", "flavor_text": "Oh ni, de dog eat da mushroom", "model_description": "A wavy cap from p. cubinsis", "notes": "if the player has aminita and the dog has cubensis the synergy is 4x to all stats of the player and gun", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "legendary", "shop_price": 50, "stat": "all", "multiplier": 2.0},
	{"id": "lazer", "name": "Lazer Guided", "description": "changes the projectiles of the gun to be hitscan instead of a moving projectile", "flavor_text": "", "model_description": "A lazer pointer", "notes": "when added to the gun it is like a lazer guided gun addition and changes how projectiles work to hitscan instead of a moving projectile, additional lazers add another lazer to the gun that is equiped only cosmetic", "category": Category.DOG_INCLUSIVE, "kind": "passive", "rarity": "uncommon", "shop_price": 20, "stat": "projectile_modifier", "effect": "hitscan"},
]

const CONSUMABLES: Array[Dictionary] = [
	{"id": "bomb", "name": "Bomb", "description": "Add one bomb. Throw with G; detonates immediately for up to 85 damage within 5 units.", "flavor_text": "Fetch is officially canceled.", "category": Category.ACTIVE, "kind": "consumable", "rarity": "common", "shop_price": 15, "effect": "bomb", "consumable": "bomb", "amount": 1.0, "damage": 85.0, "radius": 5.0, "duration": 0.0},
	{"id": "key", "name": "Key", "description": "Unlock all entrances to one item room or shop. Look at its padlock and press F; consumes one key.", "flavor_text": "Definitely opens something. Eventually.", "category": Category.ACTIVE, "kind": "consumable", "rarity": "common", "shop_price": 15, "effect": "key", "consumable": "key", "amount": 1.0}
]

static func find_item(id: String) -> Dictionary:
	for item in CATALOG + CONSUMABLES:
		if item.id == id:
			return item.duplicate(true)
	return {}

static func category_name(item: Dictionary) -> String:
	return CATEGORY_NAMES.get(int(item.get("category", Category.GLOBAL_PASSIVE)), "GLOBAL PASSIVE")

static func is_active(item: Dictionary) -> bool:
	return item.get("kind", "passive") == "active"

static func is_consumable(item: Dictionary) -> bool:
	return item.get("kind", "passive") == "consumable"

static func rarity_weight(item: Dictionary) -> float:
	return {"common": 1.0, "uncommon": 0.35, "rare": 0.12, "legendary": 0.025}.get(str(item.get("rarity", "common")).to_lower(), 1.0)

static func pick_index(items: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for item in items:
		total += rarity_weight(item)
	var roll := rng.randf() * total
	for i in range(items.size()):
		roll -= rarity_weight(items[i])
		if roll <= 0.0:
			return i
	return maxi(0, items.size() - 1)
