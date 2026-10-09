"""Flat-shaded finish for the Asset Studio GLB; run with Blender bpy Python.
Usage: python finish_mappo.py input.glb output.glb
Preserves generated geometry, UVs and base color; removes baked smooth normals.
"""
import sys
import bpy
import math
from mathutils import Matrix, Vector

source, destination = sys.argv[1:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
for obj in bpy.context.scene.objects:
    if obj.type != "MESH":
        continue
    # The generated reference pose has a diagonal body and a turned head.
    # Blender is Z-up: straighten the head around the neck, then align the
    # entire dog with +Y (Godot -Z). Bake into vertices, not the weapon holder.
    neck = Vector((0.43, 0.16, 0.80))
    body_forward = Vector((0.87590367, 0.48248602, 0.0))
    align_body = Matrix.Rotation(math.radians(61.15), 3, "Z")
    for vertex in obj.data.vertices:
        point = vertex.co.copy()
        front = point.dot(body_forward)
        weight = max(0.0, min(1.0, (point.z - 0.60) / 0.18)) if front > 0.18 else 0.0
        weight = weight * weight * (3.0 - 2.0 * weight)
        straighten_head = Matrix.Rotation(math.radians(-33.0) * weight, 3, "Z")
        vertex.co = align_body @ (neck + straighten_head @ (point - neck))
    white_paws = bpy.data.materials.new("Mappo_white_paws")
    white_paws.use_nodes = True
    paw_shader = white_paws.node_tree.nodes.get("Principled BSDF")
    paw_shader.inputs["Base Color"].default_value = (0.82, 0.82, 0.82, 1.0)
    paw_shader.inputs["Roughness"].default_value = 1.0
    paw_index = len(obj.data.materials)
    obj.data.materials.append(white_paws)
    dark_legs = bpy.data.materials.new("Mappo_black_legs")
    dark_legs.use_nodes = True
    leg_shader = dark_legs.node_tree.nodes.get("Principled BSDF")
    leg_shader.inputs["Base Color"].default_value = (0.014, 0.015, 0.020, 1.0)
    leg_shader.inputs["Roughness"].default_value = 1.0
    leg_index = len(obj.data.materials)
    obj.data.materials.append(dark_legs)
    # Keep only the lowest 10% of the previous white surface area. The rest
    # becomes black fur; do not restore the generated brown paw texture.
    obj.data.update()
    previous_white = [face for face in obj.data.polygons if face.center.z < 0.46]
    white_budget = sum(face.area for face in previous_white) * 0.10
    white_area = 0.0
    white_faces = set()
    for face in sorted(previous_white, key=lambda face: face.center.z):
        if abs(white_area + face.area - white_budget) < abs(white_area - white_budget):
            white_faces.add(face.index)
            white_area += face.area
    print("White paw area:", white_area, "target:", white_budget)
    for face in obj.data.polygons:
        face.use_smooth = False
        if face.center.z < 0.46:
            face.material_index = paw_index if face.index in white_faces else leg_index
    for material in obj.data.materials:
        if not material or not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            for name, value in [("Metallic", 0.0), ("Roughness", 1.0), ("Normal", None)]:
                socket = node.inputs.get(name)
                if socket is None:
                    continue
                for link in list(socket.links):
                    material.node_tree.links.remove(link)
                if value is not None:
                    socket.default_value = value
bpy.ops.export_scene.gltf(
    filepath=destination, export_format="GLB", export_apply=True,
    export_normals=True, export_tangents=False, export_animations=False,
    export_skins=False, export_morph=False, export_lights=False,
    export_cameras=False,
)
print("Finished flat-shaded Mappo:", destination)
