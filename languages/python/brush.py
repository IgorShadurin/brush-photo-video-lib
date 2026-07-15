"""Dependency-free curved text geometry and standalone SVG rendering."""
from __future__ import annotations
import base64, html, math
from dataclasses import dataclass, field

@dataclass(frozen=True)
class Point: x: float; y: float
@dataclass
class DrawingPath: points: list[Point]; d: str; font_size: float = 40
@dataclass
class ArcPath: points: list[Point]; segments: list[tuple[Point,Point,float,float]]; total_length: float
@dataclass
class RenderOptions:
    font_size: float=40; font_family: str="Arial, sans-serif"; font_weight: str="700"
    letter_spacing: float|None=None; color: str="#ffffff"; magic_gradient: bool=False
    opacity: float=1; stroke_color: str="rgba(15,23,42,0.72)"; stroke_width: float=1.5
    shadow: bool=True; repeat_text: bool=True; reveal_progress: float=1

def _finite(p): return math.isfinite(p.x) and math.isfinite(p.y)
def _clamp(v,a,b): return min(b,max(a,v)) if math.isfinite(v) else a
def _dist(a,b): return math.hypot(b.x-a.x,b.y-a.y)
def _fmt(v):
    v=round(v+0.0,2)
    return str(int(v)) if v==int(v) else (f"{v:.2f}".rstrip("0").rstrip("."))
def _fp(p): return f"{_fmt(p.x)} {_fmt(p.y)}"
def _along(a,b,d):
    length=_dist(a,b)
    if not length:return a
    t=min(1,d/length);return Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
def _turn(a,b,c):
    ux,uy=b.x-a.x,b.y-a.y;vx,vy=c.x-b.x,c.y-b.y;ul,vl=math.hypot(ux,uy),math.hypot(vx,vy)
    return 0 if not ul or not vl else math.degrees(math.acos(_clamp((ux*vx+uy*vy)/(ul*vl),-1,1)))
def build_rounded_drawing_path(source,font_size=40):
    p=[v for v in source if _finite(v)]
    if not p:return ""
    if len(p)==1:return "M "+_fp(p[0])
    out=["M "+_fp(p[0])];radius=max(12,font_size*1.25)
    for a,b,c in zip(p,p[1:],p[2:]):
        trim=min(radius,_dist(a,b)*.45,_dist(b,c)*.45);out.append(f"L {_fp(_along(b,a,trim))} Q {_fp(b)} {_fp(_along(b,c,trim))}")
    out.append("L "+_fp(p[-1]));return " ".join(out)
def create_drawing_path(point,font_size=40): return DrawingPath([point],"M "+_fp(point),font_size) if _finite(point) else DrawingPath([],"",font_size)
def append_drawing_point(path,point):
    if not _finite(point) or not path.points or _dist(path.points[-1],point)<3:return path
    p=path.points
    next_points=p+[point] if len(p)==1 or _turn(p[-2],p[-1],point)>=18 else p[:-1]+[point]
    return DrawingPath(next_points,build_rounded_drawing_path(next_points,path.font_size),path.font_size)
def finish_drawing_path(path): return path if len(path.points)>=2 else None
def drawing_path_from_points(points,font_size=40):
    valid=[p for p in points if _finite(p)]
    if not valid:return None
    path=create_drawing_path(valid[0],font_size)
    for p in valid[1:]:path=append_drawing_point(path,p)
    return finish_drawing_path(path)
def _perp(p,a,b):
    dx,dy=b.x-a.x,b.y-a.y;l=dx*dx+dy*dy
    if not l:return _dist(p,a)
    t=_clamp(((p.x-a.x)*dx+(p.y-a.y)*dy)/l,0,1);return _dist(p,Point(a.x+t*dx,a.y+t*dy))
def _simplify(p,tolerance):
    if len(p)<=2:return p
    keep=[False]*len(p);keep[0]=keep[-1]=True;stack=[(0,len(p)-1)]
    while stack:
        first,last=stack.pop();best,index=0,-1
        for i in range(first+1,last):
            d=_perp(p[i],p[first],p[last])
            if d>best:best,index=d,i
        if best>tolerance:keep[index]=True;stack.extend(((first,index),(index,last)))
    return [v for i,v in enumerate(p) if keep[i]]
