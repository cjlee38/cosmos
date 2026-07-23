import CoreGraphics
@testable import CosmosCore

final class FakeDisplayProvider: DisplayProviding, HidePointProviding {
    let point: CGPoint
    var snapshots: [DisplaySnapshot]
    var displayError: Error?
    private(set) var displayQueryCount = 0

    init(
        point: CGPoint = CGPoint(x: 999, y: 999),
        snapshots: [DisplaySnapshot] = [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main)
        ]
    ) {
        self.point = point
        self.snapshots = snapshots
    }

    func hidePoint(for _: WindowFrame) throws -> CGPoint {
        point
    }

    func displays() throws -> [DisplaySnapshot] {
        displayQueryCount += 1
        if let displayError {
            throw displayError
        }
        return snapshots
    }
}
