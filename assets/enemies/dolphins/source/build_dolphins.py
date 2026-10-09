"""Author/export the twenty faceted dolphins. Blender 5.2, no external textures."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
ROOT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for mat in list(bpy.data.materials):
    if mat.users == 0: bpy.data.materials.remove(mat)
materials = {}
def material(name, color, metallic=0.0):
    if name in materials: return materials[name]
    mat = bpy.data.materials.new(name); mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = .82
    bsdf.inputs['Metallic'].default_value = metallic
    materials[name] = mat; return mat
cream = material('Porcelain belly', (.90,.91,.80))
black = material('Ink eyes', (.023,.035,.054))
white = material('Eye sparkle', (.98,.99,1))
gold = material('Brass', (.85,.55,.14), .45)
rope = material('Woven rope', (.68,.47,.25))
red = material('Coral red', (.79,.17,.19))
blue = material('Sailor blue', (.08,.22,.45))
pink = material('Pearl pink', (.91,.56,.71))
purple = material('Cosmic violet', (.42,.16,.65))
green = material('Kelp green', (.16,.46,.24))
ice = material('Ice crystals', (.40,.83,.94))
smoke = material('Clouds', (.73,.80,.83))
obsidian = material('Obsidian', (.10,.12,.17))
parts=[]
def own(obj, name, mat):
    obj.name = name; obj.data.materials.append(mat); parts.append(obj)
    for poly in obj.data.polygons: poly.use_smooth=False
    return obj
def ell(name, p, s, mat, segments=12, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=p)
    obj=bpy.context.object; obj.scale=s
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return own(obj,name,mat)
def box(name,p,s,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    obj=bpy.context.object; obj.scale=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return own(obj,name,mat)
def cone(name,p,r,h,mat,r2=0,vertices=8):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r2,depth=h,location=p)
    return own(bpy.context.object,name,mat)
def rod(name,a,b,r,mat,vertices=6):
    mid=(Vector(a)+Vector(b))*.5; direction=Vector(b)-Vector(a)
    obj=cone(name,mid,r,direction.length,mat,r,vertices)
    obj.rotation_euler=direction.to_track_quat('Z','Y').to_euler();return obj
def ring(name,p,r,thickness,mat,axis='Z'):
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=4,location=p,major_radius=r,minor_radius=thickness)
    obj=own(bpy.context.object,name,mat)
    if axis=='Y': obj.rotation_euler.x=math.pi*.5
    if axis=='X': obj.rotation_euler.y=math.pi*.5
    return obj
def fin(name,points,width,mat):
    # A solid bevel-free fin, with six broad flat faces.
    vertices=[(x-width*.5,y,z) for x,y,z in points]+[(x+width*.5,y,z) for x,y,z in points]
    n=len(points);faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    return own(obj,name,mat)
def tube(name,points,r,mat):
    for i in range(len(points)-1): rod(name+str(i),points[i],points[i+1],r,mat)
def star(name,p,size,mat):
    x,y,z=p
    points=[(0,y+math.sin(i*math.pi/5)*size*(1 if i%2==0 else .45),z+math.cos(i*math.pi/5)*size*(1 if i%2==0 else .45)) for i in range(10)]
    obj=fin(name,points,.055,mat);obj.location.x=x;return obj

ROSTER=[
('reef_scout','Reef Scout',0,(.21,.64,.63)),('sailor','Deckhand Dolphin',0,(.29,.50,.73)),
('pearl','Pearl Courier',0,(.66,.60,.80)),('coral','Coral Gardener',0,(.66,.34,.44)),
('comet','Comet Flipper',1,(.34,.42,.78)),('racing','Turbo Porpoise',1,(.85,.39,.16)),
('swordfin','Swordfin Duelist',1,(.52,.61,.67)),('storm','Storm Skimmer',1,(.38,.63,.72)),
('lighthouse','Lighthouse Lookout',2,(.39,.58,.55)),('scholar','Sonar Scholar',2,(.65,.47,.32)),
('cosmic','Cosmic Listener',2,(.48,.32,.74)),('icicle','Icicle Oracle',2,(.48,.77,.84)),
('anchor','Anchor Hauler',3,(.28,.38,.44)),('armored','Reef Juggernaut',3,(.39,.49,.35)),
('volcano','Volcano Belcher',3,(.39,.24,.24)),('puffer','Puffer Bruiser',3,(.74,.58,.22)),
('crown','THE REEF REGENT',4,(.31,.63,.71)),('pirate','CAPTAIN BLACKFIN',4,(.29,.34,.44)),
('kraken',"KRAKEN'S BEST FRIEND",4,(.40,.35,.65)),('clockwork','ADMIRAL TICKTOCK',4,(.65,.45,.25))]

all_models=[]
for idx,(key,label,role,color) in enumerate(ROSTER):
    parts=[];skin=material(key+' skin',color)
    width=.45 if role not in (3,4) else .57
    length=.84 if role!=1 else .98
    if key=='puffer': width=.70;length=.78
    # Blender +Y is Godot -Z forward. All fins are biological, even in armor.
    ell('DolphinBody',(0,-.12,.73),(width,length,.38),skin)
    ell('Pale belly',(0,.05,.51),(width*.84,length*.85,.17),cream)
    ell('DolphinForehead',(0,.63,.87),(width*.82,.45,.37),skin)
    beak_length=.40 if key!='swordfin' else .64
    ell('Distinct dolphin beak',(0,.96+beak_length*.4,.69),(.18,beak_length,.11),skin,10,5)
    ell('Lower smiling jaw',(0,.99+beak_length*.4,.63),(.16,beak_length*.91,.044),cream,10,4)
    for side in [-1,1]:
        eye=ell('Friendly dark eye',(side*width*.63,.855,.97),(.060,.076,.065),black,8,4)
        ell('Eye glint',(side*width*.655,.906,.994),(.017,.02,.02),white,6,3)
        # Flippers sweep backward but keep wide triangular silhouettes.
        fin('Flipper'+('Left' if side<0 else 'Right'),[(side*.30,.27,.69),(side*(width+.46),-.29,.39),(side*.33,-.42,.59)],.08,skin)
    fin('DorsalFin',[(0,.09,.99),(0,-.18,1.54 if role!=1 else 1.46),(0,-.63,.95)],.13,skin)
    ell('Tail stem',(0,-1.0,.55),(.19,.37,.16),skin,10,5)
    for side in [-1,1]:
        fin('TailFluke'+('Left' if side<0 else 'Right'),[(0,-1.17,.57),(side*.57,-1.53,.64),(side*.53,-1.19,.50),(0,-1.05,.52)],.08,skin)
    # Accessories change outline and make each of the twenty readable at range.
    if key=='reef_scout':
        ring('Kelp scarf',(0,.34,.87),.38,.055,green,'Y')
        fin('Long scarf end',[(.38,.18,.82),(.48,-.39,.62),(.35,-.61,.72)],.12,green)
        box('Explorer satchel',(-.49,-.18,.76),(.20,.36,.33),rope)
    elif key=='sailor':
        cone('Sailor cap',(0,.56,1.20),.30,.10,white,.23,12)
        box('Cap ribbon',(0,.81,1.19),(.35,.04,.05),blue)
        for y in [-.40,-.20,0]: ring('Jacket stripe',(0,y,.72),.41,.035,white,'Y')
        ell('Life jacket',(.42,-.1,.75),(.09,.38,.26),blue)
    elif key=='pearl':
        for i in range(12):
            a=i*math.tau/12;ell('Pearl necklace',(math.sin(a)*.42,.42,math.cos(a)*.33+.78),(.055,)*3,white,6,4)
        ell('Shell satchel',(-.50,-.14,.76),(.11,.31,.29),pink,10,5)
        for i in range(6): rod('Shell rib',(-.62,-.36+i*.08,.53),(-.63,-.14,1.01),.014,cream)
    elif key=='coral':
        box('Planter pack',(0,-.62,1.05),(.50,.37,.29),rope)
        for i in range(5):
            x=(i-2)*.11;h=1.48+(i%2)*.20
            rod('Coral stalk',(x,-.62,1.12),(x,-.62,h),.045,red)
            for side in [-1,1]:rod('Coral branch',(x,-.62,h-.17),(x+side*.12,-.62,h-.06),.027,pink)
        for i in range(5):ell('Crown flower',((i-2)*.11,.62,1.20),(.07,.06,.055),pink,6,3)
    elif key=='comet':
        star('Comet star',(.31,.88,1.14),.15,gold)
        for side in [-1,1]:fin('Long comet streamer',[(side*.25,-.15,1.0),(side*.43,-1.71,1.32),(side*.25,-1.13,.83)],.06,gold)
    elif key=='racing':
        ell('Racing helmet',(0,.63,1.04),(.38,.35,.25),red)
        box('Helmet visor',(0,.91,1.05),(.49,.13,.13),obsidian)
        for side in [-1,1]:
            obj=cone('Twin rocket boosters',(side*.49,-.27,.80),.13,.63,gold,.11,8);obj.rotation_euler.x=math.pi*.5
            obj=cone('Rocket exhaust',(side*.49,-.67,.80),.11,.18,red,0,8);obj.rotation_euler.x=math.pi*.5
        fin('Racing stripe',[(0,.03,1.01),(0,-.18,1.54),(0,-.49,1.02)],.15,white)
    elif key=='swordfin':
        fin('Blade dorsal',[(0,.05,1.04),(0,-.05,1.89),(0,-.51,1.03)],.08,cream)
        ring('Fencing mask rim',(0,.84,.96),.29,.035,gold,'Y')
        for x in [-.18,0,.18]:rod('Mask vertical mesh',(x,1.0,.75),(x,1.0,1.16),.012,black)
        for z in [.85,1.03]:rod('Mask horizontal mesh',(-.25,1.0,z),(.25,1.0,z),.012,black)
    elif key=='storm':
        for i in range(4):ell('Cloud pack',((i%2-.5)*.38,-.55,1.27+i//2*.18),(.29,.24,.19),smoke,8,5)
        for side in [-1,1]:
            fin('Lightning wing',[(side*.32,0,.9),(side*.67,-.26,1.22),(side*.53,-.39,.84),(side*.79,-.56,.96),(side*.51,-.70,.68)],.065,gold)
    elif key=='lighthouse':
        cone('Lighthouse tower',(0,.56,1.40),.19,.57,cream,.13,10)
        cone('Lighthouse red band',(0,.56,1.40),.17,.07,red,.17,10)
        cone('Lantern room',(0,.56,1.75),.20,.17,gold,.20,10)
        cone('Lantern roof',(0,.56,1.91),.27,.16,red,0,10)
        for side in [-1,1]:
            obj=cone('Telescope goggles',(side*.19,.96,1.02),.09,.22,black,.09,8);obj.rotation_euler.x=math.pi*.5
    elif key=='scholar':
        box('Mortarboard',(0,.58,1.25),(.69,.48,.05),black)
        rod('Graduation tassel',(.25,.60,1.25),(.39,.60,1.02),.019,gold)
        for side in [-1,1]:ring('Round spectacles',(side*.23,.93,1.02),.12,.025,gold,'Y')
        rod('Spectacle bridge',(-.09,.95,1.02),(.09,.95,1.02),.02,gold)
        box('Book saddle',(0,-.49,1.12),(.62,.41,.09),red)
        box('Book pages',(0,-.49,1.13),(.56,.37,.08),cream)
    elif key=='cosmic':
        ell('Dorsal planet',(0,-.26,1.50),(.23,)*3,pink,10,5)
        ring('Saturn rings',(0,-.26,1.50),.36,.034,gold)
        for side in [-1,1]:
            rod('Satellite antenna',(side*.26,.53,1.16),(side*.43,.53,1.51),.025,cream)
            ell('Antenna orb',(side*.43,.53,1.54),(.075,)*3,purple,8,4)
    elif key=='icicle':
        for side in [-1,1]:
            for j in range(3):
                obj=cone('Icicle flipper',(side*(.39+j*.13),-.18-j*.13,.90-j*.04),.075,.42,ice,0,5)
                obj.rotation_euler.y=side*.55
        for i in range(4):cone('Frozen hood crest',((i-1.5)*.12,.60,1.25),.09,.42,ice,0,5)
    elif key=='anchor':
        ell('Diving helmet',(0,.53,1.03),(.49,.41,.32),gold,12,6)
        ring('Helmet porthole',(0,.94,1.03),.23,.06,obsidian,'Y')
        rod('Anchor shank',(0,-.67,.88),(0,-.67,1.89),.075,obsidian)
        ring('Anchor loop',(0,-.67,1.94),.12,.035,obsidian,'Y')
        rod('Anchor crossbar',(-.38,-.67,1.63),(.38,-.67,1.63),.06,obsidian)
        tube('Anchor hook',[(-.48,-.67,1.22),(-.30,-.67,.97),(0,-.67,.88),(.30,-.67,.97),(.48,-.67,1.22)],.06,obsidian)
        ring('Rope belt',(0,-.19,.73),.55,.06,rope,'Y')
    elif key=='armored':
        for y in [-.62,-.28,.06]:ell('Overlapping shell armor',(0,y,.97),(.64,.26,.26),green,8,4)
        for side in [-1,1]:box('Heavy flipper gauntlet',(side*.67,-.08,.63),(.39,.50,.18),gold)
        box('Helmet brow',(0,.69,1.17),(.57,.18,.13),gold)
    elif key=='volcano':
        cone('Volcano dorsal',(0,-.31,1.35),.39,.68,obsidian,.21,8)
        cone('Molten crater',(0,-.31,1.69),.21,.055,red,.21,8)
        for j in range(3):ell('Puffs of smoke',(j*.13,-.31,1.88+j*.19),(.15+j*.03,)*3,smoke,8,4)
        for side in [-1,1]:
            for j in range(3):box('Obsidian side armor',(side*.54,-.55+j*.31,.78),(.15,.26,.25),obsidian)
    elif key=='puffer':
        for i in range(12):
            a=i*math.tau/12;x=math.cos(a)*.57;z=.75+math.sin(a)*.34
            end=(math.cos(a)*.86,-.22,.75+math.sin(a)*.66)
            rod('Puffer spike',(x,-.22,z),end,.065,gold)
        for y in [-.55,.05]:
            for side in [-1,1]:cone('Vest spike',(side*.45,y,1.08),.085,.36,gold,0,5)
    elif key=='crown':
        ring('Royal crown rim',(0,.54,1.23),.34,.055,gold)
        for i in range(5):
            a=i*math.tau/5;cone('Royal crown point',(math.cos(a)*.29,.54+math.sin(a)*.29,1.43),.085,.38,gold,0,5)
        fin('Royal cape',[(0,-.20,1.18),(0,-1.48,1.09),(0,-1.61,.29),(0,-.73,.28)],.80,purple)
        for side in [-1,1]:rod('Cape trim',(side*.38,-.24,1.16),(side*.38,-1.57,.30),.025,gold)
    elif key=='pirate':
        cone('Pirate hat',(0,.55,1.29),.50,.20,black,.26,3)
        box('Eyepatch',(.32,.91,1.03),(.14,.04,.14),black)
        rod('Patch strap',(.32,.91,1.08),(-.30,.65,1.14),.025,black)
        tube('Hook flipper',[(-.57,-.01,.73),(-.88,-.13,.75),(-.97,-.30,.62),(-.83,-.39,.52),(-.74,-.29,.55)],.055,gold)
        box('Treasure chest',(0,-.63,1.16),(.67,.43,.37),rope)
        for side in [-1,1]:box('Chest brass band',(side*.20,-.63,1.16),(.05,.45,.39),gold)
    elif key=='kraken':
        ell('Octopus cloak head',(0,-.38,1.40),(.43,.43,.33),purple,10,6)
        for i in range(8):
            a=i*math.tau/8;points=[]
            for j in range(5):
                t=j/4;r=.24+t*.82;points.append((math.cos(a)*r,-.38+math.sin(a)*r,1.16-t*.81+.12*math.sin(t*math.pi*2)))
            tube('Octopus tentacle',points,.062,purple)
            for point in points[2:]:ell('Tentacle suction cup',(point[0],point[1],point[2]-.052),(.04,.04,.021),pink,6,3)
        box('Knight visor',(0,.92,1.05),(.47,.10,.13),gold)
    elif key=='clockwork':
        for side in [-1,1]:
            obj=cone('Cog flipper',(side*.62,-.08,.77),.32,.10,gold,.32,12);obj.rotation_euler.y=math.pi*.5
            for i in range(8):
                a=i*math.tau/8;box('Cog tooth',(side*.62,-.08+math.cos(a)*.33,.77+math.sin(a)*.33),(.12,.12,.12),gold)
            ring('Mechanical eye',(side*.30,.88,1.0),.09,.022,gold,'Y')
        rod('Wind-up stem',(0,-.53,1.07),(0,-.53,1.65),.06,obsidian)
        for side in [-1,1]:ring('Wind-up key',(side*.17,-.53,1.64),.16,.055,gold,'Y')
        ell('Clock dial',(.57,-.44,.92),(.04,.19,.19),cream,12,5)
        rod('Clock hand',(.62,-.44,.92),(.62,-.44,1.07),.018,black)
        rod('Clock hand',(.62,-.44,.92),(.62,-.33,.94),.018,black)

    # Normalize every authored model to 1.5m high; runtime role scaling matches collision.
    bpy.context.view_layer.update()
    coords=[obj.matrix_world@vertex.co for obj in parts for vertex in obj.data.vertices]
    minz=min(p.z for p in coords);maxz=max(p.z for p in coords);factor=1.5/(maxz-minz)
    for obj in parts:
        obj.location.z-=minz
        obj.location*=factor;obj.scale*=factor
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.export_scene.gltf(filepath=str(ROOT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT')
    collection=bpy.data.collections.new(label);bpy.context.scene.collection.children.link(collection)
    offset=Vector((-(idx%5)*3.4,-(idx//5)*5.9,0))
    for obj in parts:
        for old in list(obj.users_collection):old.objects.unlink(obj)
        collection.objects.link(obj);obj.location+=offset
    all_models.append({'id':key,'name':label,'archetype':role,'triangles':sum(len(p.data.loop_triangles) if p.data.loop_triangles else sum(len(poly.vertices)-2 for poly in p.data.polygons) for p in parts),'parts':len(parts)})
    # Name plaques belong only to the contact sheet scene, never exported GLBs.
    front=max(p.y for p in coords)*factor+offset.y
    bpy.ops.object.text_add(location=(offset.x,front+.35,.02))
    plaque=bpy.context.object;plaque.name='Label '+key;plaque.data.body=label.replace('THE ','')
    plaque.data.align_x='CENTER';plaque.data.size=.22;plaque.data.extrude=0
    plaque.rotation_euler.z=math.pi
    plaque.data.materials.append(cream)

bpy.context.scene.name='Twenty Whimsical Dolphin Enemies'
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'dolphin-roster.blend'))
(HERE/'dolphin-roster.json').write_text(json.dumps({'generator':'Blender 5.2 low-poly flat shading','normalized_height_m':1.5,'models':all_models},indent=2))
exec(compile((HERE/'render_dolphins.py').read_text(),str(HERE/'render_dolphins.py'),'exec'))
print('EXPORTED_DOLPHINS',len(all_models))
