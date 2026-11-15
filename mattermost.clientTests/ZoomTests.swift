//
//  ZoomTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ZoomTests: XCTestCase {

    private var originalFactor: CGFloat = 1.0

    override func setUp() {
        super.setUp()
        originalFactor = ZoomManager.shared.currentZoomFactor
    }

    override func tearDown() {
        ZoomManager.shared.setZoomFactor(originalFactor)
        super.tearDown()
    }

    func testZoomInAndOutFollowPresetLevels() {
        ZoomManager.shared.setZoomFactor(1.0)

        ZoomManager.shared.zoomIn()
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, 1.1, accuracy: 0.0001)

        ZoomManager.shared.zoomOut()
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, 1.0, accuracy: 0.0001)
    }

    func testZoomStopsAtPresetBounds() {
        ZoomManager.shared.setZoomFactor(2.5)
        ZoomManager.shared.zoomIn()
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, 2.5, accuracy: 0.0001)

        ZoomManager.shared.setZoomFactor(0.6)
        ZoomManager.shared.zoomOut()
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, ZoomManager.minZoomFactor, accuracy: 0.0001)
    }

    func testSetZoomFactorClampsToRange() {
        ZoomManager.shared.setZoomFactor(9)
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, ZoomManager.maxZoomFactor, accuracy: 0.0001)

        ZoomManager.shared.setZoomFactor(0.1)
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, ZoomManager.minZoomFactor, accuracy: 0.0001)
    }

    func testResetZoomUsesDefault() {
        ZoomManager.shared.setZoomFactor(1.5)
        ZoomManager.shared.resetZoom()
        XCTAssertEqual(ZoomManager.shared.currentZoomFactor, ZoomManager.defaultZoomFactor, accuracy: 0.0001)
    }

    func testSystemZoomFactorIsActualSize() {
        XCTAssertEqual(ZoomManager.systemZoomFactor, 1.0, accuracy: 0.0001)
    }

    func testZoomLevelsAreSorted() {
        let levels = ZoomManager.zoomLevels
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertTrue(levels.contains(ZoomManager.defaultZoomFactor))
    }

    func testHUDPercentageText() {
        XCTAssertEqual(ZoomManager.percentageText(for: 1.0), "100%")
        XCTAssertEqual(ZoomManager.percentageText(for: 1.25), "125%")
        XCTAssertEqual(ZoomManager.percentageText(for: 0.7), "70%")
        XCTAssertEqual(ZoomManager.percentageText(for: 1.126), "113%")
    }
}
