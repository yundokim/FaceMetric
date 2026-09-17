import Foundation
import simd
import Testing
@testable import FaceMetric

struct FaceGeometryAnalysisTests {
    @Test
    func neutralMeshBuilderAveragesTopologyMatchedFrames() throws {
        let first = FaceMesh(vertices: [SIMD3(0, 0, 0), SIMD3(2, 2, 2)], triangleIndices: [])
        let second = FaceMesh(vertices: [SIMD3(2, 4, 6), SIMD3(4, 6, 8)], triangleIndices: [])

        let result = try NeutralMeshBuilder.coordinateMean(of: [first, second])

        #expect(result.simdVertices[0] == SIMD3(1, 2, 3))
        #expect(result.simdVertices[1] == SIMD3(3, 4, 5))
    }

    @Test
    func analyzerPreservesAllLevelARatiosAndLevelBRawMetrics() throws {
        let fixture = makeFixture()
        let result = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan)

        #expect(result.metrics.values.count == FaceGeometryMetricID.allCases.count)
        #expect(abs((result.metrics.value(.faceHeightWidth) ?? 0) - 2) < 0.0001)
        #expect(abs((result.metrics.value(.leftEyeWidthRatio) ?? 0) - 0.2) < 0.0001)
        #expect(abs((result.metrics.value(.rightEyeWidthRatio) ?? 0) - 0.2) < 0.0001)
        #expect(abs((result.metrics.value(.intercanthalRatio) ?? 0) - 0.2) < 0.0001)
        #expect(abs((result.metrics.value(.upperLowerLipRatio) ?? 0) - 0.625) < 0.0001)
        #expect(result.metrics.values.filter { $0.evidenceLevel == .numericReference }.allSatisfy { $0.componentScore != nil })
        #expect(result.metrics.values.filter { $0.evidenceLevel == .directionalAssociation }.allSatisfy { $0.componentScore == nil })
        #expect(Set(result.metrics.values.map { $0.id.category }) == Set(FaceGeometryCategory.allCases))
        #expect(result.experimentalAttractiveness.score == nil)
    }

    @Test
    func thirdsAndEyeAspectPreserveSeparateMeasurements() throws {
        let fixture = makeFixture()
        let metrics = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan).metrics

        #expect(abs((metrics.value(.upperThirdRatio) ?? 0) - 0.75) < 0.0001)
        #expect(abs((metrics.value(.middleThirdRatio) ?? 0) - 0.75) < 0.0001)
        #expect(abs((metrics.value(.lowerThirdRatio) ?? 0) - 1.5) < 0.0001)
        #expect(abs((metrics.value(.leftEyeAspectRatio) ?? 0) - 4) < 0.0001)
        #expect(abs((metrics.value(.rightEyeAspectRatio) ?? 0) - 4) < 0.0001)
    }

    @Test
    func symmetricBilateralROIHasZeroOperationalError() throws {
        let fixture = makeFixture()
        let metrics = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan).metrics

        #expect((metrics.value(.meshSymmetryMeanMM) ?? 1) < 0.001)
        #expect((metrics.value(.meshSymmetryRMSMM) ?? 1) < 0.001)
        #expect((metrics.value(.zygomaticAsymmetryMM) ?? 1) < 0.001)
    }

    @Test
    func continuousScoringIsFullInsideAndSmoothOutside() {
        let inside = GeometryScorer.continuousIntervalScore(value: 1, interval: 0.9...1.1)
        let near = GeometryScorer.continuousIntervalScore(value: 1.15, interval: 0.9...1.1)
        let far = GeometryScorer.continuousIntervalScore(value: 1.3, interval: 0.9...1.1)

        #expect(inside == 100)
        #expect(near < inside)
        #expect(far < near)
        #expect(near > 0 && far > 0)
    }

    @Test
    func uncalibratedConfigurationFailsWithoutGuessingIndices() {
        let fixture = makeFixture()

        #expect(throws: FaceGeometryAnalysisError.self) {
            try FaceGeometryAnalyzer(configuration: .uncalibrated(topologyVertexCount: fixture.scan.mesh.vertices.count)).analyze(scan: fixture.scan)
        }
    }

    @Test
    func savedCalibrationIsReusedOnlyForMatchingTopology() throws {
        let suiteName = "FaceGeometryAnalysisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let mesh = FaceMesh(
            vertices: [SIMD3.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangleIndices: [0, 1, 2]
        )
        var config = FaceLandmarkConfig.uncalibrated(mesh: mesh)
        for landmark in FaceAnatomicalLandmark.requiredForMVP {
            config.landmarkVertexIndices[landmark.rawValue] = 0
        }
        config.landmarkVertexIndices[FaceAnatomicalLandmark.pronasale.rawValue] = 1
        try FaceLandmarkConfigStore.save(config, defaults: defaults)

        let matching = FaceLandmarkConfigStore.load(mesh: mesh, defaults: defaults)
        let differentTopology = FaceMesh(
            vertices: mesh.simdVertices,
            triangleIndices: [0, 2, 1]
        )
        let rejected = FaceLandmarkConfigStore.load(mesh: differentTopology, defaults: defaults)

        #expect(matching.vertexIndex(for: .pronasale) == 1)
        #expect(rejected.vertexIndex(for: .pronasale) == nil)
        #expect(mesh.topologySignature != differentTopology.topologySignature)
    }

    @Test
    func legacyVerticalBoundaryLandmarksMoveByOneTopologyEdge() throws {
        let suiteName = "FaceGeometryAnalysisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let mesh = FaceMesh(
            vertices: [
                SIMD3(0, 1, 0), SIMD3(0, 2, 0), SIMD3(1, 0, 0),
                SIMD3(0, -1, 0), SIMD3(0, -2, 0)
            ],
            triangleIndices: [0, 1, 2, 3, 4, 2]
        )
        var landmarks = Dictionary(uniqueKeysWithValues: FaceAnatomicalLandmark.requiredForMVP.map { ($0.rawValue, 2) })
        landmarks[FaceAnatomicalLandmark.trichionOrForeheadBoundary.rawValue] = 0
        landmarks[FaceAnatomicalLandmark.menton.rawValue] = 3
        let config = FaceLandmarkConfig(
            version: "arkit-manual-v1",
            topologyVertexCount: mesh.vertices.count,
            topologySignature: mesh.topologySignature,
            landmarkVertexIndices: landmarks,
            roiVertexIndices: [:]
        )
        try FaceLandmarkConfigStore.save(config, defaults: defaults)

        let corrected = FaceLandmarkConfigStore.load(mesh: mesh, defaults: defaults)

        #expect(corrected.vertexIndex(for: .trichionOrForeheadBoundary) == 1)
        #expect(corrected.vertexIndex(for: .menton) == 4)
        #expect(corrected.version == "arkit-landmark-v2-one-ring")
    }

    private func makeFixture() -> (scan: FaceScan, config: FaceLandmarkConfig) {
        var points = [FaceAnatomicalLandmark: SIMD3<Float>]()
        for landmark in FaceAnatomicalLandmark.allCases { points[landmark] = .zero }
        points[.zygionLeft] = SIMD3(-1, 0, 0)
        points[.zygionRight] = SIMD3(1, 0, 0)
        points[.trichionOrForeheadBoundary] = SIMD3(0, 2, 0)
        points[.glabella] = SIMD3(0, 1, 0)
        points[.subnasale] = SIMD3(0, 0, 0)
        points[.menton] = SIMD3(0, -2, 0)
        points[.pogonion] = SIMD3(0, -1.5, 0.2)
        points[.gonionLeft] = SIMD3(-0.6, -1.4, 0)
        points[.gonionRight] = SIMD3(0.6, -1.4, 0)
        points[.endocanthionLeft] = SIMD3(-0.2, 0.5, 0.05)
        points[.exocanthionLeft] = SIMD3(-0.6, 0.5, 0.05)
        points[.endocanthionRight] = SIMD3(0.2, 0.5, 0.05)
        points[.exocanthionRight] = SIMD3(0.6, 0.5, 0.05)
        points[.upperEyelidLeft] = SIMD3(-0.4, 0.55, 0.06)
        points[.lowerEyelidLeft] = SIMD3(-0.4, 0.45, 0.06)
        points[.upperEyelidRight] = SIMD3(0.4, 0.55, 0.06)
        points[.lowerEyelidRight] = SIMD3(0.4, 0.45, 0.06)
        points[.nasion] = SIMD3(0, 0.7, 0.05)
        points[.pronasale] = SIMD3(0, 0.1, 0.3)
        points[.alareLeft] = SIMD3(-0.2, 0.05, 0.1)
        points[.alareRight] = SIMD3(0.2, 0.05, 0.1)
        points[.labialeSuperius] = SIMD3(0, -0.2, 0.12)
        points[.stomion] = SIMD3(0, -0.3, 0.12)
        points[.labialeInferius] = SIMD3(0, -0.46, 0.12)
        points[.mouthLeft] = SIMD3(-0.3, -0.3, 0.1)
        points[.mouthRight] = SIMD3(0.3, -0.3, 0.1)

        var vertices = [SIMD3<Float>]()
        var mapping = [String: Int]()
        for landmark in FaceAnatomicalLandmark.allCases {
            mapping[landmark.rawValue] = vertices.count
            vertices.append(points[landmark]!)
        }
        vertices.append(SIMD3(0, 0.8, 0))
        vertices.append(contentsOf: [SIMD3(-0.7, 0, 0.1), SIMD3(-0.6, 0.2, 0.1)])
        vertices.append(contentsOf: [SIMD3(0.7, 0, 0.1), SIMD3(0.6, 0.2, 0.1)])
        let mesh = FaceMesh(vertices: vertices, triangleIndices: [])
        let config = FaceLandmarkConfig(
            version: "test-v1",
            topologyVertexCount: vertices.count,
            landmarkVertexIndices: mapping,
            roiVertexIndices: [:]
        )
        return (makeScan(mesh), config)
    }

    private func makeScan(_ mesh: FaceMesh) -> FaceScan {
        let quality = ScanQualityMetrics(yaw: 0, pitch: 0, roll: 0, distance: 0.4, horizontalOffset: 0, verticalOffset: 0, trackingStable: true, expressionStable: true, meshVariance: 0, expressionRMSDelta: 0, neutralExpressionMagnitude: 0)
        return FaceScan(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 1), mesh: mesh, rawAcceptedMeshes: [mesh],
            acquisitionMetadata: FaceAcquisitionMetadata(configuration: .engineeringDefault, startedAt: .distantPast, completedAt: .distantPast, acceptedFrameCount: 30, rejectedFrameCount: 0, acceptedFrameTimestamps: [], acceptedFrameQuality: [], blendShapeNames: [], representativeBlendShapes: [:], aggregationMethod: "test", coordinateSystem: "ARKit face-local meters"),
            qualityMetrics: quality,
            deviceInformation: ScanDeviceInformation(model: "test", systemName: "iOS", systemVersion: "test", appVersion: "test", appBuild: "test")
        )
    }
}
