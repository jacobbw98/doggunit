"""Updated low-poly items from Jacob's October catalog. Run with Blender --background."""
from pathlib import Path
import math, shutil, json
HERE=Path(__file__).resolve().parent
helper=(HERE/'build_items.py').read_text(encoding='utf8').split('# Crunchy bone biscuit')[0]
helper=helper.replace('Items_Katamari_Review','Catalog_October_Update')
exec(compile(helper,str(HERE/'build_items.py'),'exec'))
backup=HERE/'catalog_previous_models'
backup.mkdir(exist_ok=True)
for key in ['biscuit','zoomies','squeaker','cone','kibble','tag','howl_horn','med_bowl','magnet','leash']:
    path=ROOT/(key+'.glb')
    if path.exists() and not (backup/path.name).exists():shutil.copy2(path,backup/path.name)

chocolate=mat('dark chocolate cookie',(.095,.035,.018))
choco_light=mat('chocolate highlights',(.24,.09,.035))
cactus=mat('cactus green',(.16,.51,.23))
pink=mat('anime blush',(.97,.32,.44))

begin()
cylinder('Cookie bottom',(0,0,.075),.31,.11,chocolate,vertices=16)
cylinder('Vanilla filling',(0,0,.145),.28,.055,cream,vertices=16)
cylinder('Cookie top',(0,0,.205),.31,.09,chocolate,vertices=16)
ellipsoid('Paw pad',(0,-.055,.262),(.075,.065,.012),choco_light,8,4)
for x,y in [(-.085,.02),(-.035,.075),(.035,.075),(.085,.02)]:
    ellipsoid('Paw toe',(x,y,.262),(.027,.034,.01),choco_light,8,4)
for i in range(16):
    a=i*math.tau/16
    rod('Cookie crimp',(.275*math.cos(a),.275*math.sin(a),.255),(.30*math.cos(a),.30*math.sin(a),.255),.012,choco_light)
complete('biscuit',.26)

begin()
outline=[(-.03,.72),(.25,.72),(.045,.43),(.22,.43),(-.22,0),(-.07,.33),(-.25,.33)]
extrude('Lightning bolt',outline,.06,.12,gold)
complete('zoomies',.72)

begin()
ellipsoid('Chocolate duck body',(0,0,.20),(.25,.30,.20),chocolate)
ellipsoid('Chocolate duck head',(0,.15,.42),(.15,.15,.16),choco_light)
ellipsoid('Chocolate duck beak',(0,.31,.40),(.105,.11,.04),brown)
for s in [-1,1]:
    ellipsoid('Chocolate wing',(s*.21,-.01,.23),(.05,.15,.09),choco_light)
    ellipsoid('Candy eye',(s*.09,.27,.46),(.035,.012,.039),cream,8,4)
    ellipsoid('Eye pupil',(s*.09,.282,.46),(.015,.006,.021),black,8,4)
complete('squeaker',.55)

begin()
box('Street cone base',(0,0,.04),(.62,.62,.08),orange,.03)
cylinder('Street cone',(0,0,.38),.25,.64,orange,radius_top=.025,vertices=12)
cylinder('White cone band',(0,0,.34),.17,.09,white,radius_top=.14,vertices=12)
for s in [-1,1]:
    ellipsoid('Anime eye',(s*.07,.155,.39),(.035,.018,.058),plum,8,4)
    ellipsoid('Eye sparkle',(s*.063,.175,.415),(.012,.008,.017),white,6,3)
    ellipsoid('Blush',(s*.10,.176,.30),(.036,.012,.015),pink,8,3)
tube('Cute mouth',[(-.025,.19,.30),(0,.197,.284),(.025,.19,.30)],.009,plum)
complete('cone',.70)

def flagellum(name,angle=0,elevation=0):
    points=[]
    for i in range(12):
        t=i/11
        p=Vector((.075*math.sin(t*math.tau*1.3)*t,.075*math.cos(t*math.tau*1.3)*t,.15+t*.55))
        p.rotate(__import__('mathutils').Euler((elevation,angle,0)))
        points.append(p)
    tube(name,points,.023,mint_light,sides=6,radii=[.025*(1-i/15) for i in range(12)])
begin();flagellum('Single animated flagellum');complete('flagellum',.65)
begin()
ellipsoid('Flagella core',(0,0,.70),(.11,.11,.11),mint)
for i in range(12):
    angle=i*math.tau/12
    points=[]
    outward=Vector((math.cos(angle)*math.sin(.6+i%3),math.sin(angle)*math.sin(.6+i%3),math.cos(.6+i%3)))
    sideways=outward.cross(Vector((0,1,0))).normalized()
    for j in range(10):
        t=j/9
        points.append(Vector((0,0,.70))+outward*(.08+t*.55)+sideways*(math.sin(t*math.tau+i)*.10*t))
    tube('Wiggly strand',points,.022,mint_light,sides=6)
