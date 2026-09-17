import simd
import Testing
@testable import FaceMetric

struct FaceMetricTests {
    private let configuration = ScanQualityConfiguration.engineeringDefault

    @Test
    func coordinateMedianRejectsTransientOutlier() throws {
        let topology: [Int16] = [0, 1, 2]
        let meshes = [
            mesh(x: 0, topology: topology),
            mesh(x: 0.001, topology: topology),
            mesh(x: 0.5, topology: topology)
        ]

        let result = try FaceMeshAggregator.coordinateMedian(of: meshes)

        #expect(abs(result.vertices[0].x - 0.001) < 0.000_001)
        #expect(result.triangleIndices == topology)
    }

    @Test
    func meshVarianceIsMeanSquaredVertexDistance() {
        let baseline = FaceMesh(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)],
            triangleIndices: []
        )
        let shifted = FaceMesh(
            vertices: [SIMD3(0.001, 0, 0), SIMD3(1.003, 0, 0)],
            triangleIndices: []
        )

        let variance = FaceMeshAggregator.meanSquaredVertexDistance(
            from: baseline,
            to: shifted
        )

        #expect(variance != nil)
        #expect(abs((variance ?? 0) - 0.000_005) < 0.000_000_001)
    }

    @Test
    func stableCenteredFrameIsAccepted() {
        let mesh = mesh(x: 0, topology: [0, 1, 2])
        let cameraToFace = cameraToFaceTransform()

        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: mesh,
            blendShapes: ["jawOpen": 0],
            previousBlendShapes: ["jawOpen": 0],
            cameraToFaceTransform: cameraToFace,
            trackingState: .normal,
            configuration: configuration
        )

        #expect(evaluation.isFrameValid)
        #expect(evaluation.guidance == .ready)
        #expect(abs(evaluation.metrics.distance - 0.4) < 0.000_001)
        #expect(evaluation.metrics.meshVariance == 0)
    }

    @Test
    func excessiveYawIsRejectedWithPoseGuidance() {
        let cameraToFace = cameraToFaceTransform(
            yaw: 15 * .pi / 180
        )
        let mesh = mesh(x: 0, topology: [0, 1, 2])

        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: mesh,
            blendShapes: [:],
            previousBlendShapes: [:],
            cameraToFaceTransform: cameraToFace,
            trackingState: .normal,
            configuration: configuration
        )

        #expect(!evaluation.isFrameValid)
        #expect(evaluation.guidance == .lookStraightAhead)
        #expect(abs(evaluation.metrics.yaw - 15 * .pi / 180) < 0.000_1)
    }

    @Test
    func expressionChangeIsRejected() {
        let cameraToFace = cameraToFaceTransform()
        let mesh = mesh(x: 0, topology: [0, 1, 2])

        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: mesh,
            blendShapes: ["jawOpen": 0.1],
            previousBlendShapes: ["jawOpen": 0],
            cameraToFaceTransform: cameraToFace,
            trackingState: .normal,
            configuration: configuration
        )

        #expect(!evaluation.isFrameValid)
        #expect(!evaluation.metrics.expressionStable)
        #expect(evaluation.guidance == .keepNeutralExpression)
    }

    @Test
    func stableNonNeutralExpressionIsRejected() {
        let cameraToFace = cameraToFaceTransform()
        let mesh = mesh(x: 0, topology: [0, 1, 2])

        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: mesh,
            blendShapes: ["mouthSmileLeft": 0.4, "mouthSmileRight": 0.4],
            previousBlendShapes: ["mouthSmileLeft": 0.4, "mouthSmileRight": 0.4],
            cameraToFaceTransform: cameraToFace,
            trackingState: .normal,
            configuration: configuration
        )

        #expect(!evaluation.isFrameValid)
        #expect(evaluation.rejectionReasons.contains(.expressionNotNeutral))
        #expect(evaluation.guidance == .keepNeutralExpression)
    }

    @Test
    func distanceOutsideTightCaptureBandIsRejected() {
        let mesh = mesh(x: 0, topology: [0, 1, 2])
        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: mesh,
            blendShapes: [:],
            previousBlendShapes: [:],
            cameraToFaceTransform: cameraToFaceTransform(distance: 0.44),
            trackingState: .normal,
            configuration: configuration
        )

        #expect(!evaluation.isFrameValid)
        #expect(evaluation.rejectionReasons.contains(.tooFar))
        #expect(evaluation.guidance == .moveCloser)
    }

    @Test
    func offCenterFaceIsRejectedIndependentlyOfDistance() {
        let mesh = mesh(x: 0, topology: [0, 1, 2])
        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: mesh,
            blendShapes: [:],
            previousBlendShapes: [:],
            cameraToFaceTransform: cameraToFaceTransform(horizontalOffset: 0.03),
            trackingState: .normal,
            configuration: configuration
        )

        #expect(!evaluation.isFrameValid)
        #expect(evaluation.rejectionReasons.contains(.faceOffCenter))
        #expect(evaluation.guidance == .centerFace)
    }

    @Test
    func incompatibleTopologyIsNotAggregated() {
        let first = mesh(x: 0, topology: [0, 1, 2])
        let second = mesh(x: 0, topology: [0, 2, 1])

        #expect(throws: FaceMeshAggregator.AggregationError.incompatibleTopology) {
            try FaceMeshAggregator.coordinateMedian(of: [first, second])
        }
    }

    @Test
    func betweenScanExpressionDifferenceDetectsChangedBlendShapes() {
        let result = ExpressionDifferenceAnalyzer.compare(
            baseline: ["jawOpen": 0, "mouthPucker": 0.02],
            followup: ["jawOpen": 0.1, "mouthPucker": 0.22]
        )

        #expect(result.exceedsEngineeringWarningLevel)
        #expect(result.maximumAbsoluteDifference > 0.19)
        #expect(result.largestDifferences.first?.name == "mouthPucker")
    }

    private func cameraToFaceTransform(
        yaw: Float = 0,
        roll: Float = .pi / 2,
        distance: Float = 0.4,
        horizontalOffset: Float = 0,
        verticalOffset: Float = 0
    ) -> simd_float4x4 {
        let yawRotation = simd_float4x4(
            simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        )
        let rollRotation = simd_float4x4(
            simd_quatf(angle: roll, axis: SIMD3(0, 0, 1))
        )
        var transform = yawRotation * rollRotation
        transform.columns.3 = SIMD4(
            horizontalOffset,
            verticalOffset,
            -distance,
            1
        )
        return transform
    }

    private func mesh(x: Float, topology: [Int16]) -> FaceMesh {
        FaceMesh(
            vertices: [
                SIMD3(x, 0, 0),
                SIMD3(x, 0.01, 0),
                SIMD3(x, 0, 0.01)
            ],
            triangleIndices: topology
        )
    }
}

