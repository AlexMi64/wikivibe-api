import AppKit
import XCTest
@testable import Codenotch

/// The working arc turns in Core Animation rather than SwiftUI, so what the
/// SwiftUI version said in its modifiers is pinned here on the layer instead.
@MainActor
final class SpinningArcTests: XCTestCase {
    private func hosted(_ view: SpinningArcView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
                              styleMask: .borderless, backing: .buffered, defer: true)
        // Closed by the test while ARC still holds it.
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        return window
    }

    private func arcView(queued: Bool = false, turns: Bool = true) -> SpinningArcView {
        let side = NotchLayout.ringDiameter
        let view = SpinningArcView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        let inset = (NotchLayout.ringDiameter - NotchLayout.activityDiameter) / 2
        view.configure(color: .white, arcFraction: queued ? 1 : 0.25, dashed: queued,
                       inset: inset, turns: turns)
        view.layout()
        return view
    }

    func testTheArcIsAQuarterOfTheActivityCircle() {
        let view = arcView()
        XCTAssertEqual(view.arc.strokeStart, 0)
        XCTAssertEqual(view.arc.strokeEnd, 0.25)
        XCTAssertNil(view.arc.lineDashPattern)
        XCTAssertEqual(view.arc.lineWidth, NotchLayout.activityStroke)
        XCTAssertEqual(view.arc.lineCap, .round)

        let box = view.arc.path?.boundingBoxOfPath ?? .zero
        XCTAssertEqual(box.width, NotchLayout.activityDiameter, accuracy: 0.01,
                       "The arc must sit on the same circle the SwiftUI inset produced")
        XCTAssertEqual(box.midX, view.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(box.midY, view.bounds.midY, accuracy: 0.01)
    }

    func testQueuedRequestsDrawTheWholeCircleAsDots() {
        let view = arcView(queued: true)
        XCTAssertEqual(view.arc.strokeEnd, 1)
        XCTAssertEqual(view.arc.lineDashPattern?.count, 2)
    }

    func testItTurnsClockwiseOnceEveryPointOneOneSecondsOnScreen() throws {
        let view = arcView()
        let window = hosted(view)
        defer { window.close() }

        let turn = try XCTUnwrap(view.arc.animation(forKey: SpinningArcView.animationKey) as? CABasicAnimation)
        XCTAssertEqual(turn.keyPath, "transform.rotation.z")
        XCTAssertEqual(turn.duration, 1.1)
        XCTAssertEqual(turn.repeatCount, .infinity)
        // y-up layer coordinates: a negative angle is a clockwise turn.
        XCTAssertEqual((turn.toValue as? Double) ?? 0, -2 * .pi, accuracy: 0.0001)
    }

    func testReduceMotionHoldsItStill() {
        let view = arcView(turns: false)
        let window = hosted(view)
        defer { window.close() }
        XCTAssertNil(view.arc.animation(forKey: SpinningArcView.animationKey))
    }

    func testItNeverTakesAClick() {
        let view = arcView()
        XCTAssertNil(view.hitTest(NSPoint(x: view.bounds.midX, y: view.bounds.midY)))
    }
}
