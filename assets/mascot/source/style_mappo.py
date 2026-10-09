"""Author the Katamari-inspired Mappo revision through Blender MCP.

Run in the review scene after importing the previous GLB. Blender is Z-up,
and Mappo faces +Y, exported as Godot -Z. Review helpers are not exported.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.context.scene
for obj in list(scene.objects):
    if obj.type == 'MESH':
        obj.hide_render = True
        obj.hide_set(True)
parts = []

def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = 1
    shader.inputs['Specular IOR Level'].default_value = 0.12
    return mat

coat = material('Mappo / charcoal coat', (0.025, 0.029, 0.043))
muzzle = material('Mappo / black muzzle', (0.012, 0.014, 0.022))
nose = material('Mappo / nose and pupils', (0.003, 0.004, 0.007))
mint = material('Mappo / mint collar', (0.19, 0.83, 0.58))
blue = material('Mappo / blue heart', (0.025, 0.43, 0.95))
amber = material('Mappo / amber eyes', (0.54, 0.23, 0.035))
pink = material('Mappo / tongue and ears', (0.72, 0.17, 0.24))
spots = material('Mappo / tongue spots', (0.10, 0.055, 0.095))
white = material('Mappo / tiny white toes', (0.88, 0.91, 0.85))
ivory = material('Mappo / teeth', (0.84, 0.79, 0.64))
brindle = material('Mappo / muted lower-leg brindle', (0.060, 0.047, 0.039))
whisker_material = material('Mappo / black whiskers', (0.0, 0.0, 0.0))
whisker_material.node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value = 0.0

def finish(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = False
    parts.append(obj)
    return obj

def box(name, center, size, mat, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Single-facet toy edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat)

def ellipsoid(name, center, size, mat, segments=10, rings=5):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat)

def extrude_shape(name, outline, front, depth, mat):
    # Polygon in X/Z, with front facing +Y.
    vertices = [(x, front, z) for x,z in outline] + [(x, front-depth, z) for x,z in outline]
    n = len(outline)
    faces = [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return finish(obj, name, mat)

def limb(name, x, rings):
    # Continuous bevelled square sections, rather than separate joint blocks.
    outline = [(-0.5,-0.32),(-0.32,-0.5),(0.32,-0.5),(0.5,-0.32),
               (0.5,0.32),(0.32,0.5),(-0.32,0.5),(-0.5,0.32)]
    vertices = [(x + px*width, y + py*depth, z)
                for y,z,width,depth in rings for px,py in outline]
    faces = [tuple(range(8))]
    for i in range(len(rings)-1):
        for j in range(8):
            faces.append((i*8+j,(i+1)*8+j,(i+1)*8+(j+1)%8,i*8+(j+1)%8))
    faces.append(tuple(range(len(vertices)-1,len(vertices)-9,-1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    finish(obj, name, coat)
    obj.data.materials.append(brindle)
    for face in obj.data.polygons:
        if face.center.z < 0.30 and face.index % 5 == 2:
            face.material_index = 1
    return obj

def paw(name, x, y, width):
    ellipsoid(name, (x,y,0.05), (width/2,0.11,0.05), coat, 8, 3)
    for offset in (-0.05,0,0.05):
        ellipsoid(name+'_Toe', (x+offset,y+0.075,0.032),
                  (0.026,0.043,0.032), coat, 6, 3)
    # A tiny pale toe detail, without the previous broad white front band.
    box(name+'_WhiteToe', (x,y+0.118,0.016), (0.022,0.006,0.018), white, 0.002)

def whisker(name, start, end):
    # Thin, straight hairs with collinear rings and a tapered single-point end.
    start, end = Vector(start), Vector(end)
    points = [start, start.lerp(end, 0.58), end]
    vertices = []
    for i, radius in enumerate((0.0028,0.0019)):
        tangent = (points[i+1]-points[max(0,i-1)]).normalized()
        axis = tangent.cross(Vector((0,0,1))).normalized()
        other = tangent.cross(axis).normalized()
        for j in range(4):
            angle = j*math.pi/2
            vertices.append(points[i]+radius*(math.cos(angle)*axis+math.sin(angle)*other))
    vertices.append(points[2])
    faces = [(3,2,1,0)]
    for j in range(4):
        faces.append((j,(j+1)%4,(j+1)%4+4,j+4))
        faces.append((j+4,(j+1)%4+4,8))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return finish(obj, name, whisker_material)

# Broad shapes, deliberate facets, tapered dog legs, and a nearly cubic head.
box('Mappo_Body', (0,-0.28,0.59), (0.56,1.14,0.53), coat, 0.15)
box('Mappo_Chest', (0,0.22,0.68), (0.56,0.43,0.60), coat, 0.12)
for x in (-0.205,0.205):
    limb('Mappo_FrontLeg', x, [(0.26,0.53,0.195,0.23),
                              (0.245,0.32,0.145,0.16),
                              (0.27,0.095,0.115,0.12)])
    limb('Mappo_HindLeg', x, [(-0.65,0.66,0.24,0.29),
                             (-0.54,0.37,0.165,0.185),
                             (-0.70,0.15,0.115,0.12),
                             (-0.66,0.08,0.11,0.115)])
    paw('Mappo_FrontPaw', x, 0.315, 0.18)
    paw('Mappo_HindPaw', x, -0.635, 0.17)

box('Mappo_Collar', (0,0.27,0.835), (0.67,0.54,0.135), mint, 0.042)
box('Mappo_Head', (0,0.335,1.12), (0.64,0.64,0.60), coat, 0.06)
for side in (-1,1):
    ear = extrude_shape('Mappo_Ear', [(side*0.135,1.19),(side*0.23,1.36),(side*0.34,1.46),(side*0.403,1.335),(side*0.35,1.16)], 0.41, 0.15, coat)
    inner_ear = extrude_shape('Mappo_InnerEar', [(side*0.215,1.23),(side*0.333,1.405),(side*0.353,1.24)], 0.419, 0.008, pink)
    for part in (ear, inner_ear):
        part.scale.x = (0.64 / 0.73) * 1.30
        for vertex in part.data.vertices:
            vertex.co.z = 1.16 + (vertex.co.z - 1.16) * 1.55
        part.location.z = 0.11

# Four broad planes taper from a square cheek base to a small square nose cap.
# The base sits slightly inside the face, hiding the attachment seam.
snout_vertices = []
for y, center_z, half_width, half_height in [(0.62,1.025,0.185,0.17),(1.085,1.04,0.065,0.065)]:
    snout_vertices.extend([(-half_width,y,center_z-half_height),
                           (half_width,y,center_z-half_height),
                           (half_width,y,center_z+half_height),
                           (-half_width,y,center_z+half_height)])
snout_faces = [(0,1,2,3),(7,6,5,4),
               (0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
snout_mesh = bpy.data.meshes.new('Mappo_SquarePyramidMuzzle')
snout_mesh.from_pydata(snout_vertices, [], snout_faces)
snout_mesh.update()
snout = bpy.data.objects.new('Mappo_Muzzle', snout_mesh)
scene.collection.objects.link(snout)
finish(snout, 'Mappo_Muzzle', muzzle)
box('Mappo_Nose', (0,1.093,1.052), (0.145,0.05,0.115), nose, 0.012)
# Dark back of the mouth and upper canines stay attached to the skull.
box('Mappo_MouthCavity', (0,0.665,0.895), (0.29,0.035,0.19), nose, 0.012)
for x in (-0.065,0.065):
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.003, radius2=0.018,
                                   depth=0.076, location=(x,0.95,0.948))
    finish(bpy.context.object, 'Mappo_UpperCanine', ivory)
for x in (-0.038,-0.013,0.013,0.038):
    box('Mappo_UpperFrontTooth', (x,1.078,0.964), (0.019,0.025,0.027), ivory, 0.002)
for x in (-0.198,0.198):
    ellipsoid('Mappo_AmberEye', (x,0.648,1.193), (0.079,0.023,0.084), amber)
    ellipsoid('Mappo_Pupil', (x,0.672,1.196), (0.050,0.01,0.059), nose, 8, 4)
    ellipsoid('Mappo_EyeSpark', (x-0.016,0.683,1.220), (0.014,0.005,0.018), white, 6, 3)
for side in (-1,1):
    for y,z,reach,lift in [(0.80,0.972,0.16,0.023),
                           (0.845,0.960,0.15,-0.005),
                           (0.895,0.955,0.14,-0.025)]:
        width = 0.185 - 0.12*(y-0.62)/(1.085-0.62)
        whisker('Mappo_Whisker', (side*(width+0.001),y,z),
                                (side*(width+reach),y+0.060,z+lift))

# The lower jaw is a separate mesh hinged at the rear mouth corners.
jaw_start = len(parts)
jaw_vertices = []
for y, half_width, top_z in [(0.66,0.14,0.925),(1.045,0.073,0.958)]:
    jaw_vertices.extend([(-half_width,y,top_z-0.060),
                         (half_width,y,top_z-0.060),
                         (half_width,y,top_z),(-half_width,y,top_z)])
jaw_mesh = bpy.data.meshes.new('Mappo_LowerJaw')
jaw_mesh.from_pydata(jaw_vertices, [], snout_faces)
jaw_mesh.update()
jaw_obj = bpy.data.objects.new('Mappo_LowerJaw', jaw_mesh)
scene.collection.objects.link(jaw_obj)
finish(jaw_obj, 'Mappo_LowerJaw', muzzle)
box('Mappo_Gums', (0,0.90,0.945), (0.15,0.24,0.02), spots, 0.008)
tongue = box('Mappo_Tongue', (0,0.923,0.964), (0.15,0.22,0.023), pink, 0.020)
for vertex in tongue.data.vertices:
    vertex.co.x *= 1.0 - 0.25*max(0.0,min(1.0,(vertex.co.y+0.11)/0.22))
tongue.rotation_euler.x = math.radians(-8)
patch=box('Mappo_TongueCenterPatch',(0,0.924,0.977),(0.060,0.15,0.004),spots,0.002)
patch.rotation_euler.x=math.radians(-8)
for x,y,z in [(0.047,0.943,0.972),(-0.027,0.993,0.965)]:
    ellipsoid('Mappo_TongueSpot',(x,y,z),(0.018,0.019,0.004),spots,6,3)
for x in (-0.065,0.065):
    box('Mappo_LowerTooth',(x,0.975,0.951),(0.023,0.027,0.035),ivory,0.004)
jaw_parts = parts[jaw_start:]
del parts[jaw_start:]

# A small, readable heart rather than texture fragments.
box('Mappo_TagLoop',(0,0.555,0.815),(0.04,0.045,0.08),white,0.012)
heart = [(-0.105,0.754),(-0.105,0.809),(-0.056,0.844),(0,0.808),(0.056,0.844),(0.105,0.809),(0.105,0.754),(0,0.66)]
extrude_shape('Mappo_HeartTag',heart,0.59,0.045,blue)

# Even thickness through most of the tail, ending in a single pointed apex.
centers = [Vector(p) for p in [(0,-0.77,0.68),(0,-1.00,0.73),(0,-1.23,0.86),(0,-1.42,1.05),(0,-1.49,1.28),(0,-1.45,1.43)]]
tail_base = centers[0].copy()
centers = [tail_base + (center-tail_base)*0.85 for center in centers]
radii = [0.09,0.09,0.09,0.09,0.085]
vertices=[]
for i,(center,radius) in enumerate(zip(centers,radii)):
    tangent=(centers[min(i+1,len(centers)-1)]-centers[max(0,i-1)]).normalized()
    axis=Vector((1,0,0));other=tangent.cross(axis).normalized()
    for j in range(6):
        angle=2*math.pi*j/6
        vertices.append(center+radius*(math.cos(angle)*axis+math.sin(angle)*other))
faces=[tuple(range(5,-1,-1))]
for i in range(len(radii)-1):
    for j in range(6):
        faces.append((i*6+j,i*6+(j+1)%6,(i+1)*6+(j+1)%6,(i+1)*6+j))
tip_index = len(vertices)
vertices.append(centers[-1])
last_ring = (len(radii)-1)*6
for j in range(6):
    faces.append((last_ring+j,last_ring+(j+1)%6,tip_index))
mesh=bpy.data.meshes.new('Mappo_Tail');mesh.from_pydata(vertices,[],faces);mesh.update()
tail=bpy.data.objects.new('Mappo_Tail',mesh);scene.collection.objects.link(tail);finish(tail,'Mappo_Tail',coat)

bpy.ops.object.select_all(action='DESELECT')
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.join()
model=bpy.context.object;model.name='Mappo_Katamari'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
normalization = 1.46 / model.dimensions.z
model.scale = Vector((1,1,1)) * normalization
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
model.data.calc_loop_triangles()

bpy.ops.object.select_all(action='DESELECT')
for obj in jaw_parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = jaw_parts[0]
bpy.ops.object.join()
jaw = bpy.context.object
jaw.name = 'Mappo_LowerJaw'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Bake the same scale into both meshes so the hinge has no scale animation.
for vertex in jaw.data.vertices:
    vertex.co *= normalization
hinge = Vector((0,0.66,0.895)) * normalization
for vertex in jaw.data.vertices:
    vertex.co -= hinge
pivot = bpy.data.objects.new('Mappo_JawPivot', None)
scene.collection.objects.link(pivot)
pivot.location = hinge
jaw.parent = pivot
jaw.location = Vector((0,0,0))
jaw.data.calc_loop_triangles()
scene.render.fps = 25
scene.frame_start = 1
scene.frame_end = 8
pivot.rotation_mode = 'XYZ'
old_action = bpy.data.actions.get('Mappo_Shoot')
if old_action is not None and old_action.users == 0:
    bpy.data.actions.remove(old_action)
for frame, angle in [(1,0),(3,-29),(5,-29),(8,0)]:
    pivot.rotation_euler.x = math.radians(angle)
    pivot.keyframe_insert(data_path='rotation_euler', frame=frame)
pivot.animation_data.action.name = 'Mappo_Shoot'
scene.frame_set(1)
scene.camera.location=(2.6,4,2.25)
scene.camera.rotation_euler=(Vector((0,-0.02,0.70))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.ortho_scale=2.45
scene.render.filepath=str(ROOT/'source/mappo-katamari-preview.png')
bpy.ops.render.render(write_still=True)
scene.frame_set(4)
scene.render.filepath=str(ROOT/'source/mappo-shoot-open-preview.png')
bpy.ops.render.render(write_still=True)
scene.frame_set(1)
result={'model':model.name,'triangles':len(model.data.loop_triangles)+len(jaw.data.loop_triangles),'materials':len(model.data.materials),'dimensions':list(model.dimensions),'animation':pivot.animation_data.action.name,'jaw_mesh':jaw.name,'duration_seconds':(scene.frame_end-scene.frame_start)/scene.render.fps}
