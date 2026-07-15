package main

import (
	"fmt"
	brush "github.com/IgorShadurin/brush-photo-video-lib/languages/go"
	"math"
	"os"
	"path/filepath"
)

func main() {
	p := func(x, y float64) brush.Point { return brush.Point{X: x, Y: y} }
	points := []brush.Point{p(500, 520), p(450, 450), p(390, 395), p(320, 370), p(250, 370), p(180, 390), p(130, 450), p(120, 520), p(155, 585), p(220, 635), p(300, 650), p(380, 620), p(440, 570), p(500, 520), p(560, 465), p(620, 410), p(700, 370), p(770, 380), p(830, 420), p(870, 480), p(875, 545), p(845, 610), p(790, 660), p(720, 675), p(650, 655), p(585, 610), p(540, 560), p(500, 520)}
	if brush.BuildRoundedDrawingPath([]brush.Point{p(0, 0), p(100, 0), p(100, 100)}, 40) != "M 0 0 L 55 0 Q 100 0 100 45 L 100 100" {
		panic("rounding check failed")
	}
	if brush.SampleAt(brush.PrepareArcLengthPath([]brush.Point{p(0, 0), p(100, 0)}, .5), .5, 40).Angle != 0 {
		panic("angle check failed")
	}
	input, output := "assets/example.webp", "generated/go.svg"
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	if len(os.Args) > 2 {
		output = os.Args[2]
	}
	bytes, err := os.ReadFile(input)
	if err != nil {
		panic(err)
	}
	o := brush.DefaultOptions()
	o.MagicGradient = true
	svg, err := brush.RenderSVG(bytes, "image/webp", 1000, 1000, points, "🤝 best friends forever", o)
	if err != nil {
		panic(err)
	}
	if err = os.MkdirAll(filepath.Dir(output), 0755); err != nil {
		panic(err)
	}
	if err = os.WriteFile(output, []byte(svg), 0644); err != nil {
		panic(err)
	}
	fmt.Println("Wrote", output)
	_ = math.Pi
}
