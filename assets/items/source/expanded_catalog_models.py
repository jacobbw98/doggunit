"""Author the eight new October item models, retaining established flat shading.
Run with Blender --background --python assets/items/source/expanded_catalog_models.py.
"""
from pathlib import Path
import math, json
HERE=Path(__file__).resolve().parent
helper=(HERE/'build_items.py').read_text(encoding='utf8').split('# Crunchy bone biscuit')[0]
helper=helper.replace('Items_Katamari_Review','Expanded_Item_Catalog')
exec(compile(helper,str(HERE/'build_items.py'),'exec'))
scene.view_settings.exposure=-.45
silver=mat('bent spoon brushed silver',(.60,.66,.72),.65)
silver_shadow=mat('bent spoon inset',(.27,.34,.40),.45)
rubber=mat('rubber chicken yellow',(.98,.71,.075))
rubber_red=mat('rubber chicken comb',(.84,.10,.14))
flesh=mat('toy flesh cube',(.75,.30,.32))
flesh_light=mat('toy flesh highlights',(.94,.53,.50))
flesh_dark=mat('toy flesh veins',(.49,.12,.24))
tofu=mat('soft tofu',(.89,.86,.75))
tofu_pore=mat('tofu pores',(.59,.58,.47))
fungus_red=mat('amanita cap vermilion',(.85,.075,.055))
fungus_brown=mat('wavy mushroom caramel',(.58,.30,.10))
fungus_rim=mat('wavy cap tan rim',(.77,.50,.24))
fungus_dark=mat('wavy cap umbo',(.35,.17,.055))
laser_body=mat('laser pointer graphite',(.10,.15,.19),.2)
laser_red=mat('laser diode glow',(.96,.035,.07))
laser_lens=mat('laser lens',(.95,.43,.32))

begin()
for i in range(8):
    a=i*math.tau/8
    first=len(parts)
    bone('Swarming bone',white if i%2 else cream,.34,.036,.10)
    for ob in parts[first:]:
        ob.rotation_euler.z=a+.55
        ob.location.x+=.34*math.cos(a)
        ob.location.y+=.34*math.sin(a)
        ob.location.z+=.27+.12*math.sin(a*2)
for i in range(12):
    a=i*math.tau/12
    ellipsoid('Swarm motion mote',(.25*math.cos(a),.25*math.sin(a),.25+i%3*.04),(.02,.02,.02),mint_light,6,3)
complete('boneswarm',.52)

begin()
ellipsoid('Rubber chicken belly',(0,0,.28),(.18,.15,.27),rubber)
rod('Rubber chicken long neck',(0,.015,.38),(0,.035,.78),.064,rubber,vertices=8)
ellipsoid('Rubber chicken head',(0,.05,.82),(.105,.09,.10),rubber)
ellipsoid('Chicken red beak',(0,.157,.80),(.065,.085,.030),orange,8,4)
for s in [-1,1]:
    ellipsoid('Chicken wing',(s*.155,0,.28),(.036,.095,.13),rubber,8,4)
    ellipsoid('Chicken eye',(s*.053,.128,.86),(.019,.01,.026),black,8,4)
    rod('Chicken foot', (s*.09,0,.04),(s*.09,.11,.02),.027,orange,vertices=6)
    rod('Chicken toes',(s*.12,.1,.02),(s*.05,.1,.02),.018,orange,vertices=6)
for i in range(3):ellipsoid('Chicken comb',((i-1)*.04,.035,.93),(.026,.044,.05),rubber_red,8,4)
ellipsoid('Chicken wattle',(0,.10,.725),(.033,.018,.052),rubber_red,8,4)
complete('bounce',.98)

begin()
tube('Spoon bent handle',[(0,0,.025),(.04,-.02,.19),(-.065,.015,.35),(-.02,.025,.49),(0,.01,.56)],.026,silver,sides=8)
ellipsoid('Spoon bowl',(0,.035,.665),(.135,.037,.17),silver,12,5)
ellipsoid('Spoon inset',(0,.071,.671),(.105,.009,.13),silver_shadow,10,5)
complete('homing',.84)

begin()
box('Flesh cube',(0,0,.25),(.5,.46,.46),flesh,.07)
for center,size in [((-.10,.235,.31),(.17,.018,.06)),((.11,.237,.17),(.10,.016,.09)),((.08,-.02,.494),(.20,.12,.01))]:
    ellipsoid('Soft pale fat patch',center,size,flesh_light,8,4)
tube('Flesh vein',[(-.17,.242,.12),(-.09,.243,.18),(-.13,.244,.25),(-.04,.244,.33),(.035,.244,.38)],.011,flesh_dark,sides=5)
tube('Flesh vein branch',[(-.09,.243,.18),(.01,.245,.24),(.10,.242,.23)],.008,flesh_dark,sides=5)
complete('flesh',.5)

