import Foundation
import simd

enum ScanCapturePhase: Equatable, Sendable {
    case monitoring
    case capturing
    case complete
    case failed(String)
}

struct ScanAcquisitionUpdate: Equatable, Sendable {
    let phase: ScanCapturePhase
    let guidance: ScanGuidance
    let qualityMetrics: ScanQualityMetrics?
    let rejectionReasons: [ScanFrameRejectionReason]
    let acceptedFrameCount: Int
    let requiredFrameCount: Int
    let rejectedFrameCount: Int
    let vertexCount: Int
    let completedScan: FaceScan?

    static func initial(requiredFrameCount: Int) -> ScanAcquisitionUpdate {
        ScanAcquisitionUpdate(
            phase: .monitoring,
            guidance: .centerFace,
            qualityMetrics: nil,
            rejectionReasons: [],
            acceptedFrameCount: 0,
            requiredFrameCount: requiredFrameCount,
            rejectedFrameCount: 0,
            vertexCount: 0,
            completedScan: nil
        )
    }
}

@MainActor
final class FaceScanManager {
    private struct AcceptedFrame {
        let mesh: FaceMesh
        let timestamp: TimeInterval
        let metrics: ScanQualityMetrics
        let blendShapeNames: Set<String>
    }

    let configuration: ScanQualityConfiguration

    private let deviceInformation: ScanDeviceInformation
    private var phase = ScanCapturePhase.monitoring
    private var previousMesh: FaceMesh?
    private var previousBlendShapes: [String: Float]?
    private var acceptedFrames = [AcceptedFrame]()
    private var rejectedFrameCount = 0
    private var captureStartedAt: Date?
    private var latestMetrics: ScanQualityMetrics?
    private var latestGuidance = ScanGuidance.centerFace
    private var latestRejectionReasons = [ScanFrameRejectionReason]()
    private var latestVertexCount = 0
    private var completedScan: FaceScan?

    init(
        configuration: ScanQualityConfiguration = .engineeringDefault,
        deviceInformation: ScanDeviceInformation
    ) {
        self.configuration = configuration
        self.deviceInformation = deviceInformation
    }

    func beginCapture(at date: Date = Date()) -> ScanAcquisitionUpdate {
        phase = .capturing
        acceptedFrames.removeAll(keepingCapacity: true)
        rejectedFrameCount = 0
        captureStartedAt = date
        completedScan = nil
        return makeUpdate(guidance: latestGuidance)
    }

    func processFrame(
        mesh: FaceMesh,
        blendShapes: [String: Float],
        faceTransform: simd_float4x4,
        cameraTransform: simd_float4x4,
        trackingState: ScanTrackingState,
        frameTimestamp: TimeInterval,
        date: Date = Date()
    ) -> ScanAcquisitionUpdate {
        let cameraToFaceTransform = simd_inverse(cameraTransform) * faceTransform
        let evaluation = ScanQualityAnalyzer.evaluate(
            mesh: mesh,
            previousMesh: previousMesh,
            blendShapes: blendShapes,
            previousBlendShapes: previousBlendShapes,
            cameraToFaceTransform: cameraToFaceTransform,
            trackingState: trackingState,
            configuration: configuration
        )

        previousMesh = mesh
        previousBlendShapes = blendShapes
        latestMetrics = evaluation.metrics
        latestGuidance = evaluation.guidance
        latestRejectionReasons = evaluation.rejectionReasons
        latestVertexCount = mesh.vertices.count

        guard phase == .capturing else {
            return makeUpdate(guidance: phase == .complete ? .scanComplete : evaluation.guidance)
        }

        guard evaluation.isFrameValid else {
            rejectedFrameCount += 1
            return makeUpdate(guidance: evaluation.guidance)
        }

        acceptedFrames.append(
            AcceptedFrame(
                mesh: mesh,
                timestamp: frameTimestamp,
                metrics: evaluation.metrics,
                blendShapeNames: Set(blendShapes.keys)
            )
        )

        if hasEnoughCaptureData {
            do {
                completedScan = try makeCompletedScan(completedAt: date)
                phase = .complete
                return makeUpdate(guidance: .scanComplete)
            } catch {
                phase = .failed(error.localizedDescription)
                return makeUpdate(guidance: .holdStill)
            }
        }

        return makeUpdate(guidance: .capturing)
    }

