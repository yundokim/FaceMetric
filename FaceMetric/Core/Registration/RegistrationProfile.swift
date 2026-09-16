import Foundation
import simd

public enum RegistrationStudyRegion: String, Codable, CaseIterable, Sendable, Identifiable {
    case chin
    case nose
    case cheek
    case lipPerioral

    public var id: String { rawValue }
}

public struct RegistrationProfile: Codable, Equatable, Sendable {
    public let identifier: String
    public let referenceAnchors: [AnatomicalAnchorDefinition]
    public let stableSurfaceRegions: RegistrationRegionMask
    public let excludedRegions: [RegistrationRegionMask]
    public let treatmentRegions: [RegistrationRegionMask]

    public init(
        identifier: String,
        referenceAnchors: [AnatomicalAnchorDefinition],
        stableSurfaceRegions: RegistrationRegionMask,
        excludedRegions: [RegistrationRegionMask],
        treatmentRegions: [RegistrationRegionMask]
    ) {
        self.identifier = identifier
        self.referenceAnchors = referenceAnchors
        self.stableSurfaceRegions = stableSurfaceRegions
        self.excludedRegions = excludedRegions
        self.treatmentRegions = treatmentRegions
    }

    nonisolated func stableVertexIndices(in mesh: FaceMesh) -> [Int] {
        let vertices = mesh.simdVertices
        let included = Set(stableSurfaceRegions.selectedIndices(in: vertices))
        let forbiddenMasks = excludedRegions + treatmentRegions
        let forbidden = forbiddenMasks.reduce(into: Set<Int>()) { result, mask in
            result.formUnion(mask.selectedIndices(in: vertices))
        }
        return Array(included.subtracting(forbidden)).sorted()
    }

    nonisolated func treatmentVertexIndices(in mesh: FaceMesh) -> [Int] {
        let vertices = mesh.simdVertices
        return Array(treatmentRegions.reduce(into: Set<Int>()) { result, mask in
            result.formUnion(mask.selectedIndices(in: vertices))
        }).sorted()
    }

    /// Engineering placeholders. These normalized patches are not clinically validated.
    public static func engineeringProfile(for region: RegistrationStudyRegion) -> RegistrationProfile {
        let treatment = treatmentMask(for: region)
        let expressionSensitive = expressionSensitiveMask
        return RegistrationProfile(
            identifier: "\(region.rawValue)-engineering-v1",
            referenceAnchors: referenceAnchorDefinitions(for: region),
            stableSurfaceRegions: upperFaceStableMask,
            excludedRegions: [treatment, expressionSensitive],
            treatmentRegions: [treatment]
        )
    }

    public static let engineeringDefault = engineeringProfile(for: .chin)

    public static func referenceAnchorDefinitions(
        for region: RegistrationStudyRegion
    ) -> [AnatomicalAnchorDefinition] {
        switch region {
        case .nose:
            return upperFaceAnchorDefinitions.filter { $0.id != .nasalRoot }
        case .cheek:
            return upperFaceAnchorDefinitions.filter {
                $0.id == .upperForehead
                    || $0.id == .leftForehead
                    || $0.id == .rightForehead
                    || $0.id == .nasalRoot
            }
        case .chin, .lipPerioral:
            return upperFaceAnchorDefinitions
        }
    }

    public static let upperFaceAnchorDefinitions: [AnatomicalAnchorDefinition] = [
        AnatomicalAnchorDefinition(
            id: .upperForehead,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(0.42, 0.82, 0),
                maximum: SIMD3<Float>(0.58, 0.98, 1)
            )
        ),
        AnatomicalAnchorDefinition(
            id: .leftForehead,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(0.18, 0.70, 0),
                maximum: SIMD3<Float>(0.36, 0.90, 1)
            )
        ),
        AnatomicalAnchorDefinition(
            id: .rightForehead,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(0.64, 0.70, 0),
                maximum: SIMD3<Float>(0.82, 0.90, 1)
            )
        ),
        AnatomicalAnchorDefinition(
            id: .leftPeriorbital,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(0.18, 0.50, 0),
                maximum: SIMD3<Float>(0.38, 0.68, 1)
            )
        ),
        AnatomicalAnchorDefinition(
            id: .rightPeriorbital,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(0.62, 0.50, 0),
                maximum: SIMD3<Float>(0.82, 0.68, 1)
            )
        ),
        AnatomicalAnchorDefinition(
            id: .nasalRoot,
            patch: RegistrationBounds(
                minimum: SIMD3<Float>(0.44, 0.54, 0),
                maximum: SIMD3<Float>(0.56, 0.72, 1)
            )
        )
    ]

    public static let upperFaceStableMask = RegistrationRegionMask(
        identifier: "upper-face-stable-engineering-v1",
        includedBounds: [
            RegistrationBounds(
                minimum: SIMD3<Float>(0.12, 0.48, 0),
                maximum: SIMD3<Float>(0.88, 1, 1)
            )
        ]
    )

    public static let expressionSensitiveMask = RegistrationRegionMask(
        identifier: "expression-sensitive-engineering-v1",
        includedBounds: [
            RegistrationBounds(
                minimum: SIMD3<Float>(0.20, 0, 0),
                maximum: SIMD3<Float>(0.80, 0.48, 1)
            )
        ]
    )

    public static func treatmentMask(
        for region: RegistrationStudyRegion
    ) -> RegistrationRegionMask {
        switch region {
        case .chin:
            return RegistrationRegionMask(
                identifier: "chin-treatment-engineering-v1",
                includedBounds: [
                    RegistrationBounds(
                        minimum: SIMD3<Float>(0.30, 0, 0),
                        maximum: SIMD3<Float>(0.70, 0.25, 1)
                    )
                ]
            )
        case .nose:
            return RegistrationRegionMask(
                identifier: "nose-treatment-engineering-v1",
                includedBounds: [
                    RegistrationBounds(
                        minimum: SIMD3<Float>(0.40, 0.30, 0),
                        maximum: SIMD3<Float>(0.60, 0.62, 1)
                    )
                ]
            )
        case .cheek:
            return RegistrationRegionMask(
                identifier: "cheeks-treatment-engineering-v1",
                includedBounds: [
                    RegistrationBounds(
                        minimum: SIMD3<Float>(0.08, 0.25, 0),
                        maximum: SIMD3<Float>(0.38, 0.55, 1)
                    ),
                    RegistrationBounds(
                        minimum: SIMD3<Float>(0.62, 0.25, 0),
                        maximum: SIMD3<Float>(0.92, 0.55, 1)
                    )
                ]
            )
        case .lipPerioral:
            return RegistrationRegionMask(
                identifier: "lip-perioral-treatment-engineering-v1",
                includedBounds: [
                    RegistrationBounds(
                        minimum: SIMD3<Float>(0.32, 0.18, 0),
                        maximum: SIMD3<Float>(0.68, 0.42, 1)
                    )
                ]
            )
        }
    }
}
