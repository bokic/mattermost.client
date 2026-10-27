//
//  OutlinePanel.swift
//  mattermost.client
//
//  Created by Boris Barbulovski on 1.5.25.
//

import Cocoa

class OutlinePanel: NSView {
    // MARK: - Configurable properties
    var color: NSColor = .lightGray
    var cornerRadius: CGFloat = 5
    var borderWidth: CGFloat = 2

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
        guard let layer = self.layer else { return }

        // Only an outline: no fill
        layer.backgroundColor = NSColor.clear.cgColor
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true

        layer.borderColor = color.cgColor
        layer.borderWidth = borderWidth
    }

    // Call this after changing appearance properties to refresh the view's rendering
    func setNeedsAppearanceUpdate() {
        if wantsLayer { self.layer?.setNeedsLayout() }
        needsLayout = true
        needsDisplay = true
        updateLayerAppearance()
    }
}
