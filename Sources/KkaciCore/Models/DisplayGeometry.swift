import CoreGraphics

public enum DisplayGeometry {
    public static func index(
        containingOrNearest point: CGPoint,
        among frames: [CGRect]
    ) -> Int? {
        frames.firstIndex(where: { $0.contains(point) })
            ?? frames.indices.min { lhs, rhs in
                distanceSquared(from: point, to: frames[lhs])
                    < distanceSquared(from: point, to: frames[rhs])
            }
    }

    static func display(
        containingOrNearest point: CGPoint,
        among displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        guard let index = index(
            containingOrNearest: point,
            among: displays.map(\.frame)
        ) else {
            return nil
        }
        return displays[index]
    }

    static func clamp(_ origin: CGPoint, size: CGSize, inside rect: CGRect) -> CGPoint {
        CGPoint(
            x: clamp(origin.x, length: size.width, min: rect.minX, max: rect.maxX),
            y: clamp(origin.y, length: size.height, min: rect.minY, max: rect.maxY)
        )
    }

    static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    static func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private static func clamp(
        _ value: CGFloat,
        length: CGFloat,
        min minValue: CGFloat,
        max maxValue: CGFloat
    ) -> CGFloat {
        guard length <= maxValue - minValue else {
            return minValue
        }
        return min(max(value, minValue), maxValue - length)
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