complete('flagella',1.2)

begin()
ellipsoid('Cute tick body',(0,0,.24),(.19,.26,.22),red)
ellipsoid('Tick face',(0,.21,.25),(.15,.13,.14),purple)
for s in [-1,1]:
    for i in range(4):
        y=-.18+i*.105
        tube('Tick leg',[(s*.13,y,.23),(s*.29,y-.04,.17),(s*.32,y+.04,.03)],.019,plum,sides=5)
    ellipsoid('Tick friendly eye',(s*.058,.326,.30),(.032,.012,.04),white,8,4)
    ellipsoid('Tick pupil',(s*.055,.338,.30),(.014,.006,.023),black,8,3)
complete('kibble',.46)

begin()
for s in [-1,1]:
    loop('Glasses frame',(s*.15,.08,.13),.12,plum,.025,segments=12,plane='XZ')
    rod('Glasses arm',(s*.26,.08,.13),(s*.26,-.22,.13),.018,plum)
rod('Glasses bridge',(-.045,.08,.13),(.045,.08,.13),.021,plum)
complete('tag',.26)

begin()
cylinder('Air horn can',(0,0,.22),.12,.44,red,vertices=12)
box('Air horn label',(0,.121,.23),(.13,.018,.18),white,.01)
rod('Horn stem',(0,0,.45),(0,.15,.45),.04,gold)
horn=cylinder('Air horn bell',(0,.27,.45),.045,.28,gold,radius_top=.16,vertices=12)
horn.rotation_euler.x=-math.pi/2
complete('howl_horn',.61)

begin()
box('First aid case',(0,0,.24),(.60,.21,.43),red,.04)
box('Medical cross horizontal',(0,.12,.26),(.27,.02,.065),white)
box('Medical cross vertical',(0,.12,.26),(.065,.022,.27),white)
tube('First aid handle',[(-.11,0,.44),(-.11,0,.55),(.11,0,.55),(.11,0,.44)],.025,cream,sides=6)
for s in [-1,1]:box('Case clasp',(s*.18,.12,.43),(.04,.025,.06),gold)
complete('med_bowl',.56)

begin()
rod('Cactus femur shaft',(0,0,.17),(0,0,.73),.12,cactus,vertices=10)
for z in [.14,.76]:
    for s in [-1,1]:ellipsoid('Cactus femur knuckle',(s*.10,0,z),(.14,.13,.13),cactus,10,4)
for i in range(18):
    a=i*2.399;z=.22+(i%6)*.085
    p=Vector((.105*math.cos(a),.105*math.sin(a),z))
    rod('Cactus spine',p,p+Vector((.13*math.cos(a),.13*math.sin(a),.04)),.018,cream,end_radius=0,vertices=5)
complete('magnet',.9)

begin()
points=[(.18*math.sin(i*.30),.03*math.cos(i*.4),.12+i*.017) for i in range(25)]
tube('Braided leash',points,.038,blue,sides=6)
loop('Leash handle',(0,0,.70),.14,mint,.038,plane='XZ')
loop('Brass leash clasp',(0,0,.07),.05,gold,.018,plane='XZ')
complete('leash',.85)

for i,(key,obj) in enumerate(assets.items()):
    obj.hide_set(False);obj.hide_render=False
    obj.location=((i%4)*1.65,(i//4)*1.65,0)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'catalog-update.blend'))
# Contact sheet for model review. Reuses the original author's light helper style.
floor=box('Review floor',(2.45,1.7,-.08),(8,7,.12),floor_mat)
for pos,power,size in [((-3,-3,7),1100,5),((7,4,6),900,4)]:
    bpy.ops.object.light_add(type='AREA',location=pos)
    light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((2.4,1.7,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(5,9,8))
cam=bpy.context.object;cam.rotation_euler=(Vector((2.4,1.7,.25))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO';cam.data.ortho_scale=8.8;scene.camera=cam
scene.render.resolution_x=1200;scene.render.resolution_y=1000
scene.render.filepath=str(HERE/'catalog-models.png')
bpy.ops.render.render(write_still=True)
(HERE/'catalog-models.json').write_text(json.dumps({'source':'data/items.csv','assets':list(assets),'style':'Original low-poly cartoon models','authoring_script':'catalog_models.py'},indent=2))
