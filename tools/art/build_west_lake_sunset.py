#!/usr/bin/env python3
"""西湖夕照的可编辑程序源；压缩布局，Y 向上，单位米；零外部依赖。"""
import json
import hashlib
import math
import random
import struct
from pathlib import Path
import build_ink_lakeside_sample as g

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'src/levels/experiments/character_movement'
ART = ROOT / 'docs/art/west_lake_sunset'
PALETTE = {'Paper':'#ead9bb','Wall':'#eadfc8','Ink':'#384346','Roof':'#546568',
           'Stone':'#c3c6b5','Shore':'#a6b6a0','Wood':'#7e6654','Pink':'#d4a5a0',
           'Leaf':'#7f9d8c','Far':'#c7c5bb','Middle':'#a3b4a8','Near':'#839c90',
           'Path':'#d9ceb7','Gold':'#b89770','Bird':'#4c5755','Cloud':'#eadeca'}
g.PALETTE = PALETTE
g.rng = random.Random(106)
g.meshes.clear()
g.boxes.clear()
walk_groups = []
landmarks = []


def ellipsoid(group, mat, x,y,z, rx,ry,rz, segments=12, bands=6):
    def pt(i,j):
        a=i*math.tau/segments; t=-math.pi/2+j*math.pi/bands
        return (x+rx*math.cos(t)*math.cos(a),y+ry*math.sin(t),z+rz*math.cos(t)*math.sin(a))
    for j in range(bands):
        for i in range(segments):
            g.quad(group,mat,pt(i,j),pt(i,j+1),pt(i+1,j+1),pt(i+1,j))


def terrain():
    group='WalkShore'; walk_groups.append(group)
    # Continuous annular land; true hole is the lake, with shallow berm outside.
    def pt(i,j):
        a=i*math.tau/96; t=j/12
        x=math.cos(a)*(78+122*t); z=math.sin(a)*(64+106*t)
        hills=max(0, t-.18)*max(0, -math.cos(a)+.45)*26
        hills+=max(0,t-.42)*abs(math.sin(a))*15
        y=hills*(.75+.18*math.sin(a*9)+.10*math.cos(a*15))
        return (x,y,z)
    for j in range(12):
        for i in range(96):
            mat='Shore' if j<4 else ('Near' if j<8 else 'Middle')
            g.quad(group,mat,pt(i,j),pt(i+1,j),pt(i+1,j+1),pt(i,j+1))
    for i in range(96):
        def outer(k):
            a=k*math.tau/96; x=math.cos(a); z=math.sin(a)
            scale=650/max(abs(x),abs(z))
            return (x*scale,0,z*scale)
        g.quad(group,'Far',pt(i,12),pt(i+1,12),outer(i+1),outer(i))
    for i in range(96):
        a=pt(i,0); b=pt(i+1,0)
        g.quad(group,'Stone',a,b,(b[0],-1.6,b[2]),(a[0],-1.6,a[2]))
        g.line('ShoreInk','Leaf',a,b,.045)
        # Flat ring promenade follows the lake within flat inner berm.
        t1=i*math.tau/96; t2=(i+1)*math.tau/96
        p=lambda a,r: (math.cos(a)*(78+r),.018,math.sin(a)*(64+r))
        g.quad('Promenade','Path',p(t1,1.2),p(t1,5.4),p(t2,5.4),p(t2,1.2))


def island(group,x,z,rx,rz):
    walk_groups.append(group)
    for i in range(48):
        a=i*math.tau/48; b=(i+1)*math.tau/48
        p=(x+rx*math.cos(a),.10,z+rz*math.sin(a)); q=(x+rx*math.cos(b),.10,z+rz*math.sin(b))
        g.triangle(group,'Shore',(x,.10,z),q,p)
        g.quad(group,'Stone',p,q,(q[0],-1.6,q[2]),(p[0],-1.6,p[2]))
        g.line('IslandBanks','Leaf',p,q,.055)


def path(group,x,z,width,length):
    g.box(group,'Path',(x,-.45,z),(width,1.1,length))
    if group not in walk_groups: walk_groups.append(group)


