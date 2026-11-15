//
//  ZoomHUD.swift
//  mattermost.client
//
//  Transient overlay that shows the current zoom percentage for two seconds
//  after the zoom factor changes. The pill is sized from the measured text.
//

import AppKit
import CoreText

/// Panel that never intercepts mouse events so the overlay can sit on top of
/// the UI without stealing clicks while it is visible.
private final class ZoomHUDPanel: RoundedEdgePanel {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Draws the percentage centered on its glyph ink rather than on the font's
/// line box, which keeps the text optically centered inside the pill.
private final class ZoomHUDTextView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }
    var font: NSFont = .systemFont(ofSize: 15, weight: .semibold) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(
            x: (bounds.width - ink.width) / 2 - ink.minX,
            y: (bounds.height - ink.height) / 2 - ink.minY
        )
        CTLineDraw(line, context)
    }
}

@MainActor
final class ZoomHUD {

    static let shared = ZoomHUD()

    private var panel: ZoomHUDPanel?
    private var textView: ZoomHUDTextView?
    private var hideTimer: Timer?

    /// How long the percentage stays on screen after the last zoom change.
    private let displayDuration: TimeInterval = 2.0

    private init() {}

    func show(factor: CGFloat, in window: NSWindow) {
        guard factor > 0, let content = window.contentView else { return }

        let panel = self.panel ?? makePanel()
        let textView = self.textView!

        // The window scales its content view by dividing its bounds by the zoom
        // factor, so counter-scale the HUD to keep it the same visual size.
        let counterScale = content.bounds.width / max(content.frame.width, 1)

        // Desired on-screen metrics, independent of the current zoom.
        let fontSize: CGFloat = 15
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 8
        let cornerRadius: CGFloat = 8
        let topMargin: CGFloat = 14

        let text = "\(Int((factor * 100).rounded()))%"
        let font = MMFont.font(ofSize: fontSize * counterScale, weight: .semibold)
        let ink = inkBounds(for: text, font: font)

        // Size the pill from the glyph ink plus symmetric padding.
        let boxWidth = ceil(ink.width) + (horizontalPadding * 2 * counterScale)
        let boxHeight = ceil(ink.height) + (verticalPadding * 2 * counterScale)

        panel.frame = NSRect(
            x: ((content.bounds.width - boxWidth) / 2).rounded(),
            y: content.bounds.height - boxHeight - (topMargin * counterScale),
            width: boxWidth,
            height: boxHeight
        )
        panel.cornerRadius = cornerRadius * counterScale
        panel.setNeedsAppearanceUpdate()

        textView.frame = panel.bounds
        textView.font = font
        textView.text = text

        if panel.superview !== content {
            panel.removeFromSuperview()
            content.addSubview(panel)
        }
        panel.isHidden = false

        if panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }

        hideTimer?.invalidate()
        let timer = Timer(timeInterval: displayDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func hide() {
        guard let panel = panel, panel.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.isHidden = true
                panel.alphaValue = 0
            }
        })
    }

    private func makePanel() -> ZoomHUDPanel {
        let panel = ZoomHUDPanel()
        panel.color = NSColor(red: 27 / 255, green: 29 / 255, blue: 34 / 255, alpha: 0.88)
        panel.cornerRadius = 8
        panel.shadowColor = .black
        panel.shadowOpacity = 0.25
        panel.shadowRadius = 10
        panel.shadowOffset = CGSize(width: 0, height: -2)
        panel.alphaValue = 0

        let textView = ZoomHUDTextView()
        panel.addSubview(textView)

        self.panel = panel
        self.textView = textView
        return panel
    }

    private func inkBounds(for text: String, font: NSFont) -> CGRect {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    }
}
