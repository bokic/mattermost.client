//
//  WindowZoomController.swift
//  mattermost.client
//
//  Shared app-level zoom plumbing for every top-level window.
//
//  Scaling model
//  -------------
//  macOS already applies the user's display scale; this controller adds the
//  in-app zoom factor on top of it. The window's contentView frame stays in
//  window points, while its `bounds` is rewritten to `frame.size / zoomFactor`.
//  Because a view's bounds define its internal coordinate system, every point
//  used by the UI then maps to `zoomFactor` screen points: factor 1.25 renders
//  the same logical layout 25% larger, and factor 0.8 renders it 20% smaller.
//  Layout code consumes `contentView.bounds.size`, so it lays out in logical
//  points and never has to know about the scale. On resize we re-apply the
//  factor to the new frame and notify the owner to lay out again.
//

import AppKit

@MainActor
final class WindowZoomController {
    private weak var window: NSWindow?
    private let onLayout: (() -> Void)?
    private let showsHUD: Bool

    // Observer tokens must be released from `deinit`, which is not isolated, so
    // they are nonisolated while all other access stays on the main actor.
    nonisolated(unsafe) private var resizeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var zoomObserver: NSObjectProtocol?

    init(window: NSWindow, showsHUD: Bool = true, onLayout: (() -> Void)? = nil) {
        self.window = window
        self.onLayout = onLayout
        self.showsHUD = showsHUD

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyCurrentZoom()
            }
        }

        zoomObserver = NotificationCenter.default.addObserver(
            forName: .zoomFactorDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyCurrentZoom(showHUD: true)
            }
        }
    }

    deinit {
        stop()
    }

    nonisolated func stop() {
        if let resizeObserver = resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        if let zoomObserver = zoomObserver {
            NotificationCenter.default.removeObserver(zoomObserver)
            self.zoomObserver = nil
        }
    }

    func applyCurrentZoom(showHUD: Bool = false) {
        apply(ZoomManager.shared.currentZoomFactor, showHUD: showHUD)
    }

    func apply(_ factor: CGFloat, showHUD: Bool = false) {
        guard factor > 0,
              let window = window,
              let contentView = window.contentView else { return }

        contentView.bounds = NSRect(
            x: 0,
            y: 0,
            width: contentView.frame.width / factor,
            height: contentView.frame.height / factor
        )
        contentView.needsDisplay = true
        onLayout?()

        if showHUD && showsHUD {
            ZoomHUD.shared.show(factor: factor, in: window)
        }
    }

    /// Handles the shared View zoom shortcuts: ⌘+, ⌘=, ⌘- and ⌘0.
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers ?? "" {
        case "+", "=":
            ZoomManager.shared.zoomIn()
            return true
        case "-":
            ZoomManager.shared.zoomOut()
            return true
        case "0":
            ZoomManager.shared.resetZoom()
            return true
        default:
            return false
        }
    }
}
