# Editing the item catalog

Edit the CSV files in Excel, a spreadsheet editor, or a text editor:

- `items.csv`: 22 passive and active items.
- `consumables.csv`: bombs and keys.
- `dogs_guns.csv`: the three starter dogs and 20 collectible breed guns with their weapon stats.

Their current names, effects, flavor text, and values are implemented. Model descriptions guide future asset changes. The header is now spelled `rarity`.

The October 8 additions and their requested models are implemented. Stacking
is unlimited by design: the goal is to break the game through combinations.
Rare items use a selection weight of 0.12 and legendary items 0.025. Repeated
Spoon bender copies add projectile speed and homing acceleration; repeated
Bouncy copies add ricochets. Lazer Guided copies add visible pointers without
adding another mechanical hitscan conversion. Every dog now plays a UniMate
motion clip during reload, stretched to its recorded reload duration.
`reload_seconds` records the full dog reload animation duration, excluding
the previous shot's remaining cooldown. `sustained_dps` includes that cooldown,
magazine capacity, reload time and default criticals. The initial Ok catalog
targets 44 expected DPS (40 before criticals), before area effects, matchup
bonuses or items. Edit reload duration like other catalog values and ask Codex
to apply it. Reloads range from 1.32 to 6.75 seconds across the current dogs.

Freezing now builds per-target hit chance, starting at 1% and adding 1% per
hit. Every hit refreshes a 0.5-second window; a longer gap resets the chain.
Hits at 100% guarantee a two-second freeze. Item rooms and shops require one
key to unlock all their entrances; F interacts with their brass padlock.
Runs start with one key and each second combat-room clear earns another.

Keep an existing `item_id` when modifying an item. Add a row with a unique ID for a new item. Fill in `item_name`, `what_it_does`, `flavor_text`, and `model_description`, then set the relevant numeric columns. Leave irrelevant fields blank. Use `notes` to describe new mechanics, appearance references, or anything the existing columns cannot express.

Numeric multipliers are factors: 1.5 means 50% more. For the `fire_rate` stat, 0.82 multiplies time between shots, giving an 18% shorter interval (about 22% more shots per second). A larger `shot_interval_seconds` fires more slowly. Durations, `cooldown_seconds`, and `stun_seconds` are seconds; distances are game units. Blank means not applicable, while 0 is an explicit value. The bomb's edited 0-second duration means instant detonation on the first physics tick after placement.

Use `cooldown_rooms` for room-based recovery. First Aid requires one combat-room clear, Sound Stunner two, and Walkies four. Sound Stunner stuns for two seconds; bosses resist the duration. Walkies sends the actual equipped dog out for 12 seconds and selects another dog to hold. At least two dogs are required. Time, revisiting a cleared room, and swapping active items cannot recharge the slot. Cooldown survives floor changes; companions return before floor generation.

Glasses add 0.1 crit probability on the first copy, then 0.1 × 0.99 per successive copy. Chance may exceed 100%. At 110%, every shot has one guaranteed crit tier, with a 10% chance of a second tier. With crit multiplier X, those damages are X and X². Extra shots have no item cap; every collected tennis ball adds a projectile and a visible mouth ball. Flagella adds one animated strand to every projectile per copy. Cones stack on the player, and spring collars stack and extend every held dog's neck.

Bone Cactus is a passive. Each copy adds 40% of the currently selected dog's noncritical, item-scaled shot damage to bone pickups. A regular bone may hit each enemy once before collection; enemy matchup modifiers still apply. With Bone Swarm, bones home toward enemies, damage them on repeated contacts, and split into eight spines on their first contact. Only the original spine carries currency, which is banked when the room clears. Pickups only damage enemies in their owning room and W layer.

Weapon damage is base damage per projectile at Ok rarity, before critical hits, item bonuses, matchup modifiers, and explosion falloff. Mappo now has 45 damage and a 0.9-second shot interval. Other starter pups retain 10 damage and a 0.2-second interval.

The 20 collectible breeds each roll their type once when an enemy spawns: 25% Explosive, 25% Implosive, 25% Freezing, and 25% Accelerating, independently of breed. Breed controls appearance and base stats; type controls the existing projectile effects and matchups. Each defeated dolphin has a 5% chance of dropping the dog it carried. The drop preserves that breed, type, and player weapon stats; enemy attack damage is tuned separately. This chance is editable on RunManager (`gun_drop_chance`). Look at a dropped dog and press F to collect it. With three dogs already held, the selected dog swaps onto the same pickup; its ammo and dog-specific item bindings stay with it. Pickups belong to their room and W layer, and disappear when leaving the floor.

Categories are `starter_weapon`, `global_passive`, `dog_inclusive`, `active`, and `consumable`. Dog-inclusive items bind to the individual pup selected when collected. Passive copies stack; active items occupy one slot and share its cooldown. Bombs and keys use counters. Shop prices come from `shop_price_bones`. Common items have selection weight 1; uncommon items have weight 0.35. Dogs retain the existing weapon rarity scale; `common` maps to `Ok`.

This CSV is a design catalog, not a live game importer. After editing, ask Codex to apply the catalog changes. Codex can compare the rows with the implemented items, update mechanics and descriptions, build or revise models, and verify the result. New mechanics need implementation; adding a CSV row alone does not add an item to the game.
