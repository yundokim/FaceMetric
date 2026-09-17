import Foundation

enum FaceGeometryReferenceSex: String, Codable, CaseIterable, Sendable {
    case male
    case female
}

enum FaceGeometryReferenceSource: String, Codable, Sendable {
    case selectedAestheticCohort
    case manualAestheticReference
    case previousProvisionalReference
    case m01ProvisionalFallback
}

struct FaceGeometryMetricReference: Codable, Equatable, Sendable {
    let target: Float
    let idealInterval: ClosedRange<Float>
    let source: FaceGeometryReferenceSource
    let provenance: String
    let sampleCount: Int
    let isProvisional: Bool
}

struct FaceGeometryReferenceProfile: Codable, Equatable, Sendable {
    let sex: FaceGeometryReferenceSex
    let version: String
    let metricReferences: [FaceGeometryMetricID: FaceGeometryMetricReference]

    func reference(for metricID: FaceGeometryMetricID) -> FaceGeometryMetricReference? {
        metricReferences[metricID]
    }

    static let maleV01 = FaceGeometryReferenceProfile(
        sex: .male,
        version: "male-v0.1",
        metricReferences: [
            .faceHeightWidth: .maleV01Manual(target: 1.7032, interval: 1.678...1.728),
            .upperThirdRatio: .maleV01Fallback(target: 0.992, interval: 0.972...1.012, missingLandmark: "Sn"),
            .middleThirdRatio: .maleV01Fallback(target: 1.063, interval: 1.038...1.088, missingLandmark: "Sn"),
            .lowerThirdRatio: .maleV01Fallback(target: 0.945, interval: 0.920...0.970, missingLandmark: "Sn"),
            .leftEyeWidthRatio: .maleV01Manual(target: 0.24125, interval: 0.236...0.246, provenance: "Latest M01 manual annotation; left/right mean"),
            .rightEyeWidthRatio: .maleV01Manual(target: 0.24125, interval: 0.236...0.246, provenance: "Latest M01 manual annotation; left/right mean"),
            .leftEyeAspectRatio: .maleV01Manual(target: 2.37890, interval: 2.279...2.479, provenance: "Latest M01 manual annotation; left/right mean"),
            .rightEyeAspectRatio: .maleV01Manual(target: 2.37890, interval: 2.279...2.479, provenance: "Latest M01 manual annotation; left/right mean"),
            .intercanthalRatio: .maleV01Manual(target: 0.32586, interval: 0.319...0.333),
            .noseWidthRatio: .maleV01Manual(target: 0.31553, interval: 0.308...0.324),
            .upperLowerLipRatio: .maleV01Fallback(target: 0.889, interval: 0.854...0.924, missingLandmark: "Li")
        ]
    )

    // Female cohort measurements have not been established. This placeholder intentionally
    // contains no targets or intervals and is not used as an active scoring profile.
    static let femalePlaceholder = FaceGeometryReferenceProfile(
        sex: .female,
        version: "Female Reference unavailable",
        metricReferences: [:]
    )
}

enum FaceGeometryReferenceProfileAvailability: Equatable, Sendable {
    case available(FaceGeometryReferenceProfile)
    case unavailable(sex: FaceGeometryReferenceSex)
}

enum FaceGeometryReferenceProfiles {
    static func availability(for sex: FaceGeometryReferenceSex) -> FaceGeometryReferenceProfileAvailability {
        switch sex {
        case .male:
            return .available(.maleV01)
        case .female:
            return .unavailable(sex: .female)
        }
    }

    static func profile(for sex: FaceGeometryReferenceSex) -> FaceGeometryReferenceProfile? {
        guard case .available(let profile) = availability(for: sex) else {
            return nil
        }
        return profile
    }
}

private extension FaceGeometryMetricReference {
    static func maleV01Manual(
        target: Float,
        interval: ClosedRange<Float>,
        provenance: String = "Latest M01 manual annotation"
    ) -> FaceGeometryMetricReference {
        FaceGeometryMetricReference(
            target: target,
            idealInterval: interval,
            source: .manualAestheticReference,
            provenance: provenance,
            sampleCount: 1,
            isProvisional: true
        )
    }

    static func maleV01Fallback(
        target: Float,
        interval: ClosedRange<Float>,
        missingLandmark: String
    ) -> FaceGeometryMetricReference {
        FaceGeometryMetricReference(
            target: target,
            idealInterval: interval,
            source: .m01ProvisionalFallback,
            provenance: "M01 provisional fallback retained because the latest annotation is missing \(missingLandmark)",
            sampleCount: 1,
            isProvisional: true
        )
    }
}
