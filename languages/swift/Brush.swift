import Foundation
import CoreGraphics
import CoreText

public struct BrushPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct DrawingPath: Equatable, Sendable {
    public var points: [BrushPoint]
    public var d: String
    public var fontSize: Double
}

public struct PathSample: Equatable, Sendable {
    public let position: BrushPoint
    public let angle: Double
    public let progress: Double
}

public struct BrushStroke: Sendable {
    public var points: [BrushPoint]
    public var text: String
    public var fontSize: Double
    public var spacing: Double
    public init(points: [BrushPoint], text: String, fontSize: Double = 40, spacing: Double = 1) {
        self.points = points
        self.text = text
        self.fontSize = fontSize
        self.spacing = spacing
    }
}

public struct SVGRenderOptions: Sendable {
    public var fontSize: Double = 40
    public var fontFamily = "Arial, sans-serif"
    public var fontWeight = "700"
    public var letterSpacing: Double? = nil
    public var color = "#ffffff"
    public var magicGradient = false
    public var opacity: Double = 1
    public var strokeColor = "rgba(15,23,42,0.72)"
    public var strokeWidth: Double = 1.5
    public var shadow = true
    public var repeatText = true
    public var revealProgress: Double = 1
    public init() {}
}

public enum BrushGeometry {
    public static let minimumDrawingPointDistance = 3.0
    public static let straightDirectionToleranceDegrees = 18.0

    private static func finite(_ point: BrushPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard value.isFinite else { return low }
        return min(high, max(low, value))
    }
    private static func distance(_ a: BrushPoint, _ b: BrushPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }
    private static func pointAlong(_ from: BrushPoint, _ toward: BrushPoint, _ travel: Double) -> BrushPoint {
        let total = distance(from, toward)
        guard total > 0 else { return from }
        let t = min(1, travel / total)
        return BrushPoint(x: from.x + (toward.x - from.x) * t, y: from.y + (toward.y - from.y) * t)
    }
    private static func directionChange(_ first: BrushPoint, _ corner: BrushPoint, _ next: BrushPoint) -> Double {
        let ax = corner.x - first.x, ay = corner.y - first.y
        let bx = next.x - corner.x, by = next.y - corner.y
        let al = hypot(ax, ay), bl = hypot(bx, by)
        guard al > 0, bl > 0 else { return 0 }
        return acos(clamp((ax * bx + ay * by) / (al * bl), -1, 1)) * 180 / .pi
    }
    static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == 0 { return "0" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
    private static func pointString(_ point: BrushPoint) -> String { "\(format(point.x)) \(format(point.y))" }

    public static func buildRoundedDrawingPath(_ input: [BrushPoint], fontSize: Double) -> String {
        let points = input.filter(finite)
        guard let first = points.first else { return "" }
        guard points.count > 1 else { return "M \(pointString(first))" }
        var commands = ["M \(pointString(first))"]
        let preferredRadius = max(12, fontSize * 1.25)
        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let previous = points[index - 1], corner = points[index], next = points[index + 1]
                let trim = min(preferredRadius, distance(previous, corner) * 0.45, distance(corner, next) * 0.45)
                let entry = pointAlong(corner, previous, trim)
                let exit = pointAlong(corner, next, trim)
                commands.append("L \(pointString(entry)) Q \(pointString(corner)) \(pointString(exit))")
            }
        }
        commands.append("L \(pointString(points.last!))")
        return commands.joined(separator: " ")
    }

    public static func createDrawingPath(at point: BrushPoint, fontSize: Double = 40) -> DrawingPath {
        guard finite(point) else { return DrawingPath(points: [], d: "", fontSize: fontSize) }
        return DrawingPath(points: [point], d: "M \(pointString(point))", fontSize: fontSize)
    }

    public static func appendDrawingPoint(_ path: DrawingPath, point: BrushPoint) -> DrawingPath {
        guard finite(point), let last = path.points.last,
              distance(last, point) >= minimumDrawingPointDistance else { return path }
        var next = path.points
        if next.count == 1 {
            next.append(point)
        } else if directionChange(next[next.count - 2], last, point) < straightDirectionToleranceDegrees {
            next[next.count - 1] = point
        } else {
            next.append(point)
        }
        return DrawingPath(points: next, d: buildRoundedDrawingPath(next, fontSize: path.fontSize), fontSize: path.fontSize)
    }

    public static func finishDrawingPath(_ path: DrawingPath) -> DrawingPath? { path.points.count >= 2 ? path : nil }

    public static func drawingPath(from input: [BrushPoint], fontSize: Double = 40) -> DrawingPath? {
        let valid = input.filter(finite)
        guard let first = valid.first else { return nil }
        var result = createDrawingPath(at: first, fontSize: fontSize)
        for point in valid.dropFirst() { result = appendDrawingPoint(result, point: point) }
        return finishDrawingPath(result)
    }

    public static func stableRepeatedText(_ text: String, fontSize: Double) -> String {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return "" }
        let estimatedWidth = max(fontSize, Double(max(1, phrase.count)) * fontSize * 0.62)
        let repetitions = min(256, max(16, Int(ceil(20_000 / estimatedWidth))))
        return Array(repeating: phrase, count: repetitions).joined(separator: "   ")
    }
}

