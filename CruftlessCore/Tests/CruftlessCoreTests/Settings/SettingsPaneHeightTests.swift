import CoreGraphics
@testable import CruftlessCore
import Testing

@Suite("Settings pane height")
struct SettingsPaneHeightTests {
    /// Readings taken while the Settings window animated to a new tab, which aborted the app in a layout loop.
    private static let animatedReadings: [SettingsPaneGeometry] = [
        (700, 0), (722, 0), (722, 77), (799, 77), (799, 38.5), (761, 38.5), (761, 57.5), (780, 57.5),
        (780, 48), (770, 48), (770, 53), (775, 53), (775, 50.5), (773, 50.5), (773, 51.5), (774, 51.5)
    ].map { container, inset in
        SettingsPaneGeometry(contentHeight: 722, containerHeight: container, topInset: inset)
    }

    @Test("Window-driven container and inset changes never change the measured height")
    func windowResizeDoesNotFeedBack() {
        let heights = Set(Self.animatedReadings.compactMap(SettingsPaneHeight.measuredHeight(of:)))
        #expect(heights == [722])
    }

    @Test("The estimate stands in until content is measured, capped")
    func estimateBeforeMeasurement() {
        let sizing = SettingsPaneHeight()
        #expect(sizing.height(estimate: 700, cap: 800) == 700)
        #expect(sizing.height(estimate: 900, cap: 800) == 800)
    }

    @Test("Content changes move the height both ways and the cap still applies")
    func contentChangesTrack() {
        var sizing = SettingsPaneHeight()
        sizing.record(706)
        #expect(sizing.height(estimate: 0, cap: 800) == 706)
        sizing.record(586)
        #expect(sizing.height(estimate: 0, cap: 800) == 586)
        sizing.record(900)
        #expect(sizing.height(estimate: 0, cap: 800) == 800)
    }

    @Test("Fractional content rounds up; empty or invalid content is no measurement")
    func measurementEdges() {
        #expect(SettingsPaneHeight.measuredHeight(of: .init(contentHeight: 705.2, containerHeight: 700)) == 706)
        #expect(SettingsPaneHeight.measuredHeight(of: .init(contentHeight: 0, containerHeight: 700)) == nil)
        #expect(SettingsPaneHeight.measuredHeight(of: .init(contentHeight: .nan, containerHeight: 700)) == nil)
    }
}
