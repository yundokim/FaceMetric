import Foundation
import simd

public enum AnchorUseDecision: String, Codable, Equatable, Sendable {
    case used
    case robustlyDownweighted
    case excludedLowConfidence
}

public struct AnchorResidual: Codable, Equatable, Sendable, Identifiable {
    public let id: AnchorID
    public let residualMeters: Float
    public let effectiveWeight: Float
    public let decision: AnchorUseDecision

    nonisolated public init(
        id: AnchorID,
        residualMeters: Float,
        effectiveWeight: Float,
        decision: AnchorUseDecision
    ) {
        self.id = id
        self.residualMeters = residualMeters
        self.effectiveWeight = effectiveWeight
        self.decision = decision
    }
}

public enum RigidRegistrationStatus: String, Codable, Equatable, Sendable {
    case valid
    case validWithWarnings
}

public struct RigidRegistrationQualityMetadata: Codable, Equatable, Sendable {
    public let status: RigidRegistrationStatus
    public let warnings: [String]
    public let rejectedOrDownweightedAnchors: [AnchorID]
    public let spatialSpreadMeters: Float
    public let collinearityRatio: Float
    public let rotationDeterminant: Float

    nonisolated public init(
        status: RigidRegistrationStatus,
        warnings: [String],
        rejectedOrDownweightedAnchors: [AnchorID],
        spatialSpreadMeters: Float,
        collinearityRatio: Float,
        rotationDeterminant: Float
    ) {
        self.status = status
        self.warnings = warnings
        self.rejectedOrDownweightedAnchors = rejectedOrDownweightedAnchors
        self.spatialSpreadMeters = spatialSpreadMeters
        self.collinearityRatio = collinearityRatio
        self.rotationDeterminant = rotationDeterminant
    }
}

public struct RigidRegistrationResult: Codable, Equatable, Sendable {
    public let transform: RigidTransform
    public let rotation: [Float]
    public let translation: FaceMeshPoint
    public let anchorRMSError: Float
    public let anchorMaxError: Float
    public let anchorResiduals: [AnchorResidual]
    public let numberOfAnchors: Int
    public let qualityMetadata: RigidRegistrationQualityMetadata

    nonisolated public init(
        transform: RigidTransform,
        anchorRMSError: Float,
        anchorMaxError: Float,
        anchorResiduals: [AnchorResidual],
        numberOfAnchors: Int,
        qualityMetadata: RigidRegistrationQualityMetadata
    ) {
        self.transform = transform
        rotation = transform.rotation
        translation = transform.translation
        self.anchorRMSError = anchorRMSError
        self.anchorMaxError = anchorMaxError
        self.anchorResiduals = anchorResiduals
        self.numberOfAnchors = numberOfAnchors
        self.qualityMetadata = qualityMetadata
    }
}

public struct AnchorRegistrationConfiguration: Codable, Equatable, Sendable {
    public let minimumAnchorCount: Int
    public let minimumAnchorConfidence: Float
    public let minimumSpatialSpreadMeters: Float
    public let minimumCollinearityRatio: Float
    public let robustOutlierScale: Float
    public let robustResidualFloorMeters: Float
    public let diagnosticLargeResidualMeters: Float

    nonisolated public init(
        minimumAnchorCount: Int,
        minimumAnchorConfidence: Float,
        minimumSpatialSpreadMeters: Float,
        minimumCollinearityRatio: Float,
        robustOutlierScale: Float,
        robustResidualFloorMeters: Float,
        diagnosticLargeResidualMeters: Float
    ) {
        self.minimumAnchorCount = minimumAnchorCount
        self.minimumAnchorConfidence = minimumAnchorConfidence
        self.minimumSpatialSpreadMeters = minimumSpatialSpreadMeters
        self.minimumCollinearityRatio = minimumCollinearityRatio
        self.robustOutlierScale = robustOutlierScale
        self.robustResidualFloorMeters = robustResidualFloorMeters
        self.diagnosticLargeResidualMeters = diagnosticLargeResidualMeters
    }

