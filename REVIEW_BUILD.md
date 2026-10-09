# Doggun'it — playtest build

2026-10-09. Jacob approved publishing this gameplay version to GitHub. It includes the mossy forest, 20 dolphin enemies, 20 collectible dog breeds, the expanded item catalogs, stacking freeze chance, key-locked shops/item rooms, and UniMate reload animations balanced for initial sustained DPS. The latest mechanics and animation licensing are documented in [PROJECT_WIKI.md](PROJECT_WIKI.md) and [data/ITEM_CATALOG.md](data/ITEM_CATALOG.md). All 24 regression suites passed, with affected checks rerun after the final fixes.

The October 2 review notes below describe the earlier baseline. Existing Godot AI plugin updates are separate from this gameplay work; Godot regenerates editor caches when importing the project.

## Play

Press **F5** in Godot to open the new menu. Choose a seed to reproduce a layout, or leave it blank. Suggested test seed: **20260929**.

- WASD / mouse: move and look. Movement defaults to 8 units/second (the former running speed); there is no sprint control. Space: jump/bunny hop. Ctrl or C: slide.
- Left click: fire. R: reload. 1/2/3: Mappo (explosive), freezing, implosive pups.
- Walk near free pedestal items to collect them automatically. F: buy shop stock, spin a slot machine, or leave a cleared boss room. E: activate the equipped item. G: throw a bomb.
- Q: toggle sniffing. In a room with a hidden scent, approach the walls to reveal a secret doorway.
- Esc: pause/resume and inspect passives by family/dog, the active slot, bones, bombs, and keys. Backtick/F1: debug console during active play.
- The top-right map reveals **only rooms you enter**, including boss and secret rooms. It resets each floor. Aim at a doorway to highlight its explored destination yellow; aiming does not reveal unvisited rooms.
- Nearby item descriptions and ownership appear directly below the map. Shop items and the slot machine show their F-key action there.

Walk through colored doors, clear encounters, and walk near free pedestal items to collect them during play. Each item room offers two items; choosing one removes the other. Inventory and currency carry across three floors. Defeating the alpha leaves gameplay active for collecting its bones and shopping; use F in the cleared boss room to advance, or finish the run after the third boss. Best score, completed walks, and victories persist in Godot's `user://progress.cfg`.

Doors seal while enemies remain in either connected room and reopen after the last enemy dies. Locked doors retain their glow; open doorways have no tinted or glowing surface, so the destination is fully visible. A door closing behind a new encounter lets the entering player finish crossing naturally. Hidden secret door discovery remains separate from combat locks.

## Fixes

- Decoration normalization preserves imported mesh transforms; trees, rocks, houses, and wells stand upright and rest on the interior surface.
- Generation guarantees a connected graph and validates room placement. All door-linked spheres physically adjoin; arbitrary long-distance links are gone.
- Portals commit **W only**, preserving XYZ and velocity. Crossing is continuous; the player moves once per physics tick. Backing away does not transition. Walking and jumping share the same crossing rule.
- Gravity transport preserves facing through opposing surfaces. Hidden/off-graph portals cannot bypass wall collision.
- Knockback is applied once instead of repeatedly accumulating. Frozen players still fall and collide. The console's god mode now works.
- Projectile movement uses swept collision, skips open doorways, prevents repeat impacts, and filters W. Factory placement and crit handling avoid transform errors and double critical damage.
- Inventory HUD initializes all slots and does not duplicate ammo signal connections when swapping.
- Regenerating floors cleans up old rooms, occupants, projectiles, pedestals, bone drops, bombs, ghosts, and slicer registrations.
- Enemies use their encounter room's gravity at shared portal boundaries. A neighboring room cannot pull or clamp them through a closed seal; post-movement containment also covers frozen knockback.

## First playable Future Objectives pass

- Three seeded layout styles, varied room sizes, biome colors, and decoration mixes.
- Secret kennels at distinct home W values, with proximity-based sniff discovery.
- Grunt, rusher, sniper, brute, and alpha boss silhouettes/behavior; telegraphed attacks and a half-health boss phase.
- Three-floor progression, room-clear healing, item choices, restart, victory/defeat, persistent records.
- Thirteen original pet items in three families, plus bomb/key consumables; physical item choices, bone currency, Mildred's shops, and gambling.
- Main menu, seed validation, field guide, pause/inventory, active-item and currency HUD, boss health, result screens, and explored-only minimap.

