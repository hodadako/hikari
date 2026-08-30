import Foundation

public struct HikariVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
        guard let normalized, !normalized.isEmpty else { return nil }

        let parts = normalized.split(separator: ".")
        guard !parts.isEmpty,
              parts.allSatisfy({ Int($0) != nil }) else {
            return nil
        }
        var parsedComponents = parts.map { Int($0)! }
        while parsedComponents.count > 1, parsedComponents.last == 0 {
            parsedComponents.removeLast()
        }
        components = parsedComponents
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: HikariVersion, rhs: HikariVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
