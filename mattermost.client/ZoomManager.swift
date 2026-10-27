//
//  ZoomManager.swift
//  mattermost.client
//
//  Created on 28.10.26.
//

import Cocoa

final class ZoomManager {
    static let shared = ZoomManager()
    
    static let zoomLevels: [CGFloat] = [0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5]
    static let userDefaultsKey = "uiZoomFactor"
    static let defaultZoomFactor: CGFloat = 1.0
    static let minZoomFactor: CGFloat = 0.6
    static let maxZoomFactor: CGFloat = 2.5
    
    private(set) var currentZoomFactor: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(currentZoomFactor), forKey: Self.userDefaultsKey)
            NotificationCenter.default.post(
                name: .zoomFactorDidChange,
                object: self,
                userInfo: ["zoomFactor": currentZoomFactor]
            )
        }
    }
    
    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.userDefaultsKey)
        if saved >= Double(Self.minZoomFactor) && saved <= Double(Self.maxZoomFactor) {
            self.currentZoomFactor = CGFloat(saved)
        } else {
            self.currentZoomFactor = Self.defaultZoomFactor
        }
    }
    
    func zoomIn() {
        let current = currentZoomFactor
        if let next = Self.zoomLevels.first(where: { $0 > current + 0.01 }) {
            setZoomFactor(next)
        } else {
            setZoomFactor(min(current * 1.15, Self.maxZoomFactor))
        }
    }
    
    func zoomOut() {
        let current = currentZoomFactor
        if let prev = Self.zoomLevels.last(where: { $0 < current - 0.01 }) {
            setZoomFactor(prev)
        } else {
            setZoomFactor(max(current / 1.15, Self.minZoomFactor))
        }
    }
    
    func resetZoom() {
        setZoomFactor(Self.defaultZoomFactor)
    }
    
    func setZoomFactor(_ factor: CGFloat) {
        let clamped = min(max(factor, Self.minZoomFactor), Self.maxZoomFactor)
        // Avoid redundant notifications for equal floats
        if abs(currentZoomFactor - clamped) > 0.001 {
            currentZoomFactor = clamped
        }
    }
}

extension Notification.Name {
    static let zoomFactorDidChange = Notification.Name("uiZoomFactorDidChangeNotification")
}