begin()
box('Tofu block',(0,0,.24),(.53,.46,.46),tofu,.025)
for i in range(11):
    x=-.2+(i%4)*.125;z=.08+(i//4)*.13
    ellipsoid('Tofu pore',(x,.238,z),(.011+(i%3)*.004,.004,.008+(i%2)*.005),tofu_pore,6,3)
ellipsoid('Tofu leaf',(0,-.02,.488),(.11,.04,.014),mint,8,4)
rod('Leaf stem',(-.08,-.03,.493),(.09,.02,.493),.006,mint_light,vertices=5)
complete('tofu',.5)

begin()
rod('Amanita stem',(0,0,.04),(.01,0,.49),.075,cream,end_radius=.060,vertices=10)
ellipsoid('Amanita volva',(0,0,.09),(.11,.10,.095),white,10,5)
ring_profile('Amanita skirt',[(.26,.057),(.25,.13),(.22,.14),(.235,.06)],white,segments=12)
ring_profile('Amanita red cap',[(.73,.003),(.70,.14),(.62,.26),(.53,.35),(.47,.39)],fungus_red,segments=16)
ellipsoid('Amanita underside',(0,0,.469),(.375,.375,.018),cream,16,4)
for i in range(13):
    a=i*2.399;r=.08+(i%4)*.073
    cap_profile=[(0,.73),(.14,.70),(.26,.62),(.35,.53),(.39,.47)]
    z=.73
    for (r0,z0),(r1,z1) in zip(cap_profile,cap_profile[1:]):
        if r0<=r<=r1:
            z=z0+(z1-z0)*(r-r0)/(r1-r0)+.015
            break
    ellipsoid('Amanita ivory wart',(r*math.cos(a),r*math.sin(a),z),(.028+(i%3)*.01,.027,.016),white,8,4)
complete('aminita',.74)

begin()
tube('Curved mushroom stem',[(0,0,.02),(-.055,.01,.16),(-.025,.02,.34),(0,0,.46)],.045,cream,sides=8)
segments=20;profiles=[(.64,.002),(.61,.08),(.57,.18),(.50,.30),(.47,.35)]
verts=[];faces=[]
for row,(z,r) in enumerate(profiles):
    for i in range(segments):
        a=i*math.tau/segments
        waviness=.036*math.cos(4*a+.3)*(r/.35)**2
        verts.append((r*math.cos(a),r*math.sin(a),z+waviness))
for row in range(len(profiles)-1):
    for i in range(segments):
        a=row*segments+i;b=row*segments+(i+1)%segments;faces.append((a,b,b+segments,a+segments))
faces.append(tuple(range(segments-1,-1,-1)))
mesh('Wavy caramel cap',verts,faces,fungus_brown)
ellipsoid('Cap dark umbo',(0,0,.625),(.078,.078,.029),fungus_dark,10,4)
for i in range(20):
    a=i*math.tau/20
    tube('Cap gill',[(.04*math.cos(a),.04*math.sin(a),.463),(.22*math.cos(a),.22*math.sin(a),.469),(.34*math.cos(a),.34*math.sin(a),.47+.034*math.cos(4*a+.3))],.007,fungus_rim,sides=5)
complete('cubensis',.67)

begin()
rod('Laser pointer graphite body',(0,0,.04),(0,0,.46),.065,laser_body,vertices=10)
cylinder('Pointer brass clip collar',(0,0,.37),.069,.032,gold,vertices=10)
rod('Pointer side clip',(.066,0,.15),(.066,0,.34),.012,silver,vertices=6)
cylinder('Laser diode housing',(0,0,.475),.070,.035,laser_red,vertices=10)
cylinder('Laser lens',(0,0,.496),.040,.009,laser_lens,vertices=10)
ellipsoid('Laser button',(0,.064,.31),(.026,.009,.042),laser_red,8,4)
complete('lazer',.51)

for i,(key,obj) in enumerate(assets.items()):
    obj.hide_set(False);obj.hide_render=False;obj.location=((i%4)*1.35,(i//4)*1.6,0)
    bpy.ops.object.text_add(location=obj.location+Vector((0,.62,.035)))
    label=bpy.context.object;label.data.body=key;label.data.size=.13;label.data.align_x='CENTER';label.rotation_euler=(math.pi/2,0,math.pi);label.data.materials.append(cream)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'expanded-catalog.blend'))
floor=box('Expanded item review floor',(2,1,-.06),(7,5,.10),floor_mat)
target=Vector((2.0,.85,.25))
for pos,power,size in [((-2,1,6),1000,5),((5,6,5),700,4)]:
    bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.size=size;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(5,8,7));cam=bpy.context.object;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=6.5;scene.camera=cam
scene.render.resolution_x=1500;scene.render.resolution_y=1100;scene.render.filepath=str(HERE/'expanded-items-preview.png');bpy.ops.render.render(write_still=True)
(HERE/'expanded-items-models.json').write_text(json.dumps({'source':'data/items.csv','assets':list(assets),'style':'Original flat-shaded toy models'},indent=2))
