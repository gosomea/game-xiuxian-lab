#!/usr/bin/env python3
"""水墨湖岸样板源生成器，标准库直接导出 glTF 2.0；单位米、Y 向上。"""
import json
import math
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'src/levels/experiments/character_movement'
ART = ROOT / 'docs/art/ink_lakeside_sample'
PALETTE = {
    'Paper': '#e7dfcc', 'Wall': '#eee7d7', 'Ink': '#343c3b',
    'Roof': '#505956', 'Stone': '#c4cabb', 'Shore': '#b8c5b7',
    'Wood': '#6b6356', 'Pink': '#c98f93', 'Leaf': '#899d94',
    'Far': '#c8d1c6', 'Middle': '#aabeb3', 'Near': '#8ea99f',
}
meshes = {}
boxes = []
rng = random.Random(105)


def triangle(group, material, a, b, c):
    vertices, normals = meshes.setdefault((group, material), ([], []))
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
    length = math.sqrt(sum(x*x for x in n))
    if length < 1e-9:
        return
    vertices.extend([a, b, c])
    normals.extend([[x/length for x in n]] * 3)


def quad(g, m, a, b, c, d):
    triangle(g, m, a, b, c)
    triangle(g, m, a, c, d)


def box(g, m, p, s, collision=False):
    x, y, z = p
    w, h, d = [n/2 for n in s]
    pts = [(x+a*w, y+b*h, z+c*d) for a,b,c in
           [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1),
            (-1,1,-1),(1,1,-1),(1,1,1),(-1,1,1)]]
    for ids in [(4,7,6,5),(0,1,2,3),(3,2,6,7),(1,0,4,5),(0,3,7,4),(2,1,5,6)]:
        quad(g,m,*(pts[i] for i in ids))
    if collision:
        boxes.append({'name': g + str(len(boxes)), 'position': p, 'size': s})


def line(g, m, a, b, width, segments=6):
    direction = [b[i]-a[i] for i in range(3)]
    length = math.sqrt(sum(v*v for v in direction))
    n = [v/length for v in direction]
    ref = (0,1,0) if abs(n[1]) < .9 else (1,0,0)
    u = [n[1]*ref[2]-n[2]*ref[1], n[2]*ref[0]-n[0]*ref[2], n[0]*ref[1]-n[1]*ref[0]]
    l = math.sqrt(sum(v*v for v in u)); u = [v/l for v in u]
    v = [n[1]*u[2]-n[2]*u[1],n[2]*u[0]-n[0]*u[2],n[0]*u[1]-n[1]*u[0]]
    def point(p, angle):
        return tuple(p[j]+width*(u[j]*math.cos(angle)+v[j]*math.sin(angle)) for j in range(3))
    for i in range(segments):
        t = i*math.tau/segments; t2 = (i+1)*math.tau/segments
        quad(g,m,point(a,t),point(a,t2),point(b,t2),point(b,t))


def ring(g,m,x,z,y,r,segments=8):
    return [(x+r*math.cos(i*math.tau/segments),y,z+r*math.sin(i*math.tau/segments)) for i in range(segments)]


def drum(g,m,x,z,y,r,h,segments=8):
    low=ring(g,m,x,z,y,r,segments); high=ring(g,m,x,z,y+h,r,segments)
    for i in range(segments):
        j=(i+1)%segments
        quad(g,m,low[i],high[i],high[j],low[j])
        triangle(g,m,(x,y+h,z),high[j],high[i])


def roof(g,x,z,y,r,h,segments=8):
    levels = [(r,y+.12),(r*.83,y),(r*.52,y+h*.48),(r*.20,y+h)]
    for k in range(len(levels)-1):
        a=ring(g,'Roof',x,z,levels[k][1],levels[k][0],segments)
        b=ring(g,'Roof',x,z,levels[k+1][1],levels[k+1][0],segments)
        for i in range(segments):
            j=(i+1)%segments
            quad(g,'Roof',a[i],b[i],b[j],a[j])
            line(g,'Ink',a[i],a[j],.025)
            line(g,'Ink',a[i],b[i],.018)
    # Additional ribs make curved eaves readable from a distant orthographic view.
    for i in range(segments*3):
        t=i*math.tau/(segments*3)
        points=[(x+rr*math.cos(t),yy+.015,z+rr*math.sin(t)) for rr,yy in levels]
        for a,b in zip(points,points[1:]): line(g,'Ink',a,b,.009,4)


