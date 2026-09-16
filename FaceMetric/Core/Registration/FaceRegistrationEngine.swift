import Foundation
import simd

public struct RegistrationBounds: Codable, Equatable, Sendable {
    public let minimum: FaceMeshPoint
    public let maximum: FaceMeshPoint

    nonisolated public init(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        self.minimum = FaceMeshPoint(minimum)
        self.maximum = FaceMeshPoint(maximum)
    }

    nonisolated func contains(_ point: SIMD3<Float>) -> Bool {
        let lower = minimum.simdValue
        let upper = maximum.simdValue
        return point.x >= lower.x && point.x <= upper.x
            && point.y >= lower.y && point.y <= upper.y
            && point.z >= lower.z && point.z <= upper.z
    }
}

public struct RegistrationRegionMask: Codable, Equatable, Sendable {
    public let identifier: String
    public let includedBounds: [RegistrationBounds]
    public let excludedBounds: [RegistrationBounds]

    nonisolated public init(
        identifier: String,
        includedBounds: [RegistrationBounds],
        excludedBounds: [RegistrationBounds] = []
    ) {
        self.identifier = identifier
        self.includedBounds = includedBounds
        self.excludedBounds = excludedBounds
    }

    /// Engineering default only. The normalized boxes require empirical validation.
    nonisolated public static let genericStableRegions = RegistrationRegionMask(
        identifier: "generic-stable-v1-engineering-default",
        includedBounds: [
            RegistrationBounds(
                minimum: SIMD3<Float>(0.15, 0.62, 0),
                maximum: SIMD3<Float>(0.85, 1, 1)
            ),
            RegistrationBounds(
                minimum: SIMD3<Float>(0, 0.28, 0),
                maximum: SIMD3<Float>(0.30, 0.78, 1)
            ),
            RegistrationBounds(
                minimum: SIMD3<Float>(0.70, 0.28, 0),
                maximum: SIMD3<Float>(1, 0.78, 1)
            )
        ]
    )

    nonisolated public static let entireFace = RegistrationRegionMask(
        identifier: "entire-face",
        includedBounds: [
            RegistrationBounds(
                minimum: SIMD3<Float>(repeating: 0),
                maximum: SIMD3<Float>(repeating: 1)
            )
        ]
    )

    nonisolated func selectedIndices(in vertices: [SIMD3<Float>]) -> [Int] {
        guard let first = vertices.first else { return [] }

        var minimum = first
        var maximum = first
        for vertex in vertices.dropFirst() {
            minimum = simd_min(minimum, vertex)
            maximum = simd_max(maximum, vertex)
        }

        let extent = maximum - minimum
        let safeExtent = SIMD3<Float>(
            max(extent.x, Float.ulpOfOne),
            max(extent.y, Float.ulpOfOne),
            max(extent.z, Float.ulpOfOne)
        )

        return vertices.indices.filter { index in
            let normalized = (vertices[index] - minimum) / safeExtent
            let included = includedBounds.isEmpty || includedBounds.contains { $0.contains(normalized) }
            let excluded = excludedBounds.contains { $0.contains(normalized) }
            return included && !excluded
        }
    }
}

public struct FaceRegistrationConfiguration: Codable, Equatable, Sendable {
    public let regionMask: RegistrationRegionMask
    public let maximumIterations: Int
    public let convergenceToleranceMeters: Float
    public let maximumCorrespondenceDistanceMeters: Float
    public let minimumCorrespondenceCount: Int

    nonisolated public init(
        regionMask: RegistrationRegionMask,
        maximumIterations: Int,
        convergenceToleranceMeters: Float,
        maximumCorrespondenceDistanceMeters: Float,
        minimumCorrespondenceCount: Int
    ) {
        self.regionMask = regionMask
        self.maximumIterations = maximumIterations
        self.convergenceToleranceMeters = convergenceToleranceMeters
        self.maximumCorrespondenceDistanceMeters = maximumCorrespondenceDistanceMeters
        self.minimumCorrespondenceCount = minimumCorrespondenceCount
    }

    /// Engineering defaults requiring empirical validation on repeated physical scans.
    nonisolated public static let engineeringDefault = FaceRegistrationConfiguration(
        regionMask: .genericStableRegions,
        maximumIterations: 20,
        convergenceToleranceMeters: 0.000_01,
        maximumCorrespondenceDistanceMeters: 0.01,
        minimumCorrespondenceCount: 80
    )
}

public struct RigidTransform: Codable, Equatable, Sendable {
    /// Row-major 3 x 3 rotation.
    public let rotation: [Float]
    public let translation: FaceMeshPoint

    nonisolated public init(rotation: [Float], translation: SIMD3<Float>) {
        precondition(rotation.count == 9)
        self.rotation = rotation
        self.translation = FaceMeshPoint(translation)
    }