## Items, bones, shops, and gambling

The ten existing passives are organized into five **global** items (Forbidden Biscuit, 3 AM Zoomies, Cone of Invincibility-ish, Vampire Kibble, Cursed Flea Collar) and five **dog inclusive** items (Illegal Squeaker, Quantum Tennis Ball, Unreasonably Long Leash, World's Okayest Dog Tag, Bottomless Water Bowl). Dog inclusive items bind to the actual selected dog instance at pickup: switching or repicking that dog preserves them, while another dog of the same type or slot gets none of its benefits.

Three **active** items share one slot: Howl Horn deals 65 explosive damage within 8 units with a 12-second cooldown; Emergency Treat Bowl heals 30 with a 20-second cooldown; Bone Magnet multiplies bone pull by 2.75 for 8 seconds with an 18-second cooldown. Swapping leaves the old active on the pedestal and preserves cooldown. Bombs and keys belong to the active family as consumables but use separate counters. Bombs thrown with G have a 1.8-second fuse and 5-unit blast: 85 explosive damage with 55% linear distance falloff, plus 20 player damage inside 3 units. Keys are stored and currently do nothing.

Enemy deaths scatter larger, softly glowing bones for 1.15 seconds before they drift toward the player. Death hooks also cover externally spawned enemies killed before the next run tick. Four bone models are aesthetic variants; white is worth 1, silver 5, and gold 10. Base payout ranges are 1–3 for grunt/rusher, 3–6 for sniper, 5–9 for brute, and 20–35 for boss. Higher health can promote a payout tier; payouts scale by 1.0/1.3/1.6 on floors 1/2/3. Bones stay inside their owning room and cannot be collected through a different W layer.

Mildred, the white calico cat from the supplied photos, sits on three stacked cardboard boxes at the player's dog-gun height, tracking the equipped dog while the player is in her shop. Shops have 1–3 offerings drawn from items and consumables, each costing 15 bones. Shop displays and gambling machines spawn at least 14 metres along the floor from entry, with a 10-metre clear corridor beyond every portal opening and model footprint, including hidden doors. Gambling rooms contain a slot machine costing 3 bones per spin: 49% nothing, 20% an item pedestal, 30% 5 or 10 bones, and 1% an exploding jackpot that destroys the machine and credits 100 bones. Purchases, linked item choices, and payouts are guarded against duplicate collection.

All items and economy props have native Katamari-inspired low-poly 3D models. The 23 GLBs in `assets/items/` cover 13 items, two consumables, four bone shapes, a pedestal, slot machine, counter, and Mildred. Her model retains green eyes, a pink nose, gray/orange coat patches, and a fluffy tail. Blender source, generator, provenance, and gameplay previews are in `assets/items/source/`; reference photos remain outside the project.

## Mappo mascot

Mappo is the default starter and title-screen mascot, based on the supplied dog photos. His Katamari-inspired model has been reauthored through Blender MCP with a cubic head, a longer pyramid muzzle with a wider base, much larger pointed ears, and a shorter, mostly uniform tail with a pointed tip. The imported `assets/mascot/mappo.glb` has 2,130 triangles across a body mesh and a hinged lower jaw, with matte flat-color materials. His eyes sit slightly higher, the recessed lower jaw gives a side overbite, four front incisors show when closed, and the canines stay covered until the jaw opens. Three straight black whiskers extend from each side of his muzzle. It preserves his amber-brown eyes, black coat and muzzle, tiny pale toe details and tapered legs with angled hind hocks, dark-patched pink tongue, mint collar, and blue heart tag. The title portrait and held weapon use the same model through `scenes/mascot/mascot_dog.tscn`.

The adapter in `scripts/mascot/generated_mascot.gd` normalizes the imported model and applies matte materials, idle breathing, and a small whole-body firing pulse. It also finds the embedded `Mappo_Shoot` clip and restarts it on each successful shot. The imported 0.32-second clip opens and closes a separate jaw pivot; the tongue and lower teeth move with the jaw while the upper canines stay on the head. This uses node transform animation without a skeletal rig. The held weapon faces forward, adds recoil, and uses the existing placement. Weapon stats stay those of the existing explosive starter. Editable Blender source, the updated authoring script, preview frames, and the original GLB backup are in `assets/mascot/source/`. Asset provenance and reference history are recorded in `assets/mascot/source/generation.json`.

This is a playable foundation for balancing and content expansion. The boss is one archetype scaled across floors. Run records persist, but an unfinished run is not saved. New pups and enemy details use procedural low-poly geometry; existing scenery GLBs are reused.

## Validation

Run `./tests/run_checks.ps1 -GodotPath <path-to-Godot-console.exe>` from PowerShell. All 17 suites pass. The checks cover:

- 120 generation seeds across three layouts, reachability, adjoining doors, co-visible overlap prevention, deterministic decoration placement, and nine GLBs on six surface axes.
- Hidden-door reveal, W-only traversal, floor reset, and cleanup.
- Real CharacterBody movement through horizontal, vertical, and angled doors at normal and modified speeds; retreat and disabled-door cases.
- Single-use knockback, freeze/gravity behavior, frame-rate comparison, and god mode.
- All enemy archetypes, boss phase/death, W isolation, actual enemy/player fire, fast projectile sweeps, crit handling, and effect cleanup.
- Loadout, encounters, pedestal reward idempotence, enemy sleep/wake, explicit boss exit, floor advance, and inventory persistence/reset.
- Entered-only map visibility, viewport placement, pause/result screens, exact dog-instance modifier scope, actual multishot, one active slot, swapping, effects, and cooldowns.
- Two linked item-room choices, 15-bone shop transactions, slot outcome probabilities and one-time jackpot, bone denominations/attraction/W isolation, and timed bomb consumption/damage.
- Free walking pickups with player physics enabled, real F-key shop/slot input, descriptions below the minimap, and native/immediate-spawn enemy kills producing visible bones that eventually credit currency.
- Shop and slot portal clearance across 120 generated layouts and 485 entry points, reserved hidden doorways, persistent placements, and Mildred's three-box height and exact gaze through movement, weapon swaps, and curved gravity.
- Mappo's imported jaw animation on actual firing, rapid restart, dry fire, and missing-clip fallback.
- Combat locks on both sides of a doorway, last-enemy reopening, debug-added enemies, secret-door independence, and continuous arrival through a closing entry.
- Yellow minimap targeting with rotated cameras/portals, look-away reset, and no reveal of unvisited rooms.
- Enemy containment at closed portals: all five archetypes, three doorway orientations, room ownership, and frozen knockback.

The nine normalized scenery models were also visually reviewed in a separate Godot render. The main menu, HUD/minimap, continuous doorway crossing, item room, Mildred's shop, slot machine, and jackpot were inspected through the connected Godot editor.

After importing the generated Mappo model, combat, progression, and UI/items regressions passed again. Actual main-menu and gameplay renders were inspected with the final held-weapon placement and matte materials.

## Suggested hands-on review

1. Start seed 20260929. The map should show just the starting room.
2. Walk into a doorway without jumping. In a combat room, exits should seal until every enemy is defeated, then become completely see-through. Check the feel of momentum and view rotation.
3. Enter several rooms. Verify nothing appears on the map before entry and old explored rooms remain visible. Aim at a door leading back to an explored room: that destination should turn yellow, then reset when looking away.
4. Fight with each pup, inspect freeze/implosion feedback, and watch bones burst then drift into you. Approach an item to inspect its description below the map, then walk close to collect it without pressing a key. Choose one item-room pedestal; test a dog inclusive pickup, switch pups, and inspect ownership in pause inventory. Activate with E and check cooldown.
5. Follow a hidden scent with Q enabled and approach the wall; enter the revealed doorway to put the secret room on the map.
6. Visit Mildred's shop and spend 15 bones; try a 3-bone slot spin, use a bomb with G, and verify keys remain stored.
7. Defeat a boss, collect its bones, then use F in its room to advance. Items/currency/consumables should carry to the next floor and reset for a new run. Test defeat/retry.

## Installed model pipeline

The supplied [Asset Studio project](https://github.com/zorrobyte/asset-studio) is installed outside the game at `C:/Users/Jacob/Desktop/GameMaking/asset-studio-master`. Its reference-image workflow was adapted for this RTX 4090, with CUDA 12.8, compiled native dependencies, and cached model weights. The selected generation completed at 1024 resolution, followed by Blender optimization to a 1,800-triangle target and 1K base-color texture. Qwen/FLUX text-to-image stages were skipped in favor of the supplied cartoon reference. The external `scripts/bootstrap-reference-4090.ps1` and `scripts/submit-reference.ps1` retain the reusable setup and submission workflow.
