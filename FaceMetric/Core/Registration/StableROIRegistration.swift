import Foundation
import simd

public struct StableROIRefinementConfiguration: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let maximumIterations: Int
    public let convergenceToleranceMeters: Float
    public let maximumCorrespondenceDistanceMeters: Float
    public let trimFraction: Float
    public let minimumCorrespondenceCount: Int

    public init(
        isEnabled: Bool,
        maximumIterations: Int,
        convergenceToleranceMeters: Float,
        maximumCorrespondenceDistanceMeters: Float,
        trimFraction: Float,
        minimumCorrespondenceCount: Int
    ) {
        self.isEnabled = isEnabled
        self.maximumIterations = maximumIterations
        self.convergenceToleranceMeters = convergenceToleranceMeters
        self.maximumCorrespondenceDistanceMeters = maximumCorrespondenceDistanceMeters
        self.trimFraction = trimFraction
        self.minimumCorrespondenceCount = minimumCorrespondenceCount
    }

    /// Numerical engineering defaults requiring empirical validation.
    nonisolated public static let engineeringDefault = StableROIRefinementConfiguration(
        isEnabled: true,
        maximumIterations: 15,
        convergenceToleranceMeters: 0.000_01,
        maximumCorrespondenceDistanceMeters: 0.01,
        trimFraction: 0.15,
        minimumCorrespondenceCount: 60
    )
}

public struct StableROIRefinementResult: Codable, Equatable, Sendable {
    public let transform: RigidTransform
    public let residualMetrics: SurfaceResidualMetrics
    public let correspondenceCount: Int
    public let iterationCount: Int
    public let converged: Bool
    public let stableVertexIndices: [Int]
}

public enum StableROIRefinementError: Error, Equatable {
    case incompatibleTopology
    case insufficientStableVertices(required: Int, actual: Int)
    case insufficientCorrespondences(required: Int, actual: Int)
}

public struct StableROIRegistrationRefiner: Sendable {
    nonisolated public init() {}

    nonisolated public func refine(
        baseline: FaceMesh,
        followup: FaceMesh,
        initialTransform: RigidTransform,
        profile: RegistrationProfile,
        configuration: StableROIRefinementConfiguration = .engineeringDefault
    ) throws -> StableROIRefinementResult {
        guard baseline.vertices.count == followup.vertices.count else {
            throw StableROIRefinementError.incompatibleTopology
        }

        let stableIndices = profile.stableVertexIndices(in: baseline)
        guard stableIndices.count >= configuration.minimumCorrespondenceCount else {
            throw StableROIRefinementError.insufficientStableVertices(
                required: configuration.minimumCorrespondenceCount,
                actual: stableIndices.count
            )
        }

        if !configuration.isEnabled {
            let metrics = try stableMetrics(
                baseline: baseline,
                followup: followup,
                transform: initialTransform,
                stableIndices: stableIndices
            )
            return StableROIRefinementResult(
                transform: initialTransform,
                residualMetrics: metrics,
                correspondenceCount: stableIndices.count,
                iterationCount: 0,
                converged: true,
                stableVertexIndices: stableIndices
            )
        }

        let baselineStable = stableIndices.map { baseline.simdVertices[$0] }
        let followupStable = stableIndices.map { followup.simdVertices[$0] }
        var transform = initialTransform
        var previousRMS = Float.greatestFiniteMagnitude
        var finalCount = 0

        for iteration in 1...configuration.maximumIterations {
            var correspondences: [(source: SIMD3<Float>, target: SIMD3<Float>, distance: Float)] = []
            correspondences.reserveCapacity(followupStable.count)

            for sourceVertex in followupStable {
                let aligned = transform.applying(to: sourceVertex)
                if let nearest = nearestPoint(
                    to: aligned,
                    candidates: baselineStable,
                    maximumDistance: configuration.maximumCorrespondenceDistanceMeters
                ) {
                    correspondences.append((aligned, nearest.point, nearest.distance))
                }
            }

            correspondences.sort { $0.distance < $1.distance }
            let retainedCount = Int(
                Float(correspondences.count) * (1 - configuration.trimFraction)
            )
            let retained = Array(correspondences.prefix(max(0, retainedCount)))
            guard retained.count >= configuration.minimumCorrespondenceCount else {
                throw StableROIRefinementError.insufficientCorrespondences(
                    required: configuration.minimumCorrespondenceCount,
                    actual: retained.count
                )
            }

            let incremental = try RigidPointSetSolver.fit(
                source: retained.map(\.source),
                target: retained.map(\.target),
                weights: Array(repeating: 1, count: retained.count)
            )
            transform = incremental.concatenating(transform)
            finalCount = retained.count

            let rms = sqrt(
                retained.reduce(Float.zero) {
                    $0 + simd_length_squared(
                        incremental.applying(to: $1.source) - $1.target
                    )
                } / Float(retained.count)
            )
            if abs(previousRMS - rms) <= configuration.convergenceToleranceMeters {
                return StableROIRefinementResult(
                    transform: transform,
                    residualMetrics: try stableMetrics(
                        baseline: baseline,
                        followup: followup,
                        transform: transform,
                        stableIndices: stableIndices
                    ),
                    correspondenceCount: finalCount,
                    iterationCount: iteration,
                    converged: true,
                    stableVertexIndices: stableIndices
                )
            }
            previousRMS = rms
        }

        return StableROIRefinementResult(
            transform: transform,
            residualMetrics: try stableMetrics(
                baseline: baseline,
                followup: followup,
                transform: transform,
                stableIndices: stableIndices
            ),
            correspondenceCount: finalCount,
            iterationCount: configuration.maximumIterations,
            converged: false,
            stableVertexIndices: stableIndices
        )
    }

