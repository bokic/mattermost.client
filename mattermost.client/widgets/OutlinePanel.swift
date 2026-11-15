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

    var onFilesDropped: (([URL]) -> Void)?
    var onDropStateChanged: ((Bool) -> Void)?

    private var isFileDropTarget = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    /// File URLs from a drag, ignoring directories.
    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return (objects ?? []).filter { !$0.hasDirectoryPath }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, onFilesDropped != nil else { return [] }
        isFileDropTarget = true
        onDropStateChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, onFilesDropped != nil else { return [] }
        if !isFileDropTarget {
            isFileDropTarget = true
            onDropStateChanged?(true)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isFileDropTarget = false
        onDropStateChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, let onFilesDropped = onFilesDropped else { return false }
        isFileDropTarget = false
        onDropStateChanged?(false)
        onFilesDropped(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isFileDropTarget = false
        onDropStateChanged?(false)
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