def bridge(group,x,z,width=5,length=10,along_x=False):
    walk_groups.append(group)
    def pt(dx,zz,lower=False):
        yy=.10+.72*math.sin((zz/length+.5)*math.pi)
        if lower: yy-=.48
        return (x+zz,yy,z+dx) if along_x else (x+dx,yy,z+zz)
    for k in range(16):
        a=-length/2+length*k/16; b=-length/2+length*(k+1)/16
        deck=[pt(-width/2,a),pt(-width/2,b),pt(width/2,b),pt(width/2,a)]
        if along_x: deck.reverse()
        g.quad(group,'Stone',*deck)
        for side in [-1,1]:
            dx=side*width/2
            g.quad(group,'Stone',pt(dx,a),pt(dx,b),pt(dx,b,True),pt(dx,a,True))
            p=pt(dx,a); q=pt(dx,b)
            g.line('BridgeRails','Ink',(p[0],p[1]+.7,p[2]),(q[0],q[1]+.7,q[2]),.035)
            if k%2==0:
                g.line('BridgeRails','Stone',p,(p[0],p[1]+.85,p[2]),.11)
    # Physical rail boxes prevent stepping off sides; actual deck stays a slope.
    # Rail ornament itself is not a tall invisible wall.


def willow(x,z,scale=1.0,pink=False):
    group='Willows' if not pink else 'Blossoms'
    h=3.4*scale
    g.line(group,'Wood',(x,0,z),(x+.2*scale,h*.9,z),.12*scale)
    for k in range(5):
        a=k*math.tau/5+.3; dx=math.cos(a); dz=math.sin(a)
        tip=(x+dx*1.5*scale,h*(.92+.09*math.sin(k)),z+dz*1.5*scale)
        g.line(group,'Wood',(x+.15*scale,h*.60,z),tip,.04*scale)
        ellipsoid(group,'Pink' if pink else 'Leaf',tip[0],tip[1]-.1*scale,tip[2],1.1*scale,.6*scale,.85*scale,8,4)
        if not pink:
            for j in [-1,0,1]:
                start=(tip[0]+j*.35*scale,tip[1]-.1*scale,tip[2])
                end=(start[0]+.25*scale,start[1]-1.55*scale,start[2]+.16*scale)
                g.line(group,'Leaf',start,end,.045*scale,4)


def pavilion(x,z,r=2.3):
    g.drum('Pavilions','Stone',x,z,0,r,.25,8)
    g.box('PavilionBases','Stone',(x,.12,z),(r*1.4,.24,r*1.4),True)
    for k in range(8):
        a=k*math.tau/8
        g.line('Pavilions','Wood',(x+r*.78*math.cos(a),.25,z+r*.78*math.sin(a)),(x+r*.78*math.cos(a),3.05,z+r*.78*math.sin(a)),.10)
    g.roof('Pavilions',x,z,3.0,r+.35,1.25)


def pagoda(x,z,levels=5,r=4.2,step=2.2,label='雷峰夕照'):
    g.drum('Pagodas','Stone',x,z,0,r+2,.4,16)
    # The front apron is deliberately open for landing.
    g.box('PagodaApron','Stone',(x,.2,z+3.7),(12,.4,7),True)
    g.box('PagodaBody','Wall',(x,levels*step*.5+.4,z),(r*1.45,levels*step,r*1.45),True)
    for level in range(levels):
        y=.4+level*step; rr=r*(1-level*.10)
        g.drum('Pagodas','Wall',x,z,y,rr,step*.87)
        g.roof('Pagodas',x,z,y+step*.86,rr+.7,step*.50)
        for k in range(24):
            a=(k+.5)*math.tau/24
            g.line('Pagodas','Ink',(x+rr*math.cos(a),y+.2,z+rr*math.sin(a)),(x+rr*math.cos(a),y+step*.76,z+rr*math.sin(a)),.045)
        if level<levels-1:
            g.drum('PagodaRails','Gold',x,z,y+step*.79,rr+.25,.13,16)
    g.line('Pagodas','Ink',(x,levels*step+.6,z),(x,levels*step+3,z),.09)
    landmarks.append({'title':label,'position':[x,0,z]})


