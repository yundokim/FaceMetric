import SceneKit
import SwiftUI

struct FaceComparisonView: View {
    private enum ScanRole: String, Identifiable {
        case baseline
        case followup

        var id: String { rawValue }

        var title: String {
            self == .baseline ? "Baseline Scan" : "Follow-up Scan"
        }
    }

    @State private var baselineScan: FaceScan?
    @State private var followupScan: FaceScan?
    @State private var activeScanRole: ScanRole?
    @State private var studyRegion: RegistrationStudyRegion = .chin
    @State private var comparison: FaceComparison?
    @State private var comparisonError: String?
    @State private var isComparing = false

    init(baselineScan: FaceScan? = nil, followupScan: FaceScan? = nil) {
        _baselineScan = State(initialValue: baselineScan)
        _followupScan = State(initialValue: followupScan)
    }

    var body: some View {
        NavigationStack {
            List {
                ComparisonScanSelectionSection(
                    baseline: baselineScan,
                    followup: followupScan,
                    captureBaseline: { activeScanRole = .baseline },
                    captureFollowup: { activeScanRole = .followup }
                )

                CompareAreaSection(selection: $studyRegion)

                Section {
                    Button(action: compareScans) {
                        if isComparing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Compare")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(baselineScan == nil || followupScan == nil || isComparing)
                    .listRowBackground(Color.clear)

                    if let comparisonError {
                        Label(comparisonError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let comparison,
                   let baselineScan,
                   let followupScan,
                   let productionResult = comparison.productionRegistration {
                    ComparisonResultSections(
                        comparison: comparison,
                        result: productionResult,
                        baseline: baselineScan.mesh,
                        followup: followupScan.mesh,
                        retakeFollowup: { activeScanRole = .followup }
                    )
                }
            }
            .navigationTitle("Compare Scans")
            .sheet(item: $activeScanRole) { role in
                ScanView(scanLabel: role.title) { scan in
                    if role == .baseline {
                        baselineScan = scan
                    } else {
                        followupScan = scan
                    }
                    comparison = nil
                    comparisonError = nil
                    activeScanRole = nil
                }
            }
            .onChange(of: studyRegion) {
                comparison = nil
                comparisonError = nil
            }
        }
    }

    private func compareScans() {
        guard let baselineScan, let followupScan else { return }
        let selectedRegion = studyRegion
        let profile = RegistrationProfile.engineeringProfile(for: selectedRegion)

        isComparing = true
        comparison = nil
        comparisonError = nil

        Task {
            do {
                let result = try await Task.detached {
                    try RegistrationStrategyComparisonEngine().compare(
                        baseline: baselineScan.mesh,
                        followup: followupScan.mesh,
                        profile: profile
                    )
                }.value
                comparison = FaceComparison(
                    baselineScanID: baselineScan.id,
                    followupScanID: followupScan.id,
                    studyRegion: selectedRegion,
                    registrationComparison: result,
                    expressionDifference: ExpressionDifferenceAnalyzer.compare(
                        baseline: baselineScan.acquisitionMetadata.representativeBlendShapes,
                        followup: followupScan.acquisitionMetadata.representativeBlendShapes
                    )
                )
            } catch {
                comparisonError = "These scans could not be compared. Try retaking the follow-up scan."
            }
            isComparing = false
        }
    }
}

private struct ComparisonScanSelectionSection: View {
    let baseline: FaceScan?
    let followup: FaceScan?
    let captureBaseline: () -> Void
    let captureFollowup: () -> Void

    var body: some View {
        Section("Scans") {
            ComparisonScanRow(
                title: "Baseline",
                scan: baseline,
                capture: captureBaseline
            )
            ComparisonScanRow(
                title: "Follow-up",
                scan: followup,
                capture: captureFollowup
            )
        }
    }
}

private struct ComparisonScanRow: View {
    let title: String
    let scan: FaceScan?
    let capture: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.title)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let scan {
                    Text(scan.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No scan selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(scan == nil ? "Capture" : "Retake", action: capture)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: scan == nil ? "Capture scan" : "Retake scan", capture)
    }
}

private struct CompareAreaSection: View {
    @Binding var selection: RegistrationStudyRegion

    var body: some View {
        Section("Compare Area") {
            Picker("Face area", selection: $selection) {
                ForEach(RegistrationStudyRegion.allCases) { region in
                    Text(region.userFacingName).tag(region)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct ComparisonResultSections: View {
    let comparison: FaceComparison
    let result: StrategyRegistrationResult
    let baseline: FaceMesh
    let followup: FaceMesh
    let retakeFollowup: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(comparison.studyRegion.userFacingName.uppercased()) CHANGE")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                TreatmentDisplacementSceneView(
                    baseline: baseline,
                    followup: followup,
                    result: result
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Interactive 3D displacement map for \(comparison.studyRegion.userFacingName)")

                DisplacementScale(rangeMeters: heatmapRange)
            }
            .padding(.vertical, 6)
        }

        SurfaceChangeSummarySection(
            averageMeters: result.treatmentSurfaceDifference.metrics.meanAbsoluteResidual,
            p95Meters: result.treatmentSurfaceDifference.metrics.p95AbsoluteResidual
        )

        ComparisonQualitySection(
            comparison: comparison,
            result: result,
            retakeFollowup: retakeFollowup
        )

        Section {
            NavigationLink("View Details") {
                ComparisonDetailsView(
                    comparison: comparison,
                    result: result,
                    baseline: baseline,
                    followup: followup
                )
            }
        }
    }

    private var heatmapRange: Float {
        max(result.treatmentSurfaceDifference.metrics.p95AbsoluteResidual, 0.000_1)
    }
}

private struct DisplacementScale: View {
    let rangeMeters: Float

    var body: some View {
        VStack(spacing: 6) {
            LinearGradient(
                colors: [.blue, .white, .red],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 10)
            .clipShape(Capsule())

            HStack {
                Text(signedMillimeters(-rangeMeters))
                Spacer()
                Text("0 mm")
                Spacer()
                Text(signedMillimeters(rangeMeters))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Text("Direction is relative to the baseline surface, not improvement or worsening.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func signedMillimeters(_ meters: Float) -> String {
        String(format: "%+.1f mm", meters * 1_000)
    }
}

private struct SurfaceChangeSummarySection: View {
    let averageMeters: Float
    let p95Meters: Float

    var body: some View {
        Section("Surface Change") {
            ComparisonMetricRow(
                title: "Average surface change",
                value: millimeters(averageMeters),
                prominence: true
            )
            ComparisonMetricRow(
                title: "95th percentile",
                value: millimeters(p95Meters),
                prominence: false
            )
        }
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.1f mm", meters * 1_000)
    }
}

private struct ComparisonMetricRow: View {
    let title: String
    let value: String
    let prominence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(prominence ? .title2 : .headline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ComparisonQualitySection: View {
    let comparison: FaceComparison
    let result: StrategyRegistrationResult
    let retakeFollowup: () -> Void

    private var alignmentHasWarnings: Bool {
        result.anchorRegistration?.qualityMetadata.status == .validWithWarnings
    }

    private var expressionDiffers: Bool {
        comparison.expressionDifference.exceedsEngineeringWarningLevel
    }

    var body: some View {
        Section("Comparison Quality") {
            if alignmentHasWarnings || expressionDiffers {
                Label("Comparison may be unreliable", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Retake Follow-up Scan", action: retakeFollowup)
                    .frame(minHeight: 44)
            } else {
                Label("Alignment passed current checks", systemImage: "checkmark.circle.fill")
                Label("Expression similar", systemImage: "checkmark.circle.fill")
            }
        }
    }

    private var message: String {
        if expressionDiffers {
            return "Expression differed between scans. Consider retaking the follow-up scan."
        }
        return "Alignment checks reported an issue. Consider retaking the follow-up scan."
    }
}

private struct ComparisonDetailsView: View {
    let comparison: FaceComparison
    let result: StrategyRegistrationResult
    let baseline: FaceMesh
    let followup: FaceMesh

    var body: some View {
        List {
            Section {
                Text("Treatment measurements describe surface differences inside the selected face area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                DetailMetricRow(
                    title: "Mean signed displacement",
                    value: signedMillimeters(result.treatmentSurfaceDifference.metrics.meanSignedResidual),
                    explanation: "Average geometric direction relative to the baseline surface."
                )
                DetailMetricRow(
                    title: "Mean absolute displacement",
                    value: millimeters(result.treatmentSurfaceDifference.metrics.meanAbsoluteResidual),
                    explanation: "Average change magnitude without direction."
                )
                DetailMetricRow(
                    title: "Treatment RMS",
                    value: millimeters(result.treatmentSurfaceDifference.metrics.rmsResidual),
                    explanation: "Surface difference measure that gives more weight to larger changes."
                )
                DetailMetricRow(
                    title: "Treatment P95",
                    value: millimeters(result.treatmentSurfaceDifference.metrics.p95AbsoluteResidual),
                    explanation: "Ninety-five percent of measured changes are at or below this value."
                )
            } header: {
                Text("Treatment Measurements")
            }

            Section {
                Text("Registration metrics describe how closely the two meshes align in the stable reference area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                DetailMetricRow(
                    title: "Stable area RMS",
                    value: millimeters(result.stableROIResiduals.rmsResidual),
                    explanation: "Overall residual difference in the stable reference area."
                )
                DetailMetricRow(
                    title: "Stable area P95",
                    value: millimeters(result.stableROIResiduals.p95AbsoluteResidual),
                    explanation: "Upper range of residual differences in the stable reference area."
                )
                if let anchor = result.anchorRegistration {
                    DetailMetricRow(
                        title: "Anchor RMS",
                        value: millimeters(anchor.anchorRMSError),
                        explanation: "Residual error at the anatomical reference regions used for initial alignment."
                    )
                }
            } header: {
                Text("Registration Quality")
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink("Developer Diagnostics") {
                    RegistrationDebugView(
                        baseline: baseline,
                        followup: followup,
                        profile: RegistrationProfile.engineeringProfile(for: comparison.studyRegion),
                        comparison: comparison.registrationComparison
                    )
                }
            }
            #endif
        }
        .navigationTitle("Comparison Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.3f mm", meters * 1_000)
    }

    private func signedMillimeters(_ meters: Float) -> String {
        String(format: "%+.3f mm", meters * 1_000)
    }
}

private struct DetailMetricRow: View {
    let title: String
    let value: String
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct TreatmentDisplacementSceneView: UIViewRepresentable {
    let baseline: FaceMesh
    let followup: FaceMesh
    let result: StrategyRegistrationResult

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.scene = makeScene()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let aligned = result.finalTransform.applying(to: followup)
        let meshNode = heatmapNode(mesh: aligned)
        let bounds = meshBounds(aligned.simdVertices)
        let center = (bounds.minimum + bounds.maximum) / 2
        meshNode.simdPosition = -center
        scene.rootNode.addChildNode(meshNode)

        let size = bounds.maximum - bounds.minimum
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(size.x, size.y) * 1.2)
        camera.zNear = 0.001
        camera.zFar = 2
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(0, 0, max(size.z * 4, 0.35))
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    private func heatmapNode(mesh: FaceMesh) -> SCNNode {
        let samples = result.treatmentSurfaceDifference.samples
        let sampleByIndex = Dictionary(uniqueKeysWithValues: samples.map {
            ($0.vertexIndex, $0.signedDistanceMeters)
        })
        let range = max(result.treatmentSurfaceDifference.metrics.p95AbsoluteResidual, 0.000_1)
        let colors: [SIMD4<Float>] = mesh.vertices.indices.map { index in
            guard let displacement = sampleByIndex[index] else {
                return SIMD4<Float>(0.20, 0.22, 0.25, 0.72)
            }
            let normalized = min(1, max(-1, displacement / range))
            if normalized >= 0 {
                return SIMD4<Float>(1, 1 - normalized, 1 - normalized, 1)
            }
            return SIMD4<Float>(1 + normalized, 1 + normalized, 1, 1)
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let vertexSource = SCNGeometrySource(vertices: mesh.simdVertices.map(SCNVector3.init))
        let indices = mesh.triangleIndices.map(UInt16.init(bitPattern:))
        let element = SCNGeometryElement(
            data: indices.withUnsafeBytes { Data($0) },
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func meshBounds(
        _ vertices: [SIMD3<Float>]
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        guard let first = vertices.first else {
            return (SIMD3<Float>(repeating: -0.1), SIMD3<Float>(repeating: 0.1))
        }
        return vertices.dropFirst().reduce(into: (minimum: first, maximum: first)) { bounds, point in
            bounds.minimum = simd_min(bounds.minimum, point)
            bounds.maximum = simd_max(bounds.maximum, point)
        }
    }
}

private extension RegistrationStudyRegion {
    var userFacingName: String {
        switch self {
        case .chin:
            return "Chin"
        case .nose:
            return "Nose"
        case .cheek:
            return "Cheek"
        case .lipPerioral:
            return "Lips"
        }
    }
}
