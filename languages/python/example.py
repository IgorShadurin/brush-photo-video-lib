from pathlib import Path
import math,sys
from brush import Point,RenderOptions,build_rounded_drawing_path,prepare_arc_length_path,render_svg,sample_at
points=[Point(x,y) for x,y in [(500,520),(450,450),(390,395),(320,370),(250,370),(180,390),(130,450),(120,520),(155,585),(220,635),(300,650),(380,620),(440,570),(500,520),(560,465),(620,410),(700,370),(770,380),(830,420),(870,480),(875,545),(845,610),(790,660),(720,675),(650,655),(585,610),(540,560),(500,520)]]
assert build_rounded_drawing_path([Point(0,0),Point(100,0),Point(100,100)],40)=="M 0 0 L 55 0 Q 100 0 100 45 L 100 100"
assert sample_at(prepare_arc_length_path([Point(0,0),Point(100,0)]),.5)["angle"]==0
input_path=Path(sys.argv[1] if len(sys.argv)>1 else "assets/example.webp");output=Path(sys.argv[2] if len(sys.argv)>2 else "generated/python.svg");output.parent.mkdir(parents=True,exist_ok=True)
options=RenderOptions(magic_gradient=True);svg=render_svg(input_path.read_bytes(),"image/webp",1000,1000,points,"🤝 best friends forever",options);assert "data:image/webp;base64," in svg and "🤝 best friends forever" in svg;output.write_text(svg,encoding="utf-8");print(f"Wrote {output}")
