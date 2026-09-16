import simd
import Testing
@testable import FaceMetric

struct AnatomicalAnchorRegistrationTests {
    @Test
    func patchExtractionUsesTrimmedCentroid() throws {
        let vertices: [SIMD3<Float>] = [
            SIMD3(0.0, 0.0, 0.0),
            SIMD3(0.001, 0.0, 0.0),
            SIMD3(0.0, 0.001, 0.0),
            SIMD3(0.001, 0.001, 0.0),
            SIMD3(0.0005, 0.0005, 0.0001),
            SIMD3(0.0005, 0.0005, 0.02),
            SIMD3(0.02, 0.02, 0.02)
        ]
        let mesh = FaceMesh(vertices: vertices, triangleIndices: [])
        let definition = AnatomicalAnchorDefinition(
            id: .upperForehead,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(repeating: 0),
                maximum: SIMD3<Float>(repeating: 1)
            ),
            minimumVertexCount: 4,
            trimFraction: 0.3
        )

        let anchor = try AnatomicalAnchorExtractor()
            .extract(from: mesh, definitions: [definition])[0]

        #expect(anchor.sourceVertices.count == 4)
        #expect(anchor.position.z < 0.001)
    }

    @Test
    func identicalAnchorSetsProduceIdentity() throws {
        let anchors = baselineAnchors()
        let result = try engine.register(followup: anchors, to: anchors)

        #expect(result.anchorRMSError < 0.000_001)
        #expect(simd_length(result.translation.simdValue) < 0.000_001)
        #expect(abs(result.qualityMetadata.rotationDeterminant - 1) < 0.000_01)
    }

    @Test
    func knownTranslationIsRecovered() throws {
        let pose = RigidTransform(
            rotation: RigidTransform.identity.rotation,
            translation: SIMD3<Float>(0.012, -0.007, 0.009)
        )
        try expectPoseRecovered(pose)
    }

    @Test
    func knownRotationIsRecovered() throws {
        try expectPoseRecovered(poseTransform(angle: 0.19, translation: .zero))
    }

    @Test
    func knownRotationAndTranslationAreRecovered() throws {
        try expectPoseRecovered(
            poseTransform(
                angle: -0.23,
                translation: SIMD3<Float>(-0.008, 0.006, 0.011)
            )
        )
    }

    @Test
    func noisyAnchorsReportBoundedTransformError() throws {
        let baseline = baselineAnchors()
        let pose = poseTransform(
            angle: 0.14,
            translation: SIMD3<Float>(0.006, -0.004, 0.008)
        )
        let offsets: [SIMD3<Float>] = [
            SIMD3(0.0002, 0, 0),
            SIMD3(-0.0001, 0.0002, 0),
            SIMD3(0, -0.0002, 0.0001),
            SIMD3(0.0001, 0, -0.0002),
            SIMD3(-0.0002, 0.0001, 0)
        ]
        let followup = zip(baseline, offsets).map { anchor, noise in
            AnatomicalAnchor(
                id: anchor.id,
                position: pose.applying(to: anchor.position.simdValue) + noise,
                confidence: anchor.confidence,
                sourceVertices: anchor.sourceVertices
            )
        }

        let result = try engine.register(followup: followup, to: baseline)
        let alignedRMS = anchorAlignmentRMS(result.transform, followup, baseline)

        #expect(alignedRMS < 0.000_35)
        #expect(result.anchorRMSError < 0.000_35)
    }

    @Test
    func singleOutlierIsRecordedAndRobustlyDownweighted() throws {
        let baseline = baselineAnchors()
        var followup = baseline
        let outlier = followup[4]
        followup[4] = AnatomicalAnchor(
            id: outlier.id,
            position: outlier.position.simdValue + SIMD3<Float>(0.02, -0.015, 0.01),
            confidence: 1,
            sourceVertices: outlier.sourceVertices
        )

        let result = try engine.register(followup: followup, to: baseline)

        #expect(result.qualityMetadata.rejectedOrDownweightedAnchors.contains(outlier.id))
        #expect(
            result.anchorResiduals.first(where: { $0.id == outlier.id })?.decision
                == .robustlyDownweighted
        )
    }

    @Test
    func collinearAnchorsFailSafely() {
        let anchors = (0..<4).map { index in
            AnatomicalAnchor(
                id: AnchorID.allCases[index],
                position: SIMD3<Float>(Float(index) * 0.01, 0, 0),
                confidence: 1,
                sourceVertices: [index]
            )
        }

        #expect(throws: AnchorRigidRegistrationError.self) {
            try engine.register(followup: anchors, to: anchors)
        }
    }

    private let engine = AnchorRigidRegistrationEngine()

    private func expectPoseRecovered(_ pose: RigidTransform) throws {
        let baseline = baselineAnchors()
        let followup = baseline.map { anchor in
            AnatomicalAnchor(
                id: anchor.id,
                position: pose.applying(to: anchor.position.simdValue),
                confidence: anchor.confidence,
                sourceVertices: anchor.sourceVertices
            )
        }

        let result = try engine.register(followup: followup, to: baseline)
        #expect(anchorAlignmentRMS(result.transform, followup, baseline) < 0.000_01)
        #expect(result.anchorRMSError < 0.000_01)
    }

    private func baselineAnchors() -> [AnatomicalAnchor] {
        let positions: [SIMD3<Float>] = [
            SIMD3(-0.03, 0.05, 0.002),
            SIMD3(0.03, 0.05, 0.003),
            SIMD3(-0.035, 0.015, 0.008),
            SIMD3(0.035, 0.015, 0.009),
            SIMD3(0, 0.025, 0.018)
        ]
        return zip(AnchorID.allCases, positions).enumerated().map { index, pair in
            AnatomicalAnchor(
                id: pair.0,
                position: pair.1,
                confidence: 1,
                sourceVertices: [index]
            )
        }
    }

    private func poseTransform(angle: Float, translation: SIMD3<Float>) -> RigidTransform {
        let rotation = simd_float3x3(
            simd_quatf(
                angle: angle,
                axis: simd_normalize(SIMD3<Float>(0.3, 0.8, 0.5))
            )
        )
        return RigidTransform(matrix: rotation, translation: translation)
    }

    private func anchorAlignmentRMS(
        _ transform: RigidTransform,
        _ followup: [AnatomicalAnchor],
        _ baseline: [AnatomicalAnchor]
    ) -> Float {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let squared = followup.compactMap { anchor -> Float? in
            guard let target = baselineByID[anchor.id] else { return nil }
            return simd_length_squared(
                transform.applying(to: anchor.position.simdValue)
                    - target.position.simdValue
            )
        }
        return sqrt(squared.reduce(0, +) / Float(squared.count))
    }
}
