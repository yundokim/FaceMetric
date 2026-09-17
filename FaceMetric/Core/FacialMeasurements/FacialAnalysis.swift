import Foundation
import simd

enum FacialScoreCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    // Retained only so previously saved MVP records remain decodable.
    case balance = "Balance"
    case proportion = "Proportion"
    case symmetry = "Symmetry"
    case profile = "Profile"

    var id: String { rawValue }

    static let scoredCases: [FacialScoreCategory] = [
        .symmetry,
        .proportion,
        .profile
    ]
}

enum FacialMeasurementUnit: String, Codable, Sendable {
    case millimeters = "mm"
    case ratio
    case degrees = "°"
}

struct FacialMeasurementReference: Codable, Equatable, Sendable {
    let summary: String
    let citation: String
    /// A point range represents a mean/center. A non-zero range is a full-score interval.
    let targetRange: ClosedRange<Double>
    /// Gaussian scale outside the reference center or interval.
    let falloff: Double
}

struct FacialLandmark: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let position: FaceMeshPoint
}

enum FacialOverlayKind: String, Codable, Sendable {
    case line
    case angle
}

struct FacialOverlay: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: FacialOverlayKind
    let landmarkIDs: [String]
}

struct FacialMeasurement: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: FacialScoreCategory
    /// Raw metric value is persisted independently from its score.
    let value: Double
    let unit: FacialMeasurementUnit
    let score: Double
    let reference: FacialMeasurementReference
    let landmarkIDs: [String]

    var formattedValue: String {
        switch unit {
        case .millimeters:
            return value.formatted(.number.precision(.fractionLength(2))) + " mm"
        case .ratio:
            return value.formatted(.number.precision(.fractionLength(3)))
        case .degrees:
            return value.formatted(.number.precision(.fractionLength(1))) + "°"
        }
    }
}

struct FacialCategoryScore: Codable, Equatable, Identifiable, Sendable {
    let category: FacialScoreCategory
    let score: Double

    var id: FacialScoreCategory { category }
}

struct FacialAnalysis: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let scanID: UUID
    let createdAt: Date
    let measurements: [FacialMeasurement]
    let categoryScores: [FacialCategoryScore]
    let overallScore: Double
    let landmarks: [FacialLandmark]
    let overlays: [FacialOverlay]
    let methodologyNote: String

    func score(for category: FacialScoreCategory) -> Double {
        categoryScores.first { $0.category == category }?.score ?? 0
    }
}

enum FacialAnalysisError: Error, LocalizedError, Equatable {
    case insufficientMesh
    case symmetryRegistrationFailed

    var errorDescription: String? {
        switch self {
        case .insufficientMesh:
            return "The face mesh does not contain enough surface data for analysis."
        case .symmetryRegistrationFailed:
            return "The mirrored face could not be rigidly registered."
        }
    }
}

struct FacialAnalysisEngine: Sendable {
    // Taylor et al., J Craniofac Surg. 2014, DOI 10.1097/SCS.0b013e3182a2e99d,
    // PMID 24406564: healthy n=100, mirror-registered whole-face RMSD 0.80 ± 0.24 mm.
    // Kornreich et al., Cleft Palate Craniofac J. 2016, DOI 10.1597/13-353,
    // PMID 25489769: adults n=350, mirror-registered whole-face RMS 0.6253 ± 0.16 mm.
    private let surfaceRMSCenterMillimeters = 0.75
    private let surfaceRMSScaleMillimeters = 0.21
    private let localAsymmetryScaleMillimeters = 1.04

