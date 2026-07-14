import CoreGraphics
@testable import KkaciCore

final class FakeDisplayProvider: DisplayProviding {
    let point: CGPoint
    var snapshots: [DisplaySnapshot]
    private(set) var displayQueryCount = 0

    init(
        point: CGPoint = CGPoint(x: 999, y: 999),
        snapshots: [DisplaySnapshot] = [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), isMain: true)
        ]
    ) {
        self.point = point
        self.snapshots = snapshots
    }

    func hidePoint(for _: WindowFrame) -> CGPoint {
        point
    }

    func displays() -> [DisplaySnapshot] {
        displayQueryCount += 1
        return snapshots
    }
}
