"""Synchronize user-authored CSV metadata into native game catalogs.

Only replaces the permanent item / starter / breed catalog blocks. Runtime
methods and consumables are deliberately preserved for their owning systems.
"""
import csv, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]

def read_catalog(name):
    with (ROOT/'data'/name).open(encoding='utf-8-sig',newline='') as handle:
        return list(csv.DictReader(handle))

def numeric(record,column,fallback=None):
    value=record.get(column,'')
    return float(value) if value.strip() else fallback

def common(record):
    return {'id':record['item_id'],'name':record['item_name'],
        'description':record['what_it_does'],'flavor_text':record['flavor_text'],
        'model_description':record['model_description'],'notes':record['notes']}

def serialize(values):
    lines=[]
    for value in values:
        text=json.dumps(value,ensure_ascii=False)
        text=re.sub(r'"(Category\.[A-Z_]+)"',r'\1',text)
        lines.append('\t'+text+',')
    return '[\n'+'\n'.join(lines)+'\n]'

def replace_block(path,name,values):
    text=path.read_text(encoding='utf-8-sig')
    pattern=r'const '+name+r': Array\[Dictionary\] = \[.*?\n\]'
    replacement='const '+name+': Array[Dictionary] = '+serialize(values)
    result,count=re.subn(pattern,lambda match:replacement,text,count=1,flags=re.S)
    assert count==1,(path,name)
    path.write_text(result,encoding='utf-8')

items=[]
categories={'global_passive':'Category.GLOBAL_PASSIVE','dog_inclusive':'Category.DOG_INCLUSIVE','active':'Category.ACTIVE'}
effects={'howl_horn':'howl','med_bowl':'heal','leash':'walkies','boneswarm':'boneswarm','bounce':'bounce','homing':'homing','lazer':'hitscan'}
stack_steps={'bounce':1.0,'flesh':.1,'tofu':10.0}
for record in read_catalog('items.csv'):
    item=common(record)
    item.update(category=categories[record['category']],kind=record['kind'],rarity=record['rarity'],shop_price=int(numeric(record,'shop_price_bones',15)))
    if record['stat']:item['stat']=record['stat']
    effect=effects.get(record['item_id'],record['effect'])
    if effect:item['effect']=effect
    for column,target in [('amount','amount'),('multiplier','multiplier'),('damage','damage'),('radius','radius'),('duration_seconds','duration'),('cooldown_seconds','cooldown'),('cooldown_rooms','cooldown_rooms'),('stun_seconds','stun_duration')]:
        value=numeric(record,column)
        if value is not None:item[target]=value
    if record['item_id'] in stack_steps:item['stack_increment']=stack_steps[record['item_id']]
    items.append(item)
dogs=read_catalog('dogs_guns.csv')
starters=[];breeds=[]
for record in dogs:
    dog=common(record)
    dog.update(effect=record['effect'],damage=numeric(record,'damage'),fire_rate=numeric(record,'shot_interval_seconds'),projectile_speed=numeric(record,'projectile_speed'),max_ammo=int(numeric(record,'magazine_capacity')),rarity=record['rarity'])
    if record.get('reload_seconds','').strip():dog['reload_seconds']=numeric(record,'reload_seconds')
    (starters if record['category']=='starter_weapon' else breeds).append(dog)
assert len(items)==22 and len(starters)==3 and len(breeds)==20
replace_block(ROOT/'scripts/game/pet_items.gd','STARTER_DOGS',starters)
replace_block(ROOT/'scripts/game/pet_items.gd','CATALOG',items)
replace_block(ROOT/'scripts/weapons/dog_breeds.gd','CATALOG',breeds)
print('Synchronized 22 items, 3 starters and 20 breed metadata records.')
