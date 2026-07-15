mod brush;
use brush::*;
use std::{env, fs, path::Path};
fn main() {
    let p = |x, y| Point { x, y };
    let points = vec![
        p(500., 520.),
        p(450., 450.),
        p(390., 395.),
        p(320., 370.),
        p(250., 370.),
        p(180., 390.),
        p(130., 450.),
        p(120., 520.),
        p(155., 585.),
        p(220., 635.),
        p(300., 650.),
        p(380., 620.),
        p(440., 570.),
        p(500., 520.),
        p(560., 465.),
        p(620., 410.),
        p(700., 370.),
        p(770., 380.),
        p(830., 420.),
        p(870., 480.),
        p(875., 545.),
        p(845., 610.),
        p(790., 660.),
        p(720., 675.),
        p(650., 655.),
        p(585., 610.),
        p(540., 560.),
        p(500., 520.),
    ];
    assert_eq!(
        build_rounded_drawing_path(&[p(0., 0.), p(100., 0.), p(100., 100.)], 40.),
        "M 0 0 L 55 0 Q 100 0 100 45 L 100 100"
    );
    assert_eq!(
        sample_at(
            &prepare_arc_length_path(&[p(0., 0.), p(100., 0.)], 0.5),
            0.5,
            40.
        )
        .angle,
        0.
    );
    let args: Vec<_> = env::args().collect();
    let input = args
        .get(1)
        .map(String::as_str)
        .unwrap_or("assets/example.webp");
    let output = args
        .get(2)
        .map(String::as_str)
        .unwrap_or("generated/rust.svg");
    let mut o = Options::default();
    o.magic_gradient = true;
    let svg = render_svg(
        &fs::read(input).unwrap(),
        "image/webp",
        1000.,
        1000.,
        &points,
        "🤝 best friends forever",
        &o,
    )
    .unwrap();
    fs::create_dir_all(Path::new(output).parent().unwrap()).unwrap();
    fs::write(output, svg).unwrap();
    println!("Wrote {output}");
}
