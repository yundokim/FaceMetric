import Foundation
import simd

enum FaceGeometryEvidenceLevel: String, Codable, Sendable {
    case numericReference = "A"
    case directionalAssociation = "B"
    case operationalMetric = "C"
}

enum FaceGeometryCategory: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case facial = "Facial"
    case symmetry = "Symmetry"
    case eyeAndMidface = "Eye & Midface"
    case lowerFace = "Lower Face"

    var id: String { rawValue }
}

enum FaceGeometryMetricID: String, Codable, CaseIterable, Sendable {
    case faceHeightWidth
    case upperThirdRatio
    case middleThirdRatio
    case lowerThirdRatio
    case leftEyeWidthRatio
    case rightEyeWidthRatio
    case leftEyeAspectRatio
    case rightEyeAspectRatio
    case intercanthalRatio
    case noseWidthRatio
    case upperLowerLipRatio
    case zygomaticAsymmetryMM
    case meshSymmetryMeanMM
    case meshSymmetryRMSMM
    case meshSymmetryNormalizedRMS
    case leftCheekFullness
    case rightCheekFullness
    case cheekFullness
    case noseProjection
    case upperLipProjection
    case chinProjection

    var category: FaceGeometryCategory {
        switch self {
        case .faceHeightWidth, .upperThirdRatio, .middleThirdRatio, .lowerThirdRatio,
             .noseWidthRatio:
            return .facial
        case .zygomaticAsymmetryMM, .meshSymmetryMeanMM, .meshSymmetryRMSMM,
             .meshSymmetryNormalizedRMS:
            return .symmetry
        case .leftEyeWidthRatio, .rightEyeWidthRatio, .leftEyeAspectRatio,
             .rightEyeAspectRatio, .intercanthalRatio, .leftCheekFullness,
             .rightCheekFullness, .cheekFullness, .noseProjection:
            return .eyeAndMidface
        case .upperLowerLipRatio, .upperLipProjection, .chinProjection:
            return .lowerFace
        }
    }
}

struct FaceGeometryMetric: Codable, Equatable, Identifiable, Sendable {
    let id: FaceGeometryMetricID
    let value: Float
    let unit: String
    let evidenceLevel: FaceGeometryEvidenceLevel
    let referenceText: String?
    let referenceSource: FaceGeometryReferenceSource?
    let referenceSampleCount: Int?
    let isReferenceProvisional: Bool?
    let interpretation: String
    let componentScore: Float?
    let landmarkNames: [FaceAnatomicalLandmark]
}

struct FaceGeometryMetrics: Codable, Equatable, Sendable {
    let values: [FaceGeometryMetric]
    let scanQuality: ScanQualityMetrics
    let averagedFrameCount: Int
    let landmarkConfigurationVersion: String
    let timestamp: Date

    func value(_ id: FaceGeometryMetricID) -> Float? {
        values.first { $0.id == id }?.value
    }
}

struct FaceGeometryScore: Codable, Equatable, Sendable {
    let overall: Float
    let facialProportion: Float
    let symmetry: Float
    let eyeAndMidface: Float
    let lowerFace: Float
    let components: [FaceGeometryMetric]
}

struct ExperimentalAttractivenessResult: Codable, Equatable, Sendable {
    let score: Float?
    let modelIdentifier: String
    let note: String
}

struct FaceGeometryAnalysisResult: Codable, Equatable, Sendable {
    let metrics: FaceGeometryMetrics
    let geometryScore: FaceGeometryScore
    let experimentalAttractiveness: ExperimentalAttractivenessResult
}

enum FaceGeometryAnalysisError: Error, LocalizedError, Equatable {
    case incompleteCalibration([String])
    case invalidVertexIndex(Int)
    case degenerateFaceWidth
    case emptyROI(String)

    var errorDescription: String? {
        switch self {
        case .incompleteCalibration(let names):
            return "Landmark calibration is incomplete: \(names.joined(separator: ", "))"
        case .invalidVertexIndex(let index):
            return "Landmark vertex index \(index) is outside this ARKit mesh topology."
        case .degenerateFaceWidth:
            return "Bizygomatic width could not be measured."
        case .emptyROI(let name):
            return "The automatically generated \(name) ROI is empty."
        }
    }
}

struct FaceGeometryAnalyzer: Sendable {
    static let foreheadExtensionFactor: Float = 1.20

