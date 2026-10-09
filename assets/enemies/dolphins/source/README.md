Twenty low-poly dolphin enemies
==============================

The roster contains four silhouettes for each existing combat role. Each keeps a dolphin beak, dorsal fin, two flippers, and a split horizontal tail. Accessories and proportions change the silhouette; the models use flat faces and material colors rather than textures.

| Role | Dolphins |
| --- | --- |
| Grunt | Reef Scout, Deckhand Dolphin, Pearl Courier, Coral Gardener |
| Rusher | Comet Flipper, Turbo Porpoise, Swordfin Duelist, Storm Skimmer |
| Sniper | Lighthouse Lookout, Sonar Scholar, Cosmic Listener, Icicle Oracle |
| Brute | Anchor Hauler, Reef Juggernaut, Volcano Belcher, Puffer Bruiser |
| Boss | The Reef Regent, Captain Blackfin, Kraken's Best Friend, Admiral Ticktock |

`scripts/enemies/dolphin_catalog.gd` defines names, roles, and small health/speed/attack interval variations. `configure_dolphin` applies one definition and rolls one carried dog with the room's seeded random generator. The enemy's separate attack resource contains difficulty tuning, while the carried weapon remains suitable for a player drop. The random gun element does not change the dolphin theme.

`dolphin-roster.blend` preserves the editable objects and materials. `build_dolphins.py` rebuilds the twenty GLBs and the rendered contact sheet with Blender 5.2. Models are ground centered, normalized to 1.5 meters high before role scaling, and face Godot's -Z direction. Tail and flipper nodes remain separate for the runtime swim motion. Surface gravity, room containment, collisions, and status effects remain in Enemy4D.

Rebuild from the project directory:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python assets/enemies/dolphins/source/build_dolphins.py
```