    /// Numerical engineering defaults, not medical acceptance limits.
    nonisolated public static let engineeringDefault = AnchorRegistrationConfiguration(
        minimumAnchorCount: 3,
        minimumAnchorConfidence: 0.2,
        minimumSpatialSpreadMeters: 0.015,
        minimumCollinearityRatio: 0.015,
        robustOutlierScale: 3,
        robustResidualFloorMeters: 0.000_5,
        diagnosticLargeResidualMeters: 0.005
    )
}

public enum AnchorRigidRegistrationError: Error, Equatable {
    case insufficientCorrespondingAnchors(required: Int, actual: Int)
    case lowConfidenceAnchors(required: Int, usable: Int)
    case insufficientSpatialDistribution(spreadMeters: Float)
    case nearlyCollinear(ratio: Float)
    case degenerateWeightedGeometry
    case improperRotation(determinant: Float)
}

public struct AnchorRigidRegistrationEngine: Sendable {
    nonisolated public init() {}

    nonisolated public func register(
        followup: [AnatomicalAnchor],
        to baseline: [AnatomicalAnchor],
        configuration: AnchorRegistrationConfiguration = .engineeringDefault
    ) throws -> RigidRegistrationResult {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let pairs = followup.compactMap { source -> AnchorPair? in
            guard let target = baselineByID[source.id] else { return nil }
            return AnchorPair(source: source, target: target)
        }

        guard pairs.count >= configuration.minimumAnchorCount else {
            throw AnchorRigidRegistrationError.insufficientCorrespondingAnchors(
                required: configuration.minimumAnchorCount,
                actual: pairs.count
            )
        }

        let usable = pairs.filter {
            min($0.source.confidence, $0.target.confidence)
                >= configuration.minimumAnchorConfidence
        }
        guard usable.count >= configuration.minimumAnchorCount else {
            throw AnchorRigidRegistrationError.lowConfidenceAnchors(
                required: configuration.minimumAnchorCount,
                usable: usable.count
            )
        }

        let source = usable.map { $0.source.position.simdValue }
        let target = usable.map { $0.target.position.simdValue }
        let baseWeights = usable.map {
            Double(min($0.source.confidence, $0.target.confidence))
        }

        let distribution = spatialDistribution(points: source)
        guard distribution.spread >= configuration.minimumSpatialSpreadMeters else {
            throw AnchorRigidRegistrationError.insufficientSpatialDistribution(
                spreadMeters: distribution.spread
            )
        }
        guard distribution.collinearityRatio >= configuration.minimumCollinearityRatio else {
            throw AnchorRigidRegistrationError.nearlyCollinear(
                ratio: distribution.collinearityRatio
            )
        }

        let initial = try RigidPointSetSolver.fit(
            source: source,
            target: target,
            weights: baseWeights
        )
        let initialResiduals = zip(source, target).map {
            simd_length(initial.applying(to: $0.0) - $0.1)
        }
        let medianResidual = median(initialResiduals)
        let medianAbsoluteDeviation = median(
            initialResiduals.map { abs($0 - medianResidual) }
        )
        let robustScale = max(
            configuration.robustResidualFloorMeters,
            1.4826 * medianAbsoluteDeviation
        )
        let cutoff = medianResidual + configuration.robustOutlierScale * robustScale

        var effectiveWeights: [Double] = []
        var decisions: [AnchorUseDecision] = []
        for (weight, residual) in zip(baseWeights, initialResiduals) {
            if residual > cutoff {
                let huberFactor = max(0.05, Double(cutoff / residual))
                effectiveWeights.append(weight * huberFactor)
                decisions.append(.robustlyDownweighted)
            } else {
                effectiveWeights.append(weight)
                decisions.append(.used)
            }
        }

        let transform = try RigidPointSetSolver.fit(
            source: source,
            target: target,
            weights: effectiveWeights
        )
        let determinant = simd_determinant(transform.matrix)
        guard determinant > 0.999 && determinant < 1.001 else {
            throw AnchorRigidRegistrationError.improperRotation(determinant: determinant)
        }

        let finalResiduals = zip(source, target).map {
            simd_length(transform.applying(to: $0.0) - $0.1)
        }
        let residualModels = zip(usable.indices, finalResiduals).map { index, residual in
            AnchorResidual(
                id: usable[index].source.id,
                residualMeters: residual,
                effectiveWeight: Float(effectiveWeights[index]),
                decision: decisions[index]
            )
        }
        let weightedSquared = zip(finalResiduals, effectiveWeights).reduce(Double.zero) {
            $0 + Double($1.0 * $1.0) * $1.1
        }
        let weightSum = effectiveWeights.reduce(0, +)
        let rms = Float(sqrt(weightedSquared / weightSum))
        let maximum = finalResiduals.max() ?? 0

        var warnings: [String] = []
        let lowConfidenceIDs = pairs.filter {
            min($0.source.confidence, $0.target.confidence)
                < configuration.minimumAnchorConfidence
        }.map(\.source.id)
        if !lowConfidenceIDs.isEmpty {
            warnings.append("Low-confidence corresponding anchors were excluded.")
        }
        let downweighted = residualModels.filter {
            $0.decision == .robustlyDownweighted
        }.map(\.id)
        if !downweighted.isEmpty {
            warnings.append("Robust weighting reduced one or more anchor contributions.")
        }
        if maximum > configuration.diagnosticLargeResidualMeters {
            warnings.append("At least one anchor residual exceeded the engineering diagnostic level.")
        }

        return RigidRegistrationResult(
            transform: transform,
            anchorRMSError: rms,
            anchorMaxError: maximum,
            anchorResiduals: residualModels,
            numberOfAnchors: usable.count,
            qualityMetadata: RigidRegistrationQualityMetadata(
                status: warnings.isEmpty ? .valid : .validWithWarnings,
                warnings: warnings,
                rejectedOrDownweightedAnchors: lowConfidenceIDs + downweighted,
                spatialSpreadMeters: distribution.spread,
                collinearityRatio: distribution.collinearityRatio,
                rotationDeterminant: determinant
            )
        )
    }