public struct ArcLengthPath: Sendable {
    struct Segment: Sendable { let start, end: BrushPoint; let startDistance, length: Double }
    public let points: [BrushPoint]
    let segments: [Segment]
    public let totalLength: Double

    public init(points input: [BrushPoint], minimumPointDistance: Double = 0.5) {
        let threshold = minimumPointDistance.isFinite ? max(0, minimumPointDistance) : 0.5
        let valid = input.filter { $0.x.isFinite && $0.y.isFinite }
        var filtered: [BrushPoint] = []
        for point in valid where filtered.last.map({ hypot(point.x - $0.x, point.y - $0.y) >= threshold }) ?? true {
            filtered.append(point)
        }
        if let last = valid.last, let retained = filtered.last,
           hypot(last.x - retained.x, last.y - retained.y) > 0 { filtered.append(last) }
        points = Self.simplify(filtered, tolerance: max(threshold * 0.5, 0.1))
        var built: [Segment] = []
        var cumulative = 0.0
        if points.count >= 2 {
            for index in 1..<points.count {
                let start = points[index - 1], end = points[index]
                let length = hypot(end.x - start.x, end.y - start.y)
                guard length.isFinite, length > 0 else { continue }
                built.append(Segment(start: start, end: end, startDistance: cumulative, length: length))
                cumulative += length
            }
        }
        segments = built
        totalLength = cumulative
    }

    func point(at requested: Double) -> BrushPoint {
        guard let first = segments.first, let last = segments.last else { return BrushPoint(x: 0, y: 0) }
        let distance = min(max(requested.isFinite ? requested : 0, 0), totalLength)
        if distance <= 0 { return first.start }
        if distance >= totalLength { return last.end }
        var low = 0, high = segments.count - 1
        while low < high {
            let middle = (low + high) / 2, segment = segments[middle]
            if distance > segment.startDistance + segment.length { low = middle + 1 } else { high = middle }
        }
        let segment = segments[low]
        let t = min(max((distance - segment.startDistance) / segment.length, 0), 1)
        return BrushPoint(x: segment.start.x + (segment.end.x - segment.start.x) * t,
                          y: segment.start.y + (segment.end.y - segment.start.y) * t)
    }

    public func sample(at progress: Double, fontSize: Double = 40) -> PathSample {
        let bounded = min(max(progress.isFinite ? progress : 0, 0), 1)
        guard totalLength > 0 else { return PathSample(position: BrushPoint(x: 0, y: 0), angle: 0, progress: bounded) }
        let target = totalLength * bounded
        let tangentSample = max(min(max(fontSize * 1.1, 0.75), totalLength * 0.06), 0.75)
        let before = point(at: target - tangentSample), after = point(at: target + tangentSample)
        return PathSample(position: point(at: target), angle: atan2(after.y - before.y, after.x - before.x), progress: bounded)
    }