    nonisolated func analyze(scan: FaceScan) throws -> FacialAnalysis {
        let vertices = scan.mesh.simdVertices
        guard vertices.count >= 100 else {
            throw FacialAnalysisError.insufficientMesh
        }

        let bounds = Bounds(vertices: vertices)
        var landmarks = extractLandmarks(vertices: vertices, bounds: bounds)
        var points = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.id, $0.position.simdValue) })

        func point(_ id: String) -> SIMD3<Float> {
            points[id] ?? .zero
        }

        let sagittalPlane = SagittalPlane(
            leftZygion: point("leftZygion"),
            rightZygion: point("rightZygion")
        )
        let goodeAlarPoint = projectedPoint(
            point("pronasale"),
            ontoLineFrom: point("nasion"),
            through: point("alarCrease")
        )
        landmarks.append(
            FacialLandmark(
                id: "goodeAlarPoint",
                name: "Goode alar point",
                position: FaceMeshPoint(goodeAlarPoint)
            )
        )
        points["goodeAlarPoint"] = goodeAlarPoint

        let mirrorResult = try mirrorRegistration(
            mesh: scan.mesh,
            plane: sagittalPlane
        )

        // 1. Whole-face RMSD after mirror creation and rigid ICP registration.
        let symmetryRMS = mirrorResult.rmsMeters * 1_000

        // 2–3. Perpendicular Prn and Pg' distances from the zy-zy-defined
        // midsagittal plane.
        let noseDeviation = sagittalPlane.distance(to: point("pronasale")) * 1_000
        let chinDeviation = sagittalPlane.distance(to: point("pogonion")) * 1_000

        // 4. Mean absolute nearest-surface distance across paired cheek ROIs,
        // rather than a single cheek vertex.
        let cheekIndices = cheekROIIndices(vertices: vertices, bounds: bounds)
        let cheekDepthDifference = meanAbsoluteSurfaceDistance(
            sourceIndices: cheekIndices,
            sourceVertices: vertices,
            targetVertices: mirrorResult.alignedMirroredVertices
        ) * 1_000

        // 5. Soft-tissue jaw lengths use corresponding Go'–Me' segments.
        // D = |L-R| / ((L+R)/2).
        let leftJawLength = distance(point("leftGonion"), point("menton"))
        let rightJawLength = distance(point("rightGonion"), point("menton"))
        let meanJawLength = max((leftJawLength + rightJawLength) / 2, 0.001)
        let jawAsymmetry = abs(leftJawLength - rightJawLength) / meanJawLength

        // 6. Morphological nasal width (al-al) / bizygomatic width (zy-zy).
        let nasalWidth = distance(point("leftAlare"), point("rightAlare"))
        let facialWidth = distance(point("leftZygion"), point("rightZygion"))
        let nasalWidthRatio = nasalWidth / max(facialWidth, 0.001)

        // 7. Half-widths are perpendicular zy distances to the same midsagittal
        // plane at the bizygomatic transverse level.
        let leftHalfWidth = sagittalPlane.distance(to: point("leftZygion"))
        let rightHalfWidth = sagittalPlane.distance(to: point("rightZygion"))
        let meanHalfWidth = max((leftHalfWidth + rightHalfWidth) / 2, 0.001)
        let halfWidthRatio = leftHalfWidth / max(rightHalfWidth, 0.001)

        // 8. Legan–Burstone vertical height ratio:
        // G-Sn / Sn-Me', measured along the ARKit face-local vertical axis.
        let upperMiddleHeight = abs(Double(point("glabella").y - point("subnasale").y))
        let lowerHeight = abs(Double(point("subnasale").y - point("menton").y))
        let verticalBalance = upperMiddleHeight / max(lowerHeight, 0.001)

        // 9. Goode method: ac-Prn / N-Prn. ac is the perpendicular projection
        // of Prn onto the N-to-alar-crease facial line.
        let nasalProjection = distance(point("goodeAlarPoint"), point("pronasale"))
        let nasalLength = distance(point("nasion"), point("pronasale"))
        let nasalProjectionRatio = nasalProjection / max(nasalLength, 0.001)

        // 10. Facial convexity uses the internal G-Sn-Pg' angle only.
        let convexityAngle = angleDegrees(
            point("glabella"),
            vertex: point("subnasale"),
            point("pogonion")
        )

        let surfaceReference = FacialMeasurementReference(
            summary: "Mirror-registered healthy-face RMSD centers near 0.7–0.8 mm; perfect 0 mm symmetry is not treated as the population norm.",
            citation: "Taylor et al. PMID 24406564, DOI 10.1097/SCS.0b013e3182a2e99d; Kornreich et al. PMID 25489769, DOI 10.1597/13-353",
            targetRange: surfaceRMSCenterMillimeters...surfaceRMSCenterMillimeters,
            falloff: surfaceRMSScaleMillimeters
        )
        let midlineReference = FacialMeasurementReference(
            summary: "0 mm is geometric symmetry. Gaussian sensitivity uses Taylor's healthy whole-face mean + 1 SD (1.04 mm) as the local 3D scale.",
            citation: "Taylor et al. PMID 24406564, DOI 10.1097/SCS.0b013e3182a2e99d",
            targetRange: 0...0,
            falloff: localAsymmetryScaleMillimeters
        )
        let jawReference = FacialMeasurementReference(
            summary: "D=0 is equal left/right Go'–Me' length. The Gaussian scale converts the 1.04 mm 3D reference scale to relative jaw length.",
            citation: "Go' and Me' are standard soft-tissue anthropometric landmarks; asymmetry scale from Taylor et al. PMID 24406564",
            targetRange: 0...0,
            falloff: localAsymmetryScaleMillimeters / (meanJawLength * 1_000)
        )
        let nasalWidthReference = FacialMeasurementReference(
            summary: "The 0.20 center is the classical facial-fifths canon, not a population-independent biological optimum. The Gaussian scale reflects published cross-population departure from that canon.",
            citation: "Borman et al. PMID 10096619; Farkas et al. DOI 10.1177/229255039800600302",
            targetRange: 0.20...0.20,
            falloff: 0.061
        )
        let halfWidthReference = FacialMeasurementReference(
            summary: "1.0 is exact bilateral equality. The 1.04 mm normative 3D scale is normalized by the measured half-width.",
            citation: "Geometric bilateral definition; RMS scale from Taylor et al. PMID 24406564",
            targetRange: 1...1,
            falloff: localAsymmetryScaleMillimeters / (meanHalfWidth * 1_000)
        )
        let verticalReference = FacialMeasurementReference(
            summary: "Legan–Burstone G-Sn/Sn-Me' reference is approximately 1:1; adult samples report SD near 0.09–0.10.",
            citation: "AlBarakati & Bindayel, Saudi Med J. 2011; Legan–Burstone landmarks G, Sn, Me'",
            targetRange: 1...1,
            falloff: 0.095
        )
        let projectionReference = FacialMeasurementReference(
            summary: "Goode ac-Prn/N-Prn reference interval is 0.55–0.60. The interval width sets the continuous outside-range scale.",
            citation: "Jang et al., Arch Plast Surg. 2015, PMCID PMC4656173; Goode method",
            targetRange: 0.55...0.60,
            falloff: 0.05
        )
        // Pooled from the exact same G-Sn-Pg definition in 166 male and
        // 112 female southern Chinese 12-year-olds: male 168.10±5.10°,
        // female 169.85±4.83° -> pooled mean 168.8°, pooled SD 5.06°.
        let convexityReference = FacialMeasurementReference(
            summary: "G-Sn-Pg' internal angle reference: pooled 168.8° ± 5.1° from a population-specific southern Chinese sample.",
            citation: "Leung et al., Head Face Med. 2014; PMID 25540054, DOI 10.1186/s13005-014-0056-3",
            targetRange: 168.8...168.8,
            falloff: 5.06
        )

        let measurements = [
            measurement("surfaceSymmetry", "3D surface symmetry RMS", .symmetry, symmetryRMS, .millimeters, surfaceReference, ["leftZygion", "rightZygion"]),
            measurement("noseMidline", "Nose-tip midline deviation", .symmetry, noseDeviation, .millimeters, midlineReference, ["glabella", "pronasale", "menton"]),
            measurement("chinMidline", "Chin midline deviation", .symmetry, chinDeviation, .millimeters, midlineReference, ["glabella", "pogonion"]),
            measurement("cheekDepth", "Cheek ROI mean surface difference", .symmetry, cheekDepthDifference, .millimeters, midlineReference, ["leftCheek", "rightCheek"]),
            measurement("jawBalance", "Left/right jaw difference", .symmetry, jawAsymmetry, .ratio, jawReference, ["leftGonion", "menton", "rightGonion"]),
            measurement("halfWidthRatio", "Left/right facial half-width", .symmetry, halfWidthRatio, .ratio, halfWidthReference, ["leftZygion", "rightZygion"]),
            measurement("nasalWidth", "Nasal width / face width", .proportion, nasalWidthRatio, .ratio, nasalWidthReference, ["leftAlare", "rightAlare", "leftZygion", "rightZygion"]),
            measurement("verticalBalance", "Upper/lower face balance", .proportion, verticalBalance, .ratio, verticalReference, ["glabella", "subnasale", "menton"]),
            measurement("nasalProjection", "Goode nasal projection ratio", .profile, nasalProjectionRatio, .ratio, projectionReference, ["nasion", "goodeAlarPoint", "pronasale"]),
            measurement("facialConvexity", "G-Sn-Pg′ facial convexity", .profile, convexityAngle, .degrees, convexityReference, ["glabella", "subnasale", "pogonion"])
        ]

        let categoryScores = FacialScoreCategory.scoredCases.map { category in
            FacialCategoryScore(
                category: category,
                score: weightedCategoryScore(category, measurements: measurements)
            )
        }
        let overall = categoryScores.map(\.score).reduce(0, +) / Double(categoryScores.count)

        return FacialAnalysis(
            id: UUID(),
            scanID: scan.id,
            createdAt: Date(),
            measurements: measurements,
            categoryScores: categoryScores,
            overallScore: overall,
            landmarks: landmarks,
            overlays: [
                FacialOverlay(id: "midline", kind: .line, landmarkIDs: ["glabella", "nasion", "subnasale", "menton"]),
                FacialOverlay(id: "faceWidth", kind: .line, landmarkIDs: ["leftZygion", "rightZygion"]),
                FacialOverlay(id: "nasalWidth", kind: .line, landmarkIDs: ["leftAlare", "rightAlare"]),
                FacialOverlay(id: "cheeks", kind: .line, landmarkIDs: ["leftCheek", "rightCheek"]),
                FacialOverlay(id: "jaw", kind: .angle, landmarkIDs: ["leftGonion", "menton", "rightGonion"]),
                FacialOverlay(id: "goode", kind: .angle, landmarkIDs: ["nasion", "goodeAlarPoint", "pronasale"]),
                FacialOverlay(id: "profile", kind: .angle, landmarkIDs: ["glabella", "subnasale", "pogonion"])
            ],
            methodologyNote: "All ten raw metrics contribute to scoring. Scores use continuous Gaussian deviation from a cited mean/geometric center, or from the nearest boundary of a cited reference interval. Symmetry weighting gives the global registered surface metric 50% and shares the remaining 50% across five correlated local metrics."
        )
    }

    nonisolated private func measurement(
        _ id: String,
        _ name: String,
        _ category: FacialScoreCategory,
        _ value: Double,
        _ unit: FacialMeasurementUnit,
        _ reference: FacialMeasurementReference,
        _ landmarkIDs: [String]
    ) -> FacialMeasurement {
        FacialMeasurement(
            id: id,
            name: name,
            category: category,
            value: value,
            unit: unit,
            score: gaussianScore(value: value, reference: reference),
            reference: reference,
            landmarkIDs: landmarkIDs
        )
    }

    nonisolated private func gaussianScore(
        value: Double,
        reference: FacialMeasurementReference
    ) -> Double {
        let deviation: Double
        if reference.targetRange.contains(value) {
            deviation = 0
        } else {
            deviation = min(
                abs(value - reference.targetRange.lowerBound),
                abs(value - reference.targetRange.upperBound)
            )
        }
        let z = deviation / max(reference.falloff, 0.000_001)
        return 100 * exp(-0.5 * z * z)
    }

    nonisolated private func weightedCategoryScore(
        _ category: FacialScoreCategory,
        measurements: [FacialMeasurement]
    ) -> Double {
        // Global RMS captures distributed asymmetry and receives half the
        // Symmetry category. Five correlated local metrics share the other half.
        let weights: [String: Double]
        switch category {
        case .symmetry:
            weights = [
                "surfaceSymmetry": 0.50,
                "noseMidline": 0.10,
                "chinMidline": 0.10,
                "cheekDepth": 0.10,
                "jawBalance": 0.10,
                "halfWidthRatio": 0.10
            ]
        case .proportion:
            weights = ["nasalWidth": 0.50, "verticalBalance": 0.50]
        case .profile:
            weights = ["nasalProjection": 0.50, "facialConvexity": 0.50]
        case .balance:
            weights = [:]
        }

        let selected = measurements.filter { weights[$0.id] != nil }
        let weightSum = selected.reduce(0) { $0 + (weights[$1.id] ?? 0) }
        guard weightSum > 0 else { return 0 }
        return selected.reduce(0) {
            $0 + $1.score * (weights[$1.id] ?? 0)
        } / weightSum
    }

    nonisolated private func extractLandmarks(
        vertices: [SIMD3<Float>],
        bounds: Bounds
    ) -> [FacialLandmark] {
        let normalized = vertices.map { bounds.normalize($0) }

        func landmark(
            id: String,
            name: String,
            x: ClosedRange<Float>,
            y: ClosedRange<Float>,
            selection: Selection
        ) -> FacialLandmark {
            let candidates = vertices.indices.filter {
                x.contains(normalized[$0].x) && y.contains(normalized[$0].y)
            }
            let fallback = vertices.indices.min {
                simd_length_squared(normalized[$0] - SIMD3<Float>(0.5, y.lowerBound, 0.5))
                    < simd_length_squared(normalized[$1] - SIMD3<Float>(0.5, y.lowerBound, 0.5))
            } ?? 0
            return FacialLandmark(
                id: id,
                name: name,
                position: FaceMeshPoint(
                    selection.select(
                        from: candidates.isEmpty ? [fallback] : candidates,
                        vertices: vertices
                    )
                )
            )
        }

        let leftAlarCrease = landmark(
            id: "leftAlarCrease",
            name: "Left alar crease",
            x: 0.30...0.48,
            y: 0.34...0.48,
            selection: .minimumZ
        )
        let rightAlarCrease = landmark(
            id: "rightAlarCrease",
            name: "Right alar crease",
            x: 0.52...0.70,
            y: 0.34...0.48,
            selection: .minimumZ
        )
        let creaseMidpoint = (
            leftAlarCrease.position.simdValue + rightAlarCrease.position.simdValue
        ) / 2

        return [
            landmark(id: "glabella", name: "Glabella (G)", x: 0.42...0.58, y: 0.73...0.90, selection: .maximumZ),
            landmark(id: "nasion", name: "Soft-tissue nasion (N)", x: 0.44...0.56, y: 0.58...0.74, selection: .minimumZ),
            landmark(id: "pronasale", name: "Pronasale (Prn)", x: 0.43...0.57, y: 0.43...0.64, selection: .maximumZ),
            landmark(id: "subnasale", name: "Subnasale (Sn)", x: 0.44...0.56, y: 0.32...0.48, selection: .minimumY),
            landmark(id: "pogonion", name: "Soft-tissue pogonion (Pg′)", x: 0.40...0.60, y: 0.08...0.25, selection: .maximumZ),
            landmark(id: "menton", name: "Soft-tissue menton (Me′)", x: 0.38...0.62, y: 0.00...0.18, selection: .minimumY),
            landmark(id: "leftZygion", name: "Left zygion (zy)", x: 0.00...0.18, y: 0.42...0.66, selection: .minimumX),
            landmark(id: "rightZygion", name: "Right zygion (zy)", x: 0.82...1.00, y: 0.42...0.66, selection: .maximumX),
            landmark(id: "leftAlare", name: "Left alare (al)", x: 0.28...0.48, y: 0.36...0.52, selection: .minimumX),
            landmark(id: "rightAlare", name: "Right alare (al)", x: 0.52...0.72, y: 0.36...0.52, selection: .maximumX),
            landmark(id: "leftCheek", name: "Left cheek ROI center", x: 0.12...0.38, y: 0.34...0.60, selection: .centroid),
            landmark(id: "rightCheek", name: "Right cheek ROI center", x: 0.62...0.88, y: 0.34...0.60, selection: .centroid),
            landmark(id: "leftGonion", name: "Left soft-tissue gonion (Go′)", x: 0.08...0.34, y: 0.12...0.34, selection: .minimumX),
            landmark(id: "rightGonion", name: "Right soft-tissue gonion (Go′)", x: 0.66...0.92, y: 0.12...0.34, selection: .maximumX),
            leftAlarCrease,
            rightAlarCrease,
            FacialLandmark(id: "alarCrease", name: "Mid-sagittal alar crease reference", position: FaceMeshPoint(creaseMidpoint))
        ]
    }

    nonisolated private func mirrorRegistration(
        mesh: FaceMesh,
        plane: SagittalPlane
    ) throws -> MirrorRegistrationResult {
        let original = mesh.simdVertices
        let mirrored = original.map(plane.mirror)
        let strideValue = max(1, original.count / 400)
        let sampleIndices = Array(stride(from: 0, to: original.count, by: strideValue))
        let target = sampleIndices.map { original[$0] }
        let source = sampleIndices.map { mirrored[$0] }
        var transform = RigidTransform.identity
        var previousRMS = Float.greatestFiniteMagnitude

        for _ in 0..<20 {
            let aligned = source.map(transform.applying(to:))
            var matchedSource = [SIMD3<Float>]()
            var matchedTarget = [SIMD3<Float>]()
            matchedSource.reserveCapacity(aligned.count)
            matchedTarget.reserveCapacity(aligned.count)

            for point in aligned {
                if let nearest = nearestPoint(to: point, candidates: target) {
                    matchedSource.append(point)
                    matchedTarget.append(nearest)
                }
            }
            guard matchedSource.count >= 20 else {
                throw FacialAnalysisError.symmetryRegistrationFailed
            }
            let incremental = try RigidPointSetSolver.fit(
                source: matchedSource,
                target: matchedTarget,
                weights: Array(repeating: 1, count: matchedSource.count)
            )
            transform = incremental.concatenating(transform)
            let rms = rootMeanSquare(
                matchedSource.map(incremental.applying(to:)),
                matchedTarget
            )
            if abs(previousRMS - rms) < 0.000_001 {
                break
            }
            previousRMS = rms
        }

        let alignedFull = mirrored.map(transform.applying(to:))
        let alignedSample = sampleIndices.map { alignedFull[$0] }
        let residuals = alignedSample.map {
            nearestDistance(to: $0, candidates: target)
        }
        let rms = sqrt(
            residuals.reduce(0) { $0 + Double($1 * $1) }
                / Double(max(residuals.count, 1))
        )
        return MirrorRegistrationResult(
            alignedMirroredVertices: alignedFull,
            rmsMeters: rms
        )
    }

    nonisolated private func cheekROIIndices(
        vertices: [SIMD3<Float>],
        bounds: Bounds
    ) -> [Int] {
        vertices.indices.filter {
            let point = bounds.normalize(vertices[$0])
            let isLeft = (0.12...0.38).contains(point.x)
            let isRight = (0.62...0.88).contains(point.x)
            return (isLeft || isRight) && (0.34...0.60).contains(point.y)
        }
    }

    nonisolated private func meanAbsoluteSurfaceDistance(
        sourceIndices: [Int],
        sourceVertices: [SIMD3<Float>],
        targetVertices: [SIMD3<Float>]
    ) -> Double {
        guard !sourceIndices.isEmpty else { return 0 }
        let targetIndices = sourceIndices.filter { $0 < targetVertices.count }
        let targets = targetIndices.map { targetVertices[$0] }
        guard !targets.isEmpty else { return 0 }
        return sourceIndices.reduce(0) {
            $0 + Double(nearestDistance(to: sourceVertices[$1], candidates: targets))
        } / Double(sourceIndices.count)
    }

    nonisolated private func nearestPoint(
        to point: SIMD3<Float>,
        candidates: [SIMD3<Float>]
    ) -> SIMD3<Float>? {
        candidates.min {
            simd_length_squared($0 - point) < simd_length_squared($1 - point)
        }
    }

    nonisolated private func nearestDistance(
        to point: SIMD3<Float>,
        candidates: [SIMD3<Float>]
    ) -> Float {
        candidates.reduce(Float.greatestFiniteMagnitude) {
            min($0, simd_distance(point, $1))
        }
    }

    nonisolated private func rootMeanSquare(
        _ source: [SIMD3<Float>],
        _ target: [SIMD3<Float>]
    ) -> Float {
        guard !source.isEmpty else { return 0 }
        return sqrt(
            zip(source, target).reduce(Float.zero) {
                $0 + simd_length_squared($1.0 - $1.1)
            } / Float(source.count)
        )
    }

    nonisolated private func projectedPoint(
        _ point: SIMD3<Float>,
        ontoLineFrom start: SIMD3<Float>,
        through end: SIMD3<Float>
    ) -> SIMD3<Float> {
        let direction = end - start
        let denominator = simd_length_squared(direction)
        guard denominator > .ulpOfOne else { return start }
        let t = simd_dot(point - start, direction) / denominator
        return start + t * direction
    }

    nonisolated private func distance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Double {
        Double(simd_distance(lhs, rhs))
    }

    nonisolated private func angleDegrees(
        _ first: SIMD3<Float>,
        vertex: SIMD3<Float>,
        _ third: SIMD3<Float>
    ) -> Double {
        let firstVector = first - vertex
        let thirdVector = third - vertex
        guard simd_length_squared(firstVector) > .ulpOfOne,
              simd_length_squared(thirdVector) > .ulpOfOne else {
            return 0
        }
        let cosine = max(
            -1,
            min(1, simd_dot(simd_normalize(firstVector), simd_normalize(thirdVector)))
        )
        return Double(acos(cosine) * 180 / .pi)
    }
}