    nonisolated public static let identity = RigidTransform(
        rotation: [1, 0, 0, 0, 1, 0, 0, 0, 1],
        translation: .zero
    )

    nonisolated public func applying(to point: SIMD3<Float>) -> SIMD3<Float> {
        let rotated = SIMD3<Float>(
            rotation[0] * point.x + rotation[1] * point.y + rotation[2] * point.z,
            rotation[3] * point.x + rotation[4] * point.y + rotation[5] * point.z,
            rotation[6] * point.x + rotation[7] * point.y + rotation[8] * point.z
        )
        return rotated + translation.simdValue
    }

    nonisolated public func applying(to mesh: FaceMesh) -> FaceMesh {
        FaceMesh(
            vertices: mesh.simdVertices.map(applying(to:)),
            triangleIndices: mesh.triangleIndices
        )
    }

    nonisolated public func inverted() -> RigidTransform {
        let inverseRotation = matrix.transpose
        return RigidTransform(
            matrix: inverseRotation,
            translation: -(inverseRotation * translation.simdValue)
        )
    }

    nonisolated func concatenating(_ preceding: RigidTransform) -> RigidTransform {
        let left = matrix
        let right = preceding.matrix
        let combinedRotation = left * right
        let combinedTranslation = applying(to: preceding.translation.simdValue)
        return RigidTransform(matrix: combinedRotation, translation: combinedTranslation)
    }

    nonisolated var matrix: simd_float3x3 {
        simd_float3x3(rows: [
            SIMD3<Float>(rotation[0], rotation[1], rotation[2]),
            SIMD3<Float>(rotation[3], rotation[4], rotation[5]),
            SIMD3<Float>(rotation[6], rotation[7], rotation[8])
        ])
    }

    nonisolated init(matrix: simd_float3x3, translation: SIMD3<Float>) {
        self.init(
            rotation: [
                matrix[0, 0], matrix[1, 0], matrix[2, 0],
                matrix[0, 1], matrix[1, 1], matrix[2, 1],
                matrix[0, 2], matrix[1, 2], matrix[2, 2]
            ],
            translation: translation
        )
    }
}

public enum RegistrationQuality: String, Codable, Equatable, Sendable {
    case converged
    case iterationLimitReached
}

public struct RegistrationResult: Codable, Equatable, Sendable {
    /// Maps follow-up face-local coordinates into baseline face-local coordinates.
    public let transform: RigidTransform
    public let rmsError: Float
    public let correspondenceCount: Int
    public let iterationCount: Int
    public let quality: RegistrationQuality
    public let regionMaskIdentifier: String

    public init(
        transform: RigidTransform,
        rmsError: Float,
        correspondenceCount: Int,
        iterationCount: Int,
        quality: RegistrationQuality,
        regionMaskIdentifier: String
    ) {
        self.transform = transform
        self.rmsError = rmsError
        self.correspondenceCount = correspondenceCount
        self.iterationCount = iterationCount
        self.quality = quality
        self.regionMaskIdentifier = regionMaskIdentifier
    }
}

public enum FaceRegistrationError: Error, Equatable {
    case incompatibleTopology
    case insufficientStableVertices(required: Int, actual: Int)
    case insufficientCorrespondences(required: Int, actual: Int)
    case degenerateGeometry
}

public struct FaceRegistrationEngine: Sendable {
    nonisolated public init() {}

