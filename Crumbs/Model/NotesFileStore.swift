//
//  NotesFileStore.swift
//  Crumbs
//

import Foundation

/// Reads and writes one Markdown file per list inside a folder, and reports
/// edits made by other apps.
final class NotesFileStore {
    static let fileExtension = "md"

    private(set) var folder: URL
    var onChange: () -> Void = {}

    /// The list whose file is watched directly, in addition to the folder.
    private var watchedList: String?
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?

    init(folder: URL) {
        self.folder = folder
    }

    isolated deinit {
        folderWatcher?.cancel()
        fileWatcher?.cancel()
    }

    func setFolder(_ newFolder: URL) {
        folder = newFolder
        startWatching()
    }

    func fileURL(for list: String) -> URL {
        folder.appending(path: "\(list).\(Self.fileExtension)", directoryHint: .notDirectory)
    }

    func listNames() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == Self.fileExtension }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The list's contents, or nil when the file doesn't exist. Throws when the file
    /// exists but can't be read, so callers never mistake it for an empty list.
    func read(list: String) throws -> String? {
        let url = fileURL(for: list)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        // Not UTF-8 (UTF-16 with a BOM, or a legacy encoding): let Foundation detect it.
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    func write(_ text: String, list: String) throws {
        try ensureFolderExists()
        try Data(text.utf8).write(to: fileURL(for: list), options: .atomic)
    }

    /// Creates an empty list, failing if a file with that name (in any letter case) exists.
    func create(list: String) throws {
        try ensureFolderExists()
        try Data().write(to: fileURL(for: list), options: .withoutOverwriting)
    }

    /// Saves `text` next to the list as "<list> (Conflict <date>).md" and returns its name.
    func writeConflictCopy(_ text: String, of list: String) throws -> String {
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let name = "\(list) (Conflict \(stamp))"
        try ensureFolderExists()
        try Data(text.utf8).write(to: fileURL(for: name), options: .withoutOverwriting)
        return name
    }

    func rename(list: String, to newName: String) throws {
        try FileManager.default.moveItem(at: fileURL(for: list), to: fileURL(for: newName))
    }

    /// Moves the list to the Trash so it can be recovered.
    func trash(list: String) throws {
        try FileManager.default.trashItem(at: fileURL(for: list), resultingItemURL: nil)
    }

    func ensureFolderExists() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: - Watching

    /// Watches the folder (atomic saves, new or deleted lists) and the given list's file
    /// (in-place edits and appends, which don't touch the folder).
    func startWatching(list: String? = nil) {
        if let list { watchedList = list }
        try? ensureFolderExists()
        folderWatcher?.cancel()
        folderWatcher = makeWatcher(path: folder.path(percentEncoded: false), events: [.write, .rename, .delete]) {
            [weak self] events in
            // The descriptor follows the old folder after a rename or delete; watch the path again.
            if !events.isDisjoint(with: [.rename, .delete]) { self?.startWatching() }
            self?.watchFile()
            self?.onChange()
        }
        watchFile()
    }

    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
        guard let watchedList else { return }
        fileWatcher = makeWatcher(
            path: fileURL(for: watchedList).path(percentEncoded: false),
            events: [.write, .extend, .rename, .delete]
        ) { [weak self] events in
            // Atomic saves replace the file, so re-open it by path.
            if !events.isDisjoint(with: [.rename, .delete]) { self?.watchFile() }
            self?.onChange()
        }
    }

    private func makeWatcher(
        path: String,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak source] in
            handler(source?.data ?? [])
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }
}
