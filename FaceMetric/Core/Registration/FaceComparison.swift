import Foundation

/// Derived registration data kept separate from both immutable raw scans.
struct FaceComparison: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let baselineScanID: UUID
    let followupScanID: UUID
    let studyRegion: RegistrationStudyRegion
    let registrationComparison: RegistrationComparisonResult

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        baselineScanID: UUID,
        followupScanID: UUID,
        studyRegion: RegistrationStudyRegion,
        registrationComparison: RegistrationComparisonResult
    ) {
        self.id = id
        self.createdAt = createdAt
        self.baselineScanID = baselineScanID
        self.followupScanID = followupScanID
        self.studyRegion = studyRegion
        self.registrationComparison = registrationComparison
    }

    var productionRegistration: StrategyRegistrationResult? {
        registrationComparison.result(for: .anchorAndStableROI)
    }
}
