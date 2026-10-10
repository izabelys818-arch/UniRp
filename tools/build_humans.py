"""Bake MakeHuman CC0 anatomy and fitted assets to game-ready glTF.

Usage: python tools/build_humans.py <MakeHuman source directory>
Source directory contains 3dobjs, rigs, targets and system/base (asset pack).
No Blender or runtime Python dependency. Generated assets keep the game's bone
names so the existing UAL animation retargeter and character API are reusable.
"""
from pathlib import Path
import sys, json, re, shutil
import numpy as np
from PIL import Image

SOURCE = Path(sys.argv[1])
DEST = Path(__file__).resolve().parents[1] / 'assets/humans'
DEST.mkdir(parents=True, exist_ok=True)
SYSTEM = SOURCE / 'system/base'

def obj(path):
    vertices, uv, faces = [], [], []
    group = 'body'
    for line in path.read_text().splitlines():
        t = line.split()
        if not t: continue
        if t[0] == 'v': vertices.append(list(map(float, t[1:4])))
        elif t[0] == 'vt': uv.append(list(map(float, t[1:3])))
        elif t[0] == 'g': group = t[1]
        elif t[0] == 'f':
            corners = [tuple(int(x)-1 if x else -1 for x in s.split('/')[:2]) for s in t[1:]]
            faces.append((group, corners))
    return np.array(vertices), np.array(uv), faces

BASE, UV, FACES = obj(SOURCE/'3dobjs/base.obj')
RIG = json.loads((SOURCE/'rigs/default.mhskel').read_text())
WEIGHTS = json.loads((SOURCE/'rigs/default_weights.mhw').read_text())['weights']
BODY_IDS = sorted({c[0] for g, f in FACES if g == 'body' for c in f})

def target(path):
    out = np.zeros_like(BASE)
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith('#'): continue
        t = line.split()
        out[int(t[0])] = list(map(float, t[1:4]))
    return out

def covered_vertices(path):
    text=path.read_text()
    if 'delete_verts' not in text:return set()
    tokens=text.split('delete_verts',1)[1].split();out=set();i=0
    while i<len(tokens):
        if not tokens[i].isdigit():break
        start=int(tokens[i]);i+=1
        if i<len(tokens) and tokens[i]=='-':
            out.update(range(start,int(tokens[i+1])+1));i+=2
        else:out.add(start)
    return out

# Merge twist bones into the appropriate deform segment. Facial weights are
# merged into Head: facial expressions are separate compact blend shapes.
ALIASES = {'root':'pelvis','spine05':'spine_01','spine04':'spine_01',
           'spine03':'spine_02','spine02':'spine_02','spine01':'spine_03',
           'neck01':'neck_01','neck02':'neck_01','neck03':'neck_01','head':'Head'}
for side in ['L','R']:
    sl=side.lower()
    for old,new in [('clavicle','clavicle'),('shoulder01','clavicle'),
                    ('upperarm01','upperarm'),('upperarm02','upperarm'),
                    ('lowerarm01','lowerarm'),('lowerarm02','lowerarm'),
                    ('wrist','hand'),('upperleg01','thigh'),('upperleg02','thigh'),
                    ('lowerleg01','calf'),('lowerleg02','calf'),('foot','foot')]:
        ALIASES[old+'.'+side]=new+'_'+sl
    ALIASES['pelvis.'+side]='pelvis'
    ALIASES['breast.'+side]='spine_02'
    for digit,finger in enumerate(['thumb','index','middle','ring','pinky'],1):
        for n in range(1,4): ALIASES[f'finger{digit}-{n}.{side}']=f'{finger}_{n:02d}_{sl}'
    for n in range(1,5): ALIASES[f'metacarpal{n}.{side}']='hand_'+sl
    for old in RIG['bones']:
        if old.startswith('toe') and old.endswith('.'+side): ALIASES[old]='ball_'+sl
for old in RIG['bones']:
    if old not in ALIASES: ALIASES[old]='Head'