    private let configuration: FaceLandmarkConfig
    private let referenceProfile: FaceGeometryReferenceProfile?

    init(
        configuration: FaceLandmarkConfig,
        referenceProfile: FaceGeometryReferenceProfile? = .maleV01
    ) {
        self.configuration = configuration
        self.referenceProfile = referenceProfile
    }

    init(configuration: FaceLandmarkConfig, referenceSex: FaceGeometryReferenceSex) {
        self.init(
            configuration: configuration,
            referenceProfile: FaceGeometryReferenceProfiles.profile(for: referenceSex)
        )
    }

    static func virtualTrichion(
        rawForeheadBoundary: SIMD3<Float>,
        glabella: SIMD3<Float>,
        verticalAxis: SIMD3<Float>
    ) -> SIMD3<Float> {
        let rawForeheadVector = rawForeheadBoundary - glabella
        let rawUpperThird = simd_length(rawForeheadVector)
        guard rawUpperThird > .ulpOfOne else { return glabella }

        let normalizedVertical = safeNormalize(verticalAxis, fallback: simd_normalize(rawForeheadVector))
        let superiorDirection = simd_dot(normalizedVertical, rawForeheadVector) >= 0
            ? normalizedVertical
            : -normalizedVertical
        return glabella + superiorDirection * rawUpperThird * foreheadExtensionFactor
    }

