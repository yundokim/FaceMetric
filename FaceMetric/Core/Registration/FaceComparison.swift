import Foundation

/// Derived M5 data kept separate from both immutable raw scans.
struct FaceComparison: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let baselineScanID: UUID
    let followupScanID: UUID
    let registrationResult: RegistrationResult

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        baselineScanID: UUID,
        followupScanID: UUID,
        registrationResult: RegistrationResult
    ) {
        self.id = id
        self.createdAt = createdAt
        self.baselineScanID = baselineScanID
        self.followupScanID = followupScanID
        self.registrationResult = registrationResult
    }
}
