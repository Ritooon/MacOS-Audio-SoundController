import Testing
@testable import Orpheus

@Suite("VolumeBarMath")
struct VolumeBarMathTests {
    @Test func positionMapsToValue() {
        #expect(VolumeBarMath.value(at: 50, width: 200, maximum: 1) == 0.25)
        #expect(VolumeBarMath.value(at: 100, width: 200, maximum: 2) == 1)
    }

    @Test func positionOutsideBarIsClamped() {
        #expect(VolumeBarMath.value(at: -20, width: 200, maximum: 1) == 0)
        #expect(VolumeBarMath.value(at: 260, width: 200, maximum: 1) == 1)
    }

    @Test func zeroWidthGivesZero() {
        #expect(VolumeBarMath.value(at: 10, width: 0, maximum: 1) == 0)
    }

    @Test func steppingSnapsAndClamps() {
        #expect(abs(VolumeBarMath.stepped(0.52, by: 1, maximum: 1) - 0.55) < 0.0001)
        #expect(abs(VolumeBarMath.stepped(0.52, by: -1, maximum: 1) - 0.45) < 0.0001)
        #expect(VolumeBarMath.stepped(0.98, by: 1, maximum: 1) == 1)
        #expect(VolumeBarMath.stepped(0.01, by: -1, maximum: 1) == 0)
    }

    @Test func percentIsRounded() {
        #expect(VolumeBarMath.percent(0.555) == 56)
        #expect(VolumeBarMath.percent(1.5) == 150)
        #expect(VolumeBarMath.percent(0) == 0)
    }
}