def prepare_arc_length_path(source,minimum=.5):
    minimum=max(0,minimum) if math.isfinite(minimum) else .5;valid=[p for p in source if _finite(p)];filtered=[]
    for p in valid:
        if not filtered or _dist(filtered[-1],p)>=minimum:filtered.append(p)
    if valid and filtered and _dist(filtered[-1],valid[-1])>0:filtered.append(valid[-1])
    p=_simplify(filtered,max(minimum*.5,.1));segments=[];total=0
    for a,b in zip(p,p[1:]):
        length=_dist(a,b)
        if length>0:segments.append((a,b,total,length));total+=length
    return ArcPath(p,segments,total)
def _point_at(path,d):
    if not path.segments:return Point(0,0)
    d=_clamp(d,0,path.total_length)
    for a,b,start,length in path.segments:
        if d<=start+length:
            t=_clamp((d-start)/length,0,1);return Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
    return path.segments[-1][1]
def sample_at(path,progress,font_size=40):
    progress=_clamp(progress,0,1)
    if not path.total_length:return {"x":0,"y":0,"angle":0,"progress":progress}
    d=path.total_length*progress;w=max(min(max(font_size*1.1,.75),path.total_length*.06),.75);a,b=_point_at(path,d-w),_point_at(path,d+w);p=_point_at(path,d)
    return {"x":p.x,"y":p.y,"angle":math.atan2(b.y-a.y,b.x-a.x),"progress":progress}
def stable_repeated_text(text,font_size):
    phrase=text.strip()
    if not phrase:return ""
    count=min(256,max(16,math.ceil(20000/max(font_size,len(phrase)*font_size*.62))))
    return "   ".join([phrase]*count)
def render_svg(image_bytes,mime,width,height,points,text,options=None):
    o=options or RenderOptions()
    if mime not in {"image/png","image/jpeg","image/webp","image/gif","image/avif"}:raise ValueError("unsupported MIME")
    if not (math.isfinite(width+height) and width>0 and height>0):raise ValueError("invalid dimensions")
    phrase=text.strip();fs=o.font_size if math.isfinite(o.font_size) and o.font_size>0 else 40;path=drawing_path_from_points(points,fs)
    if not phrase or not path:raise ValueError("text and two points required")
    esc=lambda s:html.escape(str(s),quote=True).replace("&#x27;","&apos;");repeat=phrase if not o.repeat_text else stable_repeated_text(phrase,fs);spacing=o.letter_spacing if o.letter_spacing is not None else max(.75,fs*.06);reveal=_clamp(o.reveal_progress,0,1)
    gradient='<linearGradient id="brush-gradient" x1="100" y1="150" x2="900" y2="850" gradientUnits="userSpaceOnUse"><stop offset="0%" stop-color="#ec4899"/><stop offset="20%" stop-color="#f97316"/><stop offset="40%" stop-color="#facc15"/><stop offset="60%" stop-color="#10b981"/><stop offset="80%" stop-color="#3b82f6"/><stop offset="100%" stop-color="#8b5cf6"/></linearGradient>' if o.magic_gradient else "";shadow='<filter id="brush-shadow"><feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#0f172a" flood-opacity="0.65"/></filter>' if o.shadow else "";fill="url(#brush-gradient)" if o.magic_gradient else esc(o.color);filt=' filter="url(#brush-shadow)"' if o.shadow else ""
    data=base64.b64encode(image_bytes).decode("ascii")
    return f'''<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{_fmt(width)}" height="{_fmt(height)}" viewBox="0 0 {_fmt(width)} {_fmt(height)}"><image width="{_fmt(width)}" height="{_fmt(height)}" preserveAspectRatio="xMidYMid slice" href="data:{mime};base64,{data}"/><defs><path id="brush-path" d="{esc(path.d)}"/>{gradient}{shadow}<mask id="brush-reveal" maskUnits="userSpaceOnUse"><rect width="100%" height="100%" fill="black"/><path d="{esc(path.d)}" pathLength="1" fill="none" stroke="white" stroke-width="{_fmt(fs*2.4)}" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="1" stroke-dashoffset="{_fmt(1-reveal)}"/></mask></defs><g mask="url(#brush-reveal)" opacity="{_fmt(_clamp(o.opacity,0,1))}"{filt}><text font-family="{esc(o.font_family)}" font-size="{_fmt(fs)}" font-weight="{esc(o.font_weight)}" letter-spacing="{_fmt(spacing)}" fill="{fill}" stroke="{esc(o.stroke_color)}" stroke-width="{_fmt(max(0,o.stroke_width))}" paint-order="stroke fill"><textPath href="#brush-path" xlink:href="#brush-path" startOffset="0" spacing="exact">{esc(repeat)}</textPath></text></g></svg>\n'''
