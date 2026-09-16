import Foundation
import simd

public enum SyntheticDeformationDirection: String, Codable, Sendable {
    case outward
    case inward

    var multiplier: Float {
        self == .outward ? 1 : -1
    }
}

public struct SyntheticDeformationParameters: Codable, Equatable, Sendable {
    public let region: RegistrationStudyRegion
    public let maximumDisplacementMeters: Float
    public let spatialSpreadMeters: Float
    public let direction: SyntheticDeformationDirection

    public init(
        region: RegistrationStudyRegion,
        maximumDisplacementMeters: Float,
        spatialSpreadMeters: Float,
        direction: SyntheticDeformationDirection
    ) {
        self.region = region
        self.maximumDisplacementMeters = maximumDisplacementMeters
        self.spatialSpreadMeters = spatialSpreadMeters
        self.direction = direction
    }
}

public struct SyntheticDeformationResult: Codable, Equatable, Sendable {
    public let mesh: FaceMesh
    public let parameters: SyntheticDeformationParameters
    public let displacementByVertexMeters: [Float]
    public let affectedVertexIndices: [Int]
    public let center: FaceMeshPoint
}

public enum SyntheticDeformationError: Error, Equatable {
    case emptyTreatmentRegion
    case invalidSpatialSpread
}

public struct SyntheticDeformationEngine: Sendable {
    nonisolated public init() {}

    nonisolated public func deform(
        mesh: FaceMesh,
        parameters: SyntheticDeformationParameters
    ) throws -> SyntheticDeformationResult {
        guard parameters.spatialSpreadMeters > 0 else {
            throw SyntheticDeformationError.invalidSpatialSpread
        }

        let treatmentMask = RegistrationProfile.treatmentMask(for: parameters.region)
        let affected = treatmentMask.selectedIndices(in: mesh.simdVertices)
        guard !affected.isEmpty else {
            throw SyntheticDeformationError.emptyTreatmentRegion
        }

        let center = affected.reduce(SIMD3<Float>.zero) {
            $0 + mesh.simdVertices[$1]
        } / Float(affected.count)
        let normals = vertexNormals(mesh: mesh)
        let affectedSet = Set(affected)
        var vertices = mesh.simdVertices
        var displacement = [Float](repeating: 0, count: vertices.count)
        let denominator = 2 * parameters.spatialSpreadMeters * parameters.spatialSpreadMeters

        for index in vertices.indices where affectedSet.contains(index) {
            let squaredDistance = simd_length_squared(vertices[index] - center)
            let weight = exp(-squaredDistance / denominator)
            let signedMagnitude = parameters.direction.multiplier
                * parameters.maximumDisplacementMeters
                * weight
            vertices[index] += normals[index] * signedMagnitude
            displacement[index] = signedMagnitude
        }

        return SyntheticDeformationResult(
            mesh: FaceMesh(
                vertices: vertices,
                triangleIndices: mesh.triangleIndices
            ),
            parameters: parameters,
            displacementByVertexMeters: displacement,
            affectedVertexIndices: affected,
            center: FaceMeshPoint(center)
        )
    }

    nonisolated private func vertexNormals(mesh: FaceMesh) -> [SIMD3<Float>] {
        let vertices = mesh.simdVertices
        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        let indices = mesh.triangleIndices.map { Int($0) }

        for offset in stride(from: 0, to: indices.count - 2, by: 3) {
            let first = indices[offset]
            let second = indices[offset + 1]
            let third = indices[offset + 2]
            guard first < vertices.count, second < vertices.count, third < vertices.count else {
                continue
            }
            let normal = simd_cross(
                vertices[second] - vertices[first],
                vertices[third] - vertices[first]
            )
            normals[first] += normal
            normals[second] += normal
            normals[third] += normal
        }

        return normals.map {
            simd_length_squared($0) > Float.ulpOfOne
                ? simd_normalize($0)
                : SIMD3<Float>(0, 0, 1)
        }
    }
}

public struct RegistrationBiasMetrics: Codable, Equatable, Sendable {
    public let groundTruthPeakMeters: Float
    public let recoveredPeakMeters: Float
    public let peakRecoveryErrorMeters: Float
    public let groundTruthMeanMeters: Float
    public let recoveredMeanMeters: Float
    public let meanRecoveryErrorMeters: Float
    public let groundTruthRMSMeters: Float
    public let recoveredRMSMeters: Float
    public let rmsRecoveryErrorMeters: Float
    public let registrationAttenuationMeters: Float
    public let relativeAttenuation: Float?
    public let stableFalseDisplacementRMSMeters: Float
    public let spatialLocalizationErrorMeters: Float
    public let rotationRecoveryErrorRadians: Float
    public let translationRecoveryErrorMeters: Float
}

public struct SyntheticStrategyValidationResult: Codable, Equatable, Sendable, Identifiable {
    public var id: RegistrationStrategy { strategy }
    public let strategy: RegistrationStrategy
    public let metrics: RegistrationBiasMetrics
}

public struct SyntheticRegistrationValidationResult: Codable, Equatable, Sendable {
    public let deformation: SyntheticDeformationParameters
    public let poseTransform: RigidTransform
    public let strategies: [SyntheticStrategyValidationResult]
}

public struct SyntheticRegistrationValidator: Sendable {
    nonisolated public init() {}