    func markFaceNotDetected(
        trackingState: ScanTrackingState
    ) -> ScanAcquisitionUpdate {
        let guidance: ScanGuidance = trackingState == .unavailable
            ? .trackingUnavailable
            : .centerFace
        latestGuidance = guidance
        latestRejectionReasons = [
            trackingState == .unavailable ? .trackingUnavailable : .trackingLimited
        ]
        return makeUpdate(guidance: guidance)
    }

    private var hasEnoughCaptureData: Bool {
        guard acceptedFrames.count >= configuration.requiredValidFrameCount,
              let firstTimestamp = acceptedFrames.first?.timestamp,
              let lastTimestamp = acceptedFrames.last?.timestamp else {
            return false
        }

        return lastTimestamp - firstTimestamp >= configuration.minimumCaptureDuration
    }

    private func makeCompletedScan(completedAt: Date) throws -> FaceScan {
        let meshes = acceptedFrames.map(\.mesh)
        let representativeMesh = try FaceMeshAggregator.coordinateMedian(of: meshes)
        let qualityMetrics = aggregateQuality(
            acceptedFrames.map(\.metrics)
        )
        let blendShapeNames = acceptedFrames
            .reduce(into: Set<String>()) { result, frame in
                result.formUnion(frame.blendShapeNames)
            }
            .sorted()

        return FaceScan(
            id: UUID(),
            timestamp: completedAt,
            mesh: representativeMesh,
            rawAcceptedMeshes: meshes,
            acquisitionMetadata: FaceAcquisitionMetadata(
                configuration: configuration,
                startedAt: captureStartedAt ?? completedAt,
                completedAt: completedAt,
                acceptedFrameCount: acceptedFrames.count,
                rejectedFrameCount: rejectedFrameCount,
                acceptedFrameTimestamps: acceptedFrames.map(\.timestamp),
                acceptedFrameQuality: acceptedFrames.map(\.metrics),
                blendShapeNames: blendShapeNames,
                aggregationMethod: "Coordinate-wise median for each topology-matched vertex",
                coordinateSystem: "ARKit face-anchor local coordinates; meters; right-handed"
            ),
            qualityMetrics: qualityMetrics,
            deviceInformation: deviceInformation
        )
    }

    private func aggregateQuality(
        _ metrics: [ScanQualityMetrics]
    ) -> ScanQualityMetrics {
        ScanQualityMetrics(
            yaw: median(metrics.map(\.yaw)),
            pitch: median(metrics.map(\.pitch)),
            roll: median(metrics.map(\.roll)),
            distance: median(metrics.map(\.distance)),
            trackingStable: metrics.allSatisfy(\.trackingStable),
            expressionStable: metrics.allSatisfy(\.expressionStable),
            meshVariance: median(metrics.map(\.meshVariance)),
            expressionRMSDelta: median(metrics.map(\.expressionRMSDelta))
        )
    }

    private func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }

    private func makeUpdate(guidance: ScanGuidance) -> ScanAcquisitionUpdate {
        ScanAcquisitionUpdate(
            phase: phase,
            guidance: guidance,
            qualityMetrics: latestMetrics,
            rejectionReasons: latestRejectionReasons,
            acceptedFrameCount: acceptedFrames.count,
            requiredFrameCount: configuration.requiredValidFrameCount,
            rejectedFrameCount: rejectedFrameCount,
            vertexCount: latestVertexCount,
            completedScan: completedScan
        )
    }
}
