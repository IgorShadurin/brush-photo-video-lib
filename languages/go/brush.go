package brush

import (
	"encoding/base64"
	"fmt"
	"html"
	"math"
	"strings"
)

type Point struct{ X, Y float64 }
type DrawingPath struct {
	Points   []Point
	D        string
	FontSize float64
}
type segment struct {
	a, b          Point
	start, length float64
}
type ArcPath struct {
	Points      []Point
	segments    []segment
	TotalLength float64
}
type PathSample struct{ X, Y, Angle, Progress float64 }
type Options struct {
	FontSize, LetterSpacing, Opacity, StrokeWidth, RevealProgress float64
	FontFamily, FontWeight, Color, StrokeColor                    string
	MagicGradient, Shadow, RepeatText                             bool
}

func DefaultOptions() Options {
	return Options{FontSize: 40, LetterSpacing: math.NaN(), Opacity: 1, StrokeWidth: 1.5, RevealProgress: 1, FontFamily: "Arial, sans-serif", FontWeight: "700", Color: "#ffffff", StrokeColor: "rgba(15,23,42,0.72)", Shadow: true, RepeatText: true}
}
func finite(p Point) bool {
	return !math.IsNaN(p.X) && !math.IsInf(p.X, 0) && !math.IsNaN(p.Y) && !math.IsInf(p.Y, 0)
}
func clamp(v, a, b float64) float64 {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return a
	}
	return math.Min(b, math.Max(a, v))
}
func distance(a, b Point) float64 { return math.Hypot(b.X-a.X, b.Y-a.Y) }
func format(v float64) string {
	v = math.Round(v*100) / 100
	if v == 0 {
		return "0"
	}
	return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.2f", v), "0"), ".")
}
func fp(p Point) string { return format(p.X) + " " + format(p.Y) }
func along(a, b Point, d float64) Point {
	l := distance(a, b)
	if l == 0 {
		return a
	}
	t := math.Min(1, d/l)
	return Point{a.X + (b.X-a.X)*t, a.Y + (b.Y-a.Y)*t}
}
func turn(a, b, c Point) float64 {
	ux, uy, vx, vy := b.X-a.X, b.Y-a.Y, c.X-b.X, c.Y-b.Y
	ul, vl := math.Hypot(ux, uy), math.Hypot(vx, vy)
	if ul == 0 || vl == 0 {
		return 0
	}
	return math.Acos(clamp((ux*vx+uy*vy)/(ul*vl), -1, 1)) * 180 / math.Pi
}
func BuildRoundedDrawingPath(input []Point, fontSize float64) string {
	p := []Point{}
	for _, v := range input {
		if finite(v) {
			p = append(p, v)
		}
	}
	if len(p) == 0 {
		return ""
	}
	if len(p) == 1 {
		return "M " + fp(p[0])
	}
	out := []string{"M " + fp(p[0])}
	radius := math.Max(12, fontSize*1.25)
	for i := 1; i < len(p)-1; i++ {
		d := math.Min(radius, math.Min(distance(p[i-1], p[i])*.45, distance(p[i], p[i+1])*.45))
		out = append(out, "L "+fp(along(p[i], p[i-1], d))+" Q "+fp(p[i])+" "+fp(along(p[i], p[i+1], d)))
	}
	return strings.Join(append(out, "L "+fp(p[len(p)-1])), " ")
}
func CreateDrawingPath(p Point, fs float64) DrawingPath {
	if !finite(p) {
		return DrawingPath{FontSize: fs}
	}
	return DrawingPath{[]Point{p}, "M " + fp(p), fs}
}
func AppendDrawingPoint(path DrawingPath, p Point) DrawingPath {
	if !finite(p) || len(path.Points) == 0 || distance(path.Points[len(path.Points)-1], p) < 3 {
		return path
	}
	next := append([]Point{}, path.Points...)
	if len(next) == 1 || turn(next[len(next)-2], next[len(next)-1], p) >= 18 {
		next = append(next, p)
	} else {
		next[len(next)-1] = p
	}
	return DrawingPath{next, BuildRoundedDrawingPath(next, path.FontSize), path.FontSize}
}
func DrawingPathFromPoints(points []Point, fs float64) (DrawingPath, bool) {
	var path DrawingPath
	started := false
	for _, p := range points {
		if finite(p) {
			if !started {
				path = CreateDrawingPath(p, fs)
				started = true
			} else {
				path = AppendDrawingPoint(path, p)
			}
		}
	}
	return path, len(path.Points) >= 2
}
func perp(p, a, b Point) float64 {
	dx, dy := b.X-a.X, b.Y-a.Y
	l := dx*dx + dy*dy
	if l == 0 {
		return distance(p, a)
	}
	t := clamp(((p.X-a.X)*dx+(p.Y-a.Y)*dy)/l, 0, 1)
	return distance(p, Point{a.X + t*dx, a.Y + t*dy})
}
func simplify(p []Point, tolerance float64) []Point {
	if len(p) <= 2 {
		return p
	}
	keep := make([]bool, len(p))
	keep[0], keep[len(p)-1] = true, true
	stack := [][2]int{{0, len(p) - 1}}
	for len(stack) > 0 {
		r := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		best, index := 0.0, -1
		for i := r[0] + 1; i < r[1]; i++ {
			d := perp(p[i], p[r[0]], p[r[1]])
			if d > best {
				best, index = d, i
			}
		}
		if best > tolerance {
			keep[index] = true
			stack = append(stack, [2]int{r[0], index}, [2]int{index, r[1]})
		}
	}
	out := []Point{}
	for i, v := range p {
		if keep[i] {
			out = append(out, v)
		}
	}
	return out
}
func PrepareArcLengthPath(input []Point, minimum float64) ArcPath {
	if math.IsNaN(minimum) || math.IsInf(minimum, 0) {
		minimum = .5
	}
	minimum = math.Max(0, minimum)
	valid, filtered := []Point{}, []Point{}
	for _, p := range input {
		if finite(p) {
			valid = append(valid, p)
		}
	}
	for _, p := range valid {
		if len(filtered) == 0 || distance(filtered[len(filtered)-1], p) >= minimum {
			filtered = append(filtered, p)
		}
	}
	if len(valid) > 0 && len(filtered) > 0 && distance(filtered[len(filtered)-1], valid[len(valid)-1]) > 0 {
		filtered = append(filtered, valid[len(valid)-1])
	}
	p := simplify(filtered, math.Max(minimum*.5, .1))
	path := ArcPath{Points: p}
	for i := 1; i < len(p); i++ {
		l := distance(p[i-1], p[i])
		if l > 0 {
			path.segments = append(path.segments, segment{p[i-1], p[i], path.TotalLength, l})
			path.TotalLength += l
		}
	}
	return path
}
func pointAt(p ArcPath, d float64) Point {
	if len(p.segments) == 0 {
		return Point{}
	}
	d = clamp(d, 0, p.TotalLength)
	for _, s := range p.segments {
		if d <= s.start+s.length {
			t := clamp((d-s.start)/s.length, 0, 1)
			return Point{s.a.X + (s.b.X-s.a.X)*t, s.a.Y + (s.b.Y-s.a.Y)*t}
		}
	}
	return p.segments[len(p.segments)-1].b
}
func SampleAt(p ArcPath, progress, fs float64) PathSample {
	progress = clamp(progress, 0, 1)
	if p.TotalLength <= 0 {
		return PathSample{Progress: progress}
	}
	d := p.TotalLength * progress
	w := math.Max(math.Min(math.Max(fs*1.1, .75), p.TotalLength*.06), .75)
	a, b, v := pointAt(p, d-w), pointAt(p, d+w), pointAt(p, d)
	return PathSample{v.X, v.Y, math.Atan2(b.Y-a.Y, b.X-a.X), progress}
}
func StableRepeatedText(text string, fs float64) string {
	phrase := strings.TrimSpace(text)
	if phrase == "" {
		return ""
	}
	count := int(math.Ceil(20000 / math.Max(fs, float64(len([]rune(phrase)))*fs*.62)))
	if count < 16 {
		count = 16
	}
	if count > 256 {
		count = 256
	}
	parts := make([]string, count)
	for i := range parts {
		parts[i] = phrase
	}
	return strings.Join(parts, "   ")
}
func RenderSVG(bytes []byte, mime string, width, height float64, points []Point, text string, o Options) (string, error) {
	allowed := map[string]bool{"image/png": true, "image/jpeg": true, "image/webp": true, "image/gif": true, "image/avif": true}
	if !allowed[mime] {
		return "", fmt.Errorf("unsupported MIME")
	}
	if !(width > 0 && height > 0 && !math.IsInf(width+height, 0) && !math.IsNaN(width+height)) {
		return "", fmt.Errorf("invalid dimensions")
	}
	phrase := strings.TrimSpace(text)
	fs := o.FontSize
	if !(fs > 0) || math.IsInf(fs, 0) || math.IsNaN(fs) {
		fs = 40
	}
	path, ok := DrawingPathFromPoints(points, fs)
	if phrase == "" || !ok {
		return "", fmt.Errorf("text and two points required")
	}
	repeat := phrase
	if o.RepeatText {
		repeat = StableRepeatedText(phrase, fs)
	}
	gradient := ""
	if o.MagicGradient {
		gradient = `<linearGradient id="brush-gradient" x1="100" y1="150" x2="900" y2="850" gradientUnits="userSpaceOnUse"><stop offset="0%" stop-color="#ec4899"/><stop offset="20%" stop-color="#f97316"/><stop offset="40%" stop-color="#facc15"/><stop offset="60%" stop-color="#10b981"/><stop offset="80%" stop-color="#3b82f6"/><stop offset="100%" stop-color="#8b5cf6"/></linearGradient>`
	}
	shadow, filter := "", ""
	if o.Shadow {
		shadow = `<filter id="brush-shadow"><feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#0f172a" flood-opacity="0.65"/></filter>`
		filter = ` filter="url(#brush-shadow)"`
	}
	fill := html.EscapeString(o.Color)
	if o.MagicGradient {
		fill = "url(#brush-gradient)"
	}
	spacing := o.LetterSpacing
	if math.IsNaN(spacing) {
		spacing = math.Max(.75, fs*.06)
	}
	reveal := clamp(o.RevealProgress, 0, 1)
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s" viewBox="0 0 %s %s"><image width="%s" height="%s" preserveAspectRatio="xMidYMid slice" href="data:%s;base64,%s"/><defs><path id="brush-path" d="%s"/>%s%s<mask id="brush-reveal"><rect width="100%%" height="100%%" fill="black"/><path d="%s" pathLength="1" fill="none" stroke="white" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="1" stroke-dashoffset="%s"/></mask></defs><g mask="url(#brush-reveal)" opacity="%s"%s><text font-family="%s" font-size="%s" font-weight="%s" letter-spacing="%s" fill="%s" stroke="%s" stroke-width="%s" paint-order="stroke fill"><textPath href="#brush-path" xlink:href="#brush-path" startOffset="0" spacing="exact">%s</textPath></text></g></svg>
`, format(width), format(height), format(width), format(height), format(width), format(height), mime, base64.StdEncoding.EncodeToString(bytes), html.EscapeString(path.D), gradient, shadow, html.EscapeString(path.D), format(fs*2.4), format(1-reveal), format(clamp(o.Opacity, 0, 1)), filter, html.EscapeString(o.FontFamily), format(fs), html.EscapeString(o.FontWeight), format(spacing), fill, html.EscapeString(o.StrokeColor), format(math.Max(0, o.StrokeWidth)), html.EscapeString(repeat)), nil
}
