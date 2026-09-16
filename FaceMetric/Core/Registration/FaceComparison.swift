import Foundation

/// Derived registration data kept separate from both immutable raw scans.
struct FaceComparison: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let baselineScanID: UUID
    let followupScanID: UUID
    let studyRegion: RegistrationStudyRegion
    let registrationComparison: RegistrationComparisonResult
    let expressionDifference: BetweenScanExpressionMetrics

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        baselineScanID: UUID,
        followupScanID: UUID,
        studyRegion: RegistrationStudyRegion,
        registrationComparison: RegistrationComparisonResult,
        expressionDifference: BetweenScanExpressionMetrics
    ) {
        self.id = id
        self.createdAt = createdAt
        self.baselineScanID = baselineScanID
        self.followupScanID = followupScanID
        self.studyRegion = studyRegion
        self.registrationComparison = registrationComparison
        self.expressionDifference = expressionDifference
    }

    var productionRegistration: StrategyRegistrationResult? {
        registrationComparison.result(for: .anchorAndStableROI)
    }
}