    func analyze(scan: FaceScan) throws -> FaceGeometryAnalysisResult {
        let required = FaceAnatomicalLandmark.requiredForMVP
        let missing = required.filter { configuration.vertexIndex(for: $0) == nil }
        guard missing.isEmpty else {
            throw FaceGeometryAnalysisError.incompleteCalibration(missing.map(\.rawValue))
        }

        let vertices = scan.mesh.simdVertices
        func point(_ landmark: FaceAnatomicalLandmark) throws -> SIMD3<Float> {
            let index = configuration.vertexIndex(for: landmark)!
            guard vertices.indices.contains(index) else {
                throw FaceGeometryAnalysisError.invalidVertexIndex(index)
            }
            return vertices[index]
        }

        let landmarkPoints = try Dictionary(uniqueKeysWithValues: required.map { landmark in
            (landmark, try point(landmark))
        })
        let generatedROIs = try FaceAutomaticROIBuilder.build(mesh: scan.mesh, landmarks: landmarkPoints)

        let zyL = try point(.zygionLeft)
        let zyR = try point(.zygionRight)
        let faceWidth = simd_distance(zyL, zyR)
        guard faceWidth > 0.001 else { throw FaceGeometryAnalysisError.degenerateFaceWidth }

        let rawForeheadBoundary = try point(.trichionOrForeheadBoundary)
        let glabella = try point(.glabella)
        let subnasale = try point(.subnasale)
        let menton = try point(.menton)
        let transverse = simd_normalize(zyR - zyL)
        let vertical = simd_normalize(glabella - menton)
        let virtualTrichion = Self.virtualTrichion(
            rawForeheadBoundary: rawForeheadBoundary,
            glabella: glabella,
            verticalAxis: vertical
        )
        let depth = safeNormalize(simd_cross(transverse, vertical), fallback: SIMD3<Float>(0, 0, 1))
        let referenceOrigin: SIMD3<Float>
        if generatedROIs.stableUpperMidFace.isEmpty, vertices.count < 100 {
            // Unit-test/debug meshes can be too sparse to contain the bounded surface patch.
            referenceOrigin = (glabella + (try point(.nasion))) / 2
        } else {
            referenceOrigin = try roiCentroid(indices: generatedROIs.stableUpperMidFace, name: .stableUpperMidFace, vertices: vertices)
        }
        let midOrigin = (zyL + zyR) / 2

        var metrics = [FaceGeometryMetric]()
        let ye = "Ye et al. (2026), Front Comput Neurosci, DOI: 10.3389/fncom.2026.1705259, Table 1"
        let gkantidis = "Gkantidis et al. (2026), Prog Orthod 27:13, DOI: 10.1186/s40510-026-00617-2"

        func addLiteratureReference(
            _ id: FaceGeometryMetricID,
            value: Float,
            reference: ClosedRange<Float>,
            referenceText: String,
            interpretation: String,
            landmarks: [FaceAnatomicalLandmark]
        ) {
            metrics.append(FaceGeometryMetric(
                id: id,
                value: value,
                unit: id == .zygomaticAsymmetryMM ? "mm" : "ratio",
                evidenceLevel: .numericReference,
                referenceText: "\(referenceText) — \(ye)",
                referenceSource: nil,
                referenceSampleCount: nil,
                isReferenceProvisional: nil,
                interpretation: interpretation,
                componentScore: GeometryScorer.continuousIntervalScore(value: value, interval: reference),
                landmarkNames: landmarks
            ))
        }

        func addProfiled(
            _ id: FaceGeometryMetricID,
            value: Float,
            interpretation: String,
            landmarks: [FaceAnatomicalLandmark]
        ) {
            let reference = referenceProfile?.reference(for: id)
            metrics.append(FaceGeometryMetric(
                id: id,
                value: value,
                unit: "ratio",
                evidenceLevel: .numericReference,
                referenceText: reference.map {
                    "\($0.provenance); target \($0.target), ideal interval \($0.idealInterval.lowerBound)...\($0.idealInterval.upperBound)"
                },
                referenceSource: reference?.source,
                referenceSampleCount: reference?.sampleCount,
                isReferenceProvisional: reference?.isProvisional,
                interpretation: interpretation,
                componentScore: reference.map {
                    GeometryScorer.continuousIntervalScore(value: value, interval: $0.idealInterval)
                },
                landmarkNames: landmarks
            ))
        }

        // A1 Facial height/width. The virtual trichion is an estimate created by extending the
        // raw ARKit forehead boundary measurement along the facial vertical axis; it is not observed anatomy.
        // Formula: |virtualTrichion−Me| / |ZyL−ZyR|.
        let faceHeightWidth = simd_distance(virtualTrichion, menton) / faceWidth
        addProfiled(.faceHeightWidth, value: faceHeightWidth, interpretation: "Overall height relative to bizygomatic width using a virtual trichion estimated from the ARKit forehead boundary.", landmarks: [.trichionOrForeheadBoundary, .menton, .zygionLeft, .zygionRight])

        // A2 Facial thirds. Landmarks: estimated virtualTrichion–G, G–Sn, Sn–Me.
        // Formula: each length / mean third. The 1.20 factor is measurement correction, not an aesthetic target.
        let thirds = [simd_distance(virtualTrichion, glabella), simd_distance(glabella, subnasale), simd_distance(subnasale, menton)]
        let meanThird = max(thirds.reduce(0, +) / 3, 0.001)
        addProfiled(.upperThirdRatio, value: thirds[0] / meanThird, interpretation: "Upper third relative to the mean facial third using a virtual trichion estimated from the ARKit forehead boundary.", landmarks: [.trichionOrForeheadBoundary, .glabella])
        addProfiled(.middleThirdRatio, value: thirds[1] / meanThird, interpretation: "Middle third relative to the mean facial third.", landmarks: [.glabella, .subnasale])
        addProfiled(.lowerThirdRatio, value: thirds[2] / meanThird, interpretation: "Lower third relative to the mean facial third.", landmarks: [.subnasale, .menton])

        // A3 Eye width ratio. Landmarks: En–Ex on each side. Formula: palpebral width / ZyL–ZyR.
        // Level A; Ye 2026 gives face-width/5 ±8% as an MA constraint.
        let leftEyeWidth = try distance(.endocanthionLeft, .exocanthionLeft, point)
        let rightEyeWidth = try distance(.endocanthionRight, .exocanthionRight, point)
        addProfiled(.leftEyeWidthRatio, value: leftEyeWidth / faceWidth, interpretation: "Left palpebral width normalized by face width.", landmarks: [.endocanthionLeft, .exocanthionLeft])
        addProfiled(.rightEyeWidthRatio, value: rightEyeWidth / faceWidth, interpretation: "Right palpebral width normalized by face width.", landmarks: [.endocanthionRight, .exocanthionRight])

        // A4 Eye fissure aspect ratio. Landmarks: En–Ex and upper/lower eyelid points.
        // Formula: palpebral width / eyelid aperture. Level A; Ye 2026 gives approximately 3:1.
        let leftAspect = leftEyeWidth / max(try distance(.upperEyelidLeft, .lowerEyelidLeft, point), 0.000_1)
        let rightAspect = rightEyeWidth / max(try distance(.upperEyelidRight, .lowerEyelidRight, point), 0.000_1)
        addProfiled(.leftEyeAspectRatio, value: leftAspect, interpretation: "Left eye width relative to aperture height.", landmarks: [.endocanthionLeft, .exocanthionLeft, .upperEyelidLeft, .lowerEyelidLeft])
        addProfiled(.rightEyeAspectRatio, value: rightAspect, interpretation: "Right eye width relative to aperture height.", landmarks: [.endocanthionRight, .exocanthionRight, .upperEyelidRight, .lowerEyelidRight])

        // A5 Intercanthal ratio. Landmarks: EnL–EnR. Formula: distance / face width.
        // Level A; Ye 2026 gives 1/5 ±5% as an MA constraint.
        addProfiled(.intercanthalRatio, value: try distance(.endocanthionLeft, .endocanthionRight, point) / faceWidth, interpretation: "Inner-canthal spacing normalized by face width.", landmarks: [.endocanthionLeft, .endocanthionRight])

        // Nose width is stored as requested, but Ye Table 1 compares alar width with another nasal measure,
        // not face width. No numeric optimum is assigned here. Formula: AlL–AlR / ZyL–ZyR.
        addProfiled(.noseWidthRatio, value: try distance(.alareLeft, .alareRight, point) / faceWidth, interpretation: "Alar width normalized by bizygomatic width.", landmarks: [.alareLeft, .alareRight, .zygionLeft, .zygionRight])

        // A6 Upper/lower lip thickness. Landmarks: Ls–Sto and Sto–Li.
        // Formula: upper thickness / lower thickness. Level A; Ye 2026 gives 1:1.6 (~0.625).
        let lipRatio = try distance(.labialeSuperius, .stomion, point) / max(try distance(.stomion, .labialeInferius, point), 0.000_1)
        addProfiled(.upperLowerLipRatio, value: lipRatio, interpretation: "Upper lip thickness relative to lower lip thickness.", landmarks: [.labialeSuperius, .stomion, .labialeInferius])

        // A9 Zygomatic symmetry. Landmarks: ZyL, ZyR and anatomical midsagittal plane.
        // Formula: |distance(ZyL, plane) − distance(ZyR, plane)| in mm.
        // Level A; Ye 2026 gives ≤1 mm as an MA constraint.
        let zyAsymmetry = abs(signedDistance(zyL, origin: midOrigin, normal: transverse).magnitude - signedDistance(zyR, origin: midOrigin, normal: transverse).magnitude) * 1_000
        addLiteratureReference(.zygomaticAsymmetryMM, value: zyAsymmetry, reference: 0...1, referenceText: "≤1 mm", interpretation: "Difference between left and right zygion distances to the midsagittal plane.", landmarks: [.zygionLeft, .zygionRight])

        let cheekLeft = try roiMeanProjection(indices: generatedROIs.cheekLeft, name: .cheekLeft, vertices: vertices, origin: referenceOrigin, normal: depth) / faceWidth
        let cheekRight = try roiMeanProjection(indices: generatedROIs.cheekRight, name: .cheekRight, vertices: vertices, origin: referenceOrigin, normal: depth) / faceWidth

        // B1 Cheek fullness. ROI: automatically generated bilateral buccal/infraorbital surfaces.
        // Formula: mean signed prominence from anatomical coronal reference plane / face width.
        // Level B; Gkantidis 2026 reports reduced fullness association in females, no numeric optimum.
        metrics.append(rawMetric(.leftCheekFullness, value: cheekLeft, level: .directionalAssociation, reference: "No established optimum — \(gkantidis)", interpretation: "Left cheek prominence; reduced fullness was associated with higher female ratings, not an ideal target.", landmarks: []))
        metrics.append(rawMetric(.rightCheekFullness, value: cheekRight, level: .directionalAssociation, reference: "No established optimum — \(gkantidis)", interpretation: "Right cheek prominence; reduced fullness was associated with higher female ratings, not an ideal target.", landmarks: []))
        metrics.append(rawMetric(.cheekFullness, value: (cheekLeft + cheekRight) / 2, level: .directionalAssociation, reference: "No established optimum — \(gkantidis)", interpretation: "Bilateral mean cheek prominence; descriptive only.", landmarks: []))

        // B2–B4 Central projections. Landmarks: Prn, Ls, Pg (not Me).
        // Formula: signed distance from the same anatomical coronal plane / face width.
        // Level B; Gkantidis 2026 reports association directions only, not numeric optima.
        for (id, landmark, text) in [
            (FaceGeometryMetricID.noseProjection, FaceAnatomicalLandmark.pronasale, "Greater central/nasal projection was associated with higher ratings."),
            (.upperLipProjection, .labialeSuperius, "A fuller, more projected upper lip characterized higher-rated female faces."),
            (.chinProjection, .pogonion, "Less retruded/more projected chin morphology was directionally associated with higher ratings.")
        ] {
            let value = signedDistance(try point(landmark), origin: referenceOrigin, normal: depth) / faceWidth
            metrics.append(rawMetric(id, value: value, level: .directionalAssociation, reference: "No established optimum — \(gkantidis)", interpretation: text + " Descriptive only.", landmarks: [landmark]))
        }

        // C1 Whole-face 3D symmetry. ROI: automatically generated bilateral facial surface with unstable regions excluded.
        // Formula: mirror across anatomical midsagittal plane, then nearest-contralateral-surface mean/RMS.
        // Level C; our operational metric. No scientifically proven attractiveness optimum is assigned.
        let symmetry = try symmetryMetrics(indices: generatedROIs.bilateralFace, vertices: vertices, origin: midOrigin, normal: transverse, faceWidth: faceWidth)
        metrics.append(rawMetric(.meshSymmetryMeanMM, value: symmetry.meanMM, level: .operationalMetric, reference: nil, interpretation: "Mean mirror-to-contralateral surface error; operational geometry metric, not a beauty optimum.", landmarks: []))
        metrics.append(rawMetric(.meshSymmetryRMSMM, value: symmetry.rmsMM, level: .operationalMetric, reference: nil, interpretation: "RMS mirror-to-contralateral surface error; operational geometry metric, not a beauty optimum.", landmarks: []))
        metrics.append(rawMetric(.meshSymmetryNormalizedRMS, value: symmetry.normalizedRMS, level: .operationalMetric, reference: nil, interpretation: "RMS symmetry error normalized by face width.", landmarks: []))

        let model = FaceGeometryMetrics(values: metrics, scanQuality: scan.qualityMetrics, averagedFrameCount: scan.acquisitionMetadata.acceptedFrameCount, landmarkConfigurationVersion: configuration.version, timestamp: scan.timestamp)
        return FaceGeometryAnalysisResult(
            metrics: model,
            geometryScore: GeometryScorer().score(metrics: metrics),
            experimentalAttractiveness: ExperimentalAttractivenessScorer().score(metrics: model)
        )
    }

