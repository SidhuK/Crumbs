// Converts text into SVG path data with CoreText, so icon artwork needs no font files.
//
// Usage: swift Scripts/text_paths.swift <font-name|system> <weight> <size> <text>...
// Prints JSON: [{"text", "d", "width", "capHeight", "bounds"}], one entry per text argument.
// Paths are in SVG coordinates (y grows downward) with the baseline at y = 0.

import AppKit
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count >= 5, let weight = Double(args[2]), let size = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: text_paths.swift <font|system> <weight> <size> <text>...\n".utf8))
    exit(1)
}

let font: NSFont
if args[1] == "system" {
    font = .systemFont(ofSize: size, weight: NSFont.Weight(rawValue: weight))
} else if let named = NSFont(name: args[1], size: size) {
    font = named
} else {
    FileHandle.standardError.write(Data("font not found: \(args[1])\n".utf8))
    exit(2)
}

func svgPath(_ path: CGPath) -> String {
    var d = ""
    func p(_ point: CGPoint) -> String { String(format: "%.2f,%.2f", point.x, -point.y) }
    path.applyWithBlock { element in
        let pts = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(p(pts[0]))"
        case .addLineToPoint: d += "L\(p(pts[0]))"
        case .addQuadCurveToPoint: d += "Q\(p(pts[0])) \(p(pts[1]))"
        case .addCurveToPoint: d += "C\(p(pts[0])) \(p(pts[1])) \(p(pts[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

var results: [[String: Any]] = []
for text in args[4...] {
    let attributed = NSAttributedString(string: text, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let combined = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
            combined.addPath(glyphPath, transform: CGAffineTransform(translationX: position.x, y: position.y))
        }
    }
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    let box = combined.boundingBoxOfPath
    results.append([
        "text": text, "d": svgPath(combined), "width": width, "capHeight": font.capHeight,
        // Ink bounds in SVG coordinates (y down, baseline at 0).
        "bounds": ["x": box.minX, "y": -box.maxY, "width": box.width, "height": box.height],
    ])
}

let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
