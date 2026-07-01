import CoreGraphics
@testable import KkaciCore

struct FakeDisplayProvider: HidePointProviding {
    let point: CGPoint

    func hidePoint(for frame: WindowFrame) -> CGPoint {
        point
    }
}