    private func roiCentroid(indices: [Int], name: FaceROIName, vertices: [SIMD3<Float>]) throws -> SIMD3<Float> {
        let indices = indices.filter(vertices.indices.contains)
        guard !indices.isEmpty else { throw FaceGeometryAnalysisError.emptyROI(name.rawValue) }
        return indices.reduce(.zero) { $0 + vertices[$1] } / Float(indices.count)
    }

    private func roiMeanProjection(indices: [Int], name: FaceROIName, vertices: [SIMD3<Float>], origin: SIMD3<Float>, normal: SIMD3<Float>) throws -> Float {
        let indices = indices.filter(vertices.indices.contains)
        guard !indices.isEmpty else { throw FaceGeometryAnalysisError.emptyROI(name.rawValue) }
        return indices.reduce(0) { $0 + signedDistance(vertices[$1], origin: origin, normal: normal) } / Float(indices.count)
    }

    private func symmetryMetrics(indices: [Int], vertices: [SIMD3<Float>], origin: SIMD3<Float>, normal: SIMD3<Float>, faceWidth: Float) throws -> (meanMM: Float, rmsMM: Float, normalizedRMS: Float) {
        let indices = indices.filter(vertices.indices.contains)
        guard !indices.isEmpty else { throw FaceGeometryAnalysisError.emptyROI(FaceROIName.bilateralFace.rawValue) }
        let selected = indices.map { vertices[$0] }
        let left = selected.filter { signedDistance($0, origin: origin, normal: normal) < 0 }
        let right = selected.filter { signedDistance($0, origin: origin, normal: normal) >= 0 }
        guard !left.isEmpty, !right.isEmpty else { throw FaceGeometryAnalysisError.emptyROI(FaceROIName.bilateralFace.rawValue) }
        let residuals = left.map { point -> Float in
            let mirrored = point - 2 * signedDistance(point, origin: origin, normal: normal) * normal
            return right.reduce(Float.greatestFiniteMagnitude) { min($0, simd_distance(mirrored, $1)) }
        }
        let mean = residuals.reduce(0, +) / Float(residuals.count)
        let rms = sqrt(residuals.reduce(0) { $0 + $1 * $1 } / Float(residuals.count))
        return (mean * 1_000, rms * 1_000, rms / faceWidth)
    }
}

