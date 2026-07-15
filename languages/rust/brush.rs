use std::f64::consts::PI;
#[derive(Clone, Copy, Debug)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}
#[derive(Clone)]
pub struct DrawingPath {
    pub points: Vec<Point>,
    pub d: String,
    pub font_size: f64,
}
struct Segment {
    a: Point,
    b: Point,
    start: f64,
    length: f64,
}
pub struct ArcPath {
    pub points: Vec<Point>,
    segments: Vec<Segment>,
    pub total_length: f64,
}
pub struct PathSample {
    pub x: f64,
    pub y: f64,
    pub angle: f64,
    pub progress: f64,
}
pub struct Options {
    pub font_size: f64,
    pub letter_spacing: Option<f64>,
    pub opacity: f64,
    pub stroke_width: f64,
    pub reveal_progress: f64,
    pub font_family: String,
    pub font_weight: String,
    pub color: String,
    pub stroke_color: String,
    pub magic_gradient: bool,
    pub shadow: bool,
    pub repeat_text: bool,
}
impl Default for Options {
    fn default() -> Self {
        Self {
            font_size: 40.,
            letter_spacing: None,
            opacity: 1.,
            stroke_width: 1.5,
            reveal_progress: 1.,
            font_family: "Arial, sans-serif".into(),
            font_weight: "700".into(),
            color: "#ffffff".into(),
            stroke_color: "rgba(15,23,42,0.72)".into(),
            magic_gradient: false,
            shadow: true,
            repeat_text: true,
        }
    }
}
fn finite(p: Point) -> bool {
    p.x.is_finite() && p.y.is_finite()
}
fn clamp(v: f64, a: f64, b: f64) -> f64 {
    if v.is_finite() {
        v.max(a).min(b)
    } else {
        a
    }
}
fn distance(a: Point, b: Point) -> f64 {
    (b.x - a.x).hypot(b.y - a.y)
}
fn fmt(v: f64) -> String {
    let n = (v * 100.).round() / 100.;
    if n == 0. {
        return "0".into();
    }
    let s = format!("{n:0.2}");
    s.trim_end_matches('0').trim_end_matches('.').into()
}
fn fp(p: Point) -> String {
    format!("{} {}", fmt(p.x), fmt(p.y))
}
fn along(a: Point, b: Point, d: f64) -> Point {
    let l = distance(a, b);
    if l == 0. {
        return a;
    }
    let t = (d / l).min(1.);
    Point {
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
    }
}
fn turn(a: Point, b: Point, c: Point) -> f64 {
    let (ux, uy, vx, vy) = (b.x - a.x, b.y - a.y, c.x - b.x, c.y - b.y);
    let (ul, vl) = (ux.hypot(uy), vx.hypot(vy));
    if ul == 0. || vl == 0. {
        0.
    } else {
        clamp((ux * vx + uy * vy) / (ul * vl), -1., 1.).acos() * 180. / PI
    }
}
pub fn build_rounded_drawing_path(input: &[Point], fs: f64) -> String {
    let p: Vec<_> = input.iter().copied().filter(|p| finite(*p)).collect();
    if p.is_empty() {
        return String::new();
    }
    if p.len() == 1 {
        return format!("M {}", fp(p[0]));
    }
    let mut out = vec![format!("M {}", fp(p[0]))];
    let radius = 12f64.max(fs * 1.25);
    for i in 1..p.len() - 1 {
        let d = radius
            .min(distance(p[i - 1], p[i]) * 0.45)
            .min(distance(p[i], p[i + 1]) * 0.45);
        out.push(format!(
            "L {} Q {} {}",
            fp(along(p[i], p[i - 1], d)),
            fp(p[i]),
            fp(along(p[i], p[i + 1], d))
        ))
    }
    out.push(format!("L {}", fp(*p.last().unwrap())));
    out.join(" ")
}
pub fn create_drawing_path(p: Point, fs: f64) -> DrawingPath {
    if finite(p) {
        DrawingPath {
            points: vec![p],
            d: format!("M {}", fp(p)),
            font_size: fs,
        }
    } else {
        DrawingPath {
            points: vec![],
            d: String::new(),
            font_size: fs,
        }
    }
}
pub fn append_drawing_point(path: &DrawingPath, p: Point) -> DrawingPath {
    if !finite(p) || path.points.is_empty() || distance(*path.points.last().unwrap(), p) < 3. {
        return path.clone();
    }
    let mut next = path.points.clone();
    if next.len() == 1 || turn(next[next.len() - 2], next[next.len() - 1], p) >= 18. {
        next.push(p)
    } else {
        let n = next.len();
        next[n - 1] = p
    }
    DrawingPath {
        d: build_rounded_drawing_path(&next, path.font_size),
        points: next,
        font_size: path.font_size,
    }
}
pub fn drawing_path_from_points(points: &[Point], fs: f64) -> Option<DrawingPath> {
    let mut path = None;
    for &p in points.iter().filter(|p| finite(**p)) {
        path = Some(match path {
            None => create_drawing_path(p, fs),
            Some(ref old) => append_drawing_point(old, p),
        })
    }
    path.filter(|p| p.points.len() >= 2)
}
fn perp(p: Point, a: Point, b: Point) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let l = dx * dx + dy * dy;
    if l == 0. {
        return distance(p, a);
    }
    let t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / l, 0., 1.);
    distance(
        p,
        Point {
            x: a.x + t * dx,
            y: a.y + t * dy,
        },
    )
}
fn simplify(p: &[Point], tol: f64) -> Vec<Point> {
    if p.len() <= 2 {
        return p.to_vec();
    }
    let mut keep = vec![false; p.len()];
    keep[0] = true;
    keep[p.len() - 1] = true;
    let mut stack = vec![(0, p.len() - 1)];
    while let Some((first, last)) = stack.pop() {
        let (mut best, mut index) = (0., 0);
        for i in first + 1..last {
            let d = perp(p[i], p[first], p[last]);
            if d > best {
                best = d;
                index = i
            }
        }
        if best > tol {
            keep[index] = true;
            stack.push((first, index));
            stack.push((index, last))
        }
    }
    p.iter()
        .zip(keep)
        .filter_map(|(v, k)| k.then_some(*v))
        .collect()
}
pub fn prepare_arc_length_path(input: &[Point], minimum: f64) -> ArcPath {
    let min = if minimum.is_finite() {
        minimum.max(0.)
    } else {
        0.5
    };
    let valid: Vec<_> = input.iter().copied().filter(|p| finite(*p)).collect();
    let mut filtered = vec![];
    for p in valid.iter().copied() {
        if filtered
            .last()
            .map(|q| distance(*q, p) >= min)
            .unwrap_or(true)
        {
            filtered.push(p)
        }
    }
    if let (Some(&last), Some(&held)) = (valid.last(), filtered.last()) {
        if distance(held, last) > 0. {
            filtered.push(last)
        }
    }
    let points = simplify(&filtered, (min * 0.5).max(0.1));
    let (mut segments, mut total) = (vec![], 0.);
    for pair in points.windows(2) {
        let l = distance(pair[0], pair[1]);
        if l > 0. {
            segments.push(Segment {
                a: pair[0],
                b: pair[1],
                start: total,
                length: l,
            });
            total += l
        }
    }
    ArcPath {
        points,
        segments,
        total_length: total,
    }
}
fn point_at(p: &ArcPath, mut d: f64) -> Point {
    if p.segments.is_empty() {
        return Point { x: 0., y: 0. };
    }
    d = clamp(d, 0., p.total_length);
    for s in &p.segments {
        if d <= s.start + s.length {
            let t = clamp((d - s.start) / s.length, 0., 1.);
            return Point {
                x: s.a.x + (s.b.x - s.a.x) * t,
                y: s.a.y + (s.b.y - s.a.y) * t,
            };
        }
    }
    p.segments.last().unwrap().b
}
pub fn sample_at(p: &ArcPath, mut progress: f64, fs: f64) -> PathSample {
    progress = clamp(progress, 0., 1.);
    if p.total_length <= 0. {
        return PathSample {
            x: 0.,
            y: 0.,
            angle: 0.,
            progress,
        };
    }
    let d = p.total_length * progress;
    let w = (fs * 1.1).max(0.75).min(p.total_length * 0.06).max(0.75);
    let (a, b, v) = (point_at(p, d - w), point_at(p, d + w), point_at(p, d));
    PathSample {
        x: v.x,
        y: v.y,
        angle: (b.y - a.y).atan2(b.x - a.x),
        progress,
    }
}
pub fn stable_repeated_text(text: &str, fs: f64) -> String {
    let p = text.trim();
    if p.is_empty() {
        return String::new();
    }
    let count = (20000. / fs.max(p.chars().count() as f64 * fs * 0.62)).ceil() as usize;
    vec![p; count.clamp(16, 256)].join("   ")
}
fn esc(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
fn base64(data: &[u8]) -> String {
    const A: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut r = String::new();
    for c in data.chunks(3) {
        let a = c[0] as u32;
        let b = c.get(1).copied().unwrap_or(0) as u32;
        let d = c.get(2).copied().unwrap_or(0) as u32;
        let n = a << 16 | b << 8 | d;
        r.push(A[((n >> 18) & 63) as usize] as char);
        r.push(A[((n >> 12) & 63) as usize] as char);
        r.push(if c.len() > 1 {
            A[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        r.push(if c.len() > 2 {
            A[(n & 63) as usize] as char
        } else {
            '='
        })
    }
    r
}
pub fn render_svg(
    bytes: &[u8],
    mime: &str,
    width: f64,
    height: f64,
    points: &[Point],
    text: &str,
    o: &Options,
) -> Result<String, String> {
    if ![
        "image/png",
        "image/jpeg",
        "image/webp",
        "image/gif",
        "image/avif",
    ]
    .contains(&mime)
    {
        return Err("unsupported MIME".into());
    }
    if !(width > 0. && height > 0. && (width + height).is_finite()) {
        return Err("invalid dimensions".into());
    }
    let phrase = text.trim();
    let fs = if o.font_size > 0. && o.font_size.is_finite() {
        o.font_size
    } else {
        40.
    };
    let path = drawing_path_from_points(points, fs).ok_or("two points required")?;
    if phrase.is_empty() {
        return Err("text required".into());
    }
    let repeat = if o.repeat_text {
        stable_repeated_text(phrase, fs)
    } else {
        phrase.into()
    };
    let gradient = if o.magic_gradient {
        "<linearGradient id=\"brush-gradient\" x1=\"100\" y1=\"150\" x2=\"900\" y2=\"850\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0%\" stop-color=\"#ec4899\"/><stop offset=\"20%\" stop-color=\"#f97316\"/><stop offset=\"40%\" stop-color=\"#facc15\"/><stop offset=\"60%\" stop-color=\"#10b981\"/><stop offset=\"80%\" stop-color=\"#3b82f6\"/><stop offset=\"100%\" stop-color=\"#8b5cf6\"/></linearGradient>"
    } else {
        ""
    };
    let shadow = if o.shadow {
        "<filter id=\"brush-shadow\"><feDropShadow dx=\"0\" dy=\"2\" stdDeviation=\"2\" flood-color=\"#0f172a\" flood-opacity=\"0.65\"/></filter>"
    } else {
        ""
    };
    let fill = if o.magic_gradient {
        "url(#brush-gradient)".into()
    } else {
        esc(&o.color)
    };
    let filter = if o.shadow {
        " filter=\"url(#brush-shadow)\""
    } else {
        ""
    };
    let spacing = o.letter_spacing.unwrap_or((fs * 0.06).max(0.75));
    let reveal = clamp(o.reveal_progress, 0., 1.);
    Ok(format!("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"{}\" height=\"{}\" viewBox=\"0 0 {} {}\"><image width=\"{}\" height=\"{}\" preserveAspectRatio=\"xMidYMid slice\" href=\"data:{};base64,{}\"/><defs><path id=\"brush-path\" d=\"{}\"/>{}{}<mask id=\"brush-reveal\"><rect width=\"100%\" height=\"100%\" fill=\"black\"/><path d=\"{}\" pathLength=\"1\" fill=\"none\" stroke=\"white\" stroke-width=\"{}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-dasharray=\"1\" stroke-dashoffset=\"{}\"/></mask></defs><g mask=\"url(#brush-reveal)\" opacity=\"{}\"{}><text font-family=\"{}\" font-size=\"{}\" font-weight=\"{}\" letter-spacing=\"{}\" fill=\"{}\" stroke=\"{}\" stroke-width=\"{}\" paint-order=\"stroke fill\"><textPath href=\"#brush-path\" xlink:href=\"#brush-path\" startOffset=\"0\" spacing=\"exact\">{}</textPath></text></g></svg>\n",fmt(width),fmt(height),fmt(width),fmt(height),fmt(width),fmt(height),mime,base64(bytes),esc(&path.d),gradient,shadow,esc(&path.d),fmt(fs*2.4),fmt(1.-reveal),fmt(clamp(o.opacity,0.,1.)),filter,esc(&o.font_family),fmt(fs),esc(&o.font_weight),fmt(spacing),fill,esc(&o.stroke_color),fmt(o.stroke_width.max(0.)),esc(&repeat)))
}
