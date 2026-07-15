import Foundation

@main
enum Example {
    static let points = [
        BrushPoint(x: 500, y: 520), BrushPoint(x: 450, y: 450), BrushPoint(x: 390, y: 395),
        BrushPoint(x: 320, y: 370), BrushPoint(x: 250, y: 370), BrushPoint(x: 180, y: 390),
        BrushPoint(x: 130, y: 450), BrushPoint(x: 120, y: 520), BrushPoint(x: 155, y: 585),
        BrushPoint(x: 220, y: 635), BrushPoint(x: 300, y: 650), BrushPoint(x: 380, y: 620),
        BrushPoint(x: 440, y: 570), BrushPoint(x: 500, y: 520), BrushPoint(x: 560, y: 465),
        BrushPoint(x: 620, y: 410), BrushPoint(x: 700, y: 370), BrushPoint(x: 770, y: 380),
        BrushPoint(x: 830, y: 420), BrushPoint(x: 870, y: 480), BrushPoint(x: 875, y: 545),
        BrushPoint(x: 845, y: 610), BrushPoint(x: 790, y: 660), BrushPoint(x: 720, y: 675),
        BrushPoint(x: 650, y: 655), BrushPoint(x: 585, y: 610), BrushPoint(x: 540, y: 560),
        BrushPoint(x: 500, y: 520),
    ]

    static func main() throws {
        let rightAngle = BrushGeometry.buildRoundedDrawingPath([
            BrushPoint(x: 0, y: 0), BrushPoint(x: 100, y: 0), BrushPoint(x: 100, y: 100)
        ], fontSize: 40)
        precondition(rightAngle == "M 0 0 L 55 0 Q 100 0 100 45 L 100 100")
        let horizontal = ArcLengthPath(points: [BrushPoint(x: 0, y: 0), BrushPoint(x: 100, y: 0)])
        let vertical = ArcLengthPath(points: [BrushPoint(x: 0, y: 0), BrushPoint(x: 0, y: 100)])
        precondition(horizontal.sample(at: 0.5).angle == 0)
        precondition(abs(vertical.sample(at: 0.5).angle - .pi / 2) < 0.000_001)
        let input = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/example.webp"
        let output = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "generated/swift.svg"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
        var options = SVGRenderOptions(); options.magicGradient = true
        let svg = try BrushSVGRenderer.render(imageData: Data(contentsOf: URL(fileURLWithPath: input)),
            mimeType: "image/webp", width: 1000, height: 1000, points: points,
            text: "🤝 best friends forever", options: options)
        precondition(svg.contains("data:image/webp;base64,")); precondition(svg.contains("🤝 best friends forever"))
        try svg.write(toFile: output, atomically: true, encoding: .utf8)
        print("Wrote \(output)")
    }
}