struct GeometryScorer: Sendable {
    func score(metrics: [FaceGeometryMetric]) -> FaceGeometryScore {
        let scored = metrics.filter { $0.evidenceLevel == .numericReference && $0.componentScore != nil }
        func average(_ ids: Set<FaceGeometryMetricID>) -> Float {
            let values = scored.filter { ids.contains($0.id) }.compactMap(\.componentScore)
            return values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
        }
        let proportion = average([.faceHeightWidth, .upperThirdRatio, .middleThirdRatio, .lowerThirdRatio, .noseWidthRatio])
        let symmetry = average([.zygomaticAsymmetryMM])
        let eye = average([.leftEyeWidthRatio, .rightEyeWidthRatio, .leftEyeAspectRatio, .rightEyeAspectRatio, .intercanthalRatio])
        let lower = average([.upperLowerLipRatio])
        let groups = [proportion, symmetry, eye, lower].filter { $0 > 0 }
        return FaceGeometryScore(overall: groups.isEmpty ? 0 : groups.reduce(0, +) / Float(groups.count), facialProportion: proportion, symmetry: symmetry, eyeAndMidface: eye, lowerFace: lower, components: scored)
    }

    static func continuousIntervalScore(value: Float, interval: ClosedRange<Float>) -> Float {
        if interval.contains(value) { return 100 }
        let center = (interval.lowerBound + interval.upperBound) / 2
        let halfWidth = max((interval.upperBound - interval.lowerBound) / 2, abs(center) * 0.05, 0.001)
        let distance = value < interval.lowerBound ? interval.lowerBound - value : value - interval.upperBound
        return 100 * exp(-0.5 * pow(distance / halfWidth, 2))
    }

