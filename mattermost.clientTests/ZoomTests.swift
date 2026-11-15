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
    // XCTest's setUp/tearDown overrides are nonisolated on some toolchains, so
    // restore the shared zoom factor inside each test via this helper instead.
    private func withPreservedZoom(_ body: () -> Void) {
        let original = ZoomManager.shared.currentZoomFactor
        defer { ZoomManager.shared.setZoomFactor(original) }
        body()
    }

    func testZoomInAndOutFollowPresetLevels() {
        withPreservedZoom {
            ZoomManager.shared.setZoomFactor(1.0)

            ZoomManager.shared.zoomIn()
            XCTAssertEqual(ZoomManager.shared.currentZoomFactor, 1.1, accuracy: 0.0001)

            ZoomManager.shared.zoomOut()
            XCTAssertEqual(ZoomManager.shared.currentZoomFactor, 1.0, accuracy: 0.0001)
        }
    }

    func testZoomStopsAtPresetBounds() {
        withPreservedZoom {
            ZoomManager.shared.setZoomFactor(2.5)
            ZoomManager.shared.zoomIn()
            XCTAssertEqual(ZoomManager.shared.currentZoomFactor, 2.5, accuracy: 0.0001)

            ZoomManager.shared.setZoomFactor(0.6)
            ZoomManager.shared.zoomOut()
            XCTAssertEqual(
                ZoomManager.shared.currentZoomFactor,
                ZoomManager.minZoomFactor,
                accuracy: 0.0001
            )
        }
    }

    func testSetZoomFactorClampsToRange() {
        withPreservedZoom {
            ZoomManager.shared.setZoomFactor(9)
            XCTAssertEqual(
                ZoomManager.shared.currentZoomFactor,
                ZoomManager.maxZoomFactor,
                accuracy: 0.0001
            )

            ZoomManager.shared.setZoomFactor(0.1)
            XCTAssertEqual(
                ZoomManager.shared.currentZoomFactor,
                ZoomManager.minZoomFactor,
                accuracy: 0.0001
            )
        }
    }

    func testResetZoomUsesDefault() {
        withPreservedZoom {
            ZoomManager.shared.setZoomFactor(1.5)
            ZoomManager.shared.resetZoom()
            XCTAssertEqual(
                ZoomManager.shared.currentZoomFactor,
                ZoomManager.defaultZoomFactor,
                accuracy: 0.0001
            )
        }
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
