//
//  MainWindowSupport.swift
//  mattermost.client
//
//  Shared view helpers and the emoji catalog used by the MainWindow components.
//

import Cocoa
import UniformTypeIdentifiers
import ImageIO

class MainWindowViewController: NSViewController {
    override func loadView() {
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
}

class TimelineFlippedView: NSView {
    override var isFlipped: Bool { true }
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
            .foregroundColor: blue
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
        ("Custom", "star.square")
    ]

    static let entries: [EmojiEntry] = {
        let data: [(String, String, String)] = [
            // Smileys & Emotion
            ("grinning", "😀", "Smileys & Emotion"),
            ("smiley", "😃", "Smileys & Emotion"),
            ("smile", "😄", "Smileys & Emotion"),
            ("grin", "😁", "Smileys & Emotion"),
            ("laughing", "😆", "Smileys & Emotion"),
            ("sweat_smile", "😅", "Smileys & Emotion"),
            ("rofl", "🤣", "Smileys & Emotion"),
            ("joy", "😂", "Smileys & Emotion"),
            ("slightly_smiling_face", "🙂", "Smileys & Emotion"),
            ("upside_down_face", "🙃", "Smileys & Emotion"),
            ("wink", "😉", "Smileys & Emotion"),
            ("blush", "😊", "Smileys & Emotion"),
            ("innocent", "😇", "Smileys & Emotion"),
            ("smiling_face_with_3_hearts", "🥰", "Smileys & Emotion"),
            ("heart_eyes", "😍", "Smileys & Emotion"),
            ("star_struck", "🤩", "Smileys & Emotion"),
            ("kissing_heart", "😘", "Smileys & Emotion"),
            ("yum", "😋", "Smileys & Emotion"),
            ("stuck_out_tongue", "😛", "Smileys & Emotion"),
            ("zany_face", "🤪", "Smileys & Emotion"),
            ("face_with_raised_eyebrow", "🤨", "Smileys & Emotion"),
            ("monocle_face", "🧐", "Smileys & Emotion"),
            ("nerd_face", "🤓", "Smileys & Emotion"),
            ("sunglasses", "😎", "Smileys & Emotion"),
            ("partying_face", "🥳", "Smileys & Emotion"),
            ("smirk", "😏", "Smileys & Emotion"),
            ("unamused", "😒", "Smileys & Emotion"),
            ("pleading_face", "🥺", "Smileys & Emotion"),
            ("cry", "😢", "Smileys & Emotion"),
            ("sob", "😭", "Smileys & Emotion"),
            ("scream", "😱", "Smileys & Emotion"),
            ("thinking_face", "🤔", "Smileys & Emotion"),
            ("sleeping", "😴", "Smileys & Emotion"),
            ("mask", "😷", "Smileys & Emotion"),
            ("nauseated_face", "🤢", "Smileys & Emotion"),
            ("hot_face", "🥵", "Smileys & Emotion"),
            ("cold_face", "🥶", "Smileys & Emotion"),
            ("exploding_head", "🤯", "Smileys & Emotion"),
            ("cowboy_hat_face", "🤠", "Smileys & Emotion"),
            ("ghost", "👻", "Smileys & Emotion"),
            ("alien", "👽", "Smileys & Emotion"),
            ("robot", "🤖", "Smileys & Emotion"),
            ("poop", "💩", "Smileys & Emotion"),
            ("clown_face", "🤡", "Smileys & Emotion"),

            // People & Body
            ("wave", "👋", "People & Body"),
            ("raised_hand", "✋", "People & Body"),
            ("raised_back_of_hand", "🤚", "People & Body"),
            ("vulcan_salute", "🖖", "People & Body"),
            ("ok_hand", "👌", "People & Body"),
            ("pinched_fingers", "🤌", "People & Body"),
            ("victory", "✌️", "People & Body"),
            ("crossed_fingers", "🤞", "People & Body"),
            ("love_you_gesture", "🤟", "People & Body"),
            ("metal", "🤘", "People & Body"),
            ("call_me_hand", "🤙", "People & Body"),
            ("point_left", "👈", "People & Body"),
            ("point_right", "👉", "People & Body"),
            ("point_up", "☝️", "People & Body"),
            ("point_down", "👇", "People & Body"),
            ("thumbsup", "👍", "People & Body"),
            ("thumbsdown", "👎", "People & Body"),
            ("fist", "✊", "People & Body"),
            ("facepunch", "👊", "People & Body"),
            ("clap", "👏", "People & Body"),
            ("raised_hands", "🙌", "People & Body"),
            ("open_hands", "👐", "People & Body"),
            ("handshake", "🤝", "People & Body"),
            ("pray", "🙏", "People & Body"),
            ("writing_hand", "✍️", "People & Body"),
            ("nail_care", "💅", "People & Body"),
            ("muscle", "💪", "People & Body"),
            ("ear", "👂", "People & Body"),
            ("nose", "👃", "People & Body"),
            ("brain", "🧠", "People & Body"),
            ("eyes", "👀", "People & Body"),
            ("eye", "👁️", "People & Body"),
            ("tongue", "👅", "People & Body"),
            ("lips", "👄", "People & Body"),
            ("baby", "👶", "People & Body"),
            ("boy", "👦", "People & Body"),
            ("girl", "👧", "People & Body"),
            ("man", "👨", "People & Body"),
            ("woman", "👩", "People & Body"),
            ("older_man", "👴", "People & Body"),
            ("older_woman", "👵", "People & Body"),
            ("shrug", "🤷", "People & Body"),
            ("princess", "👸", "People & Body"),
            ("superhero", "🦸", "People & Body"),
            ("mage", "🧙", "People & Body"),
            ("fairy", "🧚", "People & Body"),
            ("santa", "🎅", "People & Body"),
            ("runner", "🏃", "People & Body"),
            ("dancer", "💃", "People & Body"),

            // Animals & Nature
            ("dog", "🐶", "Animals & Nature"),
            ("cat", "🐱", "Animals & Nature"),
            ("mouse", "🐭", "Animals & Nature"),
            ("hamster", "🐹", "Animals & Nature"),
            ("rabbit", "🐰", "Animals & Nature"),
            ("fox_face", "🦊", "Animals & Nature"),
            ("bear", "🐻", "Animals & Nature"),
            ("panda_face", "🐼", "Animals & Nature"),
            ("koala", "🐨", "Animals & Nature"),
            ("tiger", "🐯", "Animals & Nature"),
            ("lion", "🦁", "Animals & Nature"),
            ("cow", "🐮", "Animals & Nature"),
            ("pig", "🐷", "Animals & Nature"),
            ("frog", "🐸", "Animals & Nature"),
            ("monkey", "🐵", "Animals & Nature"),
            ("see_no_evil", "🙈", "Animals & Nature"),
            ("hear_no_evil", "🙉", "Animals & Nature"),
            ("speak_no_evil", "🙊", "Animals & Nature"),
            ("unicorn", "🦄", "Animals & Nature"),
            ("bee", "🐝", "Animals & Nature"),
            ("butterfly", "🦋", "Animals & Nature"),
            ("snail", "🐌", "Animals & Nature"),
            ("bug", "🐛", "Animals & Nature"),
            ("ant", "🐜", "Animals & Nature"),
            ("lady_beetle", "🐞", "Animals & Nature"),
            ("turtle", "🐢", "Animals & Nature"),
            ("snake", "🐍", "Animals & Nature"),
            ("octopus", "🐙", "Animals & Nature"),
            ("fish", "🐟", "Animals & Nature"),
            ("tropical_fish", "🐠", "Animals & Nature"),
            ("dolphin", "🐬", "Animals & Nature"),
            ("whale", "🐳", "Animals & Nature"),
            ("shark", "🦈", "Animals & Nature"),
            ("crocodile", "🐊", "Animals & Nature"),
            ("leopard", "🐆", "Animals & Nature"),
            ("zebra", "🦓", "Animals & Nature"),
            ("gorilla", "🦍", "Animals & Nature"),
            ("elephant", "🐘", "Animals & Nature"),
            ("eagle", "🦅", "Animals & Nature"),
            ("owl", "🦉", "Animals & Nature"),
            ("parrot", "🦜", "Animals & Nature"),
            ("penguin", "🐧", "Animals & Nature"),
            ("bird", "🐦", "Animals & Nature"),
            ("duck", "🦆", "Animals & Nature"),
            ("swan", "🦢", "Animals & Nature"),
            ("flamingo", "🦩", "Animals & Nature"),
            ("peacock", "🦚", "Animals & Nature"),
            ("turkey", "🦃", "Animals & Nature"),
            ("rooster", "🐓", "Animals & Nature"),
            ("hatching_chick", "🐣", "Animals & Nature"),

            // Food & Drink
            ("apple", "🍎", "Food & Drink"),
            ("green_apple", "🍏", "Food & Drink"),
            ("pear", "🍐", "Food & Drink"),
            ("tangerine", "🍊", "Food & Drink"),
            ("lemon", "🍋", "Food & Drink"),
            ("cherries", "🍒", "Food & Drink"),
            ("grapes", "🍇", "Food & Drink"),
            ("watermelon", "🍉", "Food & Drink"),
            ("strawberry", "🍓", "Food & Drink"),
            ("peach", "🍑", "Food & Drink"),
            ("melon", "🍈", "Food & Drink"),
            ("banana", "🍌", "Food & Drink"),
            ("pineapple", "🍍", "Food & Drink"),
            ("mango", "🥭", "Food & Drink"),
            ("avocado", "🥑", "Food & Drink"),
            ("tomato", "🍅", "Food & Drink"),
            ("eggplant", "🍆", "Food & Drink"),
            ("potato", "🥔", "Food & Drink"),
            ("carrot", "🥕", "Food & Drink"),
            ("corn", "🌽", "Food & Drink"),
            ("hot_pepper", "🌶️", "Food & Drink"),
            ("cucumber", "🥒", "Food & Drink"),
            ("broccoli", "🥦", "Food & Drink"),
            ("mushroom", "🍄", "Food & Drink"),
            ("bread", "🍞", "Food & Drink"),
            ("cheese", "🧀", "Food & Drink"),
            ("egg", "🥚", "Food & Drink"),
            ("bacon", "🥓", "Food & Drink"),
            ("hamburger", "🍔", "Food & Drink"),
            ("fries", "🍟", "Food & Drink"),
            ("pizza", "🍕", "Food & Drink"),
            ("hotdog", "🌭", "Food & Drink"),
            ("taco", "🌮", "Food & Drink"),
            ("burrito", "🌯", "Food & Drink"),
            ("cake", "🍰", "Food & Drink"),
            ("birthday", "🎂", "Food & Drink"),
            ("cookie", "🍪", "Food & Drink"),
            ("doughnut", "🍩", "Food & Drink"),
            ("icecream", "🍦", "Food & Drink"),
            ("coffee", "☕", "Food & Drink"),
            ("tea", "🍵", "Food & Drink"),
            ("beer", "🍺", "Food & Drink"),
            ("beers", "🍻", "Food & Drink"),
            ("wine_glass", "🍷", "Food & Drink"),
            ("cocktail", "🍸", "Food & Drink"),
            ("tropical_drink", "🍹", "Food & Drink"),
            ("milk_glass", "🥛", "Food & Drink"),

            // Travel & Places
            ("car", "🚗", "Travel & Places"),
            ("taxi", "🚕", "Travel & Places"),
            ("bus", "🚌", "Travel & Places"),
            ("train", "🚆", "Travel & Places"),
            ("airplane", "✈️", "Travel & Places"),
            ("rocket", "🚀", "Travel & Places"),
            ("ship", "🚢", "Travel & Places"),
            ("boat", "⛵", "Travel & Places"),
            ("anchor", "⚓", "Travel & Places"),
            ("bicycle", "🚲", "Travel & Places"),
            ("motorcycle", "🏍️", "Travel & Places"),
            ("traffic_light", "🚦", "Travel & Places"),
            ("construction", "🚧", "Travel & Places"),
            ("house", "🏠", "Travel & Places"),
            ("office", "🏢", "Travel & Places"),
            ("school", "🏫", "Travel & Places"),
            ("hospital", "🏥", "Travel & Places"),
            ("bank", "🏦", "Travel & Places"),
            ("hotel", "🏨", "Travel & Places"),
            ("tent", "⛺", "Travel & Places"),
            ("camping", "🏕️", "Travel & Places"),
            ("mountain", "⛰️", "Travel & Places"),
            ("beach", "🏖️", "Travel & Places"),
            ("desert", "🏜️", "Travel & Places"),
            ("island", "🏝️", "Travel & Places"),
            ("sunrise", "🌅", "Travel & Places"),
            ("cityscape", "🏙️", "Travel & Places"),
            ("bridge", "🌉", "Travel & Places"),
            ("statue_of_liberty", "🗽", "Travel & Places"),
            ("ferris_wheel", "🎡", "Travel & Places"),
            ("roller_coaster", "🎢", "Travel & Places"),
            ("carousel_horse", "🎠", "Travel & Places"),

            // Activities
            ("soccer", "⚽", "Activities"),
            ("basketball", "🏀", "Activities"),
            ("football", "🏈", "Activities"),
            ("baseball", "⚾", "Activities"),
            ("tennis", "🎾", "Activities"),
            ("volleyball", "🏐", "Activities"),
            ("rugby_football", "🏉", "Activities"),
            ("golf", "🏌️", "Activities"),
            ("trophy", "🏆", "Activities"),
            ("medal", "🏅", "Activities"),
            ("dart", "🎯", "Activities"),
            ("bowling", "🎳", "Activities"),
            ("video_game", "🎮", "Activities"),
            ("game_die", "🎲", "Activities"),
            ("chess_pawn", "♟️", "Activities"),
            ("art", "🎨", "Activities"),
            ("musical_note", "🎵", "Activities"),
            ("notes", "🎶", "Activities"),
            ("guitar", "🎸", "Activities"),
            ("violin", "🎻", "Activities"),
            ("drum", "🥁", "Activities"),
            ("microphone", "🎤", "Activities"),
            ("headphones", "🎧", "Activities"),
            ("ticket", "🎫", "Activities"),
            ("popcorn", "🍿", "Activities"),
            ("circus_tent", "🎪", "Activities"),
            ("magic_wand", "🪄", "Activities"),
            ("puzzle", "🧩", "Activities"),

            // Objects
            ("computer", "💻", "Objects"),
            ("desktop_computer", "🖥️", "Objects"),
            ("keyboard", "⌨️", "Objects"),
            ("printer", "🖨️", "Objects"),
            ("phone", "☎️", "Objects"),
            ("iphone", "📱", "Objects"),
            ("camera", "📷", "Objects"),
            ("video_camera", "📹", "Objects"),
            ("tv", "📺", "Objects"),
            ("radio", "📻", "Objects"),
            ("bulb", "💡", "Objects"),
            ("flashlight", "🔦", "Objects"),
            ("hammer", "🔨", "Objects"),
            ("wrench", "🔧", "Objects"),
            ("screwdriver", "🪛", "Objects"),
            ("gear", "⚙️", "Objects"),
            ("lock", "🔒", "Objects"),
            ("unlock", "🔓", "Objects"),
            ("key", "🔑", "Objects"),
            ("door", "🚪", "Objects"),
            ("couch", "🛋️", "Objects"),
            ("bed", "🛏️", "Objects"),
            ("toilet", "🚽", "Objects"),
            ("shower", "🚿", "Objects"),
            ("bathtub", "🛁", "Objects"),
            ("soap", "🧼", "Objects"),
            ("broom", "🧹", "Objects"),
            ("basket", "🧺", "Objects"),
            ("package", "📦", "Objects"),
            ("mailbox", "📫", "Objects"),
            ("calendar", "📅", "Objects"),
            ("clipboard", "📋", "Objects"),
            ("file_folder", "📁", "Objects"),
            ("books", "📚", "Objects"),
            ("bookmark", "🔖", "Objects"),
            ("pencil2", "✏️", "Objects"),
            ("paperclip", "📎", "Objects"),
            ("scissors", "✂️", "Objects"),
            ("hourglass", "⌛", "Objects"),
            ("watch", "⌚", "Objects"),
            ("alarm_clock", "⏰", "Objects"),
            ("thermometer", "🌡️", "Objects"),
            ("pill", "💊", "Objects"),
            ("microscope", "🔬", "Objects"),
            ("telescope", "🔭", "Objects"),
            ("satellite", "📡", "Objects"),
            ("battery", "🔋", "Objects"),
            ("electric_plug", "🔌", "Objects"),
            ("magnet", "🧲", "Objects"),

            // Symbols
            ("heart", "❤️", "Symbols"),
            ("orange_heart", "🧡", "Symbols"),
            ("yellow_heart", "💛", "Symbols"),
            ("green_heart", "💚", "Symbols"),
            ("blue_heart", "💙", "Symbols"),
            ("purple_heart", "💜", "Symbols"),
            ("black_heart", "🖤", "Symbols"),
            ("white_heart", "🤍", "Symbols"),
            ("broken_heart", "💔", "Symbols"),
            ("two_hearts", "💕", "Symbols"),
            ("sparkling_heart", "💖", "Symbols"),
            ("heartpulse", "💗", "Symbols"),
            ("heartbeat", "💓", "Symbols"),
            ("cupid", "💘", "Symbols"),
            ("gift_heart", "💝", "Symbols"),
            ("star", "⭐", "Symbols"),
            ("star2", "🌟", "Symbols"),
            ("sparkles", "✨", "Symbols"),
            ("zap", "⚡", "Symbols"),
            ("boom", "💥", "Symbols"),
            ("fire", "🔥", "Symbols"),
            ("snowflake", "❄️", "Symbols"),
            ("droplet", "💧", "Symbols"),
            ("ocean", "🌊", "Symbols"),
            ("rainbow", "🌈", "Symbols"),
            ("sunny", "☀️", "Symbols"),
            ("cloud", "☁️", "Symbols"),
            ("umbrella", "☔", "Symbols"),
            ("snowman", "⛄", "Symbols"),
            ("comet", "☄️", "Symbols"),
            ("earth_americas", "🌎", "Symbols"),
            ("earth_africa", "🌍", "Symbols"),
            ("earth_asia", "🌏", "Symbols"),
            ("full_moon", "🌕", "Symbols"),
            ("new_moon", "🌑", "Symbols"),
            ("crescent_moon", "🌙", "Symbols"),
            ("sun_with_face", "🌞", "Symbols"),
            ("warning", "⚠️", "Symbols"),
            ("no_entry", "⛔", "Symbols"),
            ("white_check_mark", "✅", "Symbols"),
            ("x", "❌", "Symbols"),
            ("heavy_check_mark", "✔️", "Symbols"),
            ("ballot_box_with_check", "☑️", "Symbols"),
            ("question", "❓", "Symbols"),
            ("exclamation", "❗", "Symbols"),
            ("100", "💯", "Symbols"),
            ("sos", "🆘", "Symbols"),
            ("recycle", "♻️", "Symbols"),
            ("arrow_up", "⬆️", "Symbols"),
            ("arrow_down", "⬇️", "Symbols"),
            ("arrow_left", "⬅️", "Symbols"),
            ("arrow_right", "➡️", "Symbols"),

            // Flags
            ("checkered_flag", "🏁", "Flags"),
            ("triangular_flag_on_post", "🚩", "Flags"),
            ("crossed_flags", "🎌", "Flags"),
            ("flag_us", "🇺🇸", "Flags"),
            ("flag_gb", "🇬🇧", "Flags"),
            ("flag_de", "🇩🇪", "Flags"),
            ("flag_fr", "🇫🇷", "Flags"),
            ("flag_it", "🇮🇹", "Flags"),
            ("flag_es", "🇪🇸", "Flags"),
            ("flag_jp", "🇯🇵", "Flags"),
            ("flag_cn", "🇨🇳", "Flags"),
            ("flag_ru", "🇷🇺", "Flags"),
            ("flag_in", "🇮🇳", "Flags"),
            ("flag_au", "🇦🇺", "Flags"),
            ("flag_ca", "🇨🇦", "Flags"),
            ("flag_br", "🇧🇷", "Flags"),
            ("flag_mx", "🇲🇽", "Flags"),
            ("flag_kr", "🇰🇷", "Flags"),
            ("flag_eu", "🇪🇺", "Flags"),
            ("flag_un", "🇺🇳", "Flags")
        ]
        return data.map { EmojiEntry(name: $0.0, glyph: $0.1, category: $0.2, isCustom: false) }
    }()

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

    var isFileDropTarget = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([
            .fileURL,
            .string,
            .rtf,
            .rtfd,
            .tiff,
            .png
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
        isFileDropTarget = true
        onDropStateChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, onFilesDropped != nil else {
            return super.draggingUpdated(sender)
        }
        if !isFileDropTarget {
            isFileDropTarget = true
            onDropStateChanged?(true)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isFileDropTarget = false
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
        isFileDropTarget = false
        onDropStateChanged?(false)
        onFilesDropped(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isFileDropTarget = false
        onDropStateChanged?(false)
        super.concludeDragOperation(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty, let font = font else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: placeholderColor
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholderString.draw(at: origin, withAttributes: attributes)
    }
}