def skeleton(verts):
    point=lambda name: verts[RIG['joints'][name]].mean(axis=0)
    nodes=[{'name':'Human','children':[1]}, {'name':'Armature','children':[2]}, {'name':'root','translation':[0,0,0],'children':[]}]
    names=['root']; positions=[np.zeros(3)]; parents=[-1]
    def add(name,old,parent):
        names.append(name);positions.append(point(RIG['bones'][old]['head']));parents.append(names.index(parent))
    add('pelvis','root','root');add('spine_01','spine05','pelvis')
    add('spine_02','spine03','spine_01');add('spine_03','spine01','spine_02')
    add('neck_01','neck01','spine_03');add('Head','head','neck_01')
    for side in ['L','R']:
        sl=side.lower()
        for name,old,par in [('clavicle','clavicle','spine_03'),('upperarm','upperarm01','clavicle_'+sl),
                             ('lowerarm','lowerarm01','upperarm_'+sl),('hand','wrist','lowerarm_'+sl),
                             ('thigh','upperleg01','pelvis'),('calf','lowerleg01','thigh_'+sl),
                             ('foot','foot','calf_'+sl),('ball','toe2-1','foot_'+sl)]:
            add(name+'_'+sl,old+'.'+side,par)
        for digit,finger in enumerate(['thumb','index','middle','ring','pinky'],1):
            for n in range(1,4):
                add(f'{finger}_{n:02d}_{sl}',f'finger{digit}-{n}.{side}','hand_'+sl if n==1 else f'{finger}_{n-1:02d}_{sl}')
    for i in range(1,len(names)):
        nodes.append({'name':names[i],'translation':(positions[i]-positions[parents[i]]).tolist(),'children':[]})
        nodes[parents[i]+2]['children'].append(i+2)
    dense=np.zeros((len(BASE),len(names)))
    for old,pairs in WEIGHTS.items():
        joint=names.index(ALIASES.get(old,'Head'))
        for v,w in pairs: dense[v,joint]+=w
    missing=dense.sum(axis=1)==0
    # Garment proxies mostly reference helper vertices. Transfer anatomy weights
    # to those helpers before fitting; anchoring them to pelvis tears sleeves.
    source_ids=np.array([i for i in BODY_IDS if not missing[i]])
    for first in range(0,len(BASE),128):
        ids=np.arange(first,min(first+128,len(BASE)))
        ids=ids[missing[ids]]
        if not len(ids):continue
        delta=verts[ids,None,:]-verts[source_ids][None,:,:]
        distances=np.einsum('ijk,ijk->ij',delta,delta)
        nearest=np.argpartition(distances,3,axis=1)[:,:4]
        w=1/np.maximum(np.take_along_axis(distances,nearest,axis=1),1e-8)
        w/=w.sum(axis=1)[:,None]
        dense[ids]=(dense[source_ids[nearest]]*w[:,:,None]).sum(axis=1)
    dense/=dense.sum(axis=1)[:,None]
    return nodes,names,np.array(positions),dense

def rotation_between(a,b):
    a=a/np.linalg.norm(a);b=b/np.linalg.norm(b);axis=np.cross(a,b);c=np.dot(a,b)
    k=np.array([[0,-axis[2],axis[1]],[axis[2],0,-axis[0]],[-axis[1],axis[0],0]])
    return np.eye(3)+k+k@k/max(1+c,1e-8)

def pose_for_animation(names,positions,nodes):
    # UAL and the previous compatible rig use a T rest pose. Anatomical hm08
    # uses a bent A pose. Bake only the rest-pose alignment, keeping its anatomy.
    old_path=Path(__file__).resolve().parents[1]/'assets/chars/body/Superhero_Male_FullBody.gltf'
    old=json.loads(old_path.read_text());skin=old['skins'][0]
    acc=old['accessors'][skin['inverseBindMatrices']];view=old['bufferViews'][acc['bufferView']]
    buf=(old_path.parent/old['buffers'][0]['uri']).read_bytes()
    ib=np.frombuffer(buf,dtype='<f4',count=acc['count']*16,offset=view.get('byteOffset',0)+acc.get('byteOffset',0)).reshape(-1,4,4).transpose(0,2,1)
    old_points={old['nodes'][j]['name']:np.linalg.inv(ib[i])[:3,3] for i,j in enumerate(skin['joints'])}
    orientation=np.repeat(np.eye(3)[None],len(names),axis=0);posed=positions.copy()
    next_bone={}
    for side in ['l','r']:
        for name,child in [('upperarm','lowerarm'),('lowerarm','hand'),('hand','middle_01')]:
            next_bone[name+'_'+side]=child+'_'+side
        for finger in ['thumb','index','middle','ring','pinky']:
            for n in [1,2]:next_bone[f'{finger}_{n:02d}_{side}']=f'{finger}_{n+1:02d}_{side}'
    for i,name in enumerate(names):
        if i==0:continue
        par=next(p-2 for p,node in enumerate(nodes) if p>=2 and i+2 in node.get('children',[]))
        posed[i]=posed[par]+orientation[par]@(positions[i]-positions[par])
        if name in next_bone:
            child=next_bone[name];j=names.index(child)
            orientation[i]=rotation_between(positions[j]-positions[i],old_points[child]-old_points[name])
        elif any(name.startswith(f+'_' ) for f in ['thumb','index','middle','ring','pinky']):
            orientation[i]=orientation[par]
    def warp(points,weights):
        out=np.zeros_like(points)
        for j in range(len(names)):
            out+=( (points-positions[j])@orientation[j].T+posed[j])*weights[:,j,None]
        return out
    return posed,warp