private struct MirrorRegistrationResult: Sendable {
    let alignedMirroredVertices: [SIMD3<Float>]
    let rmsMeters: Double
}

private struct SagittalPlane: Sendable {
    let origin: SIMD3<Float>
    let normal: SIMD3<Float>

    nonisolated init(leftZygion: SIMD3<Float>, rightZygion: SIMD3<Float>) {
        origin = (leftZygion + rightZygion) / 2
        let transverse = rightZygion - leftZygion
        normal = simd_length_squared(transverse) > .ulpOfOne
            ? simd_normalize(transverse)
            : SIMD3<Float>(1, 0, 0)
    }

    nonisolated func distance(to point: SIMD3<Float>) -> Double {
        abs(Double(simd_dot(point - origin, normal)))
    }

    nonisolated func mirror(_ point: SIMD3<Float>) -> SIMD3<Float> {
        point - 2 * simd_dot(point - origin, normal) * normal
    }
}

private struct Bounds: Sendable {
    let minimum: SIMD3<Float>
    let extent: SIMD3<Float>

    nonisolated init(vertices: [SIMD3<Float>]) {
        var minimum = vertices[0]
        var maximum = vertices[0]
        for vertex in vertices.dropFirst() {
            minimum = simd_min(minimum, vertex)
            maximum = simd_max(maximum, vertex)
        }
        self.minimum = minimum
        extent = simd_max(maximum - minimum, SIMD3<Float>(repeating: .ulpOfOne))
    }

    nonisolated func normalize(_ point: SIMD3<Float>) -> SIMD3<Float> {
        (point - minimum) / extent
    }
}

private enum Selection: Sendable {
    case maximumZ
    case minimumZ
    case minimumX
    case maximumX
    case minimumY
    case centroid

    nonisolated func select(
        from indices: [Int],
        vertices: [SIMD3<Float>]
    ) -> SIMD3<Float> {
        switch self {
        case .maximumZ:
            return vertices[indices.max { vertices[$0].z < vertices[$1].z } ?? indices[0]]
        case .minimumZ:
            return vertices[indices.min { vertices[$0].z < vertices[$1].z } ?? indices[0]]
        case .minimumX:
            return vertices[indices.min { vertices[$0].x < vertices[$1].x } ?? indices[0]]
        case .maximumX:
            return vertices[indices.max { vertices[$0].x < vertices[$1].x } ?? indices[0]]
        case .minimumY:
            return vertices[indices.min { vertices[$0].y < vertices[$1].y } ?? indices[0]]
        case .centroid:
            return indices.reduce(SIMD3<Float>.zero) { $0 + vertices[$1] }
                / Float(indices.count)
        }
    }
}