    private static func simplify(_ points: [BrushPoint], tolerance: Double) -> [BrushPoint] {
        guard points.count > 2, tolerance > 0 else { return points }
        var retained = Array(repeating: false, count: points.count)
        retained[0] = true; retained[points.count - 1] = true
        var ranges = [(0, points.count - 1)]
        while let (first, last) = ranges.popLast() {
            guard last > first + 1 else { continue }
            var greatest = 0.0, greatestIndex: Int?
            for index in (first + 1)..<last {
                let value = perpendicularDistance(points[index], points[first], points[last])
                if value > greatest { greatest = value; greatestIndex = index }
            }
            if greatest > tolerance, let index = greatestIndex {
                retained[index] = true; ranges.append((first, index)); ranges.append((index, last))
            }
        }
        return zip(points, retained).compactMap { $1 ? $0 : nil }
    }

    private static func perpendicularDistance(_ point: BrushPoint, _ start: BrushPoint, _ end: BrushPoint) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y, squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / squared, 0), 1)
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }
}

public struct GlyphPlacement: Sendable {
    public let glyph: String
    public let position: BrushPoint
    public let angle, fontSize, advance, progress: Double
    public let glyphID: CGGlyph
    public let fontPostScriptName: String
}

/// Native Apple layout. The complete phrase is shaped before glyphs are placed,
/// preserving contextual Arabic, RTL visual order, Indic clusters, and fallback fonts.
public enum TextPathLayouter {
    private struct Span: Hashable { let range: Range<Int>; let text: String }
    private struct Raw {
        let glyphID: CGGlyph, x, y, advance: Double, stringIndex: Int, fontSize: Double
        let fontName: String, order: Int
    }
    private struct GroupGlyph { let source: String; let raw: Raw; let offset: Double }
    private struct Group { let glyphs: [GroupGlyph]; let naturalAdvance, effectiveAdvance, maxOffset: Double }

    public static func placements(for stroke: BrushStroke, repeats: Bool = true) -> [GlyphPlacement] {
        let phrase = stroke.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = ArcLengthPath(points: stroke.points)
        guard !phrase.isEmpty, stroke.fontSize.isFinite, stroke.fontSize > 0, path.totalLength > 0 else { return [] }
        let groups = shape(phrase + " ", fontSize: stroke.fontSize, spacing: stroke.spacing)
        guard !groups.isEmpty else { return [] }
        var result: [GlyphPlacement] = [], cursor = 0.0
        cycle: while result.count < 20_000 {
            for group in groups {
                let extent = max(group.effectiveAdvance, group.maxOffset)
                guard cursor + extent <= path.totalLength + 0.000_001,
                      result.count + group.glyphs.count <= 20_000 else { break cycle }
                for glyph in group.glyphs {
                    let baselineDistance = cursor + glyph.offset
                    let tangentSample = max(min(max(group.naturalAdvance * 1.1, glyph.raw.fontSize * 1.1), path.totalLength * 0.06), 0.75)
                    let before = path.point(at: baselineDistance - tangentSample)
                    let after = path.point(at: baselineDistance + tangentSample)
                    let angle = atan2(after.y - before.y, after.x - before.x)
                    let baseline = path.point(at: baselineDistance)
                    let position = BrushPoint(x: baseline.x + sin(angle) * glyph.raw.y,
                                              y: baseline.y - cos(angle) * glyph.raw.y)
                    result.append(GlyphPlacement(glyph: glyph.source, position: position, angle: angle,
                        fontSize: glyph.raw.fontSize, advance: glyph.raw.advance,
                        progress: baselineDistance / path.totalLength, glyphID: glyph.raw.glyphID,
                        fontPostScriptName: glyph.raw.fontName))
                }
                cursor += group.effectiveAdvance
            }
            if !repeats { break }
        }
        return result
    }

