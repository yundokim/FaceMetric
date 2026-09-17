import simd
import Testing
@testable import FaceMetric

struct RegistrationPipelineValidationTests {
    @Test
    func treatmentROIIsExcludedFromStableROIAndAnchorPatches() throws {
        let mesh = validationMesh()

        for region in RegistrationStudyRegion.allCases {
            let profile = RegistrationProfile.engineeringProfile(for: region)
            let treatment = Set(profile.treatmentVertexIndices(in: mesh))
            let stable = Set(profile.stableVertexIndices(in: mesh))
            let anchors = try AnatomicalAnchorExtractor().extract(
                from: mesh,
                definitions: profile.referenceAnchors
            )
            let anchorSources = anchors.reduce(into: Set<Int>()) {
                $0.formUnion($1.sourceVertices)
            }

            #expect(stable.isDisjoint(with: treatment))
            #expect(anchorSources.isDisjoint(with: treatment))
        }
    }

    @Test
    func signedPointToSurfaceDistanceUsesBaselineNormal() throws {
        let baseline = planarTriangleMesh(z: 0)
        let outward = planarTriangleMesh(z: 0.001)

        let result = try SurfaceDifferenceAnalyzer().analyze(
            baseline: baseline,
            alignedFollowup: outward,
            sampleIndices: [0, 1, 2]
        )

        #expect(abs(result.metrics.meanSignedResidual - 0.001) < 0.000_001)
        #expect(abs(result.metrics.rmsResidual - 0.001) < 0.000_001)
    }

    @Test
    func controlPoseIsRemovedByAllStrategies() throws {
        let baseline = validationMesh()
        let pose = rigidPose(
            angle: 0.16,
            translation: SIMD3<Float>(0.008, -0.006, 0.012)
        )
        let followup = pose.applying(to: baseline)
        let profile = RegistrationProfile.engineeringProfile(for: .chin)
        let extractor = AnatomicalAnchorExtractor()
        let baselineAnchors = try extractor.extract(
            from: baseline,
            definitions: profile.referenceAnchors
        )
        let followupAnchors = try extractor.extractCorresponding(
            from: followup,
            baselineAnchors: baselineAnchors
        )
        let directAnchorResult = try AnchorRigidRegistrationEngine().register(
            followup: followupAnchors,
            to: baselineAnchors
        )
        #expect(directAnchorResult.anchorRMSError < 0.000_01)
        let directlyAligned = directAnchorResult.transform.applying(to: followup)
        let directVertexVariance = try #require(
            FaceMeshAggregator.meanSquaredVertexDistance(
                from: baseline,
                to: directlyAligned
            )
        )
        #expect(sqrt(directVertexVariance) < 0.000_01)
        let comparison = try RegistrationStrategyComparisonEngine().compare(
            baseline: baseline,
            followup: followup,
            profile: profile
        )

        for result in comparison.strategyResults {
            #expect(result.stableROIResiduals.rmsResidual < 0.000_05)
        }
    }

    private func validationMesh(size: Int = 21) -> FaceMesh {
        var vertices: [SIMD3<Float>] = []
        var triangles: [Int16] = []

        for row in 0..<size {
            let normalizedY = Float(row) / Float(size - 1)
            let y = (normalizedY - 0.5) * 0.18
            for column in 0..<size {
                let normalizedX = Float(column) / Float(size - 1)
                let x = (normalizedX - 0.5) * 0.14
                let radial = 0.55 * pow(x / 0.07, 2)
                    + 0.42 * pow(y / 0.09, 2)
                let z = 0.018 * max(0, 1 - radial)
                vertices.append(SIMD3<Float>(x, y, z))
            }
        }

        for row in 0..<(size - 1) {
            for column in 0..<(size - 1) {
                let first = row * size + column
                let right = first + 1
                let upper = first + size
                let upperRight = upper + 1
                triangles.append(contentsOf: [
                    Int16(first), Int16(right), Int16(upper),
                    Int16(right), Int16(upperRight), Int16(upper)
                ])
            }
        }

        return FaceMesh(vertices: vertices, triangleIndices: triangles)
    }

    private func planarTriangleMesh(z: Float) -> FaceMesh {
        FaceMesh(
            vertices: [
                SIMD3<Float>(0, 0, z),
                SIMD3<Float>(0.01, 0, z),
                SIMD3<Float>(0, 0.01, z)
            ],
            triangleIndices: [0, 1, 2]
        )
    }

    private func rigidPose(
        angle: Float,
        translation: SIMD3<Float>
    ) -> RigidTransform {
        RigidTransform(
            matrix: simd_float3x3(
                simd_quatf(
                    angle: angle,
                    axis: simd_normalize(SIMD3<Float>(0.2, 0.7, 0.4))
                )
            ),
            translation: translation
        )
    }
}
