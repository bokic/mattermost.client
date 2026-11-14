//
//  ZoomHUD.swift
//  mattermost.client
//
//  Transient overlay that shows the current zoom percentage for two seconds
//  after the zoom factor changes.
//

import AppKit

/// Panel that never intercepts mouse events so the overlay can sit on top of
/// the UI without stealing clicks while it is visible.
private final class ZoomHUDPanel: RoundedEdgePanel {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ZoomHUD {

    static let shared = ZoomHUD()

    private var panel: ZoomHUDPanel?
    private var label: NSTextField?
    private var hideTimer: Timer?

    /// How long the percentage stays on screen after the last zoom change.
    private let displayDuration: TimeInterval = 2.0

    private init() {}

    func show(factor: CGFloat, in window: NSWindow) {
        guard factor > 0, let content = window.contentView else { return }

        let panel = self.panel ?? makePanel()
        let label = self.label!

        // The window scales its content view by dividing its bounds by the zoom
        // factor, so counter-scale the HUD to keep it the same visual size.
        let counterScale = content.bounds.width / max(content.frame.width, 1)
        let width = 104 * counterScale
        let height = 56 * counterScale

        panel.frame = NSRect(
            x: (content.bounds.width - width) / 2,
            y: content.bounds.height - height - 20 * counterScale,
            width: width,
            height: height
        )
        panel.cornerRadius = 10 * counterScale
        panel.setNeedsAppearanceUpdate()

        label.font = MMFont.font(ofSize: 20 * counterScale, weight: .semibold)
        label.frame = panel.bounds
        label.stringValue = "\(Int((factor * 100).rounded()))%"

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
            self?.hide()
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
            panel.isHidden = true
            panel.alphaValue = 0
        })
    }

    private func makePanel() -> ZoomHUDPanel {
        let panel = ZoomHUDPanel()
        panel.color = NSColor(red: 27 / 255, green: 29 / 255, blue: 34 / 255, alpha: 0.88)
        panel.cornerRadius = 10
        panel.shadowColor = .black
        panel.shadowOpacity = 0.25
        panel.shadowRadius = 10
        panel.shadowOffset = CGSize(width: 0, height: -2)
        panel.alphaValue = 0

        let label = NSTextField(labelWithString: "100%")
        label.textColor = .white
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        panel.addSubview(label)

        self.panel = panel
        self.label = label
        return panel
    }
}
