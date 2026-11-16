//
//  MainWindowSupport.swift
//  mattermost.client
//
//  Shared view helpers and the emoji catalog used by the MainWindow components.
//

import Cocoa
import ImageIO
import UniformTypeIdentifiers

class TimelineFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Bounded, evicting image cache for avatars, emoji, and thumbnails.
@MainActor
final class BoundedImageCache {
    private let cache = NSCache<NSString, NSImage>()

    var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }

    var totalCostLimit: Int {
        get { cache.totalCostLimit }
        set { cache.totalCostLimit = newValue }
    }

    init(countLimit: Int = 300, totalCostLimit: Int = 64 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    subscript(_ key: String) -> NSImage? {
        get { cache.object(forKey: key as NSString) }
        set {
            guard let newValue = newValue else {
                cache.removeObject(forKey: key as NSString)
                return
            }
            let size = newValue.size
            let cost = max(1, Int(size.width * size.height * 4))
            cache.setObject(newValue, forKey: key as NSString, cost: cost)
        }
    }

    func removeValue(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Bounded cache for natural image/attachment sizes.
@MainActor
final class BoundedSizeCache {
    private let cache = NSCache<NSString, NSValue>()

    var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }

    init(countLimit: Int = 500) {
        cache.countLimit = countLimit
    }

    subscript(_ key: String) -> NSSize? {
        get { cache.object(forKey: key as NSString)?.sizeValue }
        set {
            guard let newValue = newValue else {
                cache.removeObject(forKey: key as NSString)
                return
            }
            cache.setObject(NSValue(size: newValue), forKey: key as NSString)
        }
    }

    func removeValue(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

class TimelineRowView: RoundedEdgePanel {
    override var isFlipped: Bool { true }
    /// Add-reaction chip revealed while the row is hovered.
    var reactionAddChip: NSView?
}

/// Draggable divider on the left edge of the right-hand panel.
class RightPanelResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var isHovering = false {
        didSet { needsDisplay = true }
    }
    var trackingArea: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            Theme.shared.buttonBg.withAlphaComponent(0.25).setFill()
            NSRect(x: 2, y: 0, width: 1.5, height: bounds.height).fill()
        }
    }
}

/// Rounded panel with a top-down coordinate system, used for file cards.
class FlippedEdgePanel: RoundedEdgePanel {
    override var isFlipped: Bool { true }
}

/// Draws the blue file-sheet thumbnail shown on attachment cards.
class FileTypeIconView: NSView {
    var fileExtension: String = ""

    override func draw(_ dirtyRect: NSRect) {
        let blue = Theme.shared.linkColor
        let sheet = NSRect(x: (bounds.width - 32) / 2, y: (bounds.height - 40) / 2, width: 32, height: 40)
        let path = NSBezierPath(roundedRect: sheet, xRadius: 3, yRadius: 3)
        path.lineWidth = 1.5
        blue.setStroke()
        path.stroke()

        let label = fileExtension.uppercased()
        guard !label.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: MMFont.font(ofSize: 8, weight: .bold),
            .foregroundColor: blue,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: sheet.midX - size.width / 2, y: sheet.midY - size.height / 2),
            withAttributes: attrs
        )
    }
}

enum CompletionKind {
    case user
    case channel
    case emoji
}

struct CompletionItem {
    let kind: CompletionKind
    let title: String
    let subtitle: String
    let insertText: String
    let glyph: String?
}

struct EmojiEntry {
    let name: String
    let glyph: String
    let category: String
    let isCustom: Bool
    var emojiId: String?
}

/// Bundled standard emoji used by the composer picker, grouped like the web client.
enum EmojiCatalog {
    static let categories: [(title: String, symbol: String)] = [
        ("Recent", "clock"),
        ("Smileys & Emotion", "face.smiling"),
        ("People & Body", "hand.wave"),
        ("Animals & Nature", "pawprint"),
        ("Food & Drink", "fork.knife"),
        ("Travel & Places", "car"),
        ("Activities", "soccerball"),
        ("Objects", "lightbulb"),
        ("Symbols", "heart"),
        ("Flags", "flag"),
        ("Custom", "star.square"),
    ]

    private static let categoryNames: [String: String] = [
        "smileys-emotion": "Smileys & Emotion",
        "people-body": "People & Body",
        "animals-nature": "Animals & Nature",
        "food-drink": "Food & Drink",
        "travel-places": "Travel & Places",
        "activities": "Activities",
        "objects": "Objects",
        "symbols": "Symbols",
        "flags": "Flags",
        "component": "Symbols",
        "skin-tone": "People & Body",
    ]

