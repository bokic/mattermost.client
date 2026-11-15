//
//  RoundedEdgePanel.swift
//  firstMacOS
//
//  Created by Boris Barbulovski on 31.10.24.
//

import Cocoa

class RoundedEdgePanel: NSView {
    // MARK: - Configurable properties
    var color: NSColor = .white

    var cornerRadius: CGFloat = 10

    // Optional border support
    var borderColor: NSColor?

    var borderWidth: CGFloat = 0

    /// Overrides subview clipping. When nil, shadows are allowed to draw outside the bounds
    /// while everything else is clipped to the rounded rectangle.
    var clipContentToBounds: Bool?

    // Optional shadow support
    var shadowColor: NSColor?

    var shadowOpacity: Float = 0

    var shadowRadius: CGFloat = 0

    var shadowOffset: CGSize = .zero

    var onHoverChanged: ((Bool) -> Void)? {
        didSet {
            updateTrackingAreas()
        }
    }

    var onClick: (() -> Void)? {
        didSet {
            setAccessibilityElement(onClick != nil)
            if onClick != nil {
                setAccessibilityRole(.button)
                focusRingType = .default
            }
            needsLayout = true
        }
    }

    /// Optional VoiceOver label; when nil the panel derives one from its first
    /// text label or image description.
    var accessibilityTitle: String?

    /// Optional VoiceOver help text (for example “Opens the channel menu”).
    var accessibilityHelp: String?

    private(set) var isHovered: Bool = false

    private var trackingArea: NSTrackingArea?

    private var shadowLayer: CALayer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard onHoverChanged != nil else { return }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        onHoverChanged?(hovered)
    }

    func updateHoverRecursively(windowMouseLocation: NSPoint, isWindowActiveAndInScrollView: Bool) {
        let isInside: Bool
        if !isWindowActiveAndInScrollView {
            isInside = false
        } else {
            let localPoint = convert(windowMouseLocation, from: nil)
            isInside = bounds.contains(localPoint)
        }
        if onHoverChanged != nil {
            setHovered(isInside)
        }
        
        for subview in subviews {
            if let panel = subview as? RoundedEdgePanel {
                panel.updateHoverRecursively(windowMouseLocation: windowMouseLocation, isWindowActiveAndInScrollView: isInside)
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick = onClick {
            onClick()
        } else {
            super.mouseDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { onClick != nil }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard onClick != nil else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 49, 76: // Return, Space, Enter
            onClick?()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick = onClick else { return false }
        onClick()
        return true
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    private func updateAccessibility() {
        guard onClick != nil else {
            setAccessibilityElement(false)
            return
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        if let accessibilityHelp = accessibilityHelp, !accessibilityHelp.isEmpty {
            setAccessibilityHelp(accessibilityHelp)
        }
        if let accessibilityTitle = accessibilityTitle, !accessibilityTitle.isEmpty {
            setAccessibilityLabel(accessibilityTitle)
            return
        }
        for subview in subviews {
            if let label = subview as? NSTextField, !label.stringValue.isEmpty {
                setAccessibilityLabel(label.stringValue)
                return
            }
            if let imageView = subview as? NSImageView,
               let description = imageView.image?.accessibilityDescription ?? imageView.accessibilityLabel(),
               !description.isEmpty {
                setAccessibilityLabel(description)
                return
            }
        }
        setAccessibilityLabel("Button")
    }

    /// Clickable panels are usually filled with `NSImageView`/label children. AppKit's
    /// `NSImageView` consumes `mouseDown` without forwarding it to its superview, which
    /// turned the icon itself into a dead zone. Keep genuinely interactive descendants
    /// (text editors, controls, scroll views and nested clickable panels) working, but
    /// otherwise make the panel the hit target so its `onClick` receives the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard onClick != nil, hit !== self else { return hit }
        if hitIsInteractive(hit) { return hit }
        return self
    }

    private func hitIsInteractive(_ hit: NSView) -> Bool {
        var view: NSView? = hit
        while let current = view, current !== self {
            if let panel = current as? RoundedEdgePanel, panel.onClick != nil {
                return true
            }
            if current is NSTextView || current is NSScrollView {
                return true
            }
            if let control = current as? NSControl, control.isEnabled {
                // Non-editable labels should not swallow clicks on their row, but
                // buttons, pop-ups and editable/selectable fields should.
                if let textField = control as? NSTextField {
                    if textField.isEditable || textField.isSelectable || textField.isBezeled {
                        return true
                    }
                } else {
                    return true
                }
            }
            view = current.superview
        }
        return false
    }

    // Call this after changing appearance properties to refresh the view's rendering
    func setNeedsAppearanceUpdate() {
        if wantsLayer { self.layer?.setNeedsLayout() }
        needsLayout = true
        needsDisplay = true
        updateLayerAppearance()
    }

    // MARK: - Layer-backed rendering
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        updateLayerAppearance()
    }

    override func layout() {
        super.layout()
        updateLayerAppearance()
        updateAccessibility()
    }

    private func updateLayerAppearance() {
        if wantsLayer == false { wantsLayer = true }
        guard let baseLayer = self.layer else { return }

        // Configure content (base) layer appearance
        let hasShadow = (shadowColor != nil && shadowOpacity > 0 && shadowRadius > 0)
        baseLayer.backgroundColor = color.cgColor
        baseLayer.cornerRadius = cornerRadius
        baseLayer.masksToBounds = clipContentToBounds ?? !hasShadow // allow shadow to render outside bounds when active

        if let borderColor = borderColor, borderWidth > 0 {
            baseLayer.borderColor = borderColor.cgColor
            baseLayer.borderWidth = borderWidth
        } else {
            baseLayer.borderColor = nil
            baseLayer.borderWidth = 0
        }

        if let sColor = shadowColor, shadowOpacity > 0, shadowRadius > 0 {
            baseLayer.shadowColor = sColor.cgColor
            baseLayer.shadowOpacity = shadowOpacity
            baseLayer.shadowRadius = shadowRadius
            baseLayer.shadowOffset = CGSize(width: shadowOffset.width, height: shadowOffset.height)
            // Use a path for better performance and to match rounded corners
            baseLayer.shadowPath = CGPath(roundedRect: baseLayer.bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        } else {
            baseLayer.shadowOpacity = 0
            baseLayer.shadowColor = nil
            baseLayer.shadowRadius = 0
            baseLayer.shadowOffset = .zero
            baseLayer.shadowPath = nil
        }
    }
}
