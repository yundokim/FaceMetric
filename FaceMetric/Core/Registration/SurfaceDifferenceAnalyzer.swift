import Foundation
import simd

public struct SurfaceResidualMetrics: Codable, Equatable, Sendable {
    public let meanSignedResidual: Float
    public let meanAbsoluteResidual: Float
    public let rmsResidual: Float
    public let p95AbsoluteResidual: Float
    public let maximumAbsoluteResidual: Float
    public let sampleCount: Int

    nonisolated public static let empty = SurfaceResidualMetrics(
        meanSignedResidual: 0,
        meanAbsoluteResidual: 0,
        rmsResidual: 0,
        p95AbsoluteResidual: 0,
        maximumAbsoluteResidual: 0,
        sampleCount: 0
    )
}

public struct SurfaceDistanceSample: Codable, Equatable, Sendable {
    public let vertexIndex: Int
    public let signedDistanceMeters: Float
    public let closestBaselinePoint: FaceMeshPoint
}

public struct SurfaceDifferenceResult: Codable, Equatable, Sendable {
    public let samples: [SurfaceDistanceSample]
    public let metrics: SurfaceResidualMetrics
}

public enum SurfaceDifferenceError: Error, Equatable {
    case noUsableTriangles
}

public struct SurfaceDifferenceAnalyzer: Sendable {
    nonisolated public init() {}

    /// Signed point-to-triangle distance. Sign is positive in the direction of
    /// the oriented baseline triangle normal and negative in the opposite direction.
    nonisolated public func analyze(
        baseline: FaceMesh,
        alignedFollowup: FaceMesh,
        sampleIndices: [Int],
        baselineRegionIndices: Set<Int>? = nil
    ) throws -> SurfaceDifferenceResult {
        let baselineVertices = baseline.simdVertices
        let followupVertices = alignedFollowup.simdVertices
        let rawIndices = baseline.triangleIndices.map { Int($0) }

        var triangles: [Triangle] = []
        var verticesCoveredByTriangles = Set<Int>()
        triangles.reserveCapacity(rawIndices.count / 3)
        for offset in stride(from: 0, to: rawIndices.count - 2, by: 3) {
            let indices = (
                rawIndices[offset],
                rawIndices[offset + 1],
                rawIndices[offset + 2]
            )
            guard indices.0 < baselineVertices.count,
                  indices.1 < baselineVertices.count,
                  indices.2 < baselineVertices.count else {
                continue
            }
            if let baselineRegionIndices,
               !(baselineRegionIndices.contains(indices.0)
                    && baselineRegionIndices.contains(indices.1)
                    && baselineRegionIndices.contains(indices.2)) {
                continue
            }
            let triangle = Triangle(
                a: baselineVertices[indices.0],
                b: baselineVertices[indices.1],
                c: baselineVertices[indices.2]
            )
            if simd_length_squared(triangle.normal) > Float.ulpOfOne {
                triangles.append(triangle)
                verticesCoveredByTriangles.formUnion([
                    indices.0,
                    indices.1,
                    indices.2
                ])
            }
        }
        guard !triangles.isEmpty else {
            throw SurfaceDifferenceError.noUsableTriangles
        }

        var samples: [SurfaceDistanceSample] = []
        samples.reserveCapacity(sampleIndices.count)
        for index in sampleIndices
        where index < followupVertices.count
            && (baselineRegionIndices == nil || verticesCoveredByTriangles.contains(index)) {
            let point = followupVertices[index]
            var nearestPoint = SIMD3<Float>.zero
            var nearestNormal = SIMD3<Float>.zero
            var nearestSquared = Float.greatestFiniteMagnitude

            for triangle in triangles {
                let candidate = closestPoint(to: point, on: triangle)
                let squared = simd_length_squared(point - candidate)
                if squared < nearestSquared {
                    nearestSquared = squared
                    nearestPoint = candidate
                    nearestNormal = triangle.normal
                }
            }

            let unsigned = sqrt(nearestSquared)
            let direction = simd_dot(point - nearestPoint, nearestNormal)
            let signed = direction < 0 ? -unsigned : unsigned
            samples.append(
                SurfaceDistanceSample(
                    vertexIndex: index,
                    signedDistanceMeters: signed,
                    closestBaselinePoint: FaceMeshPoint(nearestPoint)
                )
            )
        }

        return SurfaceDifferenceResult(
            samples: samples,
            metrics: metrics(for: samples.map(\.signedDistanceMeters))
        )
    }

    nonisolated public func metrics(for values: [Float]) -> SurfaceResidualMetrics {
        guard !values.isEmpty else { return .empty }
        let absolute = values.map(abs).sorted()
        let meanSigned = values.reduce(0, +) / Float(values.count)
        let meanAbsolute = absolute.reduce(0, +) / Float(values.count)
        let rms = sqrt(
            values.reduce(Float.zero) { $0 + $1 * $1 } / Float(values.count)
        )
        let p95Index = min(
            absolute.count - 1,
            Int(ceil(0.95 * Float(absolute.count))) - 1
        )
        return SurfaceResidualMetrics(
            meanSignedResidual: meanSigned,
            meanAbsoluteResidual: meanAbsolute,
            rmsResidual: rms,
            p95AbsoluteResidual: absolute[max(0, p95Index)],
            maximumAbsoluteResidual: absolute.last ?? 0,
            sampleCount: values.count
        )
    }

    nonisolated private func closestPoint(
        to point: SIMD3<Float>,
        on triangle: Triangle
    ) -> SIMD3<Float> {
        let ab = triangle.b - triangle.a
        let ac = triangle.c - triangle.a
        let ap = point - triangle.a
        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return triangle.a }

        let bp = point - triangle.b
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return triangle.b }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            let v = d1 / (d1 - d3)
            return triangle.a + v * ab
        }

        let cp = point - triangle.c
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return triangle.c }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            let w = d2 / (d2 - d6)
            return triangle.a + w * ac
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return triangle.b + w * (triangle.c - triangle.b)
        }

        let denominator = 1 / (va + vb + vc)
        let v = vb * denominator
        let w = vc * denominator
        return triangle.a + ab * v + ac * w
    }

    private struct Triangle {
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        let normal: SIMD3<Float>

        nonisolated init(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) {
            self.a = a
            self.b = b
            self.c = c
            normal = simd_normalize(simd_cross(b - a, c - a))
        }
    }
}
