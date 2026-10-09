"""Author the item collection and Mildred through the running Blender MCP.

Every asset is a flat shaded, ground centered mesh facing Blender +Y (Godot -Z).
Existing scenes, including Mappo, are preserved. Private references are not copied.
"""
import bpy
import math
import json
import hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ROOT.mkdir(parents=True, exist_ok=True)
scene = bpy.data.scenes.get('Items_Katamari_Review')
if scene is None:
    scene = bpy.data.scenes.new('Items_Katamari_Review')
else:
    for obj in list(scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 1600
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world = bpy.data.worlds.new('Items / studio world')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.065, .085, .12, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .65
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = -1.35
scene.view_settings.gamma = 1
parts = []
assets = {}

def mat(name, color, metal=0):
    m = bpy.data.materials.get('Items / ' + name) or bpy.data.materials.new('Items / ' + name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = .82
    p.inputs['Specular IOR Level'].default_value = .16
    return m

cream = mat('warm ivory', (.87, .82, .67))
white = mat('bone white', (.94, .93, .85))
mint = mat('mint enamel', (.17, .65, .48))
mint_light = mat('mint cushion', (.39, .86, .65))
plum = mat('deep plum', (.24, .095, .22))
purple = mat('lavender', (.57, .35, .72))
gold = mat('warm brass', (.89, .57, .10), .2)
orange = mat('tangerine', (.95, .30, .075))
red = mat('coral red', (.81, .12, .13))
blue = mat('blue enamel', (.055, .42, .82))
water = mat('bright water', (.13, .74, .90))
green = mat('tennis felt', (.57, .79, .095))
black = mat('charcoal', (.013, .017, .026))
brown = mat('biscuit and kibble', (.58, .29, .095))
crumb = mat('baked biscuit', (.87, .56, .20))
gray = mat('warm cat gray', (.25, .24, .22))
tan = mat('cat soft tan', (.65, .46, .29))
cat_white = mat('Mildred cream white', (.93, .90, .82))
cat_pink = mat('Mildred pink nose and ears', (.73, .36, .38))
cat_green = mat('Mildred green eyes', (.39, .59, .23))
cat_whisker = mat('Mildred fine white whiskers', (.81, .80, .72))
floor_mat = mat('studio floor', (.11, .15, .19))

def finish(obj, name, material):
    obj.name = name
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = False
    parts.append(obj)
    return obj

def mesh(name, vertices, faces, material):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    return finish(obj, name, material)

def box(name, center, size, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new('Single faceted edges', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return finish(obj, name, material)

def ellipsoid(name, center, size, material, segments=10, rings=5):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material)

def cylinder(name, center, radius, depth, material, radius_top=None, vertices=10):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius if radius_top is None else radius_top,
                                   depth=depth, location=center)
    return finish(bpy.context.object, name, material)

def rod(name, start, end, radius, material, end_radius=None, vertices=6):
    a, b = Vector(start), Vector(end)
    obj = cylinder(name, (a+b)/2, radius, (b-a).length, material, radius_top=end_radius, vertices=vertices)
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return obj

def tube(name, points, radius, material, sides=7, radii=None):
    points = [Vector(p) for p in points]
    vertices, faces = [], []
    for i, p in enumerate(points):
        tangent = (points[min(i+1, len(points)-1)] - points[max(0, i-1)]).normalized()
        up = Vector((0, 0, 1)) if abs(tangent.z) < .94 else Vector((0, 1, 0))
        u = tangent.cross(up).normalized()
        v = tangent.cross(u).normalized()
        r = radii[i] if radii else radius
        for j in range(sides):
            q = p + r * (u*math.cos(j*math.tau/sides) + v*math.sin(j*math.tau/sides))
            vertices.append(q)
    faces.append(tuple(range(sides-1, -1, -1)))
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a, b, b+sides, a+sides))
    faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
    return mesh(name, vertices, faces, material)

def loop(name, center, radius, material, tube_radius=.02, segments=12, plane='XY'):
    x,y,z=center
    points=[]
    for i in range(segments+1):
        a=i*math.tau/segments
        if plane=='XZ': points.append((x+radius*math.cos(a),y,z+radius*math.sin(a)))
        elif plane=='YZ': points.append((x,y+radius*math.cos(a),z+radius*math.sin(a)))
        else: points.append((x+radius*math.cos(a),y+radius*math.sin(a),z))
    return tube(name, points, tube_radius, material)

