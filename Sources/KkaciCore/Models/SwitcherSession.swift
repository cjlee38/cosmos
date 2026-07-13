import Foundation

public enum SwitcherDirection {
    case forward
    case backward
}

public enum SwitcherArrowDirection {
    case left
    case right
}

public struct SwitcherSession<Item: Equatable>: Equatable {
    public let items: [Item]
    public private(set) var selectedIndex: Int

    public init?(items: [Item], currentItem: Item?, direction: SwitcherDirection) {
        guard !items.isEmpty else {
            return nil
        }

        self.items = items
        if let currentItem, let currentIndex = items.firstIndex(of: currentItem) {
            selectedIndex = Self.advancedIndex(currentIndex, count: items.count, direction: direction)
        } else {
            selectedIndex = 0
        }
    }

    public var selectedItem: Item {
        items[selectedIndex]
    }

    public mutating func step(_ direction: SwitcherDirection, wraps: Bool = true) {
        selectedIndex = Self.advancedIndex(
            selectedIndex,
            count: items.count,
            direction: direction,
            wraps: wraps
        )
    }

    public mutating func move(_ direction: SwitcherArrowDirection) {
        switch direction {
        case .left:
            selectedIndex = max(selectedIndex - 1, 0)
        case .right:
            selectedIndex = min(selectedIndex + 1, items.count - 1)
        }
    }

    @discardableResult
    public mutating func select(_ item: Item) -> Bool {
        guard let index = items.firstIndex(of: item) else {
            return false
        }

        selectedIndex = index
        return true
    }

    private static func advancedIndex(
        _ index: Int,
        count: Int,
        direction: SwitcherDirection,
        wraps: Bool = true
    ) -> Int {
        switch direction {
        case .forward:
            wraps ? (index + 1) % count : min(index + 1, count - 1)
        case .backward:
            wraps ? (index + count - 1) % count : max(index - 1, 0)
        }
    }
}