    nonisolated private func stableMetrics(
        baseline: FaceMesh,
        followup: FaceMesh,
        transform: RigidTransform,
        stableIndices: [Int]
    ) throws -> SurfaceResidualMetrics {
        try SurfaceDifferenceAnalyzer().analyze(
            baseline: baseline,
            alignedFollowup: transform.applying(to: followup),
            sampleIndices: stableIndices,
            baselineRegionIndices: Set(stableIndices)
        ).metrics
    }

    nonisolated private func nearestPoint(
        to point: SIMD3<Float>,
        candidates: [SIMD3<Float>],
        maximumDistance: Float
    ) -> (point: SIMD3<Float>, distance: Float)? {
        var bestSquared = maximumDistance * maximumDistance
        var best: SIMD3<Float>?
        for candidate in candidates {
            let squared = simd_length_squared(candidate - point)
            if squared <= bestSquared {
                bestSquared = squared
                best = candidate
            }
        }
        return best.map { ($0, sqrt(bestSquared)) }
    }
}

public enum RegistrationStrategy: String, Codable, CaseIterable, Sendable, Identifiable {
    case fullFaceICP
    case anchorOnly
    case anchorAndStableROI

    public var id: String { rawValue }

    public var displayName: LocalizedStringResource {
        switch self {
        case .fullFaceICP:
            return "Full Face ICP (Control)"
        case .anchorOnly:
            return "Anchor Only"
        case .anchorAndStableROI:
            return "Anchor + Stable ROI"
        }
    }
}

public struct StrategyRegistrationResult: Codable, Equatable, Sendable, Identifiable {
    public var id: RegistrationStrategy { strategy }
    public let strategy: RegistrationStrategy
    public let finalTransform: RigidTransform
    public let anchorRegistration: RigidRegistrationResult?
    public let stableROIResiduals: SurfaceResidualMetrics
    public let treatmentSurfaceDifference: SurfaceDifferenceResult
    public let refinementIterations: Int
    public let baselineAnchors: [AnatomicalAnchor]
    public let followupAnchors: [AnatomicalAnchor]
}

public struct RegistrationComparisonResult: Codable, Equatable, Sendable {
    public let profileIdentifier: String
    public let strategyResults: [StrategyRegistrationResult]

    public func result(for strategy: RegistrationStrategy) -> StrategyRegistrationResult? {
        strategyResults.first { $0.strategy == strategy }
    }
}

public struct RegistrationStrategyComparisonEngine: Sendable {
    nonisolated public init() {}