    static func proportionalTargetScore(value: Float, target: Float) -> Float {
        let magnitude = max(abs(value), abs(target))
        guard magnitude > .ulpOfOne else { return 100 }
        return 100 * min(abs(value), abs(target)) / magnitude
    }
}

struct ExperimentalAttractivenessScorer: Sendable {
    func score(metrics: FaceGeometryMetrics) -> ExperimentalAttractivenessResult {
        ExperimentalAttractivenessResult(score: nil, modelIdentifier: "untrained-v0", note: "No validated regression coefficients or numeric Level-B optima are available. Raw morphology is preserved for a future VAS-trained model.")
    }
}

private func safeNormalize(_ vector: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
    simd_length_squared(vector) > .ulpOfOne ? simd_normalize(vector) : fallback
}

private func signedDistance(_ point: SIMD3<Float>, origin: SIMD3<Float>, normal: SIMD3<Float>) -> Float {
    simd_dot(point - origin, normal)
}

private func distance(_ lhs: FaceAnatomicalLandmark, _ rhs: FaceAnatomicalLandmark, _ point: (FaceAnatomicalLandmark) throws -> SIMD3<Float>) throws -> Float {
    try simd_distance(point(lhs), point(rhs))
}

private func rawMetric(_ id: FaceGeometryMetricID, value: Float, level: FaceGeometryEvidenceLevel, reference: String?, interpretation: String, landmarks: [FaceAnatomicalLandmark]) -> FaceGeometryMetric {
    let unit = id.rawValue.hasSuffix("MM") ? "mm" : "normalized ratio"
    return FaceGeometryMetric(id: id, value: value, unit: unit, evidenceLevel: level, referenceText: reference, referenceSource: nil, referenceSampleCount: nil, isReferenceProvisional: nil, interpretation: interpretation, componentScore: nil, landmarkNames: landmarks)
}