def town():
    # Lake-facing shops and street lanes on the flat eastern shore.
    for x in [94,107,123]:
        for z in range(-38,49,12):
            if x==94 and abs(z-20)<12: continue
            g.house(x,z,6.5,6,3.7+(z%3)*.3)
    for z in [-42,-16,12,38,60]:
        g.box('TownLanes','Path',(110,.012,z),(49,.02,3))
    for x in [86,100,115,134]:
        g.box('TownLanes','Path',(x,.014,8),(2,.028,105))
    for z in range(-45,59,7):
        willow(85,z,.95,pink=(z%3==0))
        # Lantern poles, warm ink accents without point-light cost.
        g.line('Lanterns','Wood',(89,0,z),(89,2.6,z),.06)
        g.box('Lanterns','Gold',(89,2.5,z),(.42,.5,.42))
    landmarks.append({'title':'杭州 · 湖滨','position':[82,0,20]})
    # Pier and benches create a foreground before the open water.
    g.box('Pier','Wood',(74,.05,20),(12,.1,5),True)
    for x in [72,77,82]:
        for side in [-1,1]:
            g.line('Pier','Wood',(x,-1.6,20+side*2.2),(x,.5,20+side*2.2),.10)
    for z in [6,32]:
        g.box('Benches','Wood',(83,.5,z),(.8,.18,2.4),True)
        for zz in [-.8,.8]: g.box('Benches','Wood',(83,.25,z+zz),(.45,.5,.3))