struct FaceRegistrationTests {
    private let configuration = FaceRegistrationConfiguration(
        regionMask: .entireFace,
        maximumIterations: 20,
        convergenceToleranceMeters: 0.000_000_1,
        maximumCorrespondenceDistanceMeters: 0.1,
        minimumCorrespondenceCount: 6
    )

    @Test
    func identicalMeshesHaveNearZeroRegistrationError() throws {
        let mesh = testMesh()

        let result = try FaceRegistrationEngine().register(
            baseline: mesh,
            followup: mesh,
            configuration: configuration
        )

        #expect(result.rmsError < 0.000_001)
        #expect(alignmentRMS(result.transform.applying(to: mesh), mesh) < 0.000_001)
    }

    @Test
    func rigidTranslationIsRemoved() throws {
        try expectPoseIsRemoved(
            RigidTransform(
                rotation: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                translation: SIMD3<Float>(0.012, -0.008, 0.015)
            )
        )
    }

    @Test
    func rigidRotationIsRemoved() throws {
        try expectPoseIsRemoved(poseTransform(angle: 13 * .pi / 180, translation: .zero))
    }

    @Test
    func combinedRigidPoseIsRemoved() throws {
        try expectPoseIsRemoved(
            poseTransform(
                angle: -17 * .pi / 180,
                translation: SIMD3<Float>(-0.009, 0.006, 0.011)
            )
        )
    }

    private func expectPoseIsRemoved(_ pose: RigidTransform) throws {
        let baseline = testMesh()
        let followup = pose.applying(to: baseline)

        let result = try FaceRegistrationEngine().register(
            baseline: baseline,
            followup: followup,
            configuration: configuration
        )

        let aligned = result.transform.applying(to: followup)
        #expect(result.rmsError < 0.000_01)
        #expect(alignmentRMS(aligned, baseline) < 0.000_01)
    }

    private func poseTransform(angle: Float, translation: SIMD3<Float>) -> RigidTransform {
        let matrix = simd_float3x3(
            simd_quatf(angle: angle, axis: simd_normalize(SIMD3<Float>(0.3, 0.8, 0.5)))
        )
        return RigidTransform(
            rotation: [
                matrix[0, 0], matrix[1, 0], matrix[2, 0],
                matrix[0, 1], matrix[1, 1], matrix[2, 1],
                matrix[0, 2], matrix[1, 2], matrix[2, 2]
            ],
            translation: translation
        )
    }

    private func testMesh() -> FaceMesh {
        var vertices: [SIMD3<Float>] = []
        for row in 0..<5 {
            for column in 0..<5 {
                let x = Float(column - 2) * 0.012
                let y = Float(row - 2) * 0.015
                let z = 0.004 * sin(Float(row * 2 + column)) + 0.002 * x * y
                vertices.append(SIMD3<Float>(x, y, z))
            }
        }
        return FaceMesh(vertices: vertices, triangleIndices: [])
    }

    private func alignmentRMS(_ first: FaceMesh, _ second: FaceMesh) -> Float {
        let sum = zip(first.simdVertices, second.simdVertices).reduce(Float.zero) {
            $0 + simd_length_squared($1.0 - $1.1)
        }
        return sqrt(sum / Float(first.vertices.count))
    }
}
