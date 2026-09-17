import Foundation
import simd

struct FaceGeneratedROIs: Sendable {
    let cheekLeft: [Int]
    let cheekRight: [Int]
    let stableUpperMidFace: [Int]
    let bilateralFace: [Int]
}

enum FaceAutomaticROIBuilder {
    static let definitionVersion = "landmark-bounded-v1"

    /// Generates reproducible surface patches from calibrated anatomical landmarks.
    /// The fractional insets below are operational boundary guards, not aesthetic
    /// reference values. All coordinates are expressed in the subject's anatomical
    /// transverse/vertical frame and normalized by bizygomatic width.
    static func build(
        mesh: FaceMesh,
        landmarks: [FaceAnatomicalLandmark: SIMD3<Float>]
    ) throws -> FaceGeneratedROIs {
        func point(_ id: FaceAnatomicalLandmark) throws -> SIMD3<Float> {
            guard let value = landmarks[id] else {
                throw FaceGeometryAnalysisError.incompleteCalibration([id.rawValue])
            }
            return value
        }

        let zyL = try point(.zygionLeft)
        let zyR = try point(.zygionRight)
        let menton = try point(.menton)
        let forehead = try point(.trichionOrForeheadBoundary)
        let transverse = safeUnit(zyR - zyL, fallback: SIMD3(1, 0, 0))
        let verticalCandidate = forehead - menton
        let vertical = safeUnit(
            verticalCandidate - simd_dot(verticalCandidate, transverse) * transverse,
            fallback: SIMD3(0, 1, 0)
        )
        let origin = (zyL + zyR) / 2
        let width = max(simd_distance(zyL, zyR), 0.001)

        func coordinates(_ point: SIMD3<Float>) -> SIMD2<Float> {
            let delta = point - origin
            return SIMD2(simd_dot(delta, transverse) / width, simd_dot(delta, vertical) / width)
        }

        let projected = Dictionary(uniqueKeysWithValues: try FaceAnatomicalLandmark.allCases.map {
            ($0, coordinates(try point($0)))
        })
        func coordinate(_ id: FaceAnatomicalLandmark) -> SIMD2<Float> { projected[id]! }

        let leftCheek = boundedPatch(
            vertices: mesh.simdVertices,
            coordinates: coordinates,
            horizontal: orderedRange(coordinate(.zygionLeft).x, coordinate(.alareLeft).x),
            vertical: orderedRange(coordinate(.mouthLeft).y, coordinate(.lowerEyelidLeft).y),
            insetFraction: 0.12
        )
        let rightCheek = boundedPatch(
            vertices: mesh.simdVertices,
            coordinates: coordinates,
            horizontal: orderedRange(coordinate(.alareRight).x, coordinate(.zygionRight).x),
            vertical: orderedRange(coordinate(.mouthRight).y, coordinate(.lowerEyelidRight).y),
            insetFraction: 0.12
        )

        let faceHorizontal = orderedRange(coordinate(.zygionLeft).x, coordinate(.zygionRight).x)
        let stableVertical = orderedRange(coordinate(.subnasale).y, coordinate(.glabella).y)
        let stableHorizontal = orderedRange(coordinate(.exocanthionLeft).x, coordinate(.exocanthionRight).x)
        let leftEyeBox = box(
            x1: coordinate(.exocanthionLeft).x,
            x2: coordinate(.endocanthionLeft).x,
            y1: coordinate(.lowerEyelidLeft).y,
            y2: coordinate(.upperEyelidLeft).y,
            padding: 0.018
        )
        let rightEyeBox = box(
            x1: coordinate(.endocanthionRight).x,
            x2: coordinate(.exocanthionRight).x,
            y1: coordinate(.lowerEyelidRight).y,
            y2: coordinate(.upperEyelidRight).y,
            padding: 0.018
        )
        let nasalOpeningBox = box(
            x1: coordinate(.alareLeft).x,
            x2: coordinate(.alareRight).x,
            y1: coordinate(.subnasale).y,
            y2: coordinate(.pronasale).y,
            padding: 0.012
        )

        // Stable reference ROI: upper/mid-face surface bounded by ExL/ExR and
        // G/Sn, excluding eyelid apertures and the mobile/inferior nasal opening.
        let stableCandidates = mesh.simdVertices.indices.filter { index in
            let value = coordinates(mesh.simdVertices[index])
            return stableHorizontal.contains(value.x)
                && stableVertical.contains(value.y)
                && !leftEyeBox.contains(value)
                && !rightEyeBox.contains(value)
                && !nasalOpeningBox.contains(value)
        }
        // Sparse synthetic/debug meshes may contain no vertex strictly inside the
        // bounded patch. A small nearest-surface patch keeps the definition usable;
        // production ARFaceGeometry normally takes the bounded branch above.
        let stableFallbackCenter = (try point(.glabella) + point(.nasion)) / 2
        let stable = stableCandidates.isEmpty
            ? nearestIndices(
                in: mesh.simdVertices,
                to: stableFallbackCenter,
                count: min(12, mesh.simdVertices.count)
            )
            : stableCandidates

        let fullVertical = inset(
            orderedRange(coordinate(.menton).y, coordinate(.trichionOrForeheadBoundary).y),
            fraction: 0.035
        )
        let fullHorizontal = inset(faceHorizontal, fraction: 0.035)
        let mouthBox = box(
            x1: coordinate(.mouthLeft).x,
            x2: coordinate(.mouthRight).x,
            y1: coordinate(.labialeInferius).y,
            y2: coordinate(.labialeSuperius).y,
            padding: 0.018
        )
        let midlineGap = max(
            abs(coordinate(.alareLeft).x),
            abs(coordinate(.alareRight).x)
        ) * 0.12

        // Bilateral symmetry ROI: paired facial surface away from the midline,
        // mesh rim, eyelids, mouth aperture and nostril opening.
        let bilateral = mesh.simdVertices.indices.filter { index in
            let value = coordinates(mesh.simdVertices[index])
            return fullHorizontal.contains(value.x)
                && fullVertical.contains(value.y)
                && abs(value.x) > midlineGap
                && !leftEyeBox.contains(value)
                && !rightEyeBox.contains(value)
                && !mouthBox.contains(value)
                && !nasalOpeningBox.contains(value)
        }

        return FaceGeneratedROIs(
            cheekLeft: leftCheek,
            cheekRight: rightCheek,
            stableUpperMidFace: stable,
            bilateralFace: bilateral
        )
    }

