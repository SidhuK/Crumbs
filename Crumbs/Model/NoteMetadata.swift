//
//  NoteMetadata.swift
//  Crumbs
//

import Foundation

/// Where a captured crumb came from, read from the frontmost app at the moment of capture.
nonisolated struct CaptureSource: Hashable, Sendable, Codable {
    var app: String?
    var bundleID: String?
    /// The focused window's title, e.g. the page or document name.
    var title: String?
    /// The web page or document the selection came from, when the app exposes one.
    var url: URL?
    var capturedAt: Date

    init(app: String? = nil, bundleID: String? = nil, title: String? = nil, url: URL? = nil, capturedAt: Date) {
        self.app = app
        self.bundleID = bundleID
        self.title = title
        self.url = url
        self.capturedAt = capturedAt
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case bundleID = "bundle"
        case title
        case url
        case capturedAt = "at"
    }

    /// The site for web pages ("example.com"), the file name for documents.
    var place: String? {
        guard let url else { return nil }
        if url.isFileURL { return url.lastPathComponent }
        guard let host = url.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "Safari · example.com"
    var label: String? {
        let parts = [app, place].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func matches(_ query: String) -> Bool {
        [app, place].contains { $0?.localizedStandardContains(query) == true }
    }
}

/// When a note was created and last edited, and where it was captured from.
///
/// Stored in the list's Markdown file as a hidden comment on the note's last line,
/// so the note text stays clean and the file renders normally anywhere.
nonisolated struct NoteMetadata: Hashable, Sendable, Codable {
    var created: Date?
    /// The last time the note's text was edited in Crumbs.
    var modified: Date?
    var sources: [CaptureSource]

    init(created: Date? = nil, modified: Date? = nil, sources: [CaptureSource] = []) {
        self.created = created
        self.modified = modified
        self.sources = sources
    }

    var isEmpty: Bool { created == nil && modified == nil && sources.isEmpty }

    /// The current time, whole seconds only, so it survives a save and reload unchanged.
    static func now() -> Date {
        Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
    }

    /// Metadata for notes joined into one: every source, the earliest creation date.
    static func merged(_ parts: [NoteMetadata], at date: Date) -> NoteMetadata {
        var sources: [CaptureSource] = []
        for source in parts.flatMap(\.sources) where !sources.contains(source) {
            sources.append(source)
        }
        return NoteMetadata(created: parts.compactMap(\.created).min(), modified: date, sources: sources)
    }

    private enum CodingKeys: String, CodingKey {
        case created, modified, sources
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        created = try container.decodeIfPresent(Date.self, forKey: .created)
        modified = try container.decodeIfPresent(Date.self, forKey: .modified)
        sources = try container.decodeIfPresent([CaptureSource].self, forKey: .sources) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(created, forKey: .created)
        try container.encodeIfPresent(modified, forKey: .modified)
        if !sources.isEmpty {
            try container.encode(sources, forKey: .sources)
        }
    }
}

// MARK: - Markdown comment

nonisolated extension NoteMetadata {
    private static let commentPrefix = "<!-- crumb "
    private static let commentSuffix = " -->"

    /// `<!-- crumb {"created":"2026-10-14T12:41:00-04:00",…} -->`
    ///
    /// HTML comments can't contain "--", so it is escaped inside the JSON, where it can
    /// only appear in strings (a page title, say) and decodes back unchanged.
    var markdownComment: String? {
        guard !isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.timestampFormatter().string(from: date))
        }
        guard let data = try? encoder.encode(self), let json = String(data: data, encoding: .utf8) else { return nil }
        let escaped = json.replacingOccurrences(of: "--", with: "\\u002d\\u002d")
        return Self.commentPrefix + escaped + Self.commentSuffix
    }

    /// Parses a line written by `markdownComment`. Returns nil for anything else,
    /// including a comment that was edited into invalid JSON, which then stays in the note.
    init?(markdownComment line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(Self.commentPrefix), trimmed.hasSuffix(Self.commentSuffix),
              trimmed.count > Self.commentPrefix.count + Self.commentSuffix.count
        else { return nil }
        let json = trimmed.dropFirst(Self.commentPrefix.count).dropLast(Self.commentSuffix.count)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Self.timestampFormatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(string)")
            }
            return date
        }
        guard let metadata = try? decoder.decode(NoteMetadata.self, from: Data(json.utf8)), !metadata.isEmpty else {
            return nil
        }
        self = metadata
    }

    /// ISO 8601 in the local time zone, e.g. 2026-10-14T12:41:00-04:00, so the file reads naturally.
    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }
}
