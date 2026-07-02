import Foundation

enum CycleDirection {
    case forward
    case backward
}

func cycledValue<T: Equatable>(in values: [T], after current: T?, direction: CycleDirection) -> T? {
    guard !values.isEmpty else {
        return nil
    }

    guard let current, let index = values.firstIndex(of: current) else {
        return values.first
    }

    switch direction {
    case .forward:
        return values[(index + 1) % values.count]
    case .backward:
        return values[(index + values.count - 1) % values.count]
    }
}
