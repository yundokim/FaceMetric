import SwiftUI

struct FaceComparisonView: View {
    private enum ScanRole: String, Identifiable {
        case baseline
        case followup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .baseline:
                return "Baseline Scan"
            case .followup:
                return "Follow-up Scan"
            }
        }
    }

    @State private var baselineScan: FaceScan?
    @State private var followupScan: FaceScan?
    @State private var activeScanRole: ScanRole?
    @State private var comparison: FaceComparison?
    @State private var registrationError: String?
    @State private var isRegistering = false

    var body: some View {
        NavigationStack {
            List {
                Section("Scans") {
                    scanRow(
                        title: "Baseline",
                        scan: baselineScan,
                        action: { activeScanRole = .baseline }
                    )
                    scanRow(
                        title: "Follow-up",
                        scan: followupScan,
                        action: { activeScanRole = .followup }
                    )
                }

                Section("Rigid registration") {
                    Text("The follow-up mesh is rigidly aligned to the baseline mesh. No vertex deformation is applied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        registerScans()
                    } label: {
                        if isRegistering {
                            ProgressView()
                        } else {
                            Label("Run Registration", systemImage: "square.3.layers.3d")
                        }
                    }
                    .disabled(baselineScan == nil || followupScan == nil || isRegistering)

                    if let registrationError {
                        Text(registrationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let comparison, let baselineScan, let followupScan {
                    let registrationResult = comparison.registrationResult
                    Section("Research / Developer") {
                        NavigationLink("Inspect Registration") {
                            RegistrationDebugView(
                                baseline: baselineScan.mesh,
                                followup: followupScan.mesh,
                                result: registrationResult
                            )
                        }

                        LabeledContent(
                            "Registration RMS",
                            value: millimeters(registrationResult.rmsError)
                        )
                        LabeledContent(
                            "Correspondences",
                            value: registrationResult.correspondenceCount.formatted()
                        )
                        LabeledContent(
                            "Iterations",
                            value: registrationResult.iterationCount.formatted()
                        )
                        LabeledContent(
                            "Status",
                            value: registrationResult.quality.rawValue
                        )
                    }
                }
            }
            .navigationTitle("FaceMetric Research")
            .sheet(item: $activeScanRole) { role in
                ScanView(scanLabel: role.title) { scan in
                    switch role {
                    case .baseline:
                        baselineScan = scan
                    case .followup:
                        followupScan = scan
                    }
                    comparison = nil
                    registrationError = nil
                    activeScanRole = nil
                }
            }
        }
    }

    private func scanRow(
        title: String,
        scan: FaceScan?,
        action: @escaping () -> Void
    ) -> some View {
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

            Button(scan == nil ? "Capture" : "Retake", action: action)
                .buttonStyle(.bordered)
        }
    }

    private func registerScans() {
        guard let baselineScan, let followupScan else { return }

        isRegistering = true
        comparison = nil
        registrationError = nil

        Task {
            do {
                let result = try await Task.detached {
                    try FaceRegistrationEngine().register(
                        baseline: baselineScan.mesh,
                        followup: followupScan.mesh
                    )
                }.value
                comparison = FaceComparison(
                    baselineScanID: baselineScan.id,
                    followupScanID: followupScan.id,
                    registrationResult: result
                )
            } catch {
                registrationError = String(describing: error)
            }
            isRegistering = false
        }
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.3f mm", meters * 1_000)
    }
}
