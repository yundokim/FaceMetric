import Foundation
import simd

public struct ScanQualityMetrics: Codable, Equatable, Sendable {
    /// Camera-relative rotation around the vertical axis, in radians.
    let yaw: Float
    /// Camera-relative rotation around the left-right axis, in radians.
    let pitch: Float
    /// Camera-relative rotation around the viewing axis, in radians.
    let roll: Float
    /// Euclidean camera-to-face-origin distance, in meters.
    let distance: Float
    /// True when ARKit tracking, pose, distance, and mesh-motion checks pass.
    let trackingStable: Bool
    /// True when temporal blend-shape RMS change is within the configured limit.
    let expressionStable: Bool
    /// Mean squared per-vertex distance from the preceding frame, in square meters.
    let meshVariance: Float
    /// RMS change in ARKit blend-shape coefficients from the preceding frame.
    let expressionRMSDelta: Float
}

public struct ScanQualityConfiguration: Codable, Equatable, Sendable {
    let maximumAbsoluteYaw: Float
    let maximumAbsolutePitch: Float
    let targetRoll: Float
    let maximumRollDeviation: Float
    let minimumDistance: Float
    let maximumDistance: Float
    let maximumMeshRMS: Float
    let maximumExpressionRMSDelta: Float
    let requiredValidFrameCount: Int
    let minimumCaptureDuration: TimeInterval

    /// Engineering defaults used to make the prototype operable.
    ///
    /// These values are not medical or clinical limits. They require empirical
    /// calibration with physical-device test-retest data.
    public nonisolated static let engineeringDefault = ScanQualityConfiguration(
        maximumAbsoluteYaw: 10 * .pi / 180,
        maximumAbsolutePitch: 10 * .pi / 180,
        targetRoll: .pi / 2,
        maximumRollDeviation: 10 * .pi / 180,
        minimumDistance: 0.25,
        maximumDistance: 0.55,
        maximumMeshRMS: 0.0008,
        maximumExpressionRMSDelta: 0.025,
        requiredValidFrameCount: 30,
        minimumCaptureDuration: 1.0
    )
}

public enum ScanGuidance: String, Codable, Equatable, Sendable {
    case centerFace = "Center your face"
    case lookStraightAhead = "Look straight ahead"
    case keepNeutralExpression = "Keep a neutral expression"
    case moveCloser = "Move closer"
    case moveFarther = "Move farther away"
    case holdStill = "Hold still"
    case ready = "Ready to capture"
    case capturing = "Capturing"
    case scanComplete = "Scan complete"
    case trackingUnavailable = "Face tracking unavailable"
}

public enum ScanTrackingState: String, Codable, Equatable, Sendable {
    case normal
    case limited
    case unavailable
}

enum ScanFrameRejectionReason: String, Codable, Equatable, Sendable {
    case trackingLimited
    case trackingUnavailable
    case yawOutsideRange
    case pitchOutsideRange
    case rollOutsideRange
    case tooClose
    case tooFar
    case meshMotion
    case expressionChange
}

public struct ScanQualityEvaluation: Equatable, Sendable {
    let metrics: ScanQualityMetrics
    let guidance: ScanGuidance
    let rejectionReasons: [ScanFrameRejectionReason]
    let isFrameValid: Bool
}

public enum ScanQualityAnalyzer {
    public nonisolated static func evaluate(
        mesh: FaceMesh,
        previousMesh: FaceMesh?,
        blendShapes: [String: Float],
        previousBlendShapes: [String: Float]?,
        cameraToFaceTransform: simd_float4x4,
        trackingState: ScanTrackingState,
        configuration: ScanQualityConfiguration
    ) -> ScanQualityEvaluation {
        let angles = eulerAngles(from: cameraToFaceTransform)
        let translation = cameraToFaceTransform.columns.3
        let distance = simd_length(SIMD3(translation.x, translation.y, translation.z))

        let meshVariance = previousMesh
            .flatMap { FaceMeshAggregator.meanSquaredVertexDistance(from: $0, to: mesh) }
            ?? 0
        let meshRMS = sqrt(meshVariance)
        let expressionRMSDelta = previousBlendShapes
            .map { expressionRMS(from: $0, to: blendShapes) }
            ?? 0

        let rejectionReasons = rejectionReasons(
            trackingState: trackingState,
            yaw: angles.yaw,
            pitch: angles.pitch,
            roll: angles.roll,
            distance: distance,
            meshRMS: meshRMS,
            expressionRMSDelta: expressionRMSDelta,
            configuration: configuration
        )
        let expressionStable = !rejectionReasons.contains(.expressionChange)
        let trackingStable = rejectionReasons.allSatisfy { $0 == .expressionChange }

        return ScanQualityEvaluation(
            metrics: ScanQualityMetrics(
                yaw: angles.yaw,
                pitch: angles.pitch,
                roll: angles.roll,
                distance: distance,
                trackingStable: trackingStable,
                expressionStable: expressionStable,
                meshVariance: meshVariance,
                expressionRMSDelta: expressionRMSDelta
            ),
            guidance: guidance(for: rejectionReasons),
            rejectionReasons: rejectionReasons,
            isFrameValid: rejectionReasons.isEmpty
        )
    }

