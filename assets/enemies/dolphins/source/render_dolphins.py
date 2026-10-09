"""Render the editable dolphin roster without changing exported game assets."""
import bpy
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(HERE/'dolphin-roster.blend'))
def studio_material():
    mat=bpy.data.materials.new('Contact sheet backdrop');mat.diffuse_color=(.22,.30,.32,1)
    mat.use_nodes=True;bsdf=mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value=(.22,.30,.32,1);bsdf.inputs['Roughness'].default_value=.9
    return mat
bpy.ops.mesh.primitive_plane_add(size=200,location=(-6.8,-8.85,-.02))
bpy.context.object.data.materials.append(studio_material())
world=bpy.context.scene.world or bpy.data.worlds.new('Studio');bpy.context.scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.78,.81,.88,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.25
for p,power,size in [((-10,5,12),1600,9),((3,-4,8),700,8)]:
    bpy.ops.object.light_add(type='AREA',location=p)
    light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((-6.8,-8.85,.6))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-6.8,10,35));camera=bpy.context.object
camera.rotation_euler=(Vector((-6.8,-8.85,.55))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=23;bpy.context.scene.camera=camera
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=48
scene.render.resolution_x=1800;scene.render.resolution_y=2300;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(HERE/'dolphin-roster.png');bpy.ops.render.render(write_still=True)
