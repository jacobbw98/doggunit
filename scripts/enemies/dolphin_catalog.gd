## Twenty handcrafted silhouettes, grouped into the existing five combat roles.
class_name DolphinCatalog
extends RefCounted

const CATALOG: Array[Dictionary] = [
	{"id": "reef_scout", "name": "Reef Scout", "archetype": 0, "health": 1.0, "speed": 1.0, "interval": 1.0, "theme": "Coral explorer with a knotted kelp scarf."},
	{"id": "sailor", "name": "Deckhand Dolphin", "archetype": 0, "health": 1.10, "speed": 0.92, "interval": 0.95, "theme": "Sailor cap, striped life jacket and a broad tail."},
	{"id": "pearl", "name": "Pearl Courier", "archetype": 0, "health": 0.85, "speed": 1.20, "interval": 1.05, "theme": "Pearl necklace and a shell satchel."},
	{"id": "coral", "name": "Coral Gardener", "archetype": 0, "health": 1.20, "speed": 0.85, "interval": 1.10, "theme": "Branching coral backpack and flower crown."},
	{"id": "comet", "name": "Comet Flipper", "archetype": 1, "health": 0.85, "speed": 1.15, "interval": 0.95, "theme": "Swept comet fins and a star on the forehead."},
	{"id": "racing", "name": "Turbo Porpoise", "archetype": 1, "health": 1.0, "speed": 1.08, "interval": 0.90, "theme": "Racing helmet and twin fin-mounted boosters."},
	{"id": "swordfin", "name": "Swordfin Duelist", "archetype": 1, "health": 1.10, "speed": 0.95, "interval": 1.0, "theme": "Long dolphin beak, fencing mask and blade dorsal fin."},
	{"id": "storm", "name": "Storm Skimmer", "archetype": 1, "health": 0.90, "speed": 1.12, "interval": 1.10, "theme": "Lightning fins and a billowing cloud backpack."},
	{"id": "lighthouse", "name": "Lighthouse Lookout", "archetype": 2, "health": 1.10, "speed": 0.90, "interval": 1.05, "theme": "Tall lighthouse helmet and telescope goggles."},
	{"id": "scholar", "name": "Sonar Scholar", "archetype": 2, "health": 0.95, "speed": 1.10, "interval": 0.95, "theme": "Oversized round spectacles, mortarboard and book saddle."},
	{"id": "cosmic", "name": "Cosmic Listener", "archetype": 2, "health": 1.0, "speed": 1.0, "interval": 1.0, "theme": "Ringed-planet dorsal fin and satellite antennae."},
	{"id": "icicle", "name": "Icicle Oracle", "archetype": 2, "health": 0.90, "speed": 1.08, "interval": 1.12, "theme": "Angular ice-crystal fins and a frosty hood."},
	{"id": "anchor", "name": "Anchor Hauler", "archetype": 3, "health": 1.15, "speed": 0.90, "interval": 1.08, "theme": "Heavy anchor pack, rope belt and brass diving helmet."},
	{"id": "armored", "name": "Reef Juggernaut", "archetype": 3, "health": 1.25, "speed": 0.85, "interval": 1.0, "theme": "Layered shell armor and reinforced square flippers."},
	{"id": "volcano", "name": "Volcano Belcher", "archetype": 3, "health": 1.0, "speed": 1.0, "interval": 0.90, "theme": "Smoking volcano dorsal cone and obsidian plates."},
	{"id": "puffer", "name": "Puffer Bruiser", "archetype": 3, "health": 0.95, "speed": 1.10, "interval": 1.05, "theme": "Round dolphin body wearing a prickly puffer vest."},
	{"id": "crown", "name": "THE REEF REGENT", "archetype": 4, "health": 1.05, "speed": 0.95, "interval": 1.0, "theme": "Five-point coral crown, royal cape and golden fins."},
	{"id": "pirate", "name": "CAPTAIN BLACKFIN", "archetype": 4, "health": 0.95, "speed": 1.10, "interval": 0.95, "theme": "Tricorn hat, eye patch, hook flipper and treasure chest."},
	{"id": "kraken", "name": "KRAKEN'S BEST FRIEND", "archetype": 4, "health": 1.15, "speed": 0.90, "interval": 1.10, "theme": "Dolphin knight in a many-tentacled octopus cloak."},
	{"id": "clockwork", "name": "ADMIRAL TICKTOCK", "archetype": 4, "health": 1.0, "speed": 1.0, "interval": 0.90, "theme": "Brass clockwork dolphin with cog fins and wind-up key."},
]

static func for_archetype(kind: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in CATALOG:
		if int(definition.archetype) == kind:
			result.append(definition)
	return result

static func pick_for_archetype(kind: int, rng: RandomNumberGenerator) -> Dictionary:
	var choices := for_archetype(kind)
	if choices.is_empty():
		return CATALOG[0]
	return choices[rng.randi_range(0, choices.size() - 1)]

static func get_definition(id: String) -> Dictionary:
	for definition in CATALOG:
		if definition.id == id:
			return definition
	return {}

static func model_path(id: String) -> String:
	return "res://assets/enemies/dolphins/%s.glb" % id
