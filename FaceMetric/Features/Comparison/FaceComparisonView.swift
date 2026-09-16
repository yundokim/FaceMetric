import SwiftUI
import simd

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
    @State private var registrationError: String?
    @State private var isRegistering = false
    @State private var syntheticMagnitudeMillimeters: Double = 2
    @State private var syntheticSpreadMillimeters: Double = 18
    @State private var syntheticDirection: SyntheticDeformationDirection = .outward
    @State private var syntheticResult: SyntheticRegistrationValidationResult?
    @State private var syntheticError: String?
    @State private var isValidatingSynthetic = false

    var body: some View {
        NavigationStack {
            List {
                Section("Scans") {
                    ScanStatusRow(
                        title: "Baseline",
                        scan: baselineScan,
                        capture: { activeScanRole = .baseline }
                    )
                    ScanStatusRow(
                        title: "Follow-up",
                        scan: followupScan,
                        capture: { activeScanRole = .followup }
                    )
                }

                Section("Registration Profile") {
                    Picker("Treatment ROI", selection: $studyRegion) {
                        ForEach(RegistrationStudyRegion.allCases) { region in
                            Text(region.rawValue).tag(region)
                        }
                    }

                    Text("The selected treatment ROI is excluded from anchor and stable-surface registration. Profiles are unvalidated engineering placeholders.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Rigid Registration") {
                    Text("Production: anatomical anchors followed by optional stable-ROI-only rigid refinement. Full-face ICP is calculated only as a research control.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        registerScans()
                    } label: {
                        if isRegistering {
                            ProgressView()
                        } else {
                            Label("Compare Registration Strategies", systemImage: "square.3.layers.3d")
                        }
                    }
                    .disabled(baselineScan == nil || followupScan == nil || isRegistering)

                    if let registrationError {
                        Text(registrationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                SyntheticValidationSection(
                    magnitudeMillimeters: $syntheticMagnitudeMillimeters,
                    spreadMillimeters: $syntheticSpreadMillimeters,
                    direction: $syntheticDirection,
                    result: syntheticResult,
                    error: syntheticError,
                    isRunning: isValidatingSynthetic,
                    canRun: baselineScan != nil,
                    run: runSyntheticValidation
                )

                if let comparison, let baselineScan, let followupScan {
                    RegistrationSummarySection(
                        comparison: comparison,
                        baseline: baselineScan.mesh,
                        followup: followupScan.mesh
                    )
                }
            }
            .navigationTitle("FaceMetric Research")
            .sheet(item: $activeScanRole) { role in
                ScanView(scanLabel: role.title) { scan in
                    if role == .baseline {
                        baselineScan = scan
                    } else {
                        followupScan = scan
                    }
                    comparison = nil
                    registrationError = nil
                    activeScanRole = nil
                }
            }
            .onChange(of: studyRegion) {
                comparison = nil
                syntheticResult = nil
            }
        }
    }

    private func registerScans() {
        guard let baselineScan, let followupScan else { return }
        let selectedRegion = studyRegion
        let profile = RegistrationProfile.engineeringProfile(for: selectedRegion)

        isRegistering = true
        comparison = nil
        registrationError = nil

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
                    registrationComparison: result
                )
            } catch {
                registrationError = String(describing: error)
            }
            isRegistering = false
        }
    }

    private func runSyntheticValidation() {
        guard let baselineScan else { return }
        let parameters = SyntheticDeformationParameters(
            region: studyRegion,
            maximumDisplacementMeters: Float(syntheticMagnitudeMillimeters / 1_000),
            spatialSpreadMeters: Float(syntheticSpreadMillimeters / 1_000),
            direction: syntheticDirection
        )
        let pose = RigidTransform(
            matrix: simd_float3x3(
                simd_quatf(
                    angle: 0.12,
                    axis: simd_normalize(SIMD3<Float>(0.2, 0.7, 0.4))
                )
            ),
            translation: SIMD3<Float>(0.006, -0.004, 0.01)
        )

        isValidatingSynthetic = true
        syntheticResult = nil
        syntheticError = nil
        Task {
            do {
                syntheticResult = try await Task.detached {
                    try SyntheticRegistrationValidator().validate(
                        baseline: baselineScan.mesh,
                        deformation: parameters,
                        poseTransform: pose
                    )
                }.value
            } catch {
                syntheticError = String(describing: error)
            }
            isValidatingSynthetic = false
        }
    }
}

