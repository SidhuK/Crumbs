# Crumbs

Crumbs is a menu bar app for macOS that saves the bits of text you'll need later. Select text in any app, tap Shift twice, and the selection lands in a floating panel on the side of your screen. When you're ready to use your notes, select a few and press ⇧⌘C. They go to the clipboard as a numbered list you can paste straight into a chat.

The notes are plain Markdown files on your disk. There's no account and no sync service, and nothing leaves your Mac.

## Requirements

- macOS 27 or later
- Xcode 27 to build
- Accessibility access, granted on first launch (see [Permissions](#permissions))

## Building

Open `Crumbs.xcodeproj` and run the Crumbs scheme, or build from the command line:

```bash
xcodebuild -project Crumbs.xcodeproj -scheme Crumbs -configuration Release build
```

The app runs from the menu bar and has no Dock icon. The panel shows up on the right edge of the main screen.

## Using it

Select text anywhere and tap Shift twice. A "Captured" pill appears next to the pointer and the note shows up in the panel. Bold, italics, inline code, links and lists from the source are kept as Markdown. Your clipboard is put back the way it was.

You can also type into the box at the bottom of the panel, or paste with ⌘V.

Notes live in sections. New notes go to the section marked with a dot, which is the last one unless you click another header. Drag notes to reorder them, or use the context menu to move them between sections.

### Keyboard

Everywhere:

| Shortcut | Action |
| --- | --- |
| Shift, Shift | Capture the selection (configurable: Shift, Command, Option or Control) |
| ⌃⌥C | Show or hide the panel (configurable) |

In the panel:

| Shortcut | Action |
| --- | --- |
| ↑ ↓, ⇧↑ ⇧↓ | Move or extend the selection |
| Space | Mark as done |
| ↩ | Edit inline |
| ⌘↩ | Edit in a separate window |
| ⌘C | Copy |
| ⇧⌘C | Copy as a numbered list, and mark those notes done |
| ⇧⌘M | Merge the selected notes |
| ⌥⌘↑ ⌥⌘↓ | Move notes up or down |
| → ← | Expand or collapse a long note |
| ⌫ | Delete |
| ⌘V | Paste the clipboard as a new note |
| ⌘N | Focus the note box |
| ⌘F | Search |
| ⌘Z, ⇧⌘Z | Undo, redo |
| Esc | Back out one step, then hide the panel |

## Storage

Each list is one Markdown file in `~/Library/Application Support/Crumbs/`. You can pick another folder in Settings › Storage. A list looks like this:

```markdown
## Research

- [ ] **Negation in inherited configs.** The moment a config can extend a base…
- [x] Three things worth locking down before it ships:
  1. A `version` field on the format.
  2. An effective-config command.
```

Headings are sections and task items are notes. Lines indented by two spaces belong to the note above. You can edit these files in any editor while Crumbs is running and it picks up the changes. If a file changes on disk while Crumbs has unsaved edits, Crumbs writes the other version to `<list> (Conflict <date>).md` before saving its own, so neither copy is lost. If a file can't be read, Crumbs leaves it alone and tells you, instead of saving an empty list over it.

## Permissions

Crumbs needs Accessibility access, under System Settings › Privacy & Security › Accessibility. It uses it for two things: to notice the double tap while another app is in front, and to send that app a Copy command so it can read your selection.

That's also why the app isn't sandboxed. A sandboxed app can't watch keys across the system or copy from other apps. Hardened Runtime is on, so it can be notarized for distribution outside the App Store.

## How it's put together

| Folder | What's in it |
| --- | --- |
| `Crumbs/Capture` | The double-tap detector, global hot keys (Carbon), the copy-and-restore capture, and rich text to Markdown conversion |
| `Crumbs/Model` | Notes and sections, the Markdown reader and writer, the store (undo, debounced saves, conflict copies), and the file watcher |
| `Crumbs/Panel` | The floating `NSPanel`, the keyboard router, the "Captured" HUD, and `PanelModel`, which holds selection, editing and focus |
| `Crumbs/Views` | SwiftUI for the panel: header, note rows, sections, the note box, and the editor window |
| `Crumbs/Settings` | Preferences and the Settings window (toolbar panes built on `NSTabViewController`) |

A few choices worth knowing about:

- The panel is a non-activating `NSPanel`. It takes keyboard input without pulling the app you're reading out of the foreground.
- Panel shortcuts go through an `NSEvent` monitor rather than SwiftUI, so ⌘F and ⌘N work even while a text field has focus.
- Settings uses `NSTabViewController` instead of SwiftUI's `Settings` scene, because a menu bar app can't open that scene reliably.

The project uses Swift 6 with main-actor default isolation.

## Tests

```bash
xcodebuild -project Crumbs.xcodeproj -scheme Crumbs test
```

The unit tests use Swift Testing. They cover the Markdown format, rich text conversion, the store's save, conflict and undo rules, panel selection and editing, and the double-tap detector. Each test gets its own temporary folder, defaults and pasteboard, so nothing touches your real notes. The UI test launches the app with `-uiTesting`, which skips the global hot key and key monitors, adds a note through the panel, and checks that it reaches the Markdown file.

## App icon

The icon is `Crumbs/AppIcon.icon`, an Icon Composer document. It sets "CR / UM / BS*" in [Geist Pixel](https://github.com/vercel/geist-pixel-font) on a yellow gradient. `Scripts/make_app_icon.py` generated the first version, using `Scripts/text_paths.swift` to turn the letters into vector paths. The icon has been adjusted by hand in Icon Composer since then, and running the script again would undo those adjustments. Make further changes in Icon Composer.
