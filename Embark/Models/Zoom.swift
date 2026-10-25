import Foundation

/// Page zoom steps, the same as Chrome's.
enum Zoom {
    static let steps: [Double] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]

    /// The next step up from `factor`, or the largest.
    static func zoomedIn(from factor: Double) -> Double {
        steps.first { $0 > factor + 0.001 } ?? steps.last!
    }

    /// The next step down from `factor`, or the smallest.
    static func zoomedOut(from factor: Double) -> Double {
        steps.last { $0 < factor - 0.001 } ?? steps.first!
    }

    /// "125%".
    static func percent(_ factor: Double) -> String {
        "\(Int((factor * 100).rounded()))%"
    }
}