    public nonisolated static func eulerAngles(
        from transform: simd_float4x4
    ) -> (yaw: Float, pitch: Float, roll: Float) {
        // Decomposition order: yaw (Y), pitch (X), then roll (Z).
        let pitch = asin(max(-1, min(1, -transform.columns.2.y)))
        let yaw = atan2(transform.columns.2.x, transform.columns.2.z)
        let roll = atan2(transform.columns.0.y, transform.columns.1.y)
        return (yaw, pitch, roll)
    }

    nonisolated private static func expressionRMS(
        from lhs: [String: Float],
        to rhs: [String: Float]
    ) -> Float {
        let keys = Set(lhs.keys).union(rhs.keys)
        guard !keys.isEmpty else {
            return 0
        }

        let sum = keys.reduce(Float.zero) { partialResult, key in
            let delta = (rhs[key] ?? 0) - (lhs[key] ?? 0)
            return partialResult + delta * delta
        }
        return sqrt(sum / Float(keys.count))
    }

    nonisolated private static func rejectionReasons(
        trackingState: ScanTrackingState,
        yaw: Float,
        pitch: Float,
        roll: Float,
        distance: Float,
        meshRMS: Float,
        expressionRMSDelta: Float,
        configuration: ScanQualityConfiguration
    ) -> [ScanFrameRejectionReason] {
        var reasons = [ScanFrameRejectionReason]()

        switch trackingState {
        case .normal:
            break
        case .limited:
            reasons.append(.trackingLimited)
        case .unavailable:
            reasons.append(.trackingUnavailable)
        }

        if abs(yaw) > configuration.maximumAbsoluteYaw {
            reasons.append(.yawOutsideRange)
        }
        if abs(pitch) > configuration.maximumAbsolutePitch {
            reasons.append(.pitchOutsideRange)
        }
        if angularDifference(roll, configuration.targetRoll)
            > configuration.maximumRollDeviation {
            reasons.append(.rollOutsideRange)
        }
        if distance < configuration.minimumDistance {
            reasons.append(.tooClose)
        }
        if distance > configuration.maximumDistance {
            reasons.append(.tooFar)
        }
        if meshRMS > configuration.maximumMeshRMS {
            reasons.append(.meshMotion)
        }
        if expressionRMSDelta > configuration.maximumExpressionRMSDelta {
            reasons.append(.expressionChange)
        }

        return reasons
    }

    nonisolated private static func angularDifference(
        _ lhs: Float,
        _ rhs: Float
    ) -> Float {
        abs(atan2(sin(lhs - rhs), cos(lhs - rhs)))
    }

    nonisolated private static func guidance(
        for reasons: [ScanFrameRejectionReason]
    ) -> ScanGuidance {
        if reasons.contains(.trackingUnavailable) {
            return .trackingUnavailable
        }
        if reasons.contains(.trackingLimited) {
            return .centerFace
        }
        if reasons.contains(.tooClose) {
            return .moveFarther
        }
        if reasons.contains(.tooFar) {
            return .moveCloser
        }
        if reasons.contains(.yawOutsideRange)
            || reasons.contains(.pitchOutsideRange)
            || reasons.contains(.rollOutsideRange) {
            return .lookStraightAhead
        }
        if reasons.contains(.expressionChange) {
            return .keepNeutralExpression
        }
        if reasons.contains(.meshMotion) {
            return .holdStill
        }
        return .ready
    }
}