def fitted(mhclo,verts,dense):
    data=mhclo.read_text().splitlines(); refs=[]; offsets=[]; coef=[]
    scales=np.ones(3); mode=False
    for line in data:
        t=line.split()
        if not t or t[0].startswith('#'):continue
        if t[0] in ['x_scale','y_scale','z_scale']:
            a='xyz'.index(t[0][0]);scales[a]=abs(verts[int(t[1]),a]-verts[int(t[2]),a])/float(t[3])
        elif t[0]=='verts':mode=True
        elif mode:
            if not t[0].lstrip('-').isdigit():
                if refs: break
                continue
            if len(t)==1: refs.append([int(t[0])]*3);coef.append([1,0,0]);offsets.append([0,0,0])
            else:refs.append(list(map(int,t[:3])));coef.append(list(map(float,t[3:6])));offsets.append(list(map(float,t[6:9])))
    refs=np.array(refs);coef=np.array(coef)
    points=(verts[refs]*coef[:,:,None]).sum(axis=1)+np.array(offsets)*scales
    weights=(dense[refs]*coef[:,:,None]).sum(axis=1)
    weights=np.maximum(weights,0);weights/=np.maximum(weights.sum(axis=1)[:,None],1e-8)
    return points,weights

def normals(v,tri):
    n=np.zeros_like(v);a,b,c=v[tri[:,0]],v[tri[:,1]],v[tri[:,2]]
    face=np.cross(b-a,c-a)
    for i in range(3): np.add.at(n,tri[:,i],face)
    return n/np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-8)

