import Foundation
import simd

enum FaceAnatomicalLandmark: String, Codable, CaseIterable, Identifiable, Sendable {
    case trichionOrForeheadBoundary
    case glabella
    case menton
    case pogonion
    case zygionLeft
    case zygionRight
    case gonionLeft
    case gonionRight
    case exocanthionLeft
    case exocanthionRight
    case endocanthionLeft
    case endocanthionRight
    case upperEyelidLeft
    case lowerEyelidLeft
    case upperEyelidRight
    case lowerEyelidRight
    case nasion
    case pronasale
    case subnasale
    case alareLeft
    case alareRight
    case labialeSuperius
    case stomion
    case labialeInferius
    case mouthLeft
    case mouthRight

    var id: String { rawValue }

    static let requiredForMVP = allCases
}

enum FaceROIName: String, Codable, CaseIterable, Identifiable, Sendable {
    case cheekLeft
    case cheekRight
    case stableUpperMidFace
    case bilateralFace

    var id: String { rawValue }
}

struct FaceLandmarkConfig: Codable, Equatable, Sendable {
    let version: String
    let topologyVertexCount: Int
    let topologySignature: String?
    var landmarkVertexIndices: [String: Int]
    var roiVertexIndices: [String: [Int]]

    init(
        version: String,
        topologyVertexCount: Int,
        topologySignature: String? = nil,
        landmarkVertexIndices: [String: Int],
        roiVertexIndices: [String: [Int]]
    ) {
        self.version = version
        self.topologyVertexCount = topologyVertexCount
        self.topologySignature = topologySignature
        self.landmarkVertexIndices = landmarkVertexIndices
        self.roiVertexIndices = roiVertexIndices
    }

    static func uncalibrated(topologyVertexCount: Int) -> FaceLandmarkConfig {
        FaceLandmarkConfig(
            version: "arkit-manual-v1",
            topologyVertexCount: topologyVertexCount,
            topologySignature: nil,
            landmarkVertexIndices: [:],
            roiVertexIndices: [:]
        )
    }

    static func uncalibrated(mesh: FaceMesh) -> FaceLandmarkConfig {
        FaceLandmarkConfig(
            version: "arkit-manual-v1",
            topologyVertexCount: mesh.vertices.count,
            topologySignature: mesh.topologySignature,
            landmarkVertexIndices: [:],
            roiVertexIndices: [:]
        )
    }

    var isCompleteForMVP: Bool {
        FaceAnatomicalLandmark.requiredForMVP.allSatisfy { vertexIndex(for: $0) != nil }
    }

    func vertexIndex(for landmark: FaceAnatomicalLandmark) -> Int? {
        landmarkVertexIndices[landmark.rawValue]
    }

    func vertexIndices(for roi: FaceROIName) -> [Int] {
        roiVertexIndices[roi.rawValue] ?? []
    }
}

enum FaceLandmarkConfigStore {
    private static let key = "FaceMetric.FaceLandmarkConfig.v1"

