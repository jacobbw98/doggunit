# Doggun'it - Project Wiki

> **4D Low-Poly FPS Roguelike** built in Godot 4.5.1

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Current Status](#current-status)
3. [Architecture](#architecture)
4. [4D System](#4d-system)
5. [Gun System](#gun-system)
6. [Debug Console](#debug-console)
7. [File Structure](#file-structure)
8. [How To Guide](#how-to-guide)

---

## Project Overview

**Doggun'it** is a 3D low-poly first-person shooter roguelike with a unique twist: the environment exists in **4D space**. Players and enemies can walk on the surfaces of 4-dimensional objects like hyperspheres and Klein bottles.

### Core Concept

- FPS roguelike with procedural elements
- **4D environments** - walk on hyperspheres, Klein bottles, and other 4D surfaces
- **Slice-based rendering** - see 3D cross-sections of 4D objects
- **Sticky gravity** - gravity always points toward the surface you're walking on

### Game philosophy

Everything stacks infinitely. There are no designed limits on item copies,
stat growth, projectile counts, or combinations. The point of the game is to
break the game: build absurd synergies, overwhelm enemies, and push each run
beyond sensible balance. Starter dogs have comparable sustained DPS so every
breed is a useful starting point; collected items are allowed to destroy that
balance. Each extra copy must keep doing something rather than reaching a
silent cap. An effect's natural endpoint, such as a guaranteed freeze at 100%
chance, does not limit how many copies or hits the player can accumulate.

### October 8 catalog and combat update

The game implements all 22 entries in `data/items.csv`, all 23 dogs in
`data/dogs_guns.csv`, and the separate bomb/key consumable catalog. User flavor
text and model descriptions are preserved. Eight additions include Bone Swarm,
Bouncy, Spoon bender, Extra Flesh, TOFU, Familier Fungus, Magic Mushrrom, and
Lazer Guided. Bouncy, homing, laser pointers and Magic Mushrrom attach visibly
to their bound dog. Brussels Griffon has the requested cartoon dad styling;
Otterhound is modeled as the requested otter.

- Freezing hits build a separate chance on each target: 1%, 2%, and so on.
  Every hit refreshes a 0.5-second window. A longer gap resets the chain;
  the 100th consecutive hit guarantees a two-second freeze. Walls do not
  build a chain. Bosses retain their shorter status duration.
- Item rooms and shops start locked. Look at a brass padlock and press F to
  spend one key, unlocking every entrance to that room for the floor. Special
  rooms are optional branches. Runs start with one key and every second combat
  clear earns another. Combat seals and key locks operate independently.
- Reloads take time, block firing, animate the dog, and show a HUD countdown.
  Empty magazines start reloading automatically. Slot changes preserve reload
  progress; Walkies dogs also reload. Floor transitions refill magazines.
  Unmodified Ok dogs target 44 expected DPS with their default 10% critical
  chance and 2x critical multiplier, equivalent to 40 DPS before criticals.
  This uses damage per projectile and includes the last shot's cooldown and a
  full reload; type matchups, area damage and acquired items are additional.
  `reload_seconds` and `sustained_dps` are recorded in the dog CSV.
- Extra Flesh adds 10% maximum health per copy. TOFU adds 50 health, then
  60, 70, etc. Both heal the newly added capacity. Familier Fungus doubles
  player stats, size and gun stats; Magic Mushrrom doubles its bound dog's
  stats. Together they give the selected player and dog 4x stats. Additional
  copies keep multiplying. Higher gun stats shorten shot/reload intervals.
- Bone Swarm homes dropped bones toward enemies and deals damage on repeated
  contacts. Bone Cactus makes the first contact split into eight swarming
  spines. The original carries the full bone value; extra spines carry none.
  Clearing the room banks all outstanding swarm currency exactly once.

### Animation workflow: UniMate

Use [Friedrich-M/UniMate](https://github.com/Friedrich-M/UniMate) for generated
character motion. The three current reload clips were sampled with the released
`unimate_uniml3d_f60_v3` checkpoint on the local RTX 4090 and retargeted from its
included quadruped rig. `assets/dogs/animations/reload_motion.json` stores three
60-frame head/body clips in Godot coordinates. The raw samples, generation
manifests and reproducible retargeting script live in the adjacent `source/`
directory. Retargeting removes travel, mirrors generated lifting motion into
an eating bow and returns to neutral at each end. Runtime playback follows each
dog's reload time, moves imported breed heads and their mouth/glasses additions,
and blends Mappo's original jaw animation. No inference runs during gameplay.

UniMate's code is MIT licensed. The preview checkpoint is **CC BY-NC 4.0**;
this pipeline uses it for the local playtest build. A commercial release needs
an appropriately licensed checkpoint or separate permission from its authors.

### Technology

- **Engine**: Godot 4.5.1
- **Language**: GDScript
- **4D Math**: Ported from [HackerPoet's Engine4D](https://github.com/HackerPoet/Engine4D)

---

## Current Review Build — 2026-10-02

**Playtest build approved by Jacob for GitHub publication on October 9, 2026.** The October 2 notes below describe the earlier baseline; current catalog and combat behavior is documented above.

Portal traversal must remain continuous, like walking through a doorway. Portal crossing changes W and room ownership only; it never relocates XYZ or applies a launch velocity. Preserve that contract in future edits.

The documented bugs are addressed:
- Imported GLB transforms are preserved and each model is centered/grounded inside its own pivot before aligning to the sphere. Nine models validated on six axes and rendered for inspection.
- All generated rooms are connected. Three seeded layout styles use physically adjoining doorways; every connection is a traversable edge.
- Movement through horizontal, angled, and vertical portals uses one player physics move, swept plane crossing, shared apertures, and continuous gravity orientation. Normal movement is 8 units/second with no sprint button.
- Freeze/implosion effects have rings, ice fragments, and frozen status visuals. Knockback is consumed once and frozen players still receive gravity/collisions.

Future Objectives now have a first playable implementation: a three-floor run, five enemy archetypes including a two-phase boss, 13 pet items in three families, physical item pedestals, a bone currency economy, Mildred's shops, slot machines, W-layer secret kennels, main/pause/result menus, and a top-right room map. **The minimap shows only rooms actually entered; discovering a secret doorway alone does not reveal that room.**

See [REVIEW_BUILD.md](REVIEW_BUILD.md) for controls, scope, verification, and suggested playtesting.

Combat locks seal paired doors while live enemies remain; locked doors retain their glow and unlocked doorway surfaces are completely transparent. Looking at a doorway highlights its already-explored destination yellow on the minimap; unvisited rooms stay hidden.

**Mappo** is the mascot and default explosive starter. The same chunky low-poly 3D model appears in the title-screen portrait and first-person loadout, based on Jacob's dog photos. The Katamari-inspired Blender MCP revision has a longer torso and pyramid muzzle with a wider base, a nearly cubic head, much larger upright ears with sharp tips and a shorter, mostly uniform tail with a pointed tip. His amber-brown eyes sit slightly higher; the side overbite exposes four front incisors with the mouth closed while covering the canines until it opens. Three straight black whiskers extend from each side of his black muzzle. He has a black coat, tiny pale toe details and tapered legs with angled hind hocks, a dark-patched pink tongue, and a mint collar with blue heart tag. `assets/mascot/mappo.glb` has 2,130 triangles across a static body mesh and a separate lower jaw. Embedded `Mappo_Shoot` animation opens and closes the hinged jaw over 0.32 seconds in Godot; the tongue and lower teeth follow it. `GeneratedMascot.bark()` restarts the clip on every successful `Gun.fire()` call, including when idle breathing is disabled for the held weapon. Editable Blender source, authoring script, renders, and previous GLB backup are in `assets/mascot/source/` (excluded from Godot imports). Reusable scene: `scenes/mascot/mascot_dog.tscn`; normalization, matte materials, idle breathing, and shot playback: `scripts/mascot/generated_mascot.gd`. Animation uses node transforms without a skeletal rig. Provenance and reference history: `assets/mascot/source/generation.json`. The other starter pups retain their own visuals.

---
### Items and economy

`PetItems` defines 13 items, with bombs and keys stored separately as consumables in the active family:

| Family | Items and scope |
|--------|-----------------|
| Global passive (5) | Forbidden Biscuit: all-dog damage; 3 AM Zoomies: movement speed; Cone of Invincibility-ish: health; Vampire Kibble: kill healing; Cursed Flea Collar: jump height. |
| Dog inclusive (5) | Illegal Squeaker: fire rate; Quantum Tennis Ball: extra shot; Unreasonably Long Leash: projectile speed; World's Okayest Dog Tag: critical chance; Bottomless Water Bowl: magazine capacity/ammo. Each binds to the actual dog selected at pickup, survives switching/drop-and-repickup, and does not transfer to another dog of the same type or slot. |
| Active (3) | Howl Horn: 65 explosive damage within 8 units, 12-second cooldown; Emergency Treat Bowl: heal 30, 20-second cooldown; Bone Magnet: 2.75× bone pull for 8 seconds, 18-second cooldown. One slot; swapping leaves the old active on the pedestal and retains cooldown. |

Room rewards use physical pedestals during play. Free items are collected automatically by walking near the pedestal; item rooms contain two linked choices, so collecting one removes the other. Combat/special/secret rooms award one pedestal. Item descriptions and ownership appear beneath the top-right map when nearby. Shops contain 1–3 items or bomb/key consumables, all priced at 15 bones and purchased with F. Mildred sits on three stacked cardboard boxes at dog-gun height and turns her body/head to watch the currently equipped dog throughout the shop visit. Shop stock, Mildred, and slot machines leave at least a 10-metre corridor beyond all portal openings and their model footprints; commerce starts at least 14 metres along the curved floor from entry. Her white calico coat, gray/orange patches, green eyes, pink nose, and fluffy tail follow the supplied photos. `assets/items/` contains 23 native low-poly GLBs authored through Blender MCP: the 13 items, two consumables, four bone shapes, pedestal, slot machine, counter, and Mildred. The cardboard stack is built from native meshes. Editable source and provenance are in `assets/items/source/`; private photos stay outside the project.

Enemies burst larger, softly glowing bone pickups outward for 1.15 seconds before attraction begins. Four shape variants are aesthetic only; white bones are worth 1, silver 5, and gold 10. Base payouts are 1–3 for grunt/rusher, 3–6 for sniper, 5–9 for brute, and 20–35 for boss; health tiers can increase payouts, with later-floor scaling of 1.0/1.3/1.6. Native and externally spawned enemies receive death hooks immediately, including a kill in their spawn frame. Drops and interactions respect their owning room and W layer. Slot spins cost 3 bones: 49% nothing, 20% an item pedestal, 30% a 5- or 10-bone payout, and 1% an explosion that destroys the machine and credits 100 bones.

**F** buys shop items, spins slots, or leaves a cleared boss room; walk near free items to collect them. **E** activates the equipped item; **G** throws a bomb; **Q** toggles sniffing. Bombs fuse for 1.8 seconds, deal 85 explosive damage within 5 units with 55% linear distance falloff, and deal 20 damage to a player within 3 units. Keys currently have no use. The HUD and pause inventory show bones, bombs, keys, active readiness, and passive ownership. Boss death leaves gameplay running so drops can be collected before choosing F to advance or finish. Collected inventory persists between floors and resets with a new run; world drops are cleared when regenerating a floor.

All 17 suites in `tests/run_checks.ps1` pass, covering item ownership, active swapping/cooldowns, walking pickups and real F-key interactions, pedestal choices, shop/slot clearance from every portal across 120 layouts, Mildred's three-box height and gaze tracking, slot probabilities/jackpot, live enemy bone drops and attraction, bombs, floor persistence, and the existing combat/portal/Mappo checks.

## Current Status

### ✅ Completed

| Feature | Description |
|---------|--------------|
| Core 4D Math | `Vector4D`, `Matrix4x4D`, `Isocline`, `Transform4D` |
| 4D Geometry | `Object4D`, `Collider4D`, `Hypersphere4D`, `KleinBottle4D` |
| 4D Physics | `Physical4D`, `SurfaceWalker4D` with sticky gravity |
| Slice Rendering | `Slicer4D` with smooth scrolling and dynamic limits |
| Gun System | 4 types × 6 rarities with rock-paper-scissors effectiveness |
| Debug Console | Commands: spawn, gun, 4d, god, heal, noclip, kill, ammo, level, ghost |
| Player Controller | 3D/4D dual-mode with surface walking, **fixed falling through floors** |
| Test Enemy | Spin-until-see, approach, and shoot AI |
| Enemy4D | 4D-aware enemies with W-slice visibility, 3D health bars, floor-only escape mode |
| Player Gun System | Visible gun meshes, projectiles, muzzle flash, **auto-fire** while holding |
| 4D Weapon System | Projectiles have W-coordinate, slice visibility, 4D hit detection |
| Torus4D | 4D torus shape with parametric equations, slice mesh, collider |
| Ghost Projections | Transparent full-shape projections for off-slice 4D objects via `ghost` command |
| Procedural Levels | Connected sphere rooms with portal doors, **auto-generation on load** |
| **Dynamic Sphere Gravity** | Walk like an ant on interior sphere surfaces with smooth rotation (fixed room clipping issues) |
| **Slide Mechanic** | Hold Ctrl while moving to slide with momentum preservation |
| **Bunny Hop (B-Hop)** | Jump on landing for uncapped speed boosts |
| **Portal W-Sync** | **Fixed visibility at spawn**, host room + adjacent rooms synced to player's W |
| **Portal See-Through** | Shader-based holes in sphere mesh show destination room interior |
| **Portal Traversal** | Continuous XYZ motion through adjoining doorways; W-only handoff on crossing |
| **Portal Crossing** | Swept plane detection, shared aperture, retreat/reversal protection |
| **Projectile Portal Support** | Projectiles transition W-coordinate when crossing portals (bidirectional) |
| **Projectile Collision Types** | Explosive (AOE + knockback), Freezing (2s freeze), Implosive (pull), Accelerating (pierce + split) |
| **Enemy Status Effects** | Enemies can be frozen, knocked back, and pulled by projectile effects |
| **Player Status Effects** | Player affected by enemy explosions, freezing, implosion pulls |
| **Wall Collision Detection** | Distance-based detection for room sphere walls (no physics colliders) |
| **Projectile Visual Effects** | Freeze (blue sphere flash) and Implosion (purple shrinking sphere) animations |
| **Room Size Variation** | Normal rooms range from 1x-2x radius for level diversity |
| **Overlap Prevention** | Graph distance ≥3 check ensures visible rooms never intersect |
| **Snappy Movement System** | Tunable acceleration/deceleration, gravity multipliers, stop threshold for responsive feel |
| **Crouch Momentum** | 0 deceleration while crouching enables infinite bhop speed building |
| **W-Coord Room Collision** | Player only interacts with rooms at matching W-coordinate |
| **Room Decorations** | Preserved GLB transforms, grounded pivots, inward orientation and seeded room theming |
| **Item Families** | Five global passives, five passives bound to a selected dog instance, three active items in one swappable slot |
| **World Rewards** | Pedestal pickups during play, two linked choices in item rooms, 23 native low-poly item/economy models |
| **Bone Economy** | Enemy bursts and attraction, four aesthetic bone shapes, white/silver/gold denominations, difficulty-scaled drops |
| **Shop & Gambling** | Mildred's 1–3-stock shops at 15 bones; 3-bone slot spins with a 1% exploding 100-bone jackpot |
| **Consumables** | Timed bombs and stored keys; currency, active readiness, and item ownership in HUD/pause inventory |

### 📋 Future Objectives

- [x] Level generation diversity improvements — three deterministic layout styles and biome variation
- [x] Secret rooms at different W values in 4D — Q sniff reveals a nearby seamless doorway
- [x] More enemy types — grunt, rusher, sniper, brute
- [x] Boss encounters — The Big Bad Good Boy, telegraphed volleys and enraged second phase
- [x] Roguelike progression system — three floors, encounter rewards, stacking items, victory/defeat, persistent records
- [x] Add absurd pet-themed items — 13 items across global, dog inclusive, and active families, with world pedestals and bomb/key consumables
- [x] Add shop and gambling economies — bone drops, Mildred's shop, and slot machines
- [x] Add a Menu screen — seeded start, controls, pause/inventory, floor completion, result screens

---

## Architecture

### Scene Tree (Typical Level)

```
Level
├── WorldEnvironment
├── DirectionalLight3D
├── Slicer4D              # Controls W-slice
├── Hypersphere4D         # 4D objects
├── KleinBottle4D
├── Player
│   ├── Camera3D
│   │   └── WeaponManager
│   └── SurfaceWalker4D   # 4D movement component
├── Enemies/
└── DebugConsole (Autoload)
```

### Script Dependencies

```
Vector4D ← Matrix4x4D ← Isocline ← Transform4D
                ↓
            Object4D ← Hypersphere4D / KleinBottle4D
                ↓
            Collider4D
                ↓
            Physical4D ← SurfaceWalker4D
                ↓
            Slicer4D
```

---

## 4D System

### How 4D Visualization Works

1. **Everything has a W coordinate** - Objects exist at position (X, Y, Z, **W**)
2. **Slice plane** - We view the 3D cross-section at a specific W value
3. **Size changes** - A hypersphere appears as a 3D sphere that grows/shrinks as you move in W
4. **Visibility** - Objects outside the slice threshold become invisible

### Key Classes

| Class | Purpose |
|-------|---------|
| `Vector4D` | 4D vector math (add, dot, cross-like `make_normal`) |
| `Matrix4x4D` | 4D rotations, transforms, Slerp |
| `Isocline` | 4D rotation as quaternion pair (qL, qR) |
| `Object4D` | Base class - tracks position_4d, auto-registers with Slicer |
| `Hypersphere4D` | 4D sphere - slice shows varying radius 3D sphere |
| `KleinBottle4D` | Non-orientable 4D surface |
| `Physical4D` | 4D physics with gravity, velocity, collisions |
| `SurfaceWalker4D` | Walk on 4D surfaces with sticky gravity |
| `Slicer4D` | Controls slice_w, updates all objects, handles scroll input |

### Slice Visualization Formula

For a hypersphere at W=0 with radius R, when slice is at W=d:

```
visible_radius = sqrt(R² - d²)  if |d| < R
invisible                        if |d| >= R
```

---

## Gun System

### Types (Rock-Paper-Scissors)

| Type | Strong Against | Weak Against | Effect |
|------|----------------|--------------|--------|
| Explosive | Freezing | Implosive | Area damage |
| Implosive | Explosive | Accelerating | Pulls enemies |
| Freezing | Accelerating | Explosive | Slows enemies |
| Accelerating | Implosive | Freezing | Piercing shots |

### Gun Stats

Each gun type has primary stats associated with it:

#### Kinetic Stats (Explosive Type)

| Stat | Description | Base Value |
|------|-------------|------------|
| `base_damage` | Damage per hit | 10.0 |
| `projectile_size` | Size of bullet (0.1 - 0.3 radius) | 1.0 |

#### Potential Stats (Implosive Type)

| Stat | Description | Base Value |
|------|-------------|------------|
| `knockback_force` | Push/pull force on hit | 5.0 |
| `projectile_speed` | Bullet travel speed (units/sec) | 20.0 |

#### Entropy Stats (Freezing Type)

| Stat | Description | Base Value |
|------|-------------|------------|
| `projectile_count` | Number of bullets per shot | 1 |
| `crit_damage_multiplier` | Damage multiplier on critical hit | 2.0x |

#### Order Stats (Accelerating Type)

| Stat | Description | Base Value |
|------|-------------|------------|
| `accuracy` | Shot accuracy (0-1, higher = more accurate) | 0.9 |
| `precision` | Spread reduction | 0.8 |
| `crit_chance` | Chance to critical hit (0-1) | 0.1 |

### Rarities

| Rarity | Multiplier | Color |
|--------|------------|-------|
| Poor | 0.7x | Gray |
| Mid | 0.85x | White |
| OK | 1.0x | Green |
| Epic | 1.2x | Blue |
| Legendary | 1.5x | Purple |
| Peak | 2.0x | Gold |

### Effectiveness

- **Strong**: 1.5x damage
- **Neutral**: 1.0x damage  
- **Weak**: 0.5x damage

---

## Debug Console

Open with **` (backtick)** or **F1**

| Command | Arguments | Description |
|---------|-----------|-------------|
| `spawn` | hypersphere, klein, enemy, enemy4d [count] | Spawn entity at crosshair |
| `gun` | type, rarity | Give gun (e.g., `gun explosive legendary`) |
| `4d` | - | Toggle scroll wheel W-axis movement |
| `god` | - | Toggle invincibility |
| `heal` | - | Full health |
| `ammo` | - | Refill ammo |
| `noclip` / `fly` | - | Toggle fly mode (no gravity, no collision) |
| `aggro` | true/false | Toggle enemy AI aggression |
| `kill` | - | Kill all enemies |
| `ghost` | - | Toggle ghost projections for off-slice 4D objects |
| `level` | [seed] | Generate procedural level with connected rooms |
| `room` | type | Spawn room sphere (normal, boss, item, shop, gambling, special) |
| `clear` | - | Clear console |
| `help` | - | Show all commands |

### Spawn Examples

```
spawn enemy4d      # Spawn 1 enemy
spawn enemy4d 10   # Spawn 10 enemies in a circle
spawn hypersphere  # Spawn a hypersphere
```

---

## File Structure

```
doggunit/
├── project.godot
├── PROJECT_WIKI.md          # This file
├── scripts/
│   ├── math4d/              # 4D math primitives
│   │   ├── vector4d.gd
│   │   ├── matrix4x4d.gd
│   │   ├── isocline.gd
│   │   └── transform4d.gd
│   ├── geometry4d/          # 4D shapes
│   │   ├── object4d.gd
│   │   ├── collider4d.gd
│   │   ├── hypersphere4d.gd
│   │   ├── klein_bottle4d.gd
│   │   ├── torus4d.gd
│   │   └── room_sphere4d.gd   # Hollow sphere for interior walking
│   ├── physics4d/           # 4D physics
│   │   ├── physical4d.gd
│   │   └── surface_walker4d.gd
│   ├── rendering4d/         # 4D visualization
│   │   └── slicer4d.gd
│   ├── level/               # Level generation
│   │   ├── level_generator.gd
│   │   ├── room_types.gd
│   │   ├── portal_door.gd
│   │   ├── portal_tube.gd
│   │   └── room_decorator.gd    # Places 3D models on sphere interiors (WIP: orientation bug)
│   ├── player/              # Player scripts
│   │   └── player_controller.gd
│   ├── weapons/             # Gun system
│   │   ├── gun_types.gd
│   │   └── weapon_manager.gd
│   ├── game/                # RunManager, RunUI, PetItems
│   ├── items/               # Pedestals, room economy, bone pickups, slots, bombs
│   ├── enemies/             # Enemy AI
│   │   ├── enemy_base.gd
│   │   ├── enemy_4d.gd        # 4D surface-walking enemy
│   │   └── test_enemy.gd
│   └── debug/               # Debug tools
│       └── debug_console.gd
├── scenes/
│   ├── player/player.tscn
│   ├── enemies/test_enemy.tscn
│   └── levels/
│       ├── test_4d.tscn
│       └── procedural_level.tscn
└── resources/
    └── shaders/
        └── slice_glow_4d.gdshader
```

---

## How To Guide

### Adding a New 4D Shape

1. Create `scripts/geometry4d/your_shape4d.gd`
2. Extend `Object4D`
3. Override these methods:

   ```gdscript
   func get_signed_distance(point: Vector4D) -> float
   func get_surface_normal(point: Vector4D) -> Vector4D
   func update_slice(slice_w: float) -> void
   ```

4. Add visual mesh generation in `_create_mesh()`

### Enabling 4D Mode on Player

In your player scene, set:

```gdscript
enable_4d_mode = true
initial_w = 0.0
```

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-05 | 0.1.0 | Initial 4D engine port from Engine4D |
| 2025-12-05 | 0.1.1 | Added smooth scrolling, spawn commands, dynamic W limits |
| 2025-12-05 | 0.1.2 | Added Enemy4D with SurfaceWalker4D integration |
| 2025-12-05 | 0.1.3 | Player gun system with visible meshes, projectiles, auto-fire |
| 2025-12-05 | 0.1.4 | Enemy 3D health bars, aggro/fly commands, spawn count |
| 2025-12-07 | 0.1.5 | Enemy4D floor-only escape mode for hypersphere/floor intersections |
| 2025-12-07 | 0.2.0 | **4D-aware weapon system** - projectiles with W-coordinate, 4D hit detection |
| 2025-12-07 | 0.2.1 | Player-relative projectile visibility, classic Klein bottle shape, 4d command fix |
| 2025-12-07 | 0.3.0 | **Torus4D** shape, **Ghost projections** for off-slice objects |
| 2025-12-08 | 0.3.1 | Fixed ghost projections - each 4D shape now generates proper full-shape ghost mesh |
| 2025-12-08 | 0.4.0 | **Procedural level generation** - RoomSphere4D, portal doors with tubes, room types |
| 2025-12-08 | 0.5.0 | **Dynamic sphere gravity** - walk on interior sphere surfaces like an ant |
| 2025-12-08 | 0.5.1 | Portal 2-style teleportation (walk through to teleport), velocity preservation |
| 2025-12-08 | 0.6.0 | **Slide & B-Hop mechanics** - crouch-slide, bunny hop with uncapped momentum |
| 2025-12-11 | 0.6.1 | **W-Axis Portal System (WIP)** - Rooms at different W coordinates, portals teleport between rooms |
| 2025-12-14 | 0.6.2 | **W-Sync Portal Visibility** - Portal see-through via W-coordinate synchronization |
| 2025-12-17 | 0.6.3 | **Portal Crossing Fix** - Side-based detection (INSIDE/OUTSIDE) eliminates oscillation bugs |
| 2025-12-20 | 0.7.0 | **Robust Portals & Auto-Gen** - Instant transitions, immediate W-sync, fixed oscillation/floor clipping |
| 2025-12-20 | 0.7.1 | **Projectile Portal Support** - Projectiles transition W-coordinate bidirectionally through portals |
| 2026-01-01 | 0.8.0 | **Projectile Collision System** - Explosive AOE/knockback, Freezing, Implosive pull, Accelerating pierce/split |
| 2026-01-01 | 0.8.1 | **Player Status Effects** - Player can be frozen, knocked back, and pulled by enemy projectiles |
| 2026-01-02 | 0.8.2 | **Projectile Visual Effects** - Freezing (blue flash) and Implosion (shrinking purple sphere) animations |
| 2026-01-02 | 0.8.3 | **Level Gen Improvements** - Room sizes 1x-2x, graph distance ≥3 overlap rule, 50 positioning attempts |
| 2026-01-02 | 0.8.4 | **Snappy Movement System** - Tunable accel/decel, gravity multipliers, move_toward for crisp stops |
| 2026-01-02 | 0.8.5 | **Crouch Momentum** - 0 deceleration while crouching for infinite bhop speed building |
| 2026-01-02 | 0.8.6 | **W-Coord Room Collision** - Player skips rooms at different W slices, fixes intersecting room interaction |
| 2026-05-10 | 0.9.0 | **Room Decorations (WIP)** - 3D models on sphere interiors, wrapper-based orientation, room-type profiles. Known bug: model orientation inconsistent |

---

## W-Axis Portal System

### Current implementation (2026-09-29)

Each connected pair of spheres meets at a shared doorway. The player physically walks through this aperture. Swept signed-plane detection commits the destination W value and room ownership without modifying position or velocity. Both source and receiving apertures stay open across the crossing; player physics owns the sole movement step. Gravity orientation is transported through the transition so forward input stays forward.

Secret doorways are unavailable until discovered near their wall while Q sniff is enabled. The receiving room retains its own home W for crossing. Host/adjacent visibility sync preserves the see-through doorway view.

Regression coverage includes retreat without crossing, aperture misses, disabled secret portals, momentum preservation, combat seals, and actual movement at normal/modified speeds through horizontal, vertical, and angled doors.

Historical version entries below describe earlier implementations; they are not the current portal contract.

---
## Projectile Collision System

### Implementation (2026-01-01)

**Gun Type Effects**:

| Type | Collision Behavior |
|------|-------------------|
| Explosive | AOE damage (100% with distance falloff), knockback force (20), visual expanding sphere |
| Freezing | Freeze nearby targets for 2 seconds (6 unit radius) |
| Implosive | Pull targets toward impact point (7 unit radius, 10 force) |
| Accelerating | Pierce through enemies, split into 2 projectiles with half damage each |

**Wall Detection**:

- Room spheres have no physics colliders (player is manually constrained)
- Projectiles use distance-based detection: trigger when `dist_to_wall < 1.5`
- Also supports raycast for regular physics walls

**Key Files**:

- `projectile.gd`: All collision types implemented with `_explode()`, `_freeze_nearby()`, `_implode_nearby()`, `_pierce_and_split()`
- `enemy_4d.gd` / `enemy_base.gd`: Added `freeze()` and `apply_external_force()` methods
- `player_controller.gd`: Added `freeze()` and `apply_external_force()` for player status effects

---

## Level Generation Improvements

### Implementation (2026-01-02)

**Room Size Variation**:

- Normal rooms now have size multiplier `randf_range(1.0, 2.0)` instead of fixed values
- Creates more visually diverse level layouts

**Overlap Prevention**:

- Rooms can only overlap in 3D if they are **≥3 graph edges apart**
- Distance 1: Adjacent rooms visible together
- Distance 2: Rooms sharing a neighbor visible together when in that neighbor
- Distance 3+: Can never be visible simultaneously → safe to overlap

**Positioning Improvements**:

- Increased `max_attempts` from 20 to 50 for finding valid tangent positions
- Added `_get_graph_distance()` BFS function for overlap checks

---

## Room Decoration System

### Implementation (2026-05-10) — WIP

**Purpose**: Populate interior sphere rooms with 3D decorative models (trees, rocks, houses, well) to break up visual monotony.

**Architecture**:

- `RoomDecorator` class (`scripts/level/room_decorator.gd`) — instantiated by `LevelGenerator`
- Called after portal creation in `_decorate_rooms()` pipeline step
- Uses a **wrapper Node3D** for sphere-surface orientation (Y = toward center)
- Model instance added as child of wrapper with `Transform3D.IDENTITY` to strip GLB root transforms

**Model Catalog** (from `res://resources/Models/`):

| Model | Native AABB Height | Scale Range (× radius) | Category |
|-------|-------------------|----------------------|----------|
| oaktree.glb | 1.38 | 0.15–0.30 | tree |
| pinetree.glb | 3.63 | 0.15–0.30 | tree |
| minipinetree.glb | 1.37 | 0.10–0.20 | tree |
| single rock.glb | 0.13 | 0.05–0.12 | rock |
| small rock cluster.glb | 0.16 | 0.05–0.12 | rock |
| big rock cluster.glb | 0.33 | 0.08–0.15 | rock |
| House1.1.glb | 2.16 | 0.20–0.40 | structure |
| house2.2.glb | ~2.0 | 0.20–0.40 | structure |
| well.glb | 0.54 | 0.15–0.30 | structure |

> **Note**: Most models have their AABB min_y ≈ 3.49, meaning geometry is offset ~3.5 units above the GLB root origin. This is a known complication for grounding logic.

**Room Type Profiles**:

| Room Type | Density | Categories | Structure Chance |
|-----------|---------|-----------|------------------|
| Normal | 1.0 | tree, rock, structure | 15% |
| Boss | 0.3 | rock only | 0% |
| Item | 0.5 | rock, structure | 80% |
| Shop | 0.6 | structure, rock | 90% |
| Gambling | 0.4 | rock only | 30% |
| Special | 2.0 | tree, rock | 5% |

**Placement Logic**:

1. Random point on sphere surface: `center + dir * (radius - 1.0)`
2. Portal avoidance: skip points within 6-unit arc distance of portals
3. Decoration spacing: minimum 3 units between any two decorations
4. Scale: `room_radius * randf_range(min_scale, max_scale)`

**Orientation Bug (Resolved 2026-06-03)**:

Previously, models (especially rocks and the well) spawned off-center, floated, or were oriented sideways.
- **Root cause**: The `.glb` models had large internal translation offsets on their children (e.g. `T=[1.56, 3.53, -3.13]` in `oaktree.glb`). Applying rotation to the instance caused the visual meshes to orbit far away.
- **Fix**: Implemented a recursive AABB visual bounds calculator `_calculate_local_aabb(instance)`. The model root position is shifted by `-center.x`, `-aabb.position.y`, `-center.z` relative to the wrapper. This grounds the bottom of the mesh at local Y = 0 and centers it horizontally at (0, 0), while Y-up points towards the room center.

---

## Snappy Movement System (WIP the current movement system still lacks that snappyness and smooth feel that games in the source engine have, I would want the movement system to be a combination of mario and megabonk)

### Implementation (2026-01-02)

**Problem**: Movement felt "floaty" due to slow lerp-based deceleration and default gravity.

**Solution**: Replaced `lerp()` with `move_toward()` for linear deceleration, added gravity multipliers, and exposed all parameters as `@export` variables.

### Tunable Parameters

All values adjustable in Inspector under **Movement Feel**:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `acceleration` | 50.0 | Ground acceleration (units/sec²) |
| `deceleration` | 60.0 | Ground stopping speed (12x faster than before) |
| `air_acceleration` | 10.0 | Reduced air control for less floaty feel |
| `air_deceleration` | 5.0 | Air friction |
| `gravity_multiplier` | 2.0 | Faster falls overall |
| `fall_gravity_multiplier` | 1.5 | Extra gravity when falling (not rising) |
| `stop_threshold` | 0.5 | Velocity snaps to zero below this |

### Tuning Guide

- **More slide**: Lower `deceleration` to 30-40
- **More air control**: Raise `air_acceleration` to 20-30
- **Floatier jumps**: Lower `gravity_multiplier` to 1.5
- **Crispier stops**: Raise `stop_threshold` to 1.0

---

*Last updated: 2026-09-29*
