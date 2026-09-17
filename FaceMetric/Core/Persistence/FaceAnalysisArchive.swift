import Foundation

struct SavedFaceAnalysis: Codable, Hashable, Identifiable, Sendable {
    let scan: FaceScan
    let analysis: FacialAnalysis
    let geometryAnalysis: FaceGeometryAnalysisResult?

    nonisolated init(
        scan: FaceScan,
        analysis: FacialAnalysis,
        geometryAnalysis: FaceGeometryAnalysisResult? = nil
    ) {
        self.scan = scan
        self.analysis = analysis
        self.geometryAnalysis = geometryAnalysis
    }

    private enum CodingKeys: String, CodingKey {
        case scan
        case analysis
        case geometryAnalysis
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scan = try container.decode(FaceScan.self, forKey: .scan)
        analysis = try container.decode(FacialAnalysis.self, forKey: .analysis)
        geometryAnalysis = try container.decodeIfPresent(FaceGeometryAnalysisResult.self, forKey: .geometryAnalysis)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scan, forKey: .scan)
        try container.encode(analysis, forKey: .analysis)
        try container.encodeIfPresent(geometryAnalysis, forKey: .geometryAnalysis)
    }

    nonisolated var id: UUID { scan.id }

    nonisolated static func == (lhs: SavedFaceAnalysis, rhs: SavedFaceAnalysis) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum FaceAnalysisArchive {
    nonisolated private static let folderName = "FaceMetricScans"

    nonisolated static func loadAll() throws -> [SavedFaceAnalysis] {
        let folder = try archiveFolder()
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                try? decoder.decode(SavedFaceAnalysis.self, from: Data(contentsOf: url))
            }
            .sorted { $0.scan.timestamp > $1.scan.timestamp }
    }

    nonisolated static func save(_ record: SavedFaceAnalysis) throws {
        let folder = try archiveFolder()
        let destination = folder
            .appendingPathComponent(record.id.uuidString)
            .appendingPathExtension("json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: destination, options: .atomic)
    }

    nonisolated static func delete(_ record: SavedFaceAnalysis) throws {
        let url = try archiveFolder()
            .appendingPathComponent(record.id.uuidString)
            .appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static func deleteAll() throws {
        let folder = try archiveFolder()
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )
        for url in urls where url.pathExtension == "json" {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func archiveFolder() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
    }
}