    static let entries: [EmojiEntry] = {
        let bundles = [Bundle.main, Bundle(for: MainWindow.self)]
        for bundle in bundles {
            let url =
                bundle.url(forResource: "emoji", withExtension: "json", subdirectory: "Resources")
                ?? bundle.url(forResource: "emoji", withExtension: "json")
            guard let url = url,
                let data = try? Data(contentsOf: url),
                let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { continue }

            var seen = Set<String>()
            var entries: [EmojiEntry] = []
            for record in records {
                guard let unified = record["unified"] as? String,
                    let glyph = emojiGlyph(unified: unified)
                else { continue }
                let names =
                    (record["short_names"] as? [String])
                    ?? (record["short_name"] as? String).map { [$0] }
                    ?? []
                let categorySlug = record["category"] as? String ?? ""
                let category = categoryNames[categorySlug] ?? "Symbols"
                for name in names where !name.isEmpty {
                    let key = name.lowercased()
                    guard seen.insert(key).inserted else { continue }
                    entries.append(
                        EmojiEntry(name: name, glyph: glyph, category: category, isCustom: false)
                    )
                }
            }
            if !entries.isEmpty { return entries }
        }
        return []
    }()

    private static func emojiGlyph(unified: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for part in unified.split(separator: "-") {
            guard let value = UInt32(part, radix: 16),
                let scalar = UnicodeScalar(value)
            else { return nil }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    static let fallbackGlyphs: [String: String] = [
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎",
        "smile": "😄", "grinning": "😀", "joy": "😂", "heart": "❤️",
        "red_heart": "❤️", "tada": "🎉", "eyes": "👀", "fire": "🔥",
        "wave": "👋", "clap": "👏", "pray": "🙏", "rocket": "🚀",
        "white_check_mark": "✅", "x": "❌", "thinking_face": "🤔",
        "cry": "😢", "sob": "😭", "sunglasses": "😎", "100": "💯",
        "ok_hand": "👌", "point_up": "☝️", "muscle": "💪", "star": "⭐",
        "coffee": "☕", "computer": "💻", "palm_tree": "🌴", "beer": "🍺",
        "pizza": "🍕", "cake": "🎂", "sunny": "☀️", "rainbow": "🌈",
        "warning": "⚠️", "bulb": "💡", "lock": "🔒", "bell": "🔔",
    ]

    static let allGlyphs: [String: String] = {
        var map = fallbackGlyphs
        for entry in entries {
            map[entry.name.lowercased()] = entry.glyph
        }
        return map
    }()

    static func glyph(for name: String) -> String? {
        let clean = name.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased()
        return allGlyphs[clean]
    }

    static let entriesByName: [String: EmojiEntry] = {
        Dictionary(entries.map { ($0.name, $0) }, uniquingKeysWith: { _, latest in latest })
    }()
}

class TimelineScrollView: NSScrollView {
    var onScrollWheel: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        onScrollWheel?()
    }
}

class TimelineContainerView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return (view === self) ? nil : view
    }

    override func keyDown(with event: NSEvent) {
        if let scrollView = subviews.compactMap({ $0 as? TimelineScrollView }).first {
            scrollView.keyDown(with: event)
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Composer editor that draws its own placeholder so the placeholder never
/// intercepts clicks meant for the text view.
final class ComposerTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }
    var placeholderColor: NSColor = Theme.shared.centerTextPlaceholder {
        didSet { needsDisplay = true }
    }

    var onFilesDropped: (([URL]) -> Void)?
    var onDropStateChanged: ((Bool) -> Void)?
    var onImagePasted: ((Data, String) -> Void)?

    private var isDropTargetActive = false

    override func paste(_ sender: Any?) {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            onImagePasted?(png, "pasted-image.png")
            return
        }
        super.paste(sender)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([
            .fileURL,
            .string,
            .rtf,
            .rtfd,
            .tiff,
            .png,
        ])
    }

    func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return (objects ?? []).filter { !$0.hasDirectoryPath }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, onFilesDropped != nil else {
            return super.draggingEntered(sender)
        }
        isDropTargetActive = true
        onDropStateChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, onFilesDropped != nil else {
            return super.draggingUpdated(sender)
        }
        if !isDropTargetActive {
            isDropTargetActive = true
            onDropStateChanged?(true)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargetActive = false
        onDropStateChanged?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, let onFilesDropped = onFilesDropped else {
            return super.performDragOperation(sender)
        }
        isDropTargetActive = false
        onDropStateChanged?(false)
        onFilesDropped(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDropTargetActive = false
        onDropStateChanged?(false)
        super.concludeDragOperation(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty, let font = font else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: placeholderColor,
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholderString.draw(at: origin, withAttributes: attributes)
    }
}