def house(x,z,w,d,h):
    g='Village'
    box(g,'Wall',(x,h/2,z),(w,h,d),True)
    # Gable roof: curved slope with raised ends, ridge and eave ink strokes.
    for sign in [-1,1]:
        for i in range(4):
            a=i/4; b=(i+1)/4
            def pt(t, end):
                return (x+sign*(w*.5+.35)*t, h+1.0*(1-t)**1.7+.1*t**6, z+end*(d*.5+.32))
            quad(g,'Roof',pt(a,-1),pt(b,-1),pt(b,1),pt(a,1))
        line(g,'Ink',(x+sign*(w/2+.35),h+.1,z-d/2-.32),(x+sign*(w/2+.35),h+.1,z+d/2+.32),.035)
        for end in [-1,1]:
            p=[(x+sign*(w/2+.35)*i/4,h+(1-i/4)**1.7+.1*(i/4)**6,z+end*(d/2+.32)) for i in range(5)]
            for a,b in zip(p,p[1:]): line(g,'Ink',a,b,.027)
    line(g,'Ink',(x,h+1,z-d/2-.35),(x,h+1,z+d/2+.35),.04)
    box(g,'Ink',(x,h*.37,z+d/2+.012),(.68,h*.74,.035))
    for dx in [-w*.30,w*.30]:
        box(g,'Wood',(x+dx,h*.52,z+d/2+.023),(.50,.66,.035))
        for k in range(3): box(g,'Wall',(x+dx-.16+k*.16,h*.52,z+d/2+.046),(.023,.60,.018))
    for dx in [-w/2,w/2]:
        line(g,'Ink',(x+dx,.08,z+d/2+.022),(x+dx,h,z+d/2+.022),.02)


def tree(x,z,s,pink=True):
    g='Blossoms' if pink else 'Willows'
    trunk=(x+.15*s,2.4*s,z)
    line(g,'Ink',(x,0,z),trunk,.055*s)
    boxes.append({'name': 'Trunk'+str(len(boxes)), 'position': [x,1.2*s,z], 'size':[.18*s,2.4*s,.18*s]})
    for i in range(9):
        t=rng.random()*math.tau; spread=rng.uniform(.45,1.5)*s
        end=(x+math.cos(t)*spread,(2.4+rng.random()*1.1)*s,z+math.sin(t)*spread)
        fork=(x+.15*s,1.4*s+i*.11*s,z)
        line(g,'Ink',fork,end,.02*s)
        for _ in range(6):
            p=(end[0]+rng.uniform(-.45,.45)*s,end[1]+rng.uniform(-.3,.4)*s,end[2]+rng.uniform(-.45,.45)*s)
            r=rng.uniform(.14,.36)*s
            # Soft irregular leaf clusters, three rings rather than faceted cubes.
            material='Pink' if pink else 'Leaf'
            rings=[ring(g,material,p[0],p[2],p[1]-r*.5,r*.4,7),ring(g,material,p[0],p[2],p[1],r,7),ring(g,material,p[0],p[2],p[1]+r*.5,r*.3,7)]
            for a,b in zip(rings,rings[1:]):
                for k in range(7): quad(g,material,a[k],b[k],b[(k+1)%7],a[(k+1)%7])


def shore():
    # Top is triangulated from a star-shaped outline about an interior point.
    polygon=[(-45,120),(45,120),(45,1),(26,1),(20,-2),(5,-3),(2,-7),(-1,-12),(-9,-17),(-17,-14),(-21,-7),(-27,-1),(-45,2)]
    # Ear clipping handles concavity; collision is generated from this exact mesh.
    ids=list(range(len(polygon)))
    def cross(a,b,c): return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    while len(ids)>2:
        for k in range(len(ids)):
            ia,ib,ic=ids[k-1],ids[k],ids[(k+1)%len(ids)]
            a,b,c=[polygon[j] for j in [ia,ib,ic]]
            if cross(a,b,c)>=0: continue
            if any(cross(a,b,polygon[j])<=0 and cross(b,c,polygon[j])<=0 and cross(c,a,polygon[j])<=0 for j in ids if j not in [ia,ib,ic]): continue
            triangle('Shore','Shore',(a[0],0,a[1]),(b[0],0,b[1]),(c[0],0,c[1]))
            ids.pop(k); break
        else: raise RuntimeError('shore triangulation failed')
    for i,(x,z) in enumerate(polygon):
        xx,zz=polygon[(i+1)%len(polygon)]
        quad('Shore','Stone',(x,0,z),(x,-1.2,z),(xx,-1.2,zz),(xx,0,zz))
        line('Banks','Leaf',(x,.015,z),(xx,.015,zz),.025)
    return polygon


def mountain_layer(g,z,color,height):
    points=[]
    for i in range(61):
        x=-180+i*6
        y=height+1.0*math.sin(i*.33)+.7*math.sin(i*.74+.6)+rng.uniform(-.2,.2)
        points.append((x,y,z))
    for a,b in zip(points,points[1:]): quad(g,color,(a[0],-3,z),a,b,(b[0],-3,z))