    private static func shape(_ text: String, fontSize: Double, spacing: Double) -> [Group] {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]))
        let spans = graphemeSpans(text), utf16Count = text.utf16.count
        guard !spans.isEmpty, utf16Count > 0 else { return [] }
        var raw: [Raw] = [], order = 0
        for case let run as CTRun in CTLineGetGlyphRuns(line) as NSArray {
            let count = CTRunGetGlyphCount(run); guard count > 0 else { continue }
            guard let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont? else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs); CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetAdvances(run, CFRange(), &advances); CTRunGetStringIndices(run, CFRange(), &indices)
            for index in 0..<count where positions[index].x.isFinite && positions[index].y.isFinite {
                raw.append(Raw(glyphID: glyphs[index], x: positions[index].x, y: positions[index].y,
                    advance: advances[index].width.isFinite ? advances[index].width : 0,
                    stringIndex: min(max(indices[index], 0), utf16Count - 1), fontSize: CTFontGetSize(runFont),
                    fontName: CTFontCopyPostScriptName(runFont) as String, order: order))
                order += 1
            }
        }
        guard !raw.isEmpty else { return [] }
        let boundaries = Array(Set(raw.map(\.stringIndex) + [utf16Count])).sorted()
        let mapped: [(Span, Raw)] = raw.compactMap { item in
            let end = boundaries.first(where: { $0 > item.stringIndex }) ?? utf16Count
            return span(covering: item.stringIndex..<max(end, item.stringIndex + 1), spans: spans).map { ($0, item) }
        }.sorted { $0.1.x == $1.1.x ? $0.1.order < $1.1.order : $0.1.x < $1.1.x }
        var grouped: [(Span, [Raw])] = []
        for (spanValue, item) in mapped {
            if let index = grouped.firstIndex(where: { $0.0 == spanValue }) { grouped[index].1.append(item) }
            else { grouped.append((spanValue, [item])) }
        }
        grouped.sort { ($0.1.map(\.x).min() ?? 0) < ($1.1.map(\.x).min() ?? 0) }
        let minX = raw.map(\.x).min() ?? 0
        let glyphMax = raw.map { $0.x + max(0, $0.advance) }.max() ?? minX
        let typeWidth = Double(CTLineGetTypographicBounds(line, nil, nil, nil))
        let lineMax = max(glyphMax, minX + max(typeWidth.isFinite ? typeWidth : 0, 0))
        let safeSpacing = spacing.isFinite ? max(spacing, 0) : 1, minimum = fontSize * 0.05
        return grouped.enumerated().map { index, value in
            let start = value.1.map(\.x).min() ?? 0
            let next = index + 1 < grouped.count ? (grouped[index + 1].1.map(\.x).min() ?? lineMax) : lineMax
            let fallback = value.1.reduce(0) { $0 + max($1.advance, 0) }
            let measured = next - start
            let natural = measured.isFinite && measured > 0 ? measured : max(fallback, minimum)
            let glyphs = value.1.sorted { $0.x == $1.x ? $0.order < $1.order : $0.x < $1.x }.map {
                GroupGlyph(source: value.0.text, raw: $0, offset: max($0.x - start, 0))
            }
            return Group(glyphs: glyphs, naturalAdvance: natural,
                         effectiveAdvance: max(natural * safeSpacing, minimum), maxOffset: glyphs.map(\.offset).max() ?? 0)
        }
    }

    private static func graphemeSpans(_ text: String) -> [Span] {
        var result: [Span] = [], offset = 0
        for character in text { let value = String(character), next = offset + value.utf16.count
            result.append(Span(range: offset..<next, text: value)); offset = next }
        return result
    }
    private static func span(covering range: Range<Int>, spans: [Span]) -> Span? {
        guard let first = spans.firstIndex(where: { $0.range.contains(range.lowerBound) }) else { return nil }
        let finalIndex = max(range.upperBound - 1, range.lowerBound)
        let last = spans.lastIndex(where: { $0.range.contains(finalIndex) }) ?? first
        let selected = spans[first...last]
        return Span(range: selected.first!.range.lowerBound..<selected.last!.range.upperBound,
                    text: selected.map(\.text).joined())
    }
}

