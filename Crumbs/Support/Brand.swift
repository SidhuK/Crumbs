//
//  Brand.swift
//  Crumbs
//

import CoreText
import SwiftUI

enum Brand {
    static let name = "Crumbs"

    /// Geist Pixel ships inside the app bundle, so it renders even when the font isn't installed.
    static func wordmarkFont(size: CGFloat) -> Font {
        _ = registerFonts
        return .custom("GeistPixel-Regular", fixedSize: size)
    }

    /// The pixel asterisk from the app icon, as a template image for the menu bar.
    static let menuBarIcon: NSImage = {
        let rows = [
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

/// The app name set in Geist Pixel.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        Text(verbatim: Brand.name)
            .font(Brand.wordmarkFont(size: size))
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        Wordmark(size: 20)
        Wordmark(size: 32)
    }
    .padding()
}
#endif