    nonisolated private func spatialDistribution(
        points: [SIMD3<Float>]
    ) -> (spread: Float, collinearityRatio: Float) {
        var maximumDistanceSquared: Float = 0
        var maximumDoubleArea: Float = 0

        for first in points.indices {
            for second in points.indices where second > first {
                maximumDistanceSquared = max(
                    maximumDistanceSquared,
                    simd_length_squared(points[second] - points[first])
                )
                for third in points.indices where third > second {
                    let cross = simd_cross(
                        points[second] - points[first],
                        points[third] - points[first]
                    )
                    maximumDoubleArea = max(maximumDoubleArea, simd_length(cross))
                }
            }
        }

        let spread = sqrt(maximumDistanceSquared)
        let ratio = maximumDistanceSquared > 0
            ? maximumDoubleArea / maximumDistanceSquared
            : 0
        return (spread, ratio)
    }

    nonisolated private func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private struct AnchorPair {
        let source: AnatomicalAnchor
        let target: AnatomicalAnchor
    }
}

enum RigidPointSetSolver {
    nonisolated static func fit(
        source: [SIMD3<Float>],
        target: [SIMD3<Float>],
        weights: [Double]
    ) throws -> RigidTransform {
        guard source.count == target.count,
              source.count == weights.count,
              source.count >= 3 else {
            throw AnchorRigidRegistrationError.degenerateWeightedGeometry
        }

        let weightSum = weights.reduce(0, +)
        guard weightSum > Double.ulpOfOne else {
            throw AnchorRigidRegistrationError.degenerateWeightedGeometry
        }

        var sourceCenter = SIMD3<Double>.zero
        var targetCenter = SIMD3<Double>.zero
        for index in source.indices {
            sourceCenter += SIMD3<Double>(source[index]) * weights[index]
            targetCenter += SIMD3<Double>(target[index]) * weights[index]
        }
        sourceCenter /= weightSum
        targetCenter /= weightSum

        var covariance = simd_double3x3(columns: (.zero, .zero, .zero))
        for index in source.indices {
            let a = SIMD3<Double>(source[index]) - sourceCenter
            let b = SIMD3<Double>(target[index]) - targetCenter
            covariance += simd_double3x3(columns: (
                a * b.x * weights[index],
                a * b.y * weights[index],
                a * b.z * weights[index]
            ))
        }

        let sxx = covariance[0, 0]
        let sxy = covariance[1, 0]
        let sxz = covariance[2, 0]
        let syx = covariance[0, 1]
        let syy = covariance[1, 1]
        let syz = covariance[2, 1]
        let szx = covariance[0, 2]
        let szy = covariance[1, 2]
        let szz = covariance[2, 2]

        var horn = [
            [sxx + syy + szz, syz - szy, szx - sxz, sxy - syx],
            [syz - szy, sxx - syy - szz, sxy + syx, szx + sxz],
            [szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy],
            [sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz]
        ]

        let quaternion = try largestEigenvector(of: &horn)

        let rotationDouble = simd_double3x3(
            simd_quatd(
                ix: quaternion[1],
                iy: quaternion[2],
                iz: quaternion[3],
                r: quaternion[0]
            )
        )
        let translationDouble = targetCenter - rotationDouble * sourceCenter
        let rotation = simd_float3x3(columns: (
            SIMD3<Float>(rotationDouble.columns.0),
            SIMD3<Float>(rotationDouble.columns.1),
            SIMD3<Float>(rotationDouble.columns.2)
        ))
        return RigidTransform(
            matrix: rotation,
            translation: SIMD3<Float>(translationDouble)
        )
    }

