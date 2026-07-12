import Foundation

public enum SwitcherDirection {
    case forward
    case backward
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

    public mutating func step(_ direction: SwitcherDirection) {
        selectedIndex = Self.advancedIndex(selectedIndex, count: items.count, direction: direction)
    }

    @discardableResult
    public mutating func select(_ item: Item) -> Bool {
        guard let index = items.firstIndex(of: item) else {
            return false
        }

        selectedIndex = index
        return true
    }

    private static func advancedIndex(_ index: Int, count: Int, direction: SwitcherDirection) -> Int {
        switch direction {
        case .forward:
            (index + 1) % count
        case .backward:
            (index + count - 1) % count
        }
    }
}