    static func load(vertexCount: Int, defaults: UserDefaults = .standard) -> FaceLandmarkConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(FaceLandmarkConfig.self, from: data),
              config.topologyVertexCount == vertexCount else {
            return .uncalibrated(topologyVertexCount: vertexCount)
        }
        return config
    }

    static func load(mesh: FaceMesh, defaults: UserDefaults = .standard) -> FaceLandmarkConfig {
        if let data = defaults.data(forKey: key),
           let config = try? JSONDecoder().decode(FaceLandmarkConfig.self, from: data),
           matches(config, mesh: mesh),
           config.isCompleteForMVP {
            return applyingOneRingVerticalCorrections(to: config, mesh: mesh)
        }

        if let bundled = BundledFaceLandmarkConfigs.all.first(where: { matches($0, mesh: mesh) }) {
            return applyingOneRingVerticalCorrections(to: bundled, mesh: mesh)
        }
        return .uncalibrated(mesh: mesh)
    }

    static func save(_ config: FaceLandmarkConfig, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(config), forKey: key)
    }

    static func exportJSON(_ config: FaceLandmarkConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(config), as: UTF8.self)
    }

    private static func matches(_ config: FaceLandmarkConfig, mesh: FaceMesh) -> Bool {
        guard config.topologyVertexCount == mesh.vertices.count else { return false }
        return config.topologySignature.map { $0 == mesh.topologySignature } ?? true
    }

    /// Migrates the original manual calibration by exactly one topology edge:
    /// Tr/forehead moves superiorly and Me moves inferiorly in the subject's
    /// face-local vertical direction. Numeric index +/- 1 is intentionally not
    /// used because ARFaceGeometry vertex ordering is not a spatial ordering.
    private static func applyingOneRingVerticalCorrections(
        to config: FaceLandmarkConfig,
        mesh: FaceMesh
    ) -> FaceLandmarkConfig {
        guard config.version == "arkit-manual-v1",
              let trichion = config.vertexIndex(for: .trichionOrForeheadBoundary),
              let menton = config.vertexIndex(for: .menton),
              mesh.vertices.indices.contains(trichion),
              mesh.vertices.indices.contains(menton) else { return config }

        let vertices = mesh.simdVertices
        let verticalCandidate = vertices[trichion] - vertices[menton]
        guard simd_length_squared(verticalCandidate) > .ulpOfOne else { return config }
        let vertical = simd_normalize(verticalCandidate)
        let adjacency = oneRingAdjacency(mesh: mesh)

        func neighbor(from index: Int, direction: Float) -> Int {
            adjacency[index]
                .filter(vertices.indices.contains)
                .max { lhs, rhs in
                    direction * simd_dot(vertices[lhs] - vertices[index], vertical)
                        < direction * simd_dot(vertices[rhs] - vertices[index], vertical)
                }
                .flatMap { candidate in
                    direction * simd_dot(vertices[candidate] - vertices[index], vertical) > 0
                        ? candidate
                        : nil
                } ?? index
        }

        var landmarks = config.landmarkVertexIndices
        landmarks[FaceAnatomicalLandmark.trichionOrForeheadBoundary.rawValue] = neighbor(from: trichion, direction: 1)
        landmarks[FaceAnatomicalLandmark.menton.rawValue] = neighbor(from: menton, direction: -1)
        return FaceLandmarkConfig(
            version: "arkit-landmark-v2-one-ring",
            topologyVertexCount: config.topologyVertexCount,
            topologySignature: config.topologySignature,
            landmarkVertexIndices: landmarks,
            roiVertexIndices: config.roiVertexIndices
        )
    }

    private static func oneRingAdjacency(mesh: FaceMesh) -> [Set<Int>] {
        var result = Array(repeating: Set<Int>(), count: mesh.vertices.count)
        let indices = mesh.triangleIndices.map { Int(UInt16(bitPattern: $0)) }
        for start in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
            let triangle = [indices[start], indices[start + 1], indices[start + 2]]
            guard triangle.allSatisfy(result.indices.contains) else { continue }
            result[triangle[0]].formUnion([triangle[1], triangle[2]])
            result[triangle[1]].formUnion([triangle[0], triangle[2]])
            result[triangle[2]].formUnion([triangle[0], triangle[1]])
        }
        return result
    }
}

/// Paste a reviewed exported configuration into this registry before release.
/// Keeping this list in source makes the shipped default auditable and removes
/// the need for end users to run developer calibration.
enum BundledFaceLandmarkConfigs {
    static let all: [FaceLandmarkConfig] = [
        FaceLandmarkConfig(
            version: "arkit-manual-v1",
            topologyVertexCount: 1_220,
            topologySignature: "2cea1c28ad36247e",
            landmarkVertexIndices: [
                "alareLeft": 325, "alareRight": 760,
                "endocanthionLeft": 1089, "endocanthionRight": 1081,
                "exocanthionLeft": 1101, "exocanthionRight": 1069,
                "glabella": 17,
                "gonionLeft": 462, "gonionRight": 1216,
                "labialeInferius": 28, "labialeSuperius": 21,
                "lowerEyelidLeft": 1108, "lowerEyelidRight": 1062,
                "menton": 1048,
                "mouthLeft": 394, "mouthRight": 824,
                "nasion": 15, "pogonion": 35, "pronasale": 8,
                "stomion": 24, "subnasale": 38,
                "trichionOrForeheadBoundary": 956,
                "upperEyelidLeft": 1095, "upperEyelidRight": 1075,
                "zygionLeft": 389, "zygionRight": 820
            ],
            roiVertexIndices: [:]
        )
    ]
}
