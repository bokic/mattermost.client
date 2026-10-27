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

    var onClick: (() -> Void)?

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

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if !isHovered {
            isHovered = true
            onHoverChanged?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if isHovered {
            isHovered = false
            onHoverChanged?(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick = onClick {
            onClick()
        } else {
            super.mouseDown(with: event)
        }
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
    }

    private func updateLayerAppearance() {
        if wantsLayer == false { wantsLayer = true }
        guard let baseLayer = self.layer else { return }

        // Configure content (base) layer appearance
        let hasShadow = (shadowColor != nil && shadowOpacity > 0 && shadowRadius > 0)
        baseLayer.backgroundColor = color.cgColor
        baseLayer.cornerRadius = cornerRadius
        baseLayer.masksToBounds = !hasShadow // allow shadow to render outside bounds when active

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

    // MARK: - Drawing
    // We no longer need custom drawing for a rounded rect background.
    // Removing draw(_:) avoids unnecessary CPU work; Core Animation handles rendering.
}