def write_glb():
    binary=bytearray(); views=[]; accessors=[]
    def accessor(values):
        while len(binary)%4: binary.append(0)
        start=len(binary)
        binary.extend(struct.pack('<'+'f'*(len(values)*3),*(v for row in values for v in row)))
        views.append({'buffer':0,'byteOffset':start,'byteLength':len(binary)-start,'target':34962})
        a={'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':'VEC3',
           'min':[min(v[i] for v in values) for i in range(3)],'max':[max(v[i] for v in values) for i in range(3)]}
        accessors.append(a); return len(accessors)-1
    material_names=list(PALETTE)
    mats=[]
    for name,color in PALETTE.items():
        rgb=[int(color[i:i+2],16)/255 for i in (1,3,5)]
        mats.append({'name':name,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':rgb+[1],'metallicFactor':0,'roughnessFactor':1}})
    groups={}
    for (group,material),(p,n) in meshes.items():
        groups.setdefault(group,[]).append({'attributes':{'POSITION':accessor(p),'NORMAL':accessor(n)},'material':material_names.index(material),'mode':4})
    gltf={'asset':{'version':'2.0','generator':'game-xiuxian-lab ink lakeside source'},'scene':0,
          'scenes':[{'nodes':list(range(len(groups)))}],'nodes':[{'name':g,'mesh':i} for i,g in enumerate(groups)],
          'meshes':[{'name':g,'primitives':v} for g,v in groups.items()],'materials':mats,
          'accessors':accessors,'bufferViews':views,'buffers':[{'byteLength':len(binary)}]}
    encoded=json.dumps(gltf,separators=(',',':')).encode(); encoded+=b' '*((-len(encoded))%4)
    binary+=b'\0'*((-len(binary))%4)
    data=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary
    (OUT/'ink_lakeside_sample_world.glb').write_bytes(data)
    return sum(len(p) for p,n in meshes.values())//3


def main():
    OUT.mkdir(parents=True,exist_ok=True); ART.mkdir(parents=True,exist_ok=True)
    polygon=shore()
    x,z=-9,-8
    drum('Pagoda','Stone',x,z,0,5.0,.6)
    boxes.append({'name':'PagodaPlatform','position':[x,.3,z],'size':[7.05,.6,7.05]})
    for i in range(3): box('Steps','Stone',(x,.1*(i+1),z+5.2-i*.6),(2.4,.2*(i+1),.6),True)
    for level in range(5):
        y=.6+level*1.8; r=2.7-level*.31
        drum('Pagoda','Wall',x,z,y,r,1.45)
        roof('Pagoda',x,z,y+1.4,r+.65,.85)
        for i in range(8):
            t=i*math.tau/8
            line('Pagoda','Ink',(x+r*math.cos(t),y,z+r*math.sin(t)),(x+r*math.cos(t),y+1.45,z+r*math.sin(t)),.028)
        for i in range(24):
            t=(i+.5)*math.tau/24
            line('Pagoda','Ink',(x+(r+.015)*math.cos(t),y+.3,z+(r+.015)*math.sin(t)),(x+(r+.015)*math.cos(t),y+1.12,z+(r+.015)*math.sin(t)),.028)
    line('Pagoda','Ink',(x,9.65,z),(x,12.0,z),.055)
    boxes.append({'name':'PagodaBody','position':[x,4.9,z],'size':[4.9,8.6,4.9]})
    for spec in [(-24,6,4,3,2.6),(-30,12,3.8,3,2.4),(-20,17,4.7,3.6,2.8),
                 (16,5,4.3,3,2.5),(22,9,4,3.5,2.8),(27,4,4.6,3,2.7),(15,17,5,3.5,3),
                 (29,19,4,3,2.5),(-11,25,4.5,3.2,2.6),(4,27,4.2,3.6,2.8)]: house(*spec)
    for spec in [(-18,-4,1.3),(-24,3,1.1),(4,2,1.25),(29,0,1.0),(-15,12,1.1),(10,18,1.0),(-28,23,1.2)]: tree(*spec)
    for spec in [(-3,-2,1.05),(21,16,1.1),(-34,8,1.15),(32,25,.9)]: tree(*spec,pink=False)
    # Footbridge crosses a narrow lake gap toward a separate landing island.
    box('Bridge','Stone',(9,.15,-4),(2.0,.3,12),True)
    for side in [-1,1]:
        for zz in [-9,-6,-3,0]: line('Bridge','Ink',(9+side*.9,.3,zz),(9+side*.9,.95,zz),.028)
        line('Bridge','Ink',(9+side*.9,.85,-9.5),(9+side*.9,.85,1.5),.022)
    drum('Island','Shore',9,-13,-.8,4,.85,32)
    # Island collision uses the exported cylinder mesh in the scene.
    tree(10,-13,.85)
    mountain_layer('FarRidge',-62,'Far',1.2)
    mountain_layer('MiddleRidge',-54,'Middle',1.5)
    mountain_layer('NearRidge',-46,'Near',1.1)
    triangles=write_glb()
    layout={'schema':'ink_lakeside/1','spawn':[0,.06,10],'palette':PALETTE,'shore_polygon':polygon,'boxes':boxes,
            'bounds':[-43,43,-30,38],'landing':[9,.05,-13],'pagoda_landing':[-9,.6,-4.7]}
    (OUT/'ink_lakeside_sample_layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
    (ART/'build_manifest.json').write_text(json.dumps({'generator':'tools/art/build_ink_lakeside_sample.py','seed':105,
        'triangles':triangles,'groups':sorted(set(k[0] for k in meshes)),'collision_boxes':len(boxes)},indent=2)+'\n')
    print(f'ink lakeside: {triangles} triangles, {len(boxes)} collision boxes')


if __name__=='__main__': main()
