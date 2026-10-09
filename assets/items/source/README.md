# Item and economy model source

`build_items.py` creates the original flat-color, low-poly models through the
running Blender MCP server on localhost port 9876. Run it with the project's
`assets/mascot/source/blender_mcp_client.py`. The script owns a separate
`Items_Katamari_Review` scene and preserves the existing Mappo scenes and objects.

Each exported GLB contains exactly one mesh node named for its asset. Origins
are ground centered. Blender +Y faces forward and exports as Godot -Z, with
Godot Y up. All surfaces are flat shaded; there are no texture dependencies.
Runtime item display code can fit models to a common size using their bounds.

The collection includes 13 upgrades, two consumables, four bone variants,
pedestal, slot machine, shop counter, and Mildred. `generation.json` records
the source mesh triangle counts and Blender/Godot dimensions. Bone variants
use a single white material so the game can apply white, silver, or gold
without changing their shapes. Their four shapes are a classic knuckle bone,
a curved long bone, a tapered rib, and a small vertebra.

Mildred's sitting calico silhouette, cream chest and paws, gray and tan back
patches, three gray forehead markings, green eyes, pink ears and nose, and
bushy curled tail follow the six user-supplied photographs. Private photos
remain outside the project.

Review files:

- `items-katamari.blend`: editable native source and review scene.
- `item-collection-preview.png`: every model in the collection.
- `mildred-preview.png`: Mildred portrait with studio lighting.

`.gdignore` excludes authoring files and previews from Godot imports.
