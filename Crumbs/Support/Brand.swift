//
//  Brand.swift
//  Crumbs
//

import CoreText
import SwiftUI

enum Brand {
    static let name = "Crumbs"

    /// Amber from the app icon. The light variant is darker so 2 pt selection outlines keep
    /// at least 3:1 contrast against the white note cards.
    static let accent = Color(nsColor: NSColor(name: "CrumbsAccent") { @Sendable appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.70, blue: 0.12, alpha: 1)
            : NSColor(srgbRed: 0.85, green: 0.43, blue: 0.00, alpha: 1)
    })

    /// Geist Pixel ships inside the app bundle, so it renders even when the font isn't installed.
    static func wordmarkFont(size: CGFloat) -> Font {
        _ = registerFonts
        return .custom("GeistPixel-Regular", fixedSize: size)
    }

    /// The asterisk from the app icon, one string per row, `X` for a filled cell.
    nonisolated static let asteriskPixels = [
        ".XX...XX.",
        ".XX...XX.",
        "..XX.XX..",
        "...XXX...",
        "XXXXXXXXX",
        "...XXX...",
        "..XX.XX..",
        ".XX...XX.",
        ".XX...XX.",
    ]

    /// The pixel asterisk as a template image for the menu bar.
    static let menuBarIcon: NSImage = {
        let rows = asteriskPixels
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            // Snap cells to whole device pixels so the pixel art stays sharp: 3 px cells on Retina, 2 px on 1x.
            let scale = abs(NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2)
            let cell = (1.5 * scale).rounded() / scale
            let side = cell * CGFloat(rows.count)
            let origin = ((rect.width - side) / 2 * scale).rounded(.down) / scale
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "X" {
                    NSRect(x: origin + CGFloat(x) * cell, y: origin + CGFloat(y) * cell, width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }()

    private static let registerFonts: Void = {
        guard let url = Bundle.main.url(forResource: "GeistPixel", withExtension: "ttf") else { return }
        // Fails harmlessly with "already registered" when the user has the font installed too.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
}

/// The app icon's pixel asterisk, scaled to fill the frame it's given.
nonisolated struct PixelAsterisk: Shape {
    func path(in rect: CGRect) -> Path {
        let rows = Brand.asteriskPixels
        let cell = min(rect.width, rect.height) / CGFloat(rows.count)
        let origin = CGPoint(
            x: rect.midX - cell * CGFloat(rows.count) / 2,
            y: rect.midY - cell * CGFloat(rows.count) / 2
        )
        var path = Path()
        for (y, row) in rows.enumerated() {
            for (x, pixel) in row.enumerated() where pixel == "X" {
                path.addRect(CGRect(
                    x: origin.x + CGFloat(x) * cell,
                    y: origin.y + CGFloat(y) * cell,
                    width: cell,
                    height: cell
                ))
            }
        }
        return path
    }
}

/// "Crumbs" in Geist Pixel, with the icon's asterisk tucked in after it like "BS*" on the app icon.
struct Wordmark: View {
    var size: CGFloat = 20
    /// Each change spins the asterisk a quarter turn.
    var spinCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Cells in half-point steps land on whole Retina pixels, so the asterisk stays crisp.
        let cell = max(0.5, (size * 0.42 / 9 * 2).rounded() / 2)

        HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
            Text(verbatim: Brand.name)
                .font(Brand.wordmarkFont(size: size))
            PixelAsterisk()
                .fill(Brand.accent)
                .frame(width: cell * 9, height: cell * 9)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(spinCount) * 90))
                .animation(.spring(duration: 0.5, bounce: 0.4), value: spinCount)
                // Sit on the cap line, like a footnote mark.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + size * 0.3 }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Wordmark") {
    VStack(alignment: .leading, spacing: 12) {
        Wordmark(size: 20)
        Wordmark(size: 32)
        PixelAsterisk()
            .fill(Brand.accent)
            .frame(width: 48, height: 48)
    }
    .padding()
}
#endif
