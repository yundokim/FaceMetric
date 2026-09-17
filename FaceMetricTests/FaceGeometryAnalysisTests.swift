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
        #expect(abs((result.metrics.value(.faceHeightWidth) ?? 0) - 2.1) < 0.0001)
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

        #expect(abs((metrics.value(.upperThirdRatio) ?? 0) - (6.0 / 7.0)) < 0.0001)
        #expect(abs((metrics.value(.middleThirdRatio) ?? 0) - (5.0 / 7.0)) < 0.0001)
        #expect(abs((metrics.value(.lowerThirdRatio) ?? 0) - (10.0 / 7.0)) < 0.0001)
        #expect(abs((metrics.value(.leftEyeAspectRatio) ?? 0) - 4) < 0.0001)
        #expect(abs((metrics.value(.rightEyeAspectRatio) ?? 0) - 4) < 0.0001)
    }

    @Test
    func virtualTrichionExtendsRawUpperThirdAlongSuperiorAxis() {
        let glabella = SIMD3<Float>(0, 0, 0)
        let rawBoundary = SIMD3<Float>(0, 1, 0.25)
        let suppliedAxisPointingInferiorly = SIMD3<Float>(0, -1, 0)

        let virtualTrichion = FaceGeometryAnalyzer.virtualTrichion(
            rawForeheadBoundary: rawBoundary,
            glabella: glabella,
            verticalAxis: suppliedAxisPointingInferiorly
        )
        let rawLength = simd_distance(glabella, rawBoundary)
        let virtualLength = simd_distance(glabella, virtualTrichion)

        #expect(abs(virtualLength / rawLength - FaceGeometryAnalyzer.foreheadExtensionFactor) < 0.0001)
        #expect(simd_dot(virtualTrichion - glabella, rawBoundary - glabella) > 0)
        #expect(abs(virtualTrichion.z - glabella.z) < 0.0001)
    }

    @Test
    func hairlineDependentMetricsUseVirtualTrichionAndThirdRatiosSumToThree() throws {
        let fixture = makeFixture()
        let metrics = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan).metrics
        let upper = try #require(metrics.value(.upperThirdRatio))
        let middle = try #require(metrics.value(.middleThirdRatio))
        let lower = try #require(metrics.value(.lowerThirdRatio))

        // Fixture lengths after correction are 1.2, 1.0, and 2.0 with face width 2.0.
        #expect(abs((metrics.value(.faceHeightWidth) ?? 0) - 2.1) < 0.0001)
        #expect(abs(upper - (1.2 / 1.4)) < 0.0001)
        #expect(abs(middle - (1.0 / 1.4)) < 0.0001)
        #expect(abs(lower - (2.0 / 1.4)) < 0.0001)
        #expect(abs(upper + middle + lower - 3) < 0.0001)
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
    func continuousTargetScoringDecaysSmoothlyWithoutAPlateauOrHardZero() {
        let interval: ClosedRange<Float> = 0.9...1.1
        let targetScore = GeometryScorer.continuousTargetScore(value: 1, target: 1, idealInterval: interval)
        let slightlyOffTarget = GeometryScorer.continuousTargetScore(value: 1.001, target: 1, idealInterval: interval)
        let halfWidthAway = GeometryScorer.continuousTargetScore(value: 1.1, target: 1, idealInterval: interval)
        let fartherAway = GeometryScorer.continuousTargetScore(value: 1.3, target: 1, idealInterval: interval)
        let finiteExtreme = GeometryScorer.continuousTargetScore(value: 100, target: 1, idealInterval: interval)

        #expect(targetScore == 100)
        #expect(slightlyOffTarget < targetScore)
        #expect(abs(halfWidthAway - 90) < 0.001)
        #expect(fartherAway < halfWidthAway)
        #expect(finiteExtreme > 0)
    }

    @Test
    func oneSidedSymmetryScoringUsesContinuousMillimeterTolerance() {
        let atZero = GeometryScorer.continuousOneSidedScore(value: 0, target: 0, tolerance: 1)
        let atOneMillimeter = GeometryScorer.continuousOneSidedScore(value: 1, target: 0, tolerance: 1)
        let atThreeMillimeters = GeometryScorer.continuousOneSidedScore(value: 3, target: 0, tolerance: 1)
        let beyondThreeMillimeters = GeometryScorer.continuousOneSidedScore(value: 4, target: 0, tolerance: 1)

        #expect(atZero == 100)
        #expect(abs(atOneMillimeter - 90) < 0.001)
        #expect(abs(atThreeMillimeters - 50) < 0.001)
        #expect(beyondThreeMillimeters < atThreeMillimeters)
        #expect(beyondThreeMillimeters > 0)
    }

    @Test
    func maleProfileContainsCurrentTargetsIntervalsAndMetadata() throws {
        let profile = FaceGeometryReferenceProfiles.male
        let expected: [FaceGeometryMetricID: (Float, ClosedRange<Float>)] = [
            .faceHeightWidth: (1.6459, 1.605...1.687),
            .upperThirdRatio: (0.9778, 0.958...0.998),
            .middleThirdRatio: (1.0720, 1.047...1.097),
            .lowerThirdRatio: (0.9502, 0.927...0.974),
            .leftEyeWidthRatio: (0.2360, 0.231...0.241),
            .rightEyeWidthRatio: (0.2360, 0.231...0.241),
            .leftEyeAspectRatio: (2.4121, 2.312...2.512),
            .rightEyeAspectRatio: (2.4121, 2.312...2.512),
            .intercanthalRatio: (0.3123, 0.305...0.319),
            .noseWidthRatio: (0.3058, 0.298...0.314),
            .upperLowerLipRatio: (0.7979, 0.758...0.838)
        ]

        #expect(profile.sex == .male)
        #expect(profile.metricReferences.count == expected.count)
        for (id, expectedReference) in expected {
            let reference = try #require(profile.reference(for: id))
            #expect(reference.target == expectedReference.0)
            #expect(reference.idealInterval == expectedReference.1)
            #expect(reference.sampleCount == 2)
            #expect(reference.isProvisional)
            #expect(reference.source == .manualAestheticReference)
        }
    }

    @Test
    func femaleProfileIsUnavailableWithoutMaleFallback() throws {
        #expect(FaceGeometryReferenceProfiles.profile(for: .female) == nil)

        let fixture = makeFixture()
        let result = try FaceGeometryAnalyzer(
            configuration: fixture.config,
            referenceSex: .female
        ).analyze(scan: fixture.scan)
        let profiledMetricIDs = Set(FaceGeometryReferenceProfiles.male.metricReferences.keys)
        let profiledMetrics = result.metrics.values.filter { profiledMetricIDs.contains($0.id) }

        #expect(profiledMetrics.allSatisfy { $0.componentScore == nil })
        #expect(profiledMetrics.allSatisfy { $0.referenceSource == nil })
    }

    @Test
    func analyzerUsesMaleTargetsForEyeLipAndNoseScoring() throws {
        let fixture = makeFixture()
        let result = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan)
        let metrics = Dictionary(uniqueKeysWithValues: result.metrics.values.map { ($0.id, $0) })

        for id in [FaceGeometryMetricID.leftEyeAspectRatio, .rightEyeAspectRatio, .upperLowerLipRatio, .noseWidthRatio] {
            let metric = try #require(metrics[id])
            let reference = try #require(FaceGeometryReferenceProfiles.male.reference(for: id))
            #expect(metric.componentScore == GeometryScorer.continuousTargetScore(value: metric.value, target: reference.target, idealInterval: reference.idealInterval))
            #expect(metric.referenceText?.contains("Ye et al.") == false)
        }

        #expect(result.geometryScore.facialProportion > 0)
        #expect(result.geometryScore.components.contains { $0.id == .noseWidthRatio })
    }

    @Test
    func overallScoreUsesProductionMetricWeights() throws {
        let fixture = makeFixture()
        let score = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan).geometryScore
        let weights: [FaceGeometryMetricID: Float] = [
            .faceHeightWidth: 1,
            .upperThirdRatio: 0.33,
            .middleThirdRatio: 0.34,
            .lowerThirdRatio: 0.33,
            .leftEyeWidthRatio: 0.5,
            .rightEyeWidthRatio: 0.5,
            .leftEyeAspectRatio: 0.375,
            .rightEyeAspectRatio: 0.375,
            .intercanthalRatio: 1,
            .noseWidthRatio: 1,
            .upperLowerLipRatio: 0.75,
            .zygomaticAsymmetryMM: 1
        ]
        let weightedComponents = score.components.compactMap { metric -> (Float, Float)? in
            guard let componentScore = metric.componentScore, let weight = weights[metric.id] else { return nil }
            return (componentScore, weight)
        }
        let expectedOverall = weightedComponents.reduce(0) { $0 + $1.0 * $1.1 }
            / weightedComponents.reduce(0) { $0 + $1.1 }
        let categoryMean = (score.facialProportion + score.symmetry + score.eyeAndMidface + score.lowerFace) / 4

        #expect(abs(score.overall - expectedOverall) < 0.0001)
        #expect(abs(score.overall - categoryMean) > 0.0001)
    }

    @Test
    func eyeBoxUsesTransverseAndVerticalProjectionAndIgnoresDepth() throws {
        let fixture = makeFixture()
        let baseline = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: fixture.scan).metrics
        var changedVertices = fixture.scan.mesh.simdVertices
        let eyeLandmarks: [FaceAnatomicalLandmark] = [
            .endocanthionLeft, .exocanthionLeft, .upperEyelidLeft, .lowerEyelidLeft,
            .endocanthionRight, .exocanthionRight, .upperEyelidRight, .lowerEyelidRight
        ]
        for (offset, landmark) in eyeLandmarks.enumerated() {
            let index = try #require(fixture.config.vertexIndex(for: landmark))
            changedVertices[index].z += Float(offset + 1)
        }
        let changedMesh = FaceMesh(vertices: changedVertices, triangleIndices: fixture.scan.mesh.triangleIndices)
        let changed = try FaceGeometryAnalyzer(configuration: fixture.config).analyze(scan: makeScan(changedMesh)).metrics

        for id in [FaceGeometryMetricID.leftEyeWidthRatio, .rightEyeWidthRatio, .leftEyeAspectRatio, .rightEyeAspectRatio] {
            #expect(changed.value(id) == baseline.value(id))
        }
        #expect(abs((baseline.value(.leftEyeAspectRatio) ?? 0) - 4) < 0.0001)
        #expect(abs((baseline.value(.rightEyeAspectRatio) ?? 0) - 4) < 0.0001)
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
