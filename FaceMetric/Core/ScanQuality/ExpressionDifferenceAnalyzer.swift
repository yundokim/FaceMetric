import Foundation

struct BlendShapeDifference: Codable, Equatable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let baselineValue: Float
    let followupValue: Float
    let delta: Float
}

struct BetweenScanExpressionMetrics: Codable, Equatable, Sendable {
    let rmsDifference: Float
    let maximumAbsoluteDifference: Float
    let largestDifferences: [BlendShapeDifference]
    let exceedsEngineeringWarningLevel: Bool
}

enum ExpressionDifferenceAnalyzer {
    /// Engineering flag only. This has not been validated as a neutral-expression threshold.
    nonisolated static let engineeringWarningRMS: Float = 0.05

    nonisolated static func compare(
        baseline: [String: Float],
        followup: [String: Float]
    ) -> BetweenScanExpressionMetrics {
        let names = Set(baseline.keys).union(followup.keys).sorted()
        guard !names.isEmpty else {
            return BetweenScanExpressionMetrics(
                rmsDifference: 0,
                maximumAbsoluteDifference: 0,
                largestDifferences: [],
                exceedsEngineeringWarningLevel: false
            )
        }

        let differences = names.map { name in
            let baselineValue = baseline[name] ?? 0
            let followupValue = followup[name] ?? 0
            return BlendShapeDifference(
                name: name,
                baselineValue: baselineValue,
                followupValue: followupValue,
                delta: followupValue - baselineValue
            )
        }
        let rms = sqrt(
            differences.reduce(Float.zero) { $0 + $1.delta * $1.delta }
                / Float(differences.count)
        )
        let sorted = differences.sorted { abs($0.delta) > abs($1.delta) }

        return BetweenScanExpressionMetrics(
            rmsDifference: rms,
            maximumAbsoluteDifference: sorted.first.map { abs($0.delta) } ?? 0,
            largestDifferences: Array(sorted.prefix(5)),
            exceedsEngineeringWarningLevel: rms > engineeringWarningRMS
        )
    }
}
