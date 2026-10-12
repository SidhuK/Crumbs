//
//  RichTextMarkdown.swift
//  Crumbs
//

import AppKit

/// Converts copied rich text into compact Markdown so emphasis, inline code,
/// links and lists survive the trip into a note.
nonisolated enum RichTextMarkdown {

    /// The pasteboard flavors the converter understands, read out up front.
    struct Clipping: Sendable {
        var plain: String?
        var rtf: Data?
        var html: Data?

        @MainActor
        init(_ pasteboard: NSPasteboard) {
            plain = pasteboard.string(forType: .string)
            rtf = pasteboard.data(forType: .rtf)
            html = pasteboard.data(forType: .html)
        }
    }

    /// Converts already-read pasteboard flavors, so the pasteboard can be restored first.
    @MainActor
    static func markdown(from clipping: Clipping) -> String? {
        let plain = clipping.plain.map(normalizePlainText)

        var attributed: NSAttributedString?
        if let rtf = clipping.rtf {
            attributed = NSAttributedString(rtf: rtf, documentAttributes: nil)
        }
        if attributed == nil, let html = clipping.html {
            // HTML import uses WebKit and must run on the main thread.
            attributed = try? NSAttributedString(
                data: html,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
        }

        if let attributed, let converted = markdown(from: attributed), !converted.isEmpty {
            return converted
        }
        return plain.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Returns nil when the text is entirely monospaced (code, terminal output),
    /// where Markdown decoration would only add noise.
    static func markdown(from attributed: NSAttributedString) -> String? {
        let string = attributed.string as NSString
        guard string.length > 0 else { return nil }

        var paragraphs: [String] = []
        var sawProportionalText = false

        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, _, _ in
            let raw = string.substring(with: paragraphRange)
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
                paragraphs.append("")
                return
            }

            var contentRange = paragraphRange
            var prefix = ""
            let depth = listDepth(in: attributed, at: paragraphRange.location)

            if let marker = listMarker(in: raw) {
                contentRange = NSRange(
                    location: paragraphRange.location + marker.length,
                    length: paragraphRange.length - marker.length
                )
                let indent = String(repeating: "  ", count: max(0, depth - 1))
                // Keep the number as written, so "5." stays 5 and "2024." isn't renumbered.
                if let number = marker.number {
                    prefix = "\(indent)\(number). "
                } else {
                    prefix = "\(indent)- "
                }
            }

            let (inline, proportional) = inlineMarkdown(attributed, in: contentRange)
            if proportional { sawProportionalText = true }
            paragraphs.append(prefix + inline)
        }

        guard sawProportionalText else { return nil }
        return collapseBlankLines(paragraphs)
    }

    // MARK: - Inline runs

    private struct RunStyle: Equatable {
        var bold = false
        var italic = false
        var code = false
        var strikethrough = false
        var link: URL?
    }

    private static func inlineMarkdown(_ attributed: NSAttributedString, in range: NSRange) -> (String, Bool) {
        let string = attributed.string as NSString
        var runs: [(text: String, style: RunStyle)] = []
        var proportional = false

        attributed.enumerateAttributes(in: range) { attributes, runRange, _ in
            let text = string.substring(with: runRange)
            let style = style(for: attributes)
            if !style.code, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                proportional = true
            }
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += text
            } else {
                runs.append((text, style))
            }
        }

        let text = runs.map { render($0.text, style: $0.style) }.joined()
        return (normalizePlainText(text), proportional)
    }

    private static func style(for attributes: [NSAttributedString.Key: Any]) -> RunStyle {
        var style = RunStyle()
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            style.code = traits.contains(.monoSpace)
            style.italic = traits.contains(.italic)
            style.bold = traits.contains(.bold)
            if !style.bold,
               let traitInfo = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
               let weight = traitInfo[.weight] as? CGFloat {
                style.bold = weight >= NSFont.Weight.semibold.rawValue
            }
        }
        if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
            style.strikethrough = true
        }
        if let url = attributes[.link] as? URL {
            style.link = url
        } else if let string = attributes[.link] as? String {
            style.link = URL(string: string)
        }
        if let scheme = style.link?.scheme?.lowercased(), !["http", "https", "mailto"].contains(scheme) {
            style.link = nil
        }
        return style
    }

    private static func render(_ text: String, style: RunStyle) -> String {
        let leading = String(text.prefix { $0.isWhitespace })
        let trailing = String(text.reversed().prefix { $0.isWhitespace }.reversed())
        let coreStart = text.index(text.startIndex, offsetBy: leading.count)
        let coreEnd = text.index(text.endIndex, offsetBy: -trailing.count, limitedBy: coreStart) ?? coreStart
        let core = String(text[coreStart..<coreEnd])
        guard !core.isEmpty else { return text }

        var result: String
        if style.code {
            let fence = core.contains("`") ? "``" : "`"
            result = fence + core + fence
        } else {
            result = escape(core)
            if style.bold && style.italic {
                result = "***\(result)***"
            } else if style.bold {
                result = "**\(result)**"
            } else if style.italic {
                result = "*\(result)*"
            }
            if style.strikethrough { result = "~~\(result)~~" }
        }

        if let link = style.link {
            if link.absoluteString == core {
                result = link.absoluteString
            } else {
                // Brackets inside link text would end the link early.
                let text = result.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                result = "[\(text)](\(link.absoluteString))"
            }
        }
        return leading + result + trailing
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if character == "\\" || character == "*" || character == "`" {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    // MARK: - Lists

    private struct ListMarker {
        var length: Int
        /// The item number for ordered lists, nil for bullets.
        var number: Int?
    }

    private static let bulletCharacters: Set<Character> = ["•", "◦", "▪", "▫", "‣", "⁃", "●", "○", "■", "□", "–", "-", "*"]

    /// Detects list markers such as "\t•\t" or "1.\t" that rich-text import leaves in the text.
    private static func listMarker(in paragraph: String) -> ListMarker? {
        let scalars = Array(paragraph)
        var index = 0
        while index < scalars.count, scalars[index] == "\t" || scalars[index] == " " { index += 1 }
        guard index < scalars.count else { return nil }

        var number: Int?
        if bulletCharacters.contains(scalars[index]) {
            index += 1
        } else if scalars[index].isNumber {
            let digitsStart = index
            while index < scalars.count, scalars[index].isNumber { index += 1 }
            number = Int(String(scalars[digitsStart..<index]))
            guard index < scalars.count else { return nil }
            if scalars[index] == "." || scalars[index] == ")" {
                index += 1
            } else if scalars[index] != "\t" {
                // HTML import writes "\t1\t"; anything else after a bare number is just text.
                return nil
            }
        } else {
            return nil
        }

        // Rich-text lists separate the marker with a tab; plain "-" or "1." needs a space.
        guard index < scalars.count, scalars[index] == "\t" || scalars[index] == " " else { return nil }
        while index < scalars.count, scalars[index] == "\t" || scalars[index] == " " { index += 1 }

        let length = String(scalars[0..<index]).utf16.count
        return ListMarker(length: length, number: number)
    }

    private static func listDepth(in attributed: NSAttributedString, at location: Int) -> Int {
        guard location < attributed.length,
              let style = attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        else { return 1 }
        return max(1, style.textLists.count)
    }

    // MARK: - Cleanup

    static func normalizePlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseBlankLines(_ lines: [String]) -> String {
        var result: [String] = []
        for line in lines {
            let trimmed = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if trimmed.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(trimmed)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }
}
