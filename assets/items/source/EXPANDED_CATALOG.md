# October 8 item art

`expanded_catalog_models.py` authors the eight additional item models from
`data/items.csv`. The scene is saved in `expanded-catalog.blend`; the labelled
contact sheet is `expanded-items-preview.png`. GLBs use the existing flat-shaded
toy materials and face Godot -Z with their base at ground level.

| ID | Model |
| --- | --- |
| boneswarm | Eight small bones orbiting a ring of pale green motion motes |
| bounce | Yellow rubber chicken with a long neck, comb and wattle |
| homing | Silver spoon with a bent handle and an inset bowl |
| flesh | Bevelled pink flesh cube with pale patches and stylized veins |
| tofu | Ivory tofu block with small pores and a leaf garnish |
| aminita | Red Amanita-style mushroom, white cap spots, stem skirt and volva |
| cubensis | Golden brown mushroom with a curved stem, wavy cap and gills |
| lazer | Graphite laser pointer with a brass collar, side clip and red lens |

Chicken, spoon, mushroom and laser-pointer copies attach to the actual dog
receiving the upgrade. `item_attachments.gd` uses native breed anchors and
stacks each additional copy visibly on that dog. Cosmetic counts survive slot
switches, Walkies and ground drops through the same item binding as gameplay.

`sync_csv_metadata.py` updates only native item, starter and breed catalog
blocks from the CSVs. It preserves descriptions, flavor, model descriptions,
notes and numeric values; it does not implement item behavior. Runtime methods
and the consumables catalog remain under their owning gameplay systems.