def main():
    ART.mkdir(parents=True,exist_ok=True)
    terrain(); town()
    # North shore and Gushan; Bai causeway intentionally curves into the east bank.
    island('WalkGushan',-22,-42,16,10)
    path('WalkBai',22,-42,83,5)  # function box dims are width x length z
    bridge('WalkBrokenBridge',63,-42,5,10,True)
    path('WalkBaiEast',72,-42,10,5)
    bridge('WalkGushanWest',-40,-42,5,11,True)
    pavilion(-22,-45,2.8)
    landmarks.extend([{'title':'白堤 · 断桥','position':[63,0,-42]}, {'title':'孤山 · 平湖秋月','position':[-22,0,-42]}])
    # Su causeway, six independently shaped stone bridges and connecting berms.
    gap_centers=[-45,-27,-9,9,27,45]
    starts=[-66]+[z+5 for z in gap_centers]
    ends=[z-5 for z in gap_centers]+[66]
    for i,(a,b) in enumerate(zip(starts,ends)): path('WalkSuBerm',-45,(a+b)/2,5,b-a+.03)
    for i,z in enumerate(gap_centers): bridge('WalkSuBridge'+str(i+1),-45,z)
    for z in range(-60,61,8):
        if min(abs(z-v) for v in gap_centers)<5: continue
        willow(-47,z,.8); willow(-43,z,.7,pink=True)
    landmarks.append({'title':'苏堤 · 六桥','position':[-45,0,0]})
    for x in range(-33,63,9): willow(x,-40, .75, pink=(x%3==0))
    # Three islands, pavilions, landing lawns, and the three small stone lantern pagodas.
    island('WalkXiaoying',-7,24,13,10); pavilion(-11,24)
    island('WalkHuxinting',4,-7,6,4); pavilion(4,-7,1.8)
    island('WalkRuangong',-25,4,7,5)
    for x,z in [(-4,26),(-13,29),(-7,19),(-26,4),(-22,3)]: willow(x,z,.8,pink=True)
    for x,z in [(-16,40),(-6,43),(3,38)]:
        g.drum('ThreePools','Stone',x,z,-1, .6,1.9,12)
        g.roof('ThreePools',x,z,.9,.9,.65)
        g.line('ThreePools','Ink',(x,1.4,z),(x,1.8,z),.06)
    landmarks.extend([{'title':'三潭印月','position':[-7,0,24]}, {'title':'湖心亭','position':[4,0,-7]}, {'title':'阮公墩','position':[-25,0,4]}])
    pagoda(15,72)
    pagoda(36,-73,7,1.25,1.4,'保俶塔')
    for x,z in [(4,70),(31,71),(-50,64),(-64,-49),(-75,18),(-73,-27),(53,-62)]: pavilion(x,z,2)
    # Shore trees stay inside the flat walking band; outer hills remain large readable washes.
    for i in range(48):
        a=i*math.tau/48
        if math.cos(a)>.6: continue
        willow(math.cos(a)*85,math.sin(a)*70,1.0+.25*math.sin(i*4),pink=(i%4==0))
    # Recessive distant ridge volumes on three sides, not vertical skyline cards.
    for x,z,rx,rz,h in [(-190,-90,70,85,30),(-230,15,70,100,39),(-190,105,85,80,27),
                        (-90,-190,100,70,28),(25,-185,90,65,23),(-70,190,110,80,29),(45,195,95,70,22)]:
        ellipsoid('DistantHills','Far',x,-8,z,rx,h,rz,24,10)
    # Boat mesh uses local coordinates: its Node3D is animated along a gentle bounded route.
    g.box('TourBoat','Wood',(0,.05,0),(2.3,.3,6))
    for side in [-1,1]: g.box('TourBoat','Wood',(side*1.12,.45,0),(.12,.6,6))
    for x in [-.9,.9]:
        for z in [-1.7,1.7]: g.line('TourBoat','Wood',(x,.2,z),(x,1.7,z),.06)
    g.box('TourBoat','Roof',(0,1.75,0),(2.4,.15,4))
    for i in range(14):
        x=-110+i*13; y=22+(i%3)*2; z=-60+(i%4)*7
        g.triangle('Birds','Bird',(x,y,z),(x-.65,y+.20,z+.20),(x-.10,y,z+.04))
        g.triangle('Birds','Bird',(x,y,z),(x+.60,y+.24,z+.18),(x+.10,y,z+.04))
    # Floating banks supply a readable cloud silhouette above the four mist sheets.
    for i,(x,z) in enumerate([(-130,-70),(-90,25),(-30,-80),(20,50),(80,-35),(130,75),
                              (-155,75),(0,-140),(110,-115),(-70,135),(0,160),(175,0)]):
        for k in range(5):
            dx=(k-2)*7; dz=math.sin(k*2.0)*5
            ellipsoid('CloudBank'+str(i),'Cloud',x+dx,39+(2-abs(k-2))*2,z+dz,
                      10+(k%3),5+(k%2),9+(k%3),20,10)
    triangles=write_glb()
    layout={'schema':'west_lake_sunset/1','spawn':[82,.12,20], 'palette':PALETTE,
            'walk_meshes':walk_groups,'boxes':g.boxes,'bounds':[-180,158,-150,150],
            'cloud_base':32,'cloud_top':48,'ceiling':180,'landmarks':landmarks,
            'landings':[[63,.82,-42],[-45,.82,9],[-7,.10,24],[15,.4,77]],
            'ray_points':[[82,0,20],[82,0,0],[0,0,68],[0,0,-68],[-45,0,0],[-45,0,9],[63,0,-42],[-7,0,24],[4,0,-7],[-25,0,4]]}
    (OUT/'west_lake_sunset_layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
    (ART/'build_manifest.json').write_text(json.dumps({'generator':'tools/art/build_west_lake_sunset.py','seed':106,
        'triangles':triangles,'groups':sorted(set(k[0] for k in g.meshes)), 'collision_boxes':len(g.boxes),
        'walk_meshes':walk_groups,'layout':'stylized, compressed, not surveyed',
        'sha256':{name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in
                  ['west_lake_sunset_world.glb','west_lake_sunset_layout.json']}},indent=2)+'\n')
    print(f'West Lake: {triangles} triangles; {len(g.boxes)} boxes; {len(walk_groups)} walk meshes')


def write_glb():
    binary=bytearray(); views=[]; accessors=[]
    def accessor(values):
        start=len(binary)
        binary.extend(struct.pack('<'+'f'*(len(values)*3),*(v for row in values for v in row)))
        views.append({'buffer':0,'byteOffset':start,'byteLength':len(binary)-start,'target':34962})
        accessors.append({'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':'VEC3',
            'min':[min(v[i] for v in values) for i in range(3)],'max':[max(v[i] for v in values) for i in range(3)]})
        return len(accessors)-1
    names=list(PALETTE); groups={}
    for (group,mat),(p,n) in g.meshes.items():
        groups.setdefault(group,[]).append({'attributes':{'POSITION':accessor(p),'NORMAL':accessor(n)},'material':names.index(mat),'mode':4})
    materials=[{'name':name,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':[int(c[i:i+2],16)/255 for i in (1,3,5)]+[1], 'metallicFactor':0,'roughnessFactor':1}} for name,c in PALETTE.items()]
    gltf={'asset':{'version':'2.0','generator':'game-xiuxian-lab West Lake source'},'scene':0,
        'scenes':[{'nodes':list(range(len(groups)))}], 'nodes':[{'name':key,'mesh':i} for i,key in enumerate(groups)],
        'meshes':[{'name':key,'primitives':value} for key,value in groups.items()], 'materials':materials,
        'accessors':accessors,'bufferViews':views,'buffers':[{'byteLength':len(binary)}]}
    encoded=json.dumps(gltf,separators=(',',':')).encode(); encoded+=b' '*((-len(encoded))%4)
    binary+=b'\0'*((-len(binary))%4)
    data=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary
    (OUT/'west_lake_sunset_world.glb').write_bytes(data)
    return sum(len(p) for p,n in g.meshes.values())//3


if __name__=='__main__': main()
