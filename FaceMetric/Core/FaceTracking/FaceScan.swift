import Foundation

struct FaceScan: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    /// Representative coordinate-wise median mesh in ARKit face-local meters.
    let mesh: FaceMesh
    /// Raw accepted frames are retained separately from the representative mesh.
    let rawAcceptedMeshes: [FaceMesh]
    let acquisitionMetadata: FaceAcquisitionMetadata
    let qualityMetrics: ScanQualityMetrics
    let deviceInformation: ScanDeviceInformation
}

struct FaceAcquisitionMetadata: Codable, Equatable, Sendable {
    let configuration: ScanQualityConfiguration
    let startedAt: Date
    let completedAt: Date
    let acceptedFrameCount: Int
    let rejectedFrameCount: Int
    let acceptedFrameTimestamps: [TimeInterval]
    let acceptedFrameQuality: [ScanQualityMetrics]
    let blendShapeNames: [String]
    /// Coordinate-wise median ARKit blend-shape coefficients across accepted frames.
    let representativeBlendShapes: [String: Float]
    let aggregationMethod: String
    let coordinateSystem: String
}

struct ScanDeviceInformation: Codable, Equatable, Sendable {
    let model: String
    let systemName: String
    let systemVersion: String
    let appVersion: String
    let appBuild: String
}