def extrude(name, outline, front, depth, material):
    n=len(outline)
    vertices=[(x,front,z) for x,z in outline]+[(x,front-depth,z) for x,z in outline]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,vertices,faces,material)

def surface_patch(name, base, outline, material):
    vertices=[]
    bpy.context.view_layer.update()
    inverse=base.matrix_world.inverted()
    for x,z in outline:
        start=inverse @ Vector((x,2,z))
        hit,point,normal,index=base.ray_cast(start,Vector((0,-1,0)))
        for attempt in range(6):
            if hit: break
            start.z-=.01
            hit,point,normal,index=base.ray_cast(start,Vector((0,-1,0)))
        if not hit: raise RuntimeError('Face patch misses '+name)
        vertices.append(base.matrix_world @ point + Vector((0,.0018,0)))
    return mesh(name,vertices,[tuple(range(len(vertices)))],material)

def ring_profile(name, rings, material, segments=12):
    # rings: z, radius. Returning to a tiny radius produces an enclosed vessel.
    vertices=[(radius*math.cos(i*math.tau/segments),radius*math.sin(i*math.tau/segments),z)
              for z,radius in rings for i in range(segments)]
    faces=[]
    for r in range(len(rings)-1):
        for j in range(segments):
            a=r*segments+j; b=r*segments+(j+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces.append(tuple(range(segments-1,-1,-1)))
    return mesh(name,vertices,faces,material)

def heart(name, center, scale, material):
    x,y,z=center
    outline=[(-.13,.04),(-.13,.14),(-.06,.19),(0,.14),(.06,.19),(.13,.14),(.13,.04),(0,-.12)]
    return extrude(name,[(x+a*scale,z+b*scale) for a,b in outline],y,.055*scale,material)

def bone(name, material, length=.44, radius=.036, z=.13):
    rod(name+' shaft',(-length*.37,0,z),(length*.37,0,z),radius,material,vertices=8)
    for s in (-1,1):
        for t in (-1,1):
            ellipsoid(name+' knuckle',(s*length*.38,t*radius*.88,z),(radius*1.6,radius*1.28,radius*1.35),material,8,4)

def frontal_bone(name, material, length, radius, center):
    x,y,z=center
    rod(name+' shaft',(x-length*.37,y,z),(x+length*.37,y,z),radius,material,vertices=8)
    for s in (-1,1):
        for t in (-1,1):
            ellipsoid(name+' knuckle',(x+s*length*.38,y,z+t*radius*.88),
                      (radius*1.6,radius*1.35,radius*1.28),material,8,4)

def begin():
    parts.clear()

def complete(asset_id, height=None):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts: obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=asset_id
    obj.data.name=asset_id
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    # Bake world positions, move ground to origin, center X/Y. Vertices are then all local.
    coords=[obj.matrix_world @ v.co for v in obj.data.vertices]
    minv=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    maxv=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    center=Vector(((minv.x+maxv.x)/2,(minv.y+maxv.y)/2,minv.z))
    factor=height/(maxv.z-minv.z) if height else 1
    obj.location=(0,0,0)
    obj.rotation_euler=(0,0,0)
    obj.scale=(1,1,1)
    for v,world in zip(obj.data.vertices,coords): v.co=(world-center)*factor
    obj.data.update()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj['asset_id']=asset_id
    obj['style']='Original Katamari inspired low poly flat color toy'
    bpy.ops.export_scene.gltf(filepath=str(ROOT/(asset_id+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,
         export_apply=True,export_normals=True,export_tangents=False,export_animations=False,
         export_lights=False,export_cameras=False,export_skins=False,export_morph=False)
    obj.hide_render=True
    obj.hide_set(True)
    assets[asset_id]=obj
    return obj

# Crunchy bone biscuit with individual baked holes.
begin(); bone('Biscuit',crumb,.48,.065,.09)
for x in (-.11,0,.11):
    ellipsoid('Baked hole',(x,0,.173),(.011,.012,.005),brown,6,3)
complete('biscuit',.22)

# A miniature mint running shoe: sole, toe, ankle tongue, and three laces.
begin()
box('Shoe outsole',(0,0,.045),(.24,.50,.08),cream,.035)
extrude('Sneaker upper',[(-.105,.065),(.105,.065),(.11,.15),(.05,.31),(-.06,.31),(-.115,.14)],-.06,.22,mint)
ellipsoid('Rounded sneaker toe',(0,.155,.13),(.12,.16,.09),mint_light,10,4)
box('Raised heel',(0,-.15,.165),(.22,.10,.19),mint,.035)
box('Ankle opening',(0,-.09,.272),(.12,.10,.025),plum,.015)
tongue=box('Shoe tongue',(0,.008,.25),(.12,.12,.035),purple,.008); tongue.rotation_euler.x=math.radians(-20)
for i in range(3): rod('Shoe lace',(-.07,.045+i*.045,.233-i*.018),(.07,.035+i*.045,.233-i*.018),.008,white)
complete('zoomies',.40)

# Rubber duck squeak toy.
begin()
ellipsoid('Duck rubber body',(0,0,.15),(.19,.23,.145),gold,10,5)
ellipsoid('Duck head',(0,.11,.35),(.125,.12,.12),gold,9,5)
beak=box('Duck beak',(0,.235,.32),(.145,.085,.04),orange,.008)
for s in (-1,1):
    ellipsoid('Duck eye',(s*.075,.206,.373),(.018,.009,.021),black,6,3)
    ellipsoid('Duck wing',(s*.16,0,.175),(.035,.125,.07),crumb,8,4)
tail=extrude('Duck tail',[(-.055,.19),(0,.29),(.055,.19)],-.18,.055,gold)
complete('squeaker',.45)

# Tennis ball with two curved stitched seams.
begin(); ellipsoid('Tennis ball',(0,0,.20),(.20,.20,.20),green,14,7)
for side in (-1,1):
    points=[]
    for i in range(17):
        a=-math.pi/2+i*math.pi/16
        points.append((side*.12*math.cos(a),.202*math.sin(a),.20+.163*math.cos(a)))
    tube('Tennis seam',points,.009,white,5)
complete('tennis',.42)

# Vet cone, hollow rather than a solid traffic cone.
begin()
ring_profile('Protective vet cone',[(.02,.075),(.31,.25),(.315,.235),(.07,.074),(.02,.075)],cream,12)
loop('Vet cone rim',(0,0,.315),.242,blue,.014)
loop('Vet cone neck',(0,0,.025),.081,mint,.018)
for a in (0,2.1,4.2):
    ellipsoid('Vet cone fastener',(.083*math.cos(a),.083*math.sin(a),.046),(.018,.018,.014),gold,6,3)
complete('cone',.43)

# Coiled leash with a lifted hand loop and a brass snap hook.
begin()
points=[]
for i in range(37):
    a=i*math.tau/12; radius=.17-i*.0025
    points.append((radius*math.cos(a),radius*math.sin(a),.03+i*.0009))
tube('Coiled leash',points,.017,blue,6)
tube('Leash end',[points[-1],(-.13,-.05,.12),(-.14,-.07,.25)],.017,blue,6)
loop('Leash handle',(-.12,-.06,.30),.075,blue,.020,12,'XZ')
loop('Leash brass hook',(.20,.045,.043),.047,gold,.012,10)
complete('leash',.42)

# Vampire kibble sack, open top with loose kibble and a cheeky fang label.
begin()
extrude('Kibble sack',[(-.17,.02),(.17,.02),(.19,.30),(.14,.42),(-.15,.42),(-.19,.29)],.10,.24,brown)
label=box('Kibble mint label',(0,.113,.21),(.235,.014,.18),mint,.018)
for s in (-1,1):
    extrude('Kibble fang',[(s*.04-.022,.24),(s*.04+.022,.24),(s*.04,.16)],.129,.009,white)
rod('Bag folded lip',(-.145,.035,.418),(.14,.035,.418),.026,cream,vertices=6)
for x,y in ((-.065,0),(.035,-.06),(.09,.012),(-.08,-.10)):
    ellipsoid('Kibble chunk',(x,y,.426),(.035,.028,.023),crumb,7,3)
complete('kibble',.51)

# Heart dog tag with brass attachment and a raised paw mark.
begin(); heart('Blue heart dog tag',(0,.055,.17),1.3,blue)
loop('Tag attachment',(0,.01,.42),.06,gold,.012,10,'XZ')
ellipsoid('Paw tag pad',(0,.069,.18),(.048,.006,.040),cream,8,4)
for x,z in ((-.048,.228),(-.017,.25),(.020,.25),(.051,.228)):
    ellipsoid('Paw tag toe',(x,.070,z),(.014,.006,.017),cream,6,3)
complete('tag',.45)

def bowl_contents(material, liquid):
    ring_profile('Low poly bowl',[(0,.17),(.02,.24),(.16,.29),(.175,.28),(.15,.245),(.055,.19),(.04,.01)],material,12)
    cylinder('Bowl contents',(0,0,.105),.23,.012,liquid,vertices=12)

begin(); bowl_contents(blue,water)
loop('Water bowl pale rim',(0,0,.17),.279,cream,.012)
frontal_bone('Bowl bone emblem',white,.19,.018,(0,.263,.092))
complete('bowl',.22)

# Flea collar is a physical open band with buckle, prongs, and tiny flea studs.
begin()
loop('Flea collar band',(0,0,.22),.19,purple,.035,14,'XZ')
box('Flea collar buckle',(.175,.011,.22),(.09,.075,.12),gold,.012)
box('Flea collar buckle opening',(.186,.053,.22),(.045,.009,.066),plum,.006)
for i in range(5):
    a=.7+i*.5
    ellipsoid('Flea collar stud',(.19*math.cos(a),.033,.22+.19*math.sin(a)),(.009,.012,.012),mint_light,6,3)
complete('spring',.45)

# Active howl horn: curled brass tubing, flared open bell, and a plum grip.
begin()
tube('Horn curled tubing',[(-.11,-.08,.07),(-.15,-.05,.13),(-.12,.02,.20),(-.06,.06,.21),(.04,.04,.20)],.031,gold,7)
bell=ring_profile('Horn open bell',[(0,.025),(.20,.12),(.215,.14),(.22,.126),(.195,.103),(.015,.021)],gold,10)
bell.rotation_euler.x=math.radians(-90); bell.location=(.04,.025,.20)
mouth=rod('Horn mouthpiece',(-.11,-.08,.075),(-.11,-.18,.075),.022,plum,vertices=8)
box('Horn mint grip',(-.12,-.045,.15),(.075,.06,.06),mint,.008)
complete('howl_horn',.40)

# Active medical bowl, recognizable white vessel and red cross.
begin(); bowl_contents(cream,mint_light)
box('Medical red cross vertical',(0,.277,.095),(.029,.008,.089),red,.002)
box('Medical red cross horizontal',(0,.278,.095),(.085,.009,.029),red,.002)
loop('Medical bowl rim',(0,0,.17),.279,red,.010)
complete('med_bowl',.23)

# An actual horseshoe magnet, with an open gap and contrasting pole tips.
begin()
outline=[(-.16,.02),(-.16,.27),(-.105,.35),(.105,.35),(.16,.27),(.16,.02),(.085,.02),(.085,.24),(.055,.27),(-.055,.27),(-.085,.24),(-.085,.02)]
extrude('Horseshoe magnet',outline,.07,.14,red)
for s in (-1,1): box('Magnet white pole',(s*.123,0,.065),(.075,.145,.085),white,.005)
complete('magnet',.40)

# Consumables.
begin(); ellipsoid('Bomb',(0,0,.17),(.17,.17,.17),black,10,5)
cylinder('Bomb fuse socket',(0,0,.337),.043,.035,gold,vertices=8)
tube('Bomb curved fuse',[(0,0,.36),(.025,0,.40),(.06,0,.43)],.008,cream,5)
ellipsoid('Bomb lit spark',(.07,0,.435),(.027,.026,.027),orange,6,3)
complete('bomb',.44)

begin(); loop('Key bow',(0,0,.34),.09,gold,.024,12,'XZ')
rod('Key shaft',(0,0,.065),(0,0,.26),.024,gold,vertices=8)
box('Key lower tooth',(.047,0,.08),(.095,.050,.040),gold,.005)
box('Key upper tooth',(.035,0,.145),(.074,.050,.035),gold,.005)
complete('key',.45)

# Four different bone silhouettes. Runtime can replace the single bone material.
begin(); bone('Classic bone',white,.43,.037,.065); complete('bone_0',.12)
begin()
tube('Curved bone',[(-.20,0,.065),(-.12,-.03,.075),(0,-.06,.086),(.12,-.03,.073),(.20,0,.065)],.029,white,7)
for s in (-1,1):
    ellipsoid('Curved bone joint',(s*.20,0,.065),(.055,.045,.040),white,8,4)
complete('bone_1',.12)
begin()
tube('Rib bone',[(-.21,.10,.06),(-.23,.035,.065),(-.17,-.07,.075),(-.065,-.13,.085),(.07,-.12,.076),(.17,-.055,.061),(.21,.045,.052)],.026,white,7,
     radii=[.035,.034,.033,.03,.026,.020,.012])
complete('bone_2',.10)
begin()
ellipsoid('Vertebra core',(0,0,.065),(.073,.072,.061),white,8,4)
rod('Vertebra left process',(0,0,.06),(-.16,.01,.045),.035,white,end_radius=.024)
rod('Vertebra right process',(0,0,.06),(.16,.01,.045),.035,white,end_radius=.024)
extrude('Vertebra spine',[(-.040,.06),(-.035,.16),(.028,.185),(.042,.06)],-.03,.058,white)
complete('bone_3',.15)

# Stone pedestal with eight faceted sides and mint velvet cushion.
begin()
cylinder('Pedestal broad foot',(0,0,.065),.40,.13,plum,radius_top=.36,vertices=8)
cylinder('Pedestal taper column',(0,0,.36),.245,.48,cream,radius_top=.29,vertices=8)
cylinder('Pedestal broad top',(0,0,.62),.39,.09,gold,radius_top=.39,vertices=8)
cylinder('Pedestal mint cushion',(0,0,.688),.35,.055,mint_light,radius_top=.33,vertices=8)
for a in range(8):
    angle=a*math.tau/8+math.pi/8
    rod('Pedestal facet trim',(.253*math.cos(angle),.253*math.sin(angle),.17),
        (.282*math.cos(angle),.282*math.sin(angle),.57),.009,mint,vertices=5)
complete('pedestal',.72)

# A toy slot machine with three reels, pull lever, payout tray and a bone sign.
begin()
box('Slot machine base',(0,0,.095),(.80,.59,.19),plum,.055)
box('Slot machine cabinet',(0,-.025,.71),(.70,.49,1.10),mint,.060)
box('Slot machine front panel',(0,.24,.79),(.62,.035,.55),gold,.025)
box('Slot black reel window',(0,.265,.87),(.56,.024,.24),black,.012)
for i in range(3):
    reel=cylinder('Slot cream reel',((i-1)*.178,.281,.87),.087,.14,cream,vertices=12)
    reel.rotation_euler.y=math.radians(90)
    if i==1: heart('Slot heart symbol',((i-1)*.178,.371,.843),.32,red)
    elif i==0:
        symbol=cylinder('Slot gold bone symbol',((i-1)*.178,.372,.864),.04,.009,gold,vertices=8)
        symbol.rotation_euler.x=math.radians(90)
    else:
        extrude('Slot diamond symbol',[(.145,.864),(.178,.904),(.211,.864),(.178,.824)],.373,.012,mint)
box('Slot reel separator left',(-.089,.362,.87),(.014,.016,.244),gold,.003)
box('Slot reel separator right',(.089,.362,.87),(.014,.016,.244),gold,.003)
box('Slot payout tray',(0,.32,.43),(.46,.21,.10),plum,.015)
box('Slot payout opening',(0,.27,.48),(.37,.015,.11),black,.008)
box('Slot coin slit',(.19,.277,.61),(.022,.010,.064),black,.003)
button=cylinder('Slot play button',(-.18,.275,.62),.045,.015,red,vertices=8); button.rotation_euler.x=math.radians(90)
box('Slot crown sign',(0,0,1.38),(.66,.22,.20),plum,.045)
frontal_bone('Slot crown bone',white,.40,.038,(0,.132,1.38))
rod('Slot lever base',(.38,-.015,.88),(.48,-.015,.88),.036,gold,vertices=8)
rod('Slot lever handle',(.48,-.015,.88),(.48,-.08,1.22),.021,gold,vertices=8)
ellipsoid('Slot lever knob',(.48,-.08,1.245),(.063,.061,.062),red,8,4)
complete('slot_machine',1.60)

# Mildred's shop counter, with a wood top and bone emblem on its front.
begin()
box('Shop counter cabinet',(0,0,.41),(1.66,.66,.70),mint,.05)
box('Shop counter top',(0,0,.83),(1.86,.79,.16),cream,.045)
box('Shop plum lower kickboard',(0,.331,.11),(1.59,.023,.105),plum,.010)
for x in (-.73,.73): box('Shop gold corner trim',(x,.332,.41),(.055,.022,.59),gold,.008)
frontal_bone('Shop bone emblem',white,.40,.042,(0,.35,.41))
box('Counter cash dish',(.58,.02,.944),(.31,.22,.06),plum,.025)
complete('shop_counter',.96)

# Mildred: cream calico, green eyes, pink ears, sitting with a bushy curled tail.
begin()
body=ellipsoid('Mildred fluffy torso',(0,-.055,.57),(.335,.27,.46),cat_white,12,7)
body.data.materials.append(gray); body.data.materials.append(tan)
for face in body.data.polygons:
    c=face.center
    if c.y<.015 and abs(c.x)>.15 and .10<c.z<.29: face.material_index=1
    if c.y<-.03 and c.x>.14 and -.27<c.z<.04: face.material_index=2
    if c.y<-.07 and c.x<-.13 and -.34<c.z<-.13: face.material_index=1
for s in (-1,1):
    ellipsoid('Mildred folded hind leg',(s*.244,-.03,.25),(.15,.215,.22),cat_white,9,5)
    ellipsoid('Mildred straight front leg',(s*.14,.168,.30),(.095,.092,.25),cat_white,9,5)
    ellipsoid('Mildred white paw',(s*.14,.208,.07),(.104,.124,.077),cat_white,10,4)
    for k in (-1,0,1):
        rod('Mildred subtle toe seam',(s*.14+k*.036,.317,.061),(s*.14+k*.036,.325,.042),.0032,cream,vertices=4)
head=ellipsoid('Mildred broad cat head',(0,.022,1.025),(.282,.222,.248),cat_white,12,6)
ellipsoid('Mildred white muzzle',(-.079,.211,.945),(.102,.054,.07),cat_white,9,4)
ellipsoid('Mildred white muzzle',(.079,.211,.945),(.102,.054,.07),cat_white,9,4)
for s in (-1,1):
    extrude('Mildred large triangular ear',[(s*.12,1.16),(s*.285,1.415),(s*.273,1.145)],.055,.115,cat_white)
    extrude('Mildred pink inner ear',[(s*.161,1.191),(s*.273,1.370),(s*.252,1.173)],.066,.018,cat_pink)
    ellipsoid('Mildred eye rim',(s*.117,.216,1.048),(.073,.019,.059),gray,10,4)
    eye=ellipsoid('Mildred green almond eye',(s*.117,.234,1.050),(.058,.012,.045),cat_green,10,4)
    eye.rotation_euler.y=s*math.radians(11)
    pupil=ellipsoid('Mildred narrow pupil',(s*.117,.245,1.051),(.014,.007,.039),black,8,4)
    ellipsoid('Mildred eye glint',(s*.105,.251,1.070),(.008,.003,.009),white,6,3)
    # Angular long fur on cheeks and the ruff, retaining the paper-toy silhouette.
    for k in range(3):
        z=.925+k*.068
        extrude('Mildred cheek fluff',[(s*.203,z-.06),(s*.302,z-.028),(s*.23,z+.055)],.12-k*.019,.10,cat_white)
    for k in range(3):
        rod('Mildred straight whisker',(s*.09,.261,.952-k*.022),(s*(.32+k*.027),.276,.98-k*.045),.0026,cat_whisker,end_radius=.0011,vertices=4)
extrude('Mildred pink nose',[(-.027,.959),(.027,.959),(0,.928)],.275,.026,cat_pink)
rod('Mildred nose line',(0,.27,.930),(0,.274,.908),.004,gray,vertices=4)
for s in (-1,1): rod('Mildred soft smile',(0,.270,.909),(s*.036,.263,.897),.0033,gray,vertices=4)
# Distinct gray markings on the forehead, following the reference's three short bars.
for x,z0,z1 in ((-.055,1.182,1.262),(0,1.199,1.275),(.055,1.190,1.247)):
    z1=min(z1,1.247 if abs(x)<.01 else 1.235)
    surface_patch('Mildred gray forehead marking',head,[(x-.012,z0),(x-.018,z1-.014),(x+.005,z1),(x+.014,z0+.015)],gray)
# Fluffy bib: one mesh of angular white locks above her white front legs.
for x,z in ((-.20,.77),(-.13,.74),(0,.72),(.13,.74),(.20,.77)):
    extrude('Mildred fluffy chest lock',[(x-.06,z+.16),(x+.06,z+.16),(x+.035,z+.04),(x,z-.035),(x-.04,z+.04)],.219,.052,cat_white)
tail_points=[(.10,-.24,.25),(-.20,-.28,.18),(-.43,-.17,.12),(-.48,.03,.095),(-.39,.235,.087),(-.20,.30,.096),(-.04,.275,.11)]
tail=tube('Mildred curled bushy tail',tail_points,.093,cat_white,9,radii=[.075,.10,.11,.105,.10,.088,.05])
tail.data.materials.append(gray); tail.data.materials.append(tan)
for face in tail.data.polygons:
    # Alternate large calico sections, with a cream tip.
    if 9<=face.index<27 or 36<=face.index<45: face.material_index=1
    if 27<=face.index<36: face.material_index=2
complete('mildred',1.40)

# Arrange a contact sheet, keeping per-file asset transforms at the origin.
display_ids=['biscuit','zoomies','squeaker','tennis','cone','leash','kibble','tag','bowl','spring',
             'howl_horn','med_bowl','magnet','bomb','key','bone_0','bone_1','bone_2','bone_3']
display_objects=[]
for i,asset_id in enumerate(display_ids):
    original=assets[asset_id]
    duplicate=original.copy(); duplicate.data=original.data
    scene.collection.objects.link(duplicate)
    duplicate.name='Display / '+asset_id
    duplicate.hide_set(False); duplicate.hide_render=False
    duplicate.location=((i%5-2)*1.13,(3-i//5)*1.08,0)
    display_objects.append(duplicate)
    # Native text labels are review helpers, never exported with the mesh.
    data=bpy.data.curves.new('Label '+asset_id,'FONT');data.body=asset_id.replace('_',' ')
    data.size=.10;data.align_x='CENTER';data.extrude=0
    label=bpy.data.objects.new('Label / '+asset_id,data);scene.collection.objects.link(label)
    label.location=(duplicate.location.x,duplicate.location.y+.43,.009)
    label.rotation_euler.z=math.pi
    label.data.materials.append(white)
    display_objects.append(label)
for i,asset_id in enumerate(('pedestal','slot_machine','shop_counter','mildred')):
    original=assets[asset_id]; duplicate=original.copy(); duplicate.data=original.data
    scene.collection.objects.link(duplicate); duplicate.hide_set(False); duplicate.hide_render=False
    duplicate.name='Display / '+asset_id
    duplicate.location=(-2.55+i*1.63,-1.30,0)
    display_objects.append(duplicate)
    data=bpy.data.curves.new('Label '+asset_id,'FONT');data.body=asset_id.replace('_',' ')
    data.size=.11;data.align_x='CENTER'
    label=bpy.data.objects.new('Label / '+asset_id,data);scene.collection.objects.link(label)
    label.location=(duplicate.location.x,-.73,.01);label.data.materials.append(white)
    label.rotation_euler.z=math.pi
    display_objects.append(label)

bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.014))
floor=bpy.context.object;floor.name='Review floor';floor.data.materials.append(floor_mat)
def light(name,location,energy,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=location
    obj.rotation_euler=(Vector((0,0,.4))-obj.location).to_track_quat('-Z','Y').to_euler()
    return obj
light('Items key',(1,4,8),1000,7)
light('Items fill',(-5,2,5),450,5)
light('Items rim',(1,-4,6),700,5)
data=bpy.data.cameras.new('Item studio camera');camera=bpy.data.objects.new('Item studio camera',data)
scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=8.55
camera.location=(6.0,9.5,10.3)
camera.rotation_euler=(Vector((0,.65,.25))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(ROOT/'source/item-collection-preview.png')
bpy.ops.render.render(write_still=True)

# Mildred portrait at eye level, with all other review objects hidden.
for obj in display_objects: obj.hide_render=True
cat=assets['mildred']; cat.hide_render=False
portrait_lighting=[('Items key',(2,4,3),650),('Items fill',(-4,3,2),550),('Items rim',(1,-4,5),600)]
for name,location,energy in portrait_lighting:
    lamp=bpy.data.objects[name];lamp.location=location;lamp.data.energy=energy
    lamp.rotation_euler=(Vector((0,0,.7))-lamp.location).to_track_quat('-Z','Y').to_euler()
scene.view_settings.exposure=-.35
camera.location=(1.2,4.0,2.3);camera.rotation_euler=(Vector((0,0,.70))-camera.location).to_track_quat('-Z','Y').to_euler()
data.ortho_scale=1.9
scene.render.resolution_x=1100;scene.render.resolution_y=1100
scene.render.filepath=str(ROOT/'source/mildred-preview.png')
bpy.ops.render.render(write_still=True)
cat.hide_render=True
scene.view_settings.exposure=-1.35
for name,location,energy in [('Items key',(1,4,8),1000),('Items fill',(-5,2,5),450),('Items rim',(1,-4,6),700)]:
    lamp=bpy.data.objects[name];lamp.location=location;lamp.data.energy=energy
    lamp.rotation_euler=(Vector((0,0,.4))-lamp.location).to_track_quat('-Z','Y').to_euler()
for obj in display_objects: obj.hide_render=False
camera.location=(6.0,9.5,10.3);camera.rotation_euler=(Vector((0,.65,.25))-camera.location).to_track_quat('-Z','Y').to_euler()
data.ortho_scale=8.55
scene.render.resolution_x=1600;scene.render.resolution_y=1100
scene.render.filepath=str(ROOT/'source/item-collection-preview.png')
manifest={}
for asset_id,obj in assets.items():
    obj.data.calc_loop_triangles()
    coords=[v.co for v in obj.data.vertices]
    manifest[asset_id]={'triangles':len(obj.data.loop_triangles),'vertices':len(obj.data.vertices),
      'dimensions_blender_xyz':[max(v[i] for v in coords)-min(v[i] for v in coords) for i in range(3)],
      'dimensions_godot_xyz':[max(v.x for v in coords)-min(v.x for v in coords),max(v.z for v in coords)-min(v.z for v in coords),max(v.y for v in coords)-min(v.y for v in coords)],
      'file':asset_id+'.glb'}
    raw=(ROOT/(asset_id+'.glb')).read_bytes()
    manifest[asset_id]['sha256']=hashlib.sha256(raw).hexdigest()
    manifest[asset_id]['bytes']=len(raw)
    manifest[asset_id]['gltf_triangles']=len(obj.data.loop_triangles)
(ROOT/'source/generation.json').write_text(json.dumps({'authoring':'Blender MCP localhost 9876',
 'style':'Original low-poly flat-color Katamari-inspired props',
 'orientation':'Ground-centered. Blender +Y front exports Godot -Z front.',
 'Mildred_reference':'Six user-supplied photographs. Private photographs remain outside the project.',
 'assets':manifest},indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source/items-katamari.blend'),copy=True)
result={'assets_exported':len(assets),'manifest':manifest,'preview':str(ROOT/'source/item-collection-preview.png'),
        'mildred_preview':str(ROOT/'source/mildred-preview.png'),'source':str(ROOT/'source/items-katamari.blend')}
