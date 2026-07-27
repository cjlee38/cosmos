import Foundation

public struct SpaceID: RawRepresentable, Hashable, Comparable, Codable, CaseIterable, ExpressibleByStringLiteral {
    public static let allCases: [SpaceID] = {
        let numbers = (0 ... 9).map { SpaceID(unchecked: String($0)) }
        let letters = (UnicodeScalar("A").value ... UnicodeScalar("Z").value).compactMap {
            UnicodeScalar($0).map { SpaceID(unchecked: String(Character($0))) }
        }
        return numbers + letters
    }()

    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.uppercased()
        guard Self.allRawValues.contains(normalized) else {
            return nil
        }
        self.init(unchecked: normalized)
    }

    public init(stringLiteral value: String) {
        guard let id = SpaceID(rawValue: value) else {
            panic("Invalid space ID: \(value)")
        }
        self = id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = if let number = try? container.decode(Int.self) {
            String(number)
        } else {
            try container.decode(String.self)
        }

        guard let id = SpaceID(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid space ID: \(value). Expected 0...9 or A...Z"
            )
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let number = Int(rawValue) {
            try container.encode(number)
        } else {
            try container.encode(rawValue)
        }
    }

    public static func < (lhs: SpaceID, rhs: SpaceID) -> Bool {
        orderByRawValue[lhs.rawValue, default: 0] < orderByRawValue[rhs.rawValue, default: 0]
    }

    public var defaultShortcutKey: String {
        rawValue.lowercased()
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    private static let allRawValues = Set(allCases.map(\.rawValue))
    private static let orderByRawValue = Dictionary(
        uniqueKeysWithValues: allCases.enumerated().map { ($0.element.rawValue, $0.offset) }
    )
}