    nonisolated private static func largestEigenvector(
        of matrix: inout [[Double]]
    ) throws -> [Double] {
        var eigenvectors = (0..<4).map { row in
            (0..<4).map { column in row == column ? 1.0 : 0.0 }
        }

        for _ in 0..<64 {
            var p = 0
            var q = 1
            var largest = abs(matrix[p][q])
            for row in 0..<4 {
                for column in (row + 1)..<4 where abs(matrix[row][column]) > largest {
                    p = row
                    q = column
                    largest = abs(matrix[row][column])
                }
            }
            if largest < 1e-15 { break }

            let angle = 0.5 * atan2(
                2 * matrix[p][q],
                matrix[q][q] - matrix[p][p]
            )
            let cosine = cos(angle)
            let sine = sin(angle)

            let app = matrix[p][p]
            let aqq = matrix[q][q]
            let apq = matrix[p][q]
            matrix[p][p] = cosine * cosine * app
                - 2 * sine * cosine * apq
                + sine * sine * aqq
            matrix[q][q] = sine * sine * app
                + 2 * sine * cosine * apq
                + cosine * cosine * aqq
            matrix[p][q] = 0
            matrix[q][p] = 0

            for index in 0..<4 where index != p && index != q {
                let aip = matrix[index][p]
                let aiq = matrix[index][q]
                matrix[index][p] = cosine * aip - sine * aiq
                matrix[p][index] = matrix[index][p]
                matrix[index][q] = sine * aip + cosine * aiq
                matrix[q][index] = matrix[index][q]
            }

            for row in 0..<4 {
                let vip = eigenvectors[row][p]
                let viq = eigenvectors[row][q]
                eigenvectors[row][p] = cosine * vip - sine * viq
                eigenvectors[row][q] = sine * vip + cosine * viq
            }
        }

        guard let largestIndex = (0..<4).max(by: {
            matrix[$0][$0] < matrix[$1][$1]
        }) else {
            throw AnchorRigidRegistrationError.degenerateWeightedGeometry
        }
        let vector = (0..<4).map { eigenvectors[$0][largestIndex] }
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > Double.ulpOfOne else {
            throw AnchorRigidRegistrationError.degenerateWeightedGeometry
        }
        return vector.map { $0 / magnitude }
    }
}
