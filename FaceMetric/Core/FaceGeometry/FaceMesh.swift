import Foundation
import simd

public struct FaceMeshPoint: Codable, Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float

    public nonisolated init(_ value: SIMD3<Float>) {
        x = value.x
        y = value.y
        z = value.z
    }

    public nonisolated var simdValue: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

public struct FaceMesh: Codable, Equatable, Sendable {
    public let vertices: [FaceMeshPoint]
    public let triangleIndices: [Int16]

    public nonisolated init(vertices: [SIMD3<Float>], triangleIndices: [Int16]) {
        self.vertices = vertices.map(FaceMeshPoint.init)
        self.triangleIndices = triangleIndices
    }

    public nonisolated var simdVertices: [SIMD3<Float>] {
        vertices.map(\.simdValue)
    }
}

public enum FaceMeshAggregator {
    public enum AggregationError: Error, Equatable {
        case noFrames
        case incompatibleTopology
    }

    /// Produces a representative face by taking the coordinate-wise median at
    /// every topology-matched vertex. Median aggregation limits the influence
    /// of transient per-frame outliers without deformable registration.
    public nonisolated static func coordinateMedian(of meshes: [FaceMesh]) throws -> FaceMesh {
        guard let first = meshes.first else {
            throw AggregationError.noFrames
        }

        guard meshes.allSatisfy({
            $0.vertices.count == first.vertices.count
                && $0.triangleIndices == first.triangleIndices
        }) else {
            throw AggregationError.incompatibleTopology
        }

        var aggregated = [SIMD3<Float>]()
        aggregated.reserveCapacity(first.vertices.count)

        for vertexIndex in first.vertices.indices {
            var xValues = [Float]()
            var yValues = [Float]()
            var zValues = [Float]()
            xValues.reserveCapacity(meshes.count)
            yValues.reserveCapacity(meshes.count)
            zValues.reserveCapacity(meshes.count)

            for mesh in meshes {
                let vertex = mesh.vertices[vertexIndex]
                xValues.append(vertex.x)
                yValues.append(vertex.y)
                zValues.append(vertex.z)
            }

            aggregated.append(
                SIMD3(
                    median(xValues),
                    median(yValues),
                    median(zValues)
                )
            )
        }

        return FaceMesh(
            vertices: aggregated,
            triangleIndices: first.triangleIndices
        )
    }

    public nonisolated static func meanSquaredVertexDistance(
        from lhs: FaceMesh,
        to rhs: FaceMesh
    ) -> Float? {
        guard lhs.vertices.count == rhs.vertices.count,
              !lhs.vertices.isEmpty else {
            return nil
        }

        let squaredDistanceSum = zip(lhs.simdVertices, rhs.simdVertices)
            .reduce(Float.zero) { partialResult, pair in
                let delta = pair.0 - pair.1
                return partialResult + simd_length_squared(delta)
            }

        return squaredDistanceSum / Float(lhs.vertices.count)
    }

    nonisolated private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }
}