    nonisolated public func compare(
        baseline: FaceMesh,
        followup: FaceMesh,
        profile: RegistrationProfile,
        refinementConfiguration: StableROIRefinementConfiguration = .engineeringDefault
    ) throws -> RegistrationComparisonResult {
        let extractor = AnatomicalAnchorExtractor()
        let baselineAnchors = try extractor.extract(
            from: baseline,
            definitions: profile.referenceAnchors
        )
        let followupAnchors = try extractor.extractCorresponding(
            from: followup,
            baselineAnchors: baselineAnchors
        )
        let anchorResult = try AnchorRigidRegistrationEngine().register(
            followup: followupAnchors,
            to: baselineAnchors
        )
        let stableIndices = profile.stableVertexIndices(in: baseline)

        let anchorStableMetrics = try SurfaceDifferenceAnalyzer().analyze(
            baseline: baseline,
            alignedFollowup: anchorResult.transform.applying(to: followup),
            sampleIndices: stableIndices,
            baselineRegionIndices: Set(stableIndices)
        ).metrics

        let refinement = try StableROIRegistrationRefiner().refine(
            baseline: baseline,
            followup: followup,
            initialTransform: anchorResult.transform,
            profile: profile,
            configuration: refinementConfiguration
        )

        let minimumFullFaceCorrespondences = min(
            80,
            max(3, baseline.vertices.count / 4)
        )
        let fullFaceResult = try FaceRegistrationEngine().register(
            baseline: baseline,
            followup: followup,
            configuration: FaceRegistrationConfiguration(
                regionMask: .entireFace,
                maximumIterations: 20,
                convergenceToleranceMeters: 0.000_01,
                maximumCorrespondenceDistanceMeters: 0.02,
                minimumCorrespondenceCount: minimumFullFaceCorrespondences
            )
        )
        let fullFaceStableMetrics = try SurfaceDifferenceAnalyzer().analyze(
            baseline: baseline,
            alignedFollowup: fullFaceResult.transform.applying(to: followup),
            sampleIndices: stableIndices,
            baselineRegionIndices: Set(stableIndices)
        ).metrics
        let treatmentIndices = profile.treatmentVertexIndices(in: baseline)
        let treatmentSet = Set(treatmentIndices)
        func treatmentDifference(
            transform: RigidTransform
        ) throws -> SurfaceDifferenceResult {
            try SurfaceDifferenceAnalyzer().analyze(
                baseline: baseline,
                alignedFollowup: transform.applying(to: followup),
                sampleIndices: treatmentIndices,
                baselineRegionIndices: treatmentSet
            )
        }

        return RegistrationComparisonResult(
            profileIdentifier: profile.identifier,
            strategyResults: [
                StrategyRegistrationResult(
                    strategy: .fullFaceICP,
                    finalTransform: fullFaceResult.transform,
                    anchorRegistration: nil,
                    stableROIResiduals: fullFaceStableMetrics,
                    treatmentSurfaceDifference: try treatmentDifference(
                        transform: fullFaceResult.transform
                    ),
                    refinementIterations: fullFaceResult.iterationCount,
                    baselineAnchors: baselineAnchors,
                    followupAnchors: followupAnchors
                ),
                StrategyRegistrationResult(
                    strategy: .anchorOnly,
                    finalTransform: anchorResult.transform,
                    anchorRegistration: anchorResult,
                    stableROIResiduals: anchorStableMetrics,
                    treatmentSurfaceDifference: try treatmentDifference(
                        transform: anchorResult.transform
                    ),
                    refinementIterations: 0,
                    baselineAnchors: baselineAnchors,
                    followupAnchors: followupAnchors
                ),
                StrategyRegistrationResult(
                    strategy: .anchorAndStableROI,
                    finalTransform: refinement.transform,
                    anchorRegistration: anchorResult,
                    stableROIResiduals: refinement.residualMetrics,
                    treatmentSurfaceDifference: try treatmentDifference(
                        transform: refinement.transform
                    ),
                    refinementIterations: refinement.iterationCount,
                    baselineAnchors: baselineAnchors,
                    followupAnchors: followupAnchors
                )
            ]
        )
    }
}
