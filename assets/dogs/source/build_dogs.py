"""Original flat-shaded dogs. Blender +Y forward exports to Godot -Z.
Run Blender --background --python assets/dogs/source/build_dogs.py.
Editable separate head and attachment anchors are retained in every export.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
HERE = Path(__file__).resolve().parent
OUT = HERE.parent
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.name = 'Unusual Dog Gun Breeds'
scene.render.engine = 'BLENDER_EEVEE'
scene.world.color = (.12,.15,.19)
scene.render.resolution_x = 1900
scene.render.resolution_y = 1450
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
materials,parts,models = {},[],[]
def mat(name,color):
    if name in materials:return materials[name]
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.86
    materials[name]=m;return m
INK=mat('Nose and pupils',(.025,.025,.038));CREAM=mat('Warm cream',(.91,.85,.69));WHITE=mat('Eye glints and ivory fur',(.96,.94,.85))
PINK=mat('Inner ears',(.62,.29,.35));MINT=mat('TypeCollar',(.26,.75,.55));METAL=mat('Collar brass',(.92,.65,.2))
def empty(name,loc=(0,0,0),parent=None):
    ob=bpy.data.objects.new(name,None);scene.collection.objects.link(ob);ob.location=loc
    bpy.context.view_layer.update()
    if parent:
        world=ob.matrix_world.copy();ob.parent=parent;ob.matrix_world=world
    return ob
def finish(ob,name,material,parent):
    ob.name=name;ob.data.materials.append(material)
    for face in ob.data.polygons:face.use_smooth=False
    bpy.context.view_layer.update();world=ob.matrix_world.copy();ob.parent=parent;ob.matrix_world=world
    parts.append(ob);return ob
def ellipsoid(name,center,size,material,parent,segments=10,rings=5):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=center)
    ob=bpy.context.object;ob.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(ob,name,material,parent)
def rod(name,a,b,radius,material,parent,radius_end=None,vertices=6):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if radius_end is None else radius_end,depth=(b-a).length,location=(a+b)/2)
    ob=bpy.context.object;ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return finish(ob,name,material,parent)
def tube(name,points,radius,material,parent):
    for i in range(len(points)-1):rod(name,points[i],points[i+1],radius,material,parent)
def lock(name,a,b,width,material,parent):rod(name,a,b,width,material,parent,width*.75,5)
def ear(name,x,y,z,width,height,material,parent,flop=False):
    if flop:
        ob=ellipsoid(name,(x,y,z-height*.25),(width,.075,height*.58),material,parent,8,4);ob.rotation_euler.y=-.15 if x>0 else .15;return ob
    verts=[(x-width,y-.05,z),(x+width,y-.05,z),(x,y-.005,z+height),(x-width,y+.04,z),(x+width,y+.04,z),(x,y+.055,z+height)]
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]);data.update()
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);return finish(ob,name,material,parent)
def dog(key,name,color,legs=.29,body_width=.24,body_length=.43,head_width=.18,head_height=.18,muzzle=.19,ears='up',ear_height=.22,features=()):
    global parts
    parts=[];root=empty(key);fur=mat(name+' coat',color);shade=mat(name+' coat shadows',tuple(c*.76 for c in color))
    body_z=legs+.19;head_y=.33;head_z=body_z+.27
    head=empty('HeadRoot',(0,head_y,head_z),root);bpy.context.view_layer.update()
    ellipsoid('Body',(0,-.02,body_z),(body_width,body_length,.25),fur,root)
    ellipsoid('Chest',(0,.27,body_z-.025),(body_width*.8,.18,.24),fur,root)
    for s in [-1,1]:
        for front in [-1,1]:
            y=.27 if front>0 else -.32;x=s*body_width*.7
            rod('FrontLeg' if front>0 else 'HindLeg',(x,y,.075),(x,y+(.035 if front>0 else -.015),legs+.12),.065 if legs<.4 else .044,fur,root)
            ellipsoid('Paw',(x,y+.035,.065),(.082,.11,.06),fur,root,8,4)
    ellipsoid('Head',(0,head_y,head_z),(head_width,.19,head_height),fur,head)
    nose_y=head_y+.12+muzzle
    ellipsoid('Muzzle',(0,head_y+.13+muzzle*.42,head_z-.045),(head_width*.65,muzzle*.67,.092),fur if 'hairless' in features else CREAM,head,10,4)
    ellipsoid('Nose',(0,nose_y,head_z-.01),(head_width*.34,.044,.043),INK,head,8,4)
    rod('Mouth',(-head_width*.38,nose_y-.012,head_z-.08),(head_width*.38,nose_y-.012,head_z-.08),.012,INK,head)
    for s in [-1,1]:
        eyex=s*head_width*.67;eyey=head_y+.145
        ellipsoid('Eye',(eyex,eyey,head_z+.05),(.038,.025,.043),INK,head,8,4)
        ellipsoid('EyeGlint',(eyex+.008,eyey+.021,head_z+.064),(.011,.008,.012),WHITE,head,6,3)
        ear('Ear',s*head_width*.78,head_y-.01,head_z+.09,.065,ear_height,fur,head,ears=='flop')
        if ears=='up':ear('InnerEar',s*head_width*.78,head_y+.055,head_z+.105,.033,ear_height*.65,PINK,head)
    ellipsoid('TypeCollar',(0,.26,body_z+.11),(body_width*.87,.145,.072),MINT,root,10,4)
    ellipsoid('Tag',(0,.412,body_z+.055),(.038,.012,.05),METAL,root,8,4)
    tail=[(0,-body_length*.85,body_z+.03),(0,-body_length-.20,body_z+.13),(0,-body_length-.30,body_z+.29)]
    if 'curl' in features:tail=[(0,-body_length,body_z+.04)]+[(0,-body_length-.13+.14*math.cos(i*.65),body_z+.25+.14*math.sin(i*.65)) for i in range(9)]
    if 'sighthound' in features:tail=[(0,-body_length,body_z+.08),(.025,-body_length-.22,body_z-.03),(.05,-body_length-.30,body_z-.22),(.05,-body_length-.40,body_z-.16)]
    tube('Tail',tail,.041 if body_width<.26 else .067,fur,root)
    if 'hairless' in features:
        for i in range(5):
            side=1 if i%2 else -1;ellipsoid('SkinSpot',(side*body_width*.89,-.28+i*.14,body_z+.035),(.014,.065,.075),shade,root,6,4)
    if 'crest' in features:
        for i in range(5):lock('HeadCrest',((i-2)*.045,head_y,head_z+.12),((i-2)*.064,head_y-.04,head_z+.35-abs(i-2)*.022),.037,WHITE,head)
        for ob in list(parts):
            if ob.name.startswith('Paw'):ellipsoid('FurrySock',ob.location+Vector((0,0,.06)),(.085,.10,.10),WHITE,root,8,4)
        ellipsoid('TailPlume',tail[-1],(.075,.08,.14),WHITE,root,8,4)
    if 'tuft' in features:
        for i in range(3):lock('ForeheadTuft',((i-1)*.04,head_y,head_z+.14),((i-1)*.04,head_y+.08,head_z+.28),.035,WHITE,head)
    if 'cords' in features or 'flocks' in features:
        for row in range(5):
            y=-.32+row*.16
            for s in [-1,1]:
                for k in range(3):
                    x=s*(body_width*.72+k*.029);a=(x,y,body_z+.18-k*.045);b=(x+s*.03,y+.035,.09+(k%2)*.07)
                    if 'flocks' in features:
                        ob=ellipsoid('FlatFlock',(Vector(a)+Vector(b))/2,(.065,.07,(Vector(b)-Vector(a)).length*.55),shade if (row+k)%3==0 else fur,root,6,4);ob.rotation_euler.y=s*.16
                    else:lock('CoatCord',a,b,.035,fur if k%2 else shade,root)
        for s in [-1,1]:
            for k in range(4):lock('HeadCord',(s*(.055+k*.034),head_y+.015,head_z+.14),(s*(.07+k*.044),head_y+.06,head_z-.27),.03,fur if k%2 else shade,head)
    if 'lamb' in features:
        ellipsoid('LambTopknot',(0,head_y+.12,head_z+.14),(.14,.23,.13),WHITE,head,10,5)
        for s in [-1,1]:ellipsoid('EarTassel',(s*head_width*.8,head_y,head_z-.12),(.07,.07,.10),WHITE,head,8,4)
        ellipsoid('ArchedBack',(0,-.06,body_z+.15),(.22,.33,.12),WHITE,root)
    if 'egg' in features:
        ellipsoid('EggProfile',(0,head_y+.13,head_z+.025),(head_width*.97,.28,.16),fur,head)
        ellipsoid('BlackEyePatch',(-head_width*.74,head_y+.13,head_z+.08),(.07,.047,.065),INK,head,8,4)
        ellipsoid('PatchEyeGlint',(-head_width*.78,head_y+.168,head_z+.10),(.01,.01,.012),WHITE,head,6,3)
    if 'wrinkles' in features:
        for j in range(4):
            z=head_z+.12-j*.065;tube('FaceFold',[(-head_width*.85,head_y+.08,z),(0,head_y+.198,z-.025),(head_width*.85,head_y+.08,z)],.022,shade,head)
        for j in range(4):
            y=-.22+j*.15;tube('ShoulderFold',[(-body_width*.84,y,body_z),(0,y,body_z+.235),(body_width*.84,y,body_z)],.02,shade,root)
    if 'jowls' in features:
        for s in [-1,1]:ellipsoid('DroopingJowl',(s*head_width*.47,nose_y-.05,head_z-.13),(.115,.095,.12),shade,head)
        ellipsoid('Dewlap',(0,.32,body_z-.06),(.16,.13,.20),shade,root)
    if 'beard' in features or 'monkey' in features:
        bc=shade if 'beard' in features else fur
        ellipsoid('Beard',(0,head_y+.13,head_z-.18),(head_width*.9,.11,.14),bc,head,8,4)
        for s in [-1,1]:
            for i in range(4):lock('CheekWhisker',(s*.1,head_y+.09,head_z-.04+i*.033),(s*(head_width+.10),head_y+.11,head_z-.1+i*.057),.025,bc,head)
            ellipsoid('ExpressiveBrow',(s*.11,head_y+.12,head_z+.11),(.077,.045,.035),bc,head,8,4)
    if 'longcoat' in features:
        for s in [-1,1]:
            for j in range(6):
                y=-.34+j*.13;lock('SilkySkirt',(s*body_width*.85,y,body_z+.13),(s*(body_width+.03),y+.03,.07),.064,fur if j%2 else shade,root)
            for j in range(4):lock('SilkyEar',(s*head_width*.92,head_y-.04+j*.037,head_z+.10),(s*(head_width+.085),head_y-.03+j*.037,head_z-.36),.048,fur if j%2 else shade,head)
        ellipsoid('SilkyTopknot',(0,head_y-.02,head_z+.16),(.19,.18,.09),fur,head)
    if 'feathers' in features:
        for s in [-1,1]:
            for j in range(3):lock('EarFeather',(s*head_width*.9,head_y-.02+j*.035,head_z+.04),(s*(head_width+.05),head_y-.04+j*.03,head_z-.25-j*.03),.025,shade,head)
        for j in range(3):lock('TailFeather',tail[j],Vector(tail[j])+Vector((.08,0,-.10)),.028,CREAM,root)
    if 'whitefeet' in features:
        for s in [-1,1]:ellipsoid('WhiteSock',(s*body_width*.7,.305,.09),(.067,.08,.11),WHITE,root,8,4)
        ellipsoid('ChestBlaze',(0,.398,body_z-.04),(.075,.018,.14),WHITE,root,8,4)
    if 'extra_toes' in features:
        for s in [-1,1]:
            for j in range(6):ellipsoid('LundehundToe',(s*body_width*.7+(j-2.5)*.024,.393-.035*abs(j-2.5),.041),(.021,.035,.025),WHITE,root,6,3)
        ellipsoid('WhiteBib',(0,.398,body_z-.02),(.085,.018,.13),WHITE,root,8,4)
    if 'shaggy' in features:
        for s in [-1,1]:
            for j in range(6):lock('ShaggySide',(s*body_width*.84,-.32+j*.14,body_z+.13),(s*(body_width+.06),-.30+j*.14,body_z-.18),.045,shade if j%2 else fur,root)
        ellipsoid('BigShaggyBeard',(0,head_y+.1,head_z-.2),(.20,.14,.17),shade,head,8,4)
        for s in [-1,1]:ellipsoid('ShaggyEyebrow',(s*.11,head_y+.12,head_z+.11),(.10,.05,.047),CREAM,head,8,4)
    if 'dandie' in features:
        ellipsoid('DandieTopknot',(0,head_y,head_z+.18),(.23,.19,.12),WHITE,head,10,5)
        ellipsoid('DandieMoustache',(0,head_y+.18,head_z-.08),(.21,.11,.08),CREAM,head,8,4)
    if 'griffin_vibe' in features:
        # Keep the rust Griffon's face and beard, with the requested portly
        # cartoon-sitcom silhouette, white shirt, green trousers and spectacles.
        green_pants=mat('Griffon forest-green trousers',(.15,.34,.16))
        ellipsoid('WhiteShirt',(0,-.005,body_z+.025),(body_width*1.11,body_length*.94,.27),WHITE,root)
        ellipsoid('GreenTrousers',(0,-.285,body_z-.06),(body_width*1.10,.235,.20),green_pants,root)
        for s in [-1,1]:
            rod('TrouserCuff',(s*body_width*.7,-.32,.08),(s*body_width*.7,-.32,.22),.077,green_pants,root)
            cx=s*.105
            points=[(cx+.068*math.cos(i*math.tau/12),head_y+.197,head_z+.057+.069*math.sin(i*math.tau/12)) for i in range(13)]
            tube('RoundSpectacleFrame',points,.008,INK,head)
            rod('ShirtCollar',(s*.06,.285,body_z+.225),(s*.105,.32,body_z+.12),.03,WHITE,root)
        rod('SpectacleBridge',(-.035,head_y+.197,head_z+.057),(.035,head_y+.197,head_z+.057),.008,INK,head)
        for z in [body_z,body_z+.10]:ellipsoid('ShirtButton',(0,.396,z),(.011,.008,.012),INK,root,6,3)
    if 'otter' in features:
        # The CSV deliberately changes this gun to a real otter. Remove the
        # canine ear/body/leg primitives, leaving its functional gun anchors.
        for ob in list(parts):
            if ob.parent==root or (ob.parent==head and not ob.name.startswith('Eye')):
                parts.remove(ob);bpy.data.objects.remove(ob,do_unlink=True)
        otter_fur=mat('Otter warm brown',(.31,.20,.13))
        otter_face=mat('Otter pale cheeks',(.63,.49,.32))
        body_z=.29;head_z=.62;head_y=.32;nose_y=.58
        head.location=(0,head_y,head_z)
        ellipsoid('OtterLongBody',(0,-.08,body_z),(.27,.53,.28),otter_fur,root,12,6)
        ellipsoid('OtterChest',(0,.28,.39),(.21,.20,.29),otter_fur,root)
        ellipsoid('OtterHead',(0,head_y,head_z),(.23,.20,.20),otter_fur,head,12,6)
        for s in [-1,1]:
            ellipsoid('OtterSmallRoundEar',(s*.20,.27,.74),(.055,.045,.064),otter_fur,head,8,4)
            ellipsoid('OtterCheek',(s*.095,.483,.58),(.105,.070,.074),otter_face,head,10,5)
            ellipsoid('OtterFrontWebbedPaw',(s*.23,.25,.065),(.11,.15,.057),otter_fur,root,8,4)
            ellipsoid('OtterRearWebbedPaw',(s*.24,-.35,.065),(.12,.17,.065),otter_fur,root,8,4)
            for j in range(3):
                tube('OtterWhisker',[(s*.085,.536,.58+j*.015),(s*.22,.57,.55+j*.031),(s*.32,.565,.55+j*.035)],.005,CREAM,head)
        ellipsoid('OtterNose',(0,.549,.63),(.065,.032,.04),INK,head,8,4)
        tail_points=[(0,-.44,.28),(0,-.72,.19),(.06,-.93,.13),(.12,-1.12,.095)]
        for i in range(3):rod('OtterThickTail',tail_points[i],tail_points[i+1],.14-i*.034,otter_fur,root,.10-i*.032,8)
        ellipsoid('TypeCollar',(0,.23,.485),(.205,.15,.055),MINT,root,10,4)
    bpy.context.view_layer.update()
    empty('MouthAnchor',(0,nose_y+.015,head_z-.07),head);empty('GlassesAnchor',(0,head_y+.165,head_z+.045),head);empty('CollarAnchor',(0,.26,body_z+.12),root)
    bpy.context.view_layer.update()
    triangles=sum(len(p.vertices)-2 for ob in parts for p in ob.data.polygons)
    # Export two combined mesh nodes with shared material surfaces. The source
    # blend keeps every primitive editable, but carried guns avoid dozens of
    # unnecessary scene nodes and repeated same-material draw calls.
    export_meshes=[]
    for parent,mesh_name in [(root,'BodyMesh'),(head,'HeadMesh')]:
        bpy.ops.object.select_all(action='DESELECT');copies=[]
        for original in parts:
            if original.parent==parent:
                duplicate=original.copy();duplicate.data=original.data.copy();scene.collection.objects.link(duplicate)
                duplicate.select_set(True);copies.append(duplicate)
        if copies:
            bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join()
            combined=bpy.context.object;combined.name=mesh_name;export_meshes.append(combined)
    bpy.ops.object.select_all(action='DESELECT')
    export_nodes=[root]+[ob for ob in root.children_recursive if ob.type=='EMPTY']+export_meshes
    for ob in export_nodes:ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    for ob in export_meshes:bpy.data.objects.remove(ob,do_unlink=True)
    # Free shared node names before constructing the next breed. Each GLB keeps
    # exact HeadRoot/MouthAnchor/GlassesAnchor/CollarAnchor names for attachments.
    for ob in root.children_recursive:ob.name=key+'__'+ob.name
    models.append((root,name,triangles));return root

dog('xoloitzcuintli','Xoloitzcuintli',(.22,.25,.29),legs=.35,body_width=.20,muzzle=.23,ear_height=.29,features=('hairless',))
dog('chinese_crested','Chinese Crested',(.77,.49,.47),legs=.32,body_width=.16,muzzle=.19,ear_height=.20,features=('hairless','crest'))
dog('peruvian_inca_orchid','Peruvian Inca Orchid',(.34,.27,.31),legs=.42,body_width=.18,muzzle=.25,ear_height=.23,features=('hairless','tuft','sighthound'))
dog('american_hairless_terrier','American Hairless Terrier',(.74,.60,.47),legs=.26,body_width=.21,muzzle=.16,ear_height=.21,features=('hairless',))
dog('komondor','Komondor',(.88,.84,.70),legs=.29,body_width=.30,body_length=.47,head_width=.23,muzzle=.17,ears='flop',features=('cords',))
dog('puli','Puli',(.13,.14,.16),legs=.18,body_width=.27,body_length=.35,head_width=.22,muzzle=.12,ears='flop',ear_height=.15,features=('cords','curl'))
dog('bergamasco_shepherd','Bergamasco Shepherd',(.46,.43,.40),legs=.29,body_width=.30,body_length=.47,head_width=.23,muzzle=.22,ears='flop',features=('flocks',))
dog('bedlington_terrier','Bedlington Terrier',(.73,.77,.80),legs=.34,body_width=.21,head_width=.15,head_height=.22,muzzle=.25,ears='flop',ear_height=.24,features=('lamb',))
dog('bull_terrier','Bull Terrier',(.95,.91,.79),legs=.25,body_width=.25,head_width=.18,head_height=.19,muzzle=.18,ear_height=.20,features=('egg',))
dog('neapolitan_mastiff','Neapolitan Mastiff',(.29,.34,.41),legs=.26,body_width=.33,body_length=.46,head_width=.27,head_height=.20,muzzle=.15,ears='flop',ear_height=.20,features=('wrinkles','jowls'))
dog('shar_pei','Shar-Pei',(.69,.43,.23),legs=.26,body_width=.26,head_width=.23,head_height=.19,muzzle=.17,ears='flop',ear_height=.11,features=('wrinkles','curl'))
dog('brussels_griffon','Brussels Griffon',(.57,.27,.14),legs=.20,body_width=.23,body_length=.33,head_width=.21,head_height=.21,muzzle=.06,ear_height=.12,features=('beard','griffin_vibe'))
dog('affenpinscher','Affenpinscher',(.19,.19,.21),legs=.19,body_width=.20,body_length=.32,head_width=.20,head_height=.21,muzzle=.07,ear_height=.12,features=('monkey',))
dog('borzoi','Borzoi',(.91,.87,.75),legs=.46,body_width=.19,body_length=.48,head_width=.13,head_height=.16,muzzle=.40,ears='flop',ear_height=.09,features=('sighthound','feathers'))
dog('afghan_hound','Afghan Hound',(.76,.54,.30),legs=.40,body_width=.22,body_length=.45,head_width=.17,head_height=.17,muzzle=.30,ears='flop',ear_height=.30,features=('sighthound','longcoat'))
dog('saluki','Saluki',(.77,.64,.44),legs=.46,body_width=.17,body_length=.47,head_width=.13,head_height=.16,muzzle=.31,ears='flop',ear_height=.22,features=('sighthound','feathers'))
dog('azawakh','Azawakh',(.53,.26,.13),legs=.52,body_width=.15,body_length=.45,head_width=.13,head_height=.15,muzzle=.27,ears='flop',ear_height=.15,features=('sighthound','whitefeet'))
dog('norwegian_lundehund','Norwegian Lundehund',(.74,.43,.20),legs=.24,body_width=.21,body_length=.35,head_width=.16,muzzle=.17,ear_height=.18,features=('extra_toes','curl'))
dog('otterhound','Otterhound',(.59,.43,.27),legs=.32,body_width=.28,body_length=.47,head_width=.23,head_height=.20,muzzle=.25,ears='flop',ear_height=.28,features=('otter',))
dog('dandie_dinmont_terrier','Dandie Dinmont Terrier',(.39,.41,.44),legs=.12,body_width=.23,body_length=.51,head_width=.21,head_height=.18,muzzle=.18,ears='flop',ear_height=.19,features=('dandie',))

for i,(root,name,tris) in enumerate(models):
    root.location=((i%5)*2.6,(i//5)*2.4,0)
    bpy.ops.object.text_add(location=root.location+Vector((0,.98,.02)))
    label=bpy.context.object;label.name=name+' label'
    label.data.body=name
    label.data.size=.115 if len(name)>19 else .14
    label.data.align_x='CENTER';label.data.materials.append(INK);label.rotation_euler=(math.pi/2,0,math.pi)
floor=mat('Warm studio floor',(.66,.70,.73));bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012));bpy.context.object.data.materials.append(floor)
target=Vector((5.2,3.8,.30))
for pos,power,size in [((0,1,12),2100,9),((11,8,10),1600,8)]:
    bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(10.2,17.5,13.8));cam=bpy.context.object;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=16.7;scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'unusual-dog-guns.blend'))
scene.render.filepath=str(HERE/'dog-breeds-preview.png');bpy.ops.render.render(write_still=True)
(HERE/'models.json').write_text(json.dumps({'style':'Original flat-shaded breed models','forward':'Godot -Z','assets':[{'id':root.name,'name':name,'triangles':tris} for root,name,tris in models]},indent=2))
print('Exported all20 breed GLBs, editable blend and contact sheet.')