    private static func boundedPatch(
        vertices: [SIMD3<Float>],
        coordinates: (SIMD3<Float>) -> SIMD2<Float>,
        horizontal: ClosedRange<Float>,
        vertical: ClosedRange<Float>,
        insetFraction: Float
    ) -> [Int] {
        let x = inset(orderedRange(horizontal.lowerBound, horizontal.upperBound), fraction: insetFraction)
        let y = inset(orderedRange(vertical.lowerBound, vertical.upperBound), fraction: insetFraction)
        return vertices.indices.filter {
            let value = coordinates(vertices[$0])
            return x.contains(value.x) && y.contains(value.y)
        }
    }

    private static func orderedRange(_ lhs: Float, _ rhs: Float) -> ClosedRange<Float> {
        min(lhs, rhs)...max(lhs, rhs)
    }

    private static func inset(_ range: ClosedRange<Float>, fraction: Float) -> ClosedRange<Float> {
        let amount = (range.upperBound - range.lowerBound) * fraction
        return (range.lowerBound + amount)...(range.upperBound - amount)
    }

    private static func box(
        x1: Float,
        x2: Float,
        y1: Float,
        y2: Float,
        padding: Float
    ) -> NormalizedBox {
        let x = orderedRange(x1, x2)
        let y = orderedRange(y1, y2)
        return NormalizedBox(
            x: (x.lowerBound - padding)...(x.upperBound + padding),
            y: (y.lowerBound - padding)...(y.upperBound + padding)
        )
    }

    private static func safeUnit(_ vector: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        simd_length_squared(vector) > .ulpOfOne ? simd_normalize(vector) : fallback
    }

    private static func nearestIndices(in vertices: [SIMD3<Float>], to target: SIMD3<Float>, count: Int) -> [Int] {
        vertices.indices
            .sorted { simd_length_squared(vertices[$0] - target) < simd_length_squared(vertices[$1] - target) }
            .prefix(count)
            .map { $0 }
    }
}

private struct NormalizedBox {
    let x: ClosedRange<Float>
    let y: ClosedRange<Float>

    func contains(_ point: SIMD2<Float>) -> Bool {
        x.contains(point.x) && y.contains(point.y)
    }
}
