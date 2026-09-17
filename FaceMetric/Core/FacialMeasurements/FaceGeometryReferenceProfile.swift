import Foundation

enum FaceGeometryReferenceSex: String, Codable, CaseIterable, Sendable {
    case male
    case female
}

enum FaceGeometryReferenceSource: String, Codable, Sendable {
    case manualAestheticReference
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
    let metricReferences: [FaceGeometryMetricID: FaceGeometryMetricReference]

    func reference(
        for metricID: FaceGeometryMetricID
    ) -> FaceGeometryMetricReference? {
        metricReferences[metricID]
    }
}

enum FaceGeometryReferenceProfiles {

    static let male = FaceGeometryReferenceProfile(
        sex: .male,
        metricReferences: [

            .faceHeightWidth: reference(
                target: 1.6459,
                interval: 1.605...1.687
            ),

            .upperThirdRatio: reference(
                target: 0.9778,
                interval: 0.958...0.998
            ),

            .middleThirdRatio: reference(
                target: 1.0720,
                interval: 1.047...1.097
            ),

            .lowerThirdRatio: reference(
                target: 0.9502,
                interval: 0.927...0.974
            ),

            .leftEyeWidthRatio: reference(
                target: 0.2360,
                interval: 0.231...0.241
            ),

            .rightEyeWidthRatio: reference(
                target: 0.2360,
                interval: 0.231...0.241
            ),

            .leftEyeAspectRatio: reference(
                target: 2.4121,
                interval: 2.312...2.512
            ),

            .rightEyeAspectRatio: reference(
                target: 2.4121,
                interval: 2.312...2.512
            ),

            .intercanthalRatio: reference(
                target: 0.3123,
                interval: 0.305...0.319
            ),

            .noseWidthRatio: reference(
                target: 0.3058,
                interval: 0.298...0.314
            ),

            .upperLowerLipRatio: reference(
                target: 0.7979,
                interval: 0.758...0.838
            )
        ]
    )

    static func profile(
        for sex: FaceGeometryReferenceSex
    ) -> FaceGeometryReferenceProfile? {
        switch sex {
        case .male:
            return male

        case .female:
            // Female reference values will be added after
            // the female reference cohort has been measured.
            return nil
        }
    }

    private static func reference(
        target: Float,
        interval: ClosedRange<Float>
    ) -> FaceGeometryMetricReference {
        FaceGeometryMetricReference(
            target: target,
            idealInterval: interval,
            source: .manualAestheticReference,
            provenance:
                "Manual 2D anatomical landmark annotation of selected male aesthetic reference samples M01-M02.",
            sampleCount: 2,
            isProvisional: true
        )
    }
}
