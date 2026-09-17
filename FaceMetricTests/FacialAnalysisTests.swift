import Foundation
import simd
import Testing
@testable import FaceMetric

struct FacialAnalysisTests {
    @Test
    func analysisProducesTenTraceableMeasurementsAndThreeCategories() throws {
        let scan = makeScan(mesh: symmetricFaceMesh())

        let analysis = try FacialAnalysisEngine().analyze(scan: scan)

        #expect(analysis.measurements.count == 10)
        #expect(analysis.categoryScores.count == 3)
        #expect(Set(analysis.categoryScores.map(\.category)) == Set([.symmetry, .proportion, .profile]))
        #expect(analysis.measurements.allSatisfy { $0.score.isFinite })
        #expect(analysis.measurements.allSatisfy { !$0.reference.citation.isEmpty })
        #expect((0...100).contains(analysis.overallScore))
    }

    @Test
    func symmetricMeshHasLowSurfaceSymmetryError() throws {
        let analysis = try FacialAnalysisEngine().analyze(
            scan: makeScan(mesh: symmetricFaceMesh())
        )
        let symmetry = analysis.measurements.first { $0.id == "surfaceSymmetry" }

        #expect(symmetry != nil)
        #expect((symmetry?.value ?? 1) < 0.2)
    }

    @Test
    func analysisRoundTripsThroughCodableStorage() throws {
        let scan = makeScan(mesh: symmetricFaceMesh())
        let analysis = try FacialAnalysisEngine().analyze(scan: scan)
        let record = SavedFaceAnalysis(scan: scan, analysis: analysis)

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SavedFaceAnalysis.self, from: encoded)

        #expect(decoded == record)
        #expect(decoded.analysis.measurements.count == 10)
    }

    private func symmetricFaceMesh() -> FaceMesh {
        var vertices = [SIMD3<Float>]()
        for row in 0..<15 {
            let y = -0.10 + Float(row) * (0.20 / 14)
            for column in 0..<15 {
                let x = -0.075 + Float(column) * (0.15 / 14)
                let normalizedX = x / 0.075
                let normalizedY = y / 0.10
                let faceDome = max(0, 1 - normalizedX * normalizedX - 0.45 * normalizedY * normalizedY)
                let nose = 0.018 * exp(
                    -(x * x / 0.00018 + (y - 0.005) * (y - 0.005) / 0.0008)
                )
                vertices.append(SIMD3(x, y, 0.025 * faceDome + nose))
            }
        }
        return FaceMesh(vertices: vertices, triangleIndices: [])
    }

    private func makeScan(mesh: FaceMesh) -> FaceScan {
        FaceScan(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_000),
            mesh: mesh,
            rawAcceptedMeshes: [mesh],
            acquisitionMetadata: FaceAcquisitionMetadata(
                configuration: .engineeringDefault,
                startedAt: Date(timeIntervalSince1970: 999),
                completedAt: Date(timeIntervalSince1970: 1_000),
                acceptedFrameCount: 30,
                rejectedFrameCount: 0,
                acceptedFrameTimestamps: [],
                acceptedFrameQuality: [],
                blendShapeNames: [],
                representativeBlendShapes: [:],
                aggregationMethod: "test",
                coordinateSystem: "ARKit face-local"
            ),
            qualityMetrics: ScanQualityMetrics(
                yaw: 0,
                pitch: 0,
                roll: .pi / 2,
                distance: 0.4,
                horizontalOffset: 0,
                verticalOffset: 0,
                trackingStable: true,
                expressionStable: true,
                meshVariance: 0,
                expressionRMSDelta: 0,
                neutralExpressionMagnitude: 0
            ),
            deviceInformation: ScanDeviceInformation(
                model: "Test",
                systemName: "iOS",
                systemVersion: "Test",
                appVersion: "Test",
                appBuild: "Test"
            )
        )
    }
}