public enum BrushSVGRenderer {
    private static let allowedMIMEs = ["image/png", "image/jpeg", "image/webp", "image/gif", "image/avif"]
    private static func clamp(_ value: Double) -> Double { min(max(value.isFinite ? value : 0, 0), 1) }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    public static func render(imageData: Data, mimeType: String, width: Double, height: Double,
                              points: [BrushPoint], text: String,
                              options: SVGRenderOptions = SVGRenderOptions()) throws -> String {
        guard allowedMIMEs.contains(mimeType) else { throw NSError(domain: "BrushSVG", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported image MIME type"]) }
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw NSError(domain: "BrushSVG", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid image dimensions"]) }
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontSize = options.fontSize.isFinite && options.fontSize > 0 ? options.fontSize : 40
        guard !phrase.isEmpty, let path = BrushGeometry.drawingPath(from: points, fontSize: fontSize) else {
            throw NSError(domain: "BrushSVG", code: 3, userInfo: [NSLocalizedDescriptionKey: "Text and at least two points are required"])
        }
        let f = BrushGeometry.format
        let spacing = options.letterSpacing ?? max(0.75, fontSize * 0.06)
        let repeated = options.repeatText ? BrushGeometry.stableRepeatedText(phrase, fontSize: fontSize) : phrase
        let gradient = options.magicGradient ? "<linearGradient id=\"brush-gradient\" x1=\"100\" y1=\"150\" x2=\"900\" y2=\"850\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0%\" stop-color=\"#ec4899\"/><stop offset=\"20%\" stop-color=\"#f97316\"/><stop offset=\"40%\" stop-color=\"#facc15\"/><stop offset=\"60%\" stop-color=\"#10b981\"/><stop offset=\"80%\" stop-color=\"#3b82f6\"/><stop offset=\"100%\" stop-color=\"#8b5cf6\"/></linearGradient>" : ""
        let shadow = options.shadow ? "<filter id=\"brush-shadow\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\"><feDropShadow dx=\"0\" dy=\"2\" stdDeviation=\"2\" flood-color=\"#0f172a\" flood-opacity=\"0.65\"/></filter>" : ""
        let fill = options.magicGradient ? "url(#brush-gradient)" : escape(options.color)
        let filter = options.shadow ? " filter=\"url(#brush-shadow)\"" : ""
        let reveal = clamp(options.revealProgress)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(f(width))" height="\(f(height))" viewBox="0 0 \(f(width)) \(f(height))">
          <image width="\(f(width))" height="\(f(height))" preserveAspectRatio="xMidYMid slice" href="data:\(mimeType);base64,\(imageData.base64EncodedString())"/>
          <defs><path id="brush-path" d="\(escape(path.d))"/>\(gradient)\(shadow)<mask id="brush-reveal" x="0" y="0" width="\(f(width))" height="\(f(height))" maskUnits="userSpaceOnUse"><rect width="100%" height="100%" fill="black"/><path d="\(escape(path.d))" pathLength="1" fill="none" stroke="white" stroke-width="\(f(fontSize * 2.4))" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="1" stroke-dashoffset="\(f(1 - reveal))"/></mask></defs>
          <g mask="url(#brush-reveal)" opacity="\(f(clamp(options.opacity)))"\(filter)><text font-family="\(escape(options.fontFamily))" font-size="\(f(fontSize))" font-weight="\(escape(options.fontWeight))" letter-spacing="\(f(spacing))" fill="\(fill)" stroke="\(escape(options.strokeColor))" stroke-width="\(f(max(0, options.strokeWidth)))" paint-order="stroke fill"><textPath href="#brush-path" xlink:href="#brush-path" startOffset="0" spacing="exact">\(escape(repeated))</textPath></text></g>
        </svg>

        """
    }
}