    nonisolated public func validate(
        baseline: FaceMesh,
        deformation: SyntheticDeformationParameters,
        poseTransform: RigidTransform
    ) throws -> SyntheticRegistrationValidationResult {
        let synthetic = try SyntheticDeformationEngine().deform(
            mesh: baseline,
            parameters: deformation
        )
        let posedFollowup = poseTransform.applying(to: synthetic.mesh)
        let profile = RegistrationProfile.engineeringProfile(for: deformation.region)
        let comparison = try RegistrationStrategyComparisonEngine().compare(
            baseline: baseline,
            followup: posedFollowup,
            profile: profile
        )
        let expectedRegistration = poseTransform.inverted()
        let treatmentIndices = profile.treatmentVertexIndices(in: baseline)
        let treatmentSet = Set(treatmentIndices)
        let truth = treatmentIndices.map {
            synthetic.displacementByVertexMeters[$0]
        }
        let truthMetrics = SurfaceDifferenceAnalyzer().metrics(for: truth)
        let truthPeakIndex = treatmentIndices.max {
            abs(synthetic.displacementByVertexMeters[$0])
                < abs(synthetic.displacementByVertexMeters[$1])
        } ?? treatmentIndices[0]

        let results = try comparison.strategyResults.map { result in
            let aligned = result.finalTransform.applying(to: posedFollowup)
            let measured = try SurfaceDifferenceAnalyzer().analyze(
                baseline: baseline,
                alignedFollowup: aligned,
                sampleIndices: treatmentIndices,
                baselineRegionIndices: treatmentSet
            )
            let measuredPeakSample = measured.samples.max {
                abs($0.signedDistanceMeters) < abs($1.signedDistanceMeters)
            }
            let measuredPeak = measuredPeakSample?.signedDistanceMeters ?? 0
            let truthPeak = synthetic.displacementByVertexMeters[truthPeakIndex]
            let attenuation = abs(truthPeak) - abs(measuredPeak)
            let localizationError: Float
            if let measuredPeakSample {
                localizationError = simd_length(
                    baseline.simdVertices[measuredPeakSample.vertexIndex]
                        - baseline.simdVertices[truthPeakIndex]
                )
            } else {
                localizationError = .infinity
            }

            return SyntheticStrategyValidationResult(
                strategy: result.strategy,
                metrics: RegistrationBiasMetrics(
                    groundTruthPeakMeters: truthPeak,
                    recoveredPeakMeters: measuredPeak,
                    peakRecoveryErrorMeters: measuredPeak - truthPeak,
                    groundTruthMeanMeters: truthMetrics.meanSignedResidual,
                    recoveredMeanMeters: measured.metrics.meanSignedResidual,
                    meanRecoveryErrorMeters: measured.metrics.meanSignedResidual
                        - truthMetrics.meanSignedResidual,
                    groundTruthRMSMeters: truthMetrics.rmsResidual,
                    recoveredRMSMeters: measured.metrics.rmsResidual,
                    rmsRecoveryErrorMeters: measured.metrics.rmsResidual
                        - truthMetrics.rmsResidual,
                    registrationAttenuationMeters: attenuation,
                    relativeAttenuation: abs(truthPeak) > Float.ulpOfOne
                        ? attenuation / abs(truthPeak)
                        : nil,
                    stableFalseDisplacementRMSMeters:
                        result.stableROIResiduals.rmsResidual,
                    spatialLocalizationErrorMeters: localizationError,
                    rotationRecoveryErrorRadians: rotationError(
                        result.finalTransform,
                        expectedRegistration
                    ),
                    translationRecoveryErrorMeters: simd_length(
                        result.finalTransform.translation.simdValue
                            - expectedRegistration.translation.simdValue
                    )
                )
            )
        }

        return SyntheticRegistrationValidationResult(
            deformation: deformation,
            poseTransform: poseTransform,
            strategies: results
        )
    }

    nonisolated private func rotationError(
        _ measured: RigidTransform,
        _ expected: RigidTransform
    ) -> Float {
        let relative = measured.matrix * expected.matrix.transpose
        let cosine = min(
            1,
            max(-1, (relative[0, 0] + relative[1, 1] + relative[2, 2] - 1) / 2)
        )
        return acos(cosine)
    }
}

public struct SyntheticPoseGenerator: Sendable {
    nonisolated public init() {}

    /// Reproducible engineering pose perturbations for validation experiments.
    nonisolated public func generate(
        seed: UInt64,
        count: Int,
        maximumRotationRadians: Float = 0.2,
        maximumTranslationMeters: Float = 0.012
    ) -> [RigidTransform] {
        var state = seed
        func nextUnit() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        func symmetric() -> Float { 2 * nextUnit() - 1 }

        return (0..<count).map { _ in
            var axis = SIMD3<Float>(symmetric(), symmetric(), symmetric())
            if simd_length_squared(axis) < 0.01 {
                axis = SIMD3<Float>(0, 1, 0)
            }
            let rotation = simd_float3x3(
                simd_quatf(
                    angle: symmetric() * maximumRotationRadians,
                    axis: simd_normalize(axis)
                )
            )
            let translation = SIMD3<Float>(
                symmetric(), symmetric(), symmetric()
            ) * maximumTranslationMeters
            return RigidTransform(matrix: rotation, translation: translation)
        }
    }
}