class Export:
    def __init__(self,nodes,names,positions):
        self.doc={'asset':{'version':'2.0','generator':'UniRp / MakeHuman CC0'},'scene':0,'scenes':[{'nodes':[1]}],
                  'nodes':nodes,'meshes':[],'materials':[],'images':[],'textures':[],'accessors':[],'bufferViews':[]}
        self.buf=bytearray();self.names=names
        ib=np.repeat(np.eye(4)[None],len(names),axis=0);ib[:,:3,3]=-positions
        self.doc['skins']=[{'name':'HumanSkin','skeleton':2,'joints':list(range(2,len(names)+2)),
                            'inverseBindMatrices':self.access(ib.transpose(0,2,1).reshape(-1,16).astype('<f4'),'MAT4')}]
    def access(self,a,typ):
        a=np.ascontiguousarray(a);self.buf.extend(b'\0'*((-len(self.buf))%4));start=len(self.buf);self.buf.extend(a.tobytes())
        view=len(self.doc['bufferViews']);self.doc['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':a.nbytes})
        comp={'float32':5126,'uint16':5123,'uint32':5125}[str(a.dtype)]
        item={'bufferView':view,'componentType':comp,'count':len(a),'type':typ}
        if typ=='VEC3':item.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
        self.doc['accessors'].append(item);return len(self.doc['accessors'])-1
    def material(self,name,texture=None,alpha=False):
        m={'name':name,'pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':.85},'doubleSided':True}
        if texture:
            self.doc['images'].append({'uri':texture});self.doc['textures'].append({'source':len(self.doc['images'])-1})
            m['pbrMetallicRoughness']['baseColorTexture']={'index':len(self.doc['textures'])-1}
        if alpha:m.update(alphaMode='MASK',alphaCutoff=.35)
        self.doc['materials'].append(m);return len(self.doc['materials'])-1
    def mesh(self,name,v,uv,faces,dense,mat,body=False,part=None):
        remap={};ids=[];tex=[];tri=[]
        for group,corners in faces:
            if body and group!='body':continue
            if part and not part(v[[c[0] for c in corners]].mean(axis=0)):continue
            row=[]
            for vi,ti in corners:
                key=(vi,ti)
                if key not in remap:
                    remap[key]=len(ids);ids.append(vi);tex.append(uv[ti] if ti>=0 else [0,0])
                row.append(remap[key])
            for n in range(1,len(row)-1):tri.append([row[0],row[n],row[n+1]])
        if not tri:return
        vv=v[ids].astype('<f4');tt=np.array(tri,dtype='<u4');nn=normals(vv,tt).astype('<f4')
        weights=dense[ids];j=np.argsort(weights,axis=1)[:,-4:][:,::-1];w=np.take_along_axis(weights,j,axis=1)
        w/=np.maximum(w.sum(axis=1)[:,None],1e-8)
        # Smooth UV seams by shared anatomical vertex rather than UV corner.
        sums=np.zeros_like(v);np.add.at(sums,ids,nn);normal=sums[ids];normal/=np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-8)
        attrs={'POSITION':self.access(vv,'VEC3'),'NORMAL':self.access(normal.astype('<f4'),'VEC3'),
               'TEXCOORD_0':self.access(np.array(tex,dtype='<f4')*np.array([1,-1],dtype='<f4')+np.array([0,1],dtype='<f4'),'VEC2'),
               'JOINTS_0':self.access(j.astype('<u2'),'VEC4'),'WEIGHTS_0':self.access(w.astype('<f4'),'VEC4')}
        if body:
            # Godot may reorder vertices while importing. Carry the anatomical
            # ID with each vertex so garment occlusion remains exact.
            source=np.array(ids)
            colors=np.column_stack([(source%256)/255,(source//256)/255,np.zeros(len(ids)),np.ones(len(ids))])
            attrs['COLOR_0']=self.access(colors.astype('<f4'),'VEC4')
        mid=len(self.doc['meshes']);self.doc['meshes'].append({'name':name,'primitives':[{'attributes':attrs,'indices':self.access(tt.reshape(-1),'SCALAR'),'material':mat}]})
        nid=len(self.doc['nodes']);self.doc['nodes'].append({'name':name,'mesh':mid,'skin':0});self.doc['nodes'][1]['children'].append(nid)
        return ids
    def save(self,name):
        self.doc['buffers']=[{'byteLength':len(self.buf),'uri':name+'.bin'}]
        (DEST/(name+'.bin')).write_bytes(self.buf);(DEST/(name+'.gltf')).write_text(json.dumps(self.doc,separators=(',',':')))

def texture(path,name,gray=False,size=2048):
    image=Image.open(path).convert('RGBA');image.thumbnail((size,size),Image.Resampling.LANCZOS)
    if gray:
        a=image.getchannel('A')
        lum=np.array(image.convert('L'),dtype=float)
        visible=np.array(a)>128
        reference=max(float(np.percentile(lum[visible],85)),20)
        lum=np.clip(lum*(190/reference),0,255).astype('uint8')
        image=Image.fromarray(lum).convert('RGBA');image.putalpha(a)
    image.save(DEST/name);return name

for gender,stage in [('male','young'),('female','young'),('male','child'),('female','child')]:
    human=BASE.copy()
    for ethnicity,weight in [('caucasian',.58),('african',.22),('asian',.20)]:
        human+=target(SOURCE/f'targets/macrodetails/{ethnicity}-{gender}-{stage}.target')*weight
    human+=target(SOURCE/f'targets/macrodetails/universal-{gender}-{stage}-averagemuscle-averageweight.target')
    nodes,names,positions,dense=skeleton(human)
    posed,warp=pose_for_animation(names,positions,nodes)
    human_rest=warp(human,dense)
    floor=human[BODY_IDS,1].min();factor=1.8/(human[BODY_IDS,1].max()-floor)
    def world(points):
        out=points.copy();out[:,1]-=floor;return out*factor
    positions=world(posed);positions[0]=0
    for i in range(1,len(names)):
        parent=next((p-2 for p,n in enumerate(nodes) if i+2 in n.get('children',[]) and p>=2),0)
        nodes[i+2]['translation']=(positions[i]-positions[parent]).tolist()
    ex=Export(nodes,names,positions)
    skin=texture(SYSTEM/f'skins/textures/young_lightskinned_{gender}_diffuse.png',gender+'_skin.png')
    for age_group in ['middleage','old']:
        path=SYSTEM/f'skins/{age_group}_caucasian_{gender}/{age_group}_lightskinned_{gender}_diffuse.png'
        if path.exists():texture(path,gender+'_'+age_group+'_skin.png')
    mat=ex.material('HumanSkin',skin)
    body_ids=ex.mesh('HumanBody',world(human_rest),UV,FACES,dense,mat,body=True)
    # Fitted sclera/iris geometry comes from the same anatomical eye helpers.
    eye_path=SOURCE/'eyes/high-poly/high-poly.mhclo'
    ev,ew=fitted(eye_path,human,dense);_,eu,ef=obj(eye_path.with_suffix('.obj'))
    eye=texture(SOURCE/'system/base/eyes/materials/brown_eye.png','eyes.png') if (SOURCE/'system/base/eyes/materials/brown_eye.png').exists() else None
    # The blue UV island is the optional cornea shell of the MakeHuman shader.
    # Godot gets the actual eye surface; a matte blue shell would hide the iris.
    ef=[(g,c) for g,c in ef if not all(eu[t][0]>.85 and eu[t][1]<.15 for _,t in c)]
    ex.mesh('Eyes',world(warp(ev,ew)),eu,ef,ew,ex.material('Eyes',eye))
    for folder,name,node in [('eyebrows','eyebrow001','Eyebrows'),('eyelashes','eyelashes01','Eyelashes')]:
        path=SYSTEM/folder/name/(name+'.mhclo')
        bv,bw=fitted(path,human,dense);_,bu,bf=obj(path.with_suffix('.obj'))
        mt=path.with_suffix('.mhmat').read_text()
        line=next((l.split(maxsplit=1)[1] for l in mt.splitlines() if l.startswith('diffuseTexture ')),None)
        tex=texture(path.parent/line,name+'.png',gray=True,size=512) if line else None
        ex.mesh(node,world(warp(bv,bw)),bu,bf,bw,ex.material(node,tex,alpha=True))
    for name in ['short01','short02','short03','short04','bob01','long01','ponytail01','afro01','braid01']:
        path=SYSTEM/'hair'/name/(name+'.mhclo')
        if not path.exists():continue
        hv,hw=fitted(path,human,dense);_,hu,hf=obj(path.with_suffix('.obj'))
        mt=path.with_suffix('.mhmat').read_text();line=next((l.split(maxsplit=1)[1] for l in mt.splitlines() if l.startswith('diffuseTexture ')),None)
        tex=texture(path.parent/line,name+'_hair.png',gray=True,size=1024) if line else None
        ex.mesh('HumanHair_'+name,world(warp(hv,hw)),hu,hf,hw,ex.material('Hair_'+name,tex,alpha=True))
    garments=['male_casualsuit01','male_casualsuit02','male_worksuit01'] if gender=='male' else ['female_casualsuit01','female_casualsuit02','female_sportsuit01']
    coverage={}
    for i,name in enumerate(garments):
        path=SYSTEM/'clothes'/name/(name+'.mhclo');cv,cw=fitted(path,human,dense);_,cu,cf=obj(path.with_suffix('.obj'))
        tex=texture(path.parent/(name+'_diffuse.png'),name+'_cloth.png',gray=True,size=1024)
        # Real garments keep their sculpted folds, cuffs, neckline and pockets.
        # Separate pieces allow the existing creator to tint top and trousers.
        wv=world(warp(cv,cw))
        ex.mesh('HumanTop_'+str(i),wv,cu,cf,cw,ex.material('Top_'+str(i),tex),part=lambda p:p[1]>.97)
        ex.mesh('HumanPants_'+str(i),wv,cu,cf,cw,ex.material('Pants_'+str(i),tex),part=lambda p:p[1]<=.97)
        coverage[str(i)]=sorted(covered_vertices(path)|covered_vertices(SYSTEM/'clothes/shoes01/shoes01.mhclo'))
    path=SYSTEM/'clothes/shoes01/shoes01.mhclo';sv,sw=fitted(path,human,dense);_,su,sf=obj(path.with_suffix('.obj'))
    tex=texture(path.parent/'shoes01_diffuse.png','shoes.png',gray=True,size=512)
    ex.mesh('HumanShoes',world(warp(sv,sw)),su,sf,sw,ex.material('Shoes',tex))
    asset_name='Human_'+gender+('_child' if stage=='child' else '')
    ex.save(asset_name)
    (DEST/(asset_name+'_coverage.json')).write_text(json.dumps({'outfits':coverage},separators=(',',':')))
    print(gender,stage,'anatomical vertices',len(BODY_IDS),'bones',len(names),'MB',round(len(ex.buf)/1e6,2),flush=True)