    nonisolated public func register(
        baseline: FaceMesh,
        followup: FaceMesh,
        configuration: FaceRegistrationConfiguration = .engineeringDefault
    ) throws -> RegistrationResult {
        let baselineVertices = baseline.simdVertices
        let followupVertices = followup.simdVertices
        guard baselineVertices.count == followupVertices.count else {
            throw FaceRegistrationError.incompatibleTopology
        }

        let stableIndices = configuration.regionMask.selectedIndices(in: baselineVertices)
        guard stableIndices.count >= configuration.minimumCorrespondenceCount else {
            throw FaceRegistrationError.insufficientStableVertices(
                required: configuration.minimumCorrespondenceCount,
                actual: stableIndices.count
            )
        }

        let stableBaseline = stableIndices.map { baselineVertices[$0] }
        let stableFollowup = stableIndices.map { followupVertices[$0] }

        // ARFaceGeometry uses consistent topology. Its paired stable vertices provide
        // a deterministic face-local initial alignment before nearest-neighbor ICP.
        var transform = try rigidFit(source: stableFollowup, target: stableBaseline)
        var previousRMS = Float.greatestFiniteMagnitude
        var finalRMS = previousRMS
        var finalCount = 0

        for iteration in 1...configuration.maximumIterations {
            var sourceCorrespondences: [SIMD3<Float>] = []
            var targetCorrespondences: [SIMD3<Float>] = []
            sourceCorrespondences.reserveCapacity(stableFollowup.count)
            targetCorrespondences.reserveCapacity(stableFollowup.count)

            for vertex in stableFollowup {
                let aligned = transform.applying(to: vertex)
                if let match = nearestPoint(
                    to: aligned,
                    in: stableBaseline,
                    maximumDistance: configuration.maximumCorrespondenceDistanceMeters
                ) {
                    sourceCorrespondences.append(aligned)
                    targetCorrespondences.append(match)
                }
            }

            guard sourceCorrespondences.count >= configuration.minimumCorrespondenceCount else {
                throw FaceRegistrationError.insufficientCorrespondences(
                    required: configuration.minimumCorrespondenceCount,
                    actual: sourceCorrespondences.count
                )
            }

            let refinement = try rigidFit(
                source: sourceCorrespondences,
                target: targetCorrespondences
            )
            transform = refinement.concatenating(transform)
            finalRMS = rms(
                sourceCorrespondences.map { refinement.applying(to: $0) },
                targetCorrespondences
            )
            finalCount = sourceCorrespondences.count

            if abs(previousRMS - finalRMS) <= configuration.convergenceToleranceMeters {
                return RegistrationResult(
                    transform: transform,
                    rmsError: finalRMS,
                    correspondenceCount: finalCount,
                    iterationCount: iteration,
                    quality: .converged,
                    regionMaskIdentifier: configuration.regionMask.identifier
                )
            }
            previousRMS = finalRMS
        }

        return RegistrationResult(
            transform: transform,
            rmsError: finalRMS,
            correspondenceCount: finalCount,
            iterationCount: configuration.maximumIterations,
            quality: .iterationLimitReached,
            regionMaskIdentifier: configuration.regionMask.identifier
        )
    }

    nonisolated private func nearestPoint(
        to point: SIMD3<Float>,
        in candidates: [SIMD3<Float>],
        maximumDistance: Float
    ) -> SIMD3<Float>? {
        let maximumSquared = maximumDistance * maximumDistance
        var bestSquared = maximumSquared
        var best: SIMD3<Float>?

        for candidate in candidates {
            let delta = candidate - point
            let squared = simd_length_squared(delta)
            if squared <= bestSquared {
                bestSquared = squared
                best = candidate
            }
        }
        return best
    }

    nonisolated private func rms(_ source: [SIMD3<Float>], _ target: [SIMD3<Float>]) -> Float {
        let total = zip(source, target).reduce(Float.zero) { partial, pair in
            partial + simd_length_squared(pair.0 - pair.1)
        }
        return sqrt(total / Float(source.count))
    }

    nonisolated private func rigidFit(
        source: [SIMD3<Float>],
        target: [SIMD3<Float>]
    ) throws -> RigidTransform {
        guard source.count == target.count, source.count >= 3 else {
            throw FaceRegistrationError.degenerateGeometry
        }

        let sourceCenter = source.reduce(.zero, +) / Float(source.count)
        let targetCenter = target.reduce(.zero, +) / Float(target.count)

        var covariance = simd_float3x3(columns: (.zero, .zero, .zero))
        for (sourcePoint, targetPoint) in zip(source, target) {
            let a = sourcePoint - sourceCenter
            let b = targetPoint - targetCenter
            covariance += simd_float3x3(columns: (
                a * b.x,
                a * b.y,
                a * b.z
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

        let shift = horn.map { row in row.reduce(Float.zero) { $0 + abs($1) } }.max() ?? 0
        guard shift > Float.ulpOfOne else {
            throw FaceRegistrationError.degenerateGeometry
        }
        for index in 0..<4 {
            horn[index][index] += shift
        }

        var quaternion = [Float(1), 0, 0, 0]
        for _ in 0..<80 {
            var next = [Float](repeating: 0, count: 4)
            for row in 0..<4 {
                for column in 0..<4 {
                    next[row] += horn[row][column] * quaternion[column]
                }
            }
            let magnitude = sqrt(next.reduce(Float.zero) { $0 + $1 * $1 })
            guard magnitude > Float.ulpOfOne else {
                throw FaceRegistrationError.degenerateGeometry
            }
            quaternion = next.map { $0 / magnitude }
        }

        let rotationQuaternion = simd_quatf(
            ix: quaternion[1],
            iy: quaternion[2],
            iz: quaternion[3],
            r: quaternion[0]
        )
        let rotation = simd_float3x3(rotationQuaternion)
        let translation = targetCenter - rotation * sourceCenter
        return RigidTransform(matrix: rotation, translation: translation)
    }
}
