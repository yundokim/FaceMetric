import Foundation
import simd

public enum AnchorID: String, Codable, CaseIterable, Sendable {
    case upperForehead
    case leftForehead
    case rightForehead
    case leftPeriorbital
    case rightPeriorbital
    case nasalRoot
}

public struct AnatomicalAnchor: Codable, Equatable, Sendable, Identifiable {
    public let id: AnchorID
    public let position: FaceMeshPoint
    public let confidence: Float
    public let sourceVertices: [Int]

    nonisolated public init(
        id: AnchorID,
        position: SIMD3<Float>,
        confidence: Float,
        sourceVertices: [Int]
    ) {
        self.id = id
        self.position = FaceMeshPoint(position)
        self.confidence = min(max(confidence, 0), 1)
        self.sourceVertices = sourceVertices
    }
}

public struct AnatomicalAnchorDefinition: Codable, Equatable, Sendable {
    public let id: AnchorID
    public let patch: RegistrationBounds
    public let priorConfidence: Float
    public let minimumVertexCount: Int
    public let trimFraction: Float

    public init(
        id: AnchorID,
        patch: RegistrationBounds,
        priorConfidence: Float = 1,
        minimumVertexCount: Int = 4,
        trimFraction: Float = 0.2
    ) {
        self.id = id
        self.patch = patch
        self.priorConfidence = priorConfidence
        self.minimumVertexCount = minimumVertexCount
        self.trimFraction = min(max(trimFraction, 0), 0.45)
    }
}

public enum AnatomicalAnchorExtractionError: Error, Equatable {
    case insufficientPatchVertices(anchor: AnchorID, required: Int, actual: Int)
}

public struct AnatomicalAnchorExtractor: Sendable {
    nonisolated public init() {}

    /// Returns a trimmed centroid. Vertices farthest from the coordinate-wise
    /// median are discarded, then retained vertices are averaged.
    nonisolated public func extract(
        from mesh: FaceMesh,
        definitions: [AnatomicalAnchorDefinition]
    ) throws -> [AnatomicalAnchor] {
        let vertices = mesh.simdVertices
        let normalization = FaceBoundsNormalization(vertices: vertices)

        return try definitions.map { definition in
            let indices = vertices.indices.filter {
                definition.patch.contains(normalization.normalize(vertices[$0]))
            }
            guard indices.count >= definition.minimumVertexCount else {
                throw AnatomicalAnchorExtractionError.insufficientPatchVertices(
                    anchor: definition.id,
                    required: definition.minimumVertexCount,
                    actual: indices.count
                )
            }

            let patchVertices = indices.map { vertices[$0] }
            let robustCenter = coordinateMedian(patchVertices)
            let ordered = indices.sorted {
                simd_length_squared(vertices[$0] - robustCenter)
                    < simd_length_squared(vertices[$1] - robustCenter)
            }
            let retainedCount = max(
                definition.minimumVertexCount,
                Int(Float(ordered.count) * (1 - definition.trimFraction))
            )
            let retained = Array(ordered.prefix(retainedCount))
            let centroid = retained.reduce(SIMD3<Float>.zero) {
                $0 + vertices[$1]
            } / Float(retained.count)
            let coverageConfidence = min(
                1,
                Float(retained.count) / Float(max(definition.minimumVertexCount * 2, 1))
            )

            return AnatomicalAnchor(
                id: definition.id,
                position: centroid,
                confidence: definition.priorConfidence * coverageConfidence,
                sourceVertices: retained
            )
        }
    }

    /// Recomputes corresponding patch centroids from the topology-defined
    /// source sets established on the baseline mesh.
    nonisolated public func extractCorresponding(
        from mesh: FaceMesh,
        baselineAnchors: [AnatomicalAnchor]
    ) throws -> [AnatomicalAnchor] {
        let vertices = mesh.simdVertices
        return try baselineAnchors.map { baselineAnchor in
            let indices = baselineAnchor.sourceVertices.filter { $0 < vertices.count }
            guard indices.count == baselineAnchor.sourceVertices.count,
                  !indices.isEmpty else {
                throw AnatomicalAnchorExtractionError.insufficientPatchVertices(
                    anchor: baselineAnchor.id,
                    required: baselineAnchor.sourceVertices.count,
                    actual: indices.count
                )
            }
            let centroid = indices.reduce(SIMD3<Float>.zero) {
                $0 + vertices[$1]
            } / Float(indices.count)
            return AnatomicalAnchor(
                id: baselineAnchor.id,
                position: centroid,
                confidence: baselineAnchor.confidence,
                sourceVertices: indices
            )
        }
    }

    nonisolated private func coordinateMedian(_ vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        func median(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            if sorted.count.isMultiple(of: 2) {
                return (sorted[middle - 1] + sorted[middle]) / 2
            }
            return sorted[middle]
        }

        return SIMD3<Float>(
            median(vertices.map(\.x)),
            median(vertices.map(\.y)),
            median(vertices.map(\.z))
        )
    }
}

struct FaceBoundsNormalization: Sendable {
    let minimum: SIMD3<Float>
    let extent: SIMD3<Float>

    nonisolated init(vertices: [SIMD3<Float>]) {
        var lower = vertices.first ?? .zero
        var upper = vertices.first ?? .zero
        for vertex in vertices.dropFirst() {
            lower = simd_min(lower, vertex)
            upper = simd_max(upper, vertex)
        }
        minimum = lower
        let rawExtent = upper - lower
        extent = SIMD3<Float>(
            max(rawExtent.x, Float.ulpOfOne),
            max(rawExtent.y, Float.ulpOfOne),
            max(rawExtent.z, Float.ulpOfOne)
        )
    }

    nonisolated func normalize(_ point: SIMD3<Float>) -> SIMD3<Float> {
        (point - minimum) / extent
    }
}
