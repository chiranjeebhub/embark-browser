import Foundation
import Testing

/// Zooming steps through Chrome's levels.
struct ZoomTests {
    @Test func zoomingInAndOutStepsThroughTheLevels() {
        #expect(Zoom.zoomedIn(from: 1) == 1.1)
        #expect(Zoom.zoomedOut(from: 1) == 0.9)
        #expect(Zoom.zoomedIn(from: 1.05) == 1.1)
        #expect(Zoom.zoomedOut(from: 1.05) == 1)
    }

    @Test func zoomStopsAtTheEnds() {
        #expect(Zoom.zoomedIn(from: 5) == 5)
        #expect(Zoom.zoomedOut(from: 0.25) == 0.25)
    }

    @Test func percentRounds() {
        #expect(Zoom.percent(1.25) == "125%")
        #expect(Zoom.percent(0.33) == "33%")
        #expect(Zoom.percent(pow(1.2, 1)) == "120%")
    }
}
