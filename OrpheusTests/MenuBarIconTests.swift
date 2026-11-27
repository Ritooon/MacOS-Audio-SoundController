import AppKit
import Testing
@testable import Orpheus

@MainActor
@Suite("MenuBarIcon")
struct MenuBarIconTests {
    @Test(arguments: [MenuBarIcon.State.normal, .boosted, .muted])
    func iconIsMenuBarSizedAndNotTemplate(state: MenuBarIcon.State) {
        let image = MenuBarIcon.image(for: state)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(!image.isTemplate)
    }

    @Test func iconIsCachedPerState() {
        #expect(MenuBarIcon.image(for: .normal) === MenuBarIcon.image(for: .normal))
        #expect(MenuBarIcon.image(for: .normal) !== MenuBarIcon.image(for: .muted))
    }

    @Test func lyreFillsTheIconBounds() {
        let box = LyreGeometry.frame.boundingBoxOfPath.union(LyreGeometry.base.boundingBoxOfPath)
        #expect(LyreGeometry.bounds.insetBy(dx: -0.05, dy: -0.05).contains(box))
    }
}