private struct SyntheticValidationSection: View {
    @Binding var magnitudeMillimeters: Double
    @Binding var spreadMillimeters: Double
    @Binding var direction: SyntheticDeformationDirection
    let result: SyntheticRegistrationValidationResult?
    let error: String?
    let isRunning: Bool
    let canRun: Bool
    let run: () -> Void

    var body: some View {
        Section("Synthetic Registration Validation") {
            LabeledContent(
                "Maximum displacement",
                value: magnitudeMillimeters.formatted(.number.precision(.fractionLength(1))) + " mm"
            )
            Slider(value: $magnitudeMillimeters, in: 1...3, step: 1)
            LabeledContent(
                "Gaussian spread",
                value: spreadMillimeters.formatted(.number.precision(.fractionLength(0))) + " mm"
            )
            Slider(value: $spreadMillimeters, in: 8...30, step: 1)
            Picker("Direction", selection: $direction) {
                Text("Outward").tag(SyntheticDeformationDirection.outward)
                Text("Inward").tag(SyntheticDeformationDirection.inward)
            }

            Button("Run Known-Deformation Experiment", action: run)
                .disabled(!canRun || isRunning)

            if isRunning {
                ProgressView()
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let result {
                ForEach(result.strategies) { strategy in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strategy.strategy.displayName)
                            .font(.headline)
                        LabeledContent(
                            "Peak ground truth / recovered",
                            value: "\(millimeters(strategy.metrics.groundTruthPeakMeters)) / \(millimeters(strategy.metrics.recoveredPeakMeters))"
                        )
                        LabeledContent(
                            "Registration attenuation",
                            value: millimeters(strategy.metrics.registrationAttenuationMeters)
                        )
                        LabeledContent(
                            "Stable false RMS",
                            value: millimeters(strategy.metrics.stableFalseDisplacementRMSMeters)
                        )
                    }
                    .font(.caption.monospaced())
                }
            }
        }
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.3f mm", meters * 1_000)
    }
}

private struct ScanStatusRow: View {
    let title: String
    let scan: FaceScan?
    let capture: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                if let scan {
                    Text("\(scan.mesh.vertices.count) vertices · \(scan.timestamp.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not captured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(scan == nil ? "Capture" : "Retake", action: capture)
                .buttonStyle(.bordered)
        }
    }
}

private struct RegistrationSummarySection: View {
    let comparison: FaceComparison
    let baseline: FaceMesh
    let followup: FaceMesh

    var body: some View {
        Section("Research / Developer") {
            NavigationLink("Inspect Registration Comparison") {
                RegistrationDebugView(
                    baseline: baseline,
                    followup: followup,
                    profile: RegistrationProfile.engineeringProfile(
                        for: comparison.studyRegion
                    ),
                    comparison: comparison.registrationComparison
                )
            }

            ForEach(comparison.registrationComparison.strategyResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.strategy.displayName)
                        .font(.headline)
                    if let anchors = result.anchorRegistration {
                        LabeledContent(
                            "Anchor RMS",
                            value: millimeters(anchors.anchorRMSError)
                        )
                    } else {
                        LabeledContent("Anchor RMS", value: "Control — N/A")
                    }
                    LabeledContent(
                        "Stable ROI RMS",
                        value: millimeters(result.stableROIResiduals.rmsResidual)
                    )
                    LabeledContent(
                        "Stable ROI P95",
                        value: millimeters(result.stableROIResiduals.p95AbsoluteResidual)
                    )
                }
                .font(.caption.monospaced())
            }
        }
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.3f mm", meters * 1_000)
    }
}
