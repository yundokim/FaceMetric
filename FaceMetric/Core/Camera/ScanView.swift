import ARKit
import SceneKit
import SwiftUI

struct ScanView: View {
    let scanLabel: String
    let onScanCompleted: ((FaceScan) -> Void)?

    @State private var acquisition = ScanAcquisitionUpdate.initial(
        requiredFrameCount: ScanQualityConfiguration.engineeringDefault.requiredValidFrameCount
    )
    @State private var captureRequestID = 0
    @State private var completedScan: FaceScan?

    init(
        scanLabel: String = "Face Scan",
        onScanCompleted: ((FaceScan) -> Void)? = nil
    ) {
        self.scanLabel = scanLabel
        self.onScanCompleted = onScanCompleted
    }

    var body: some View {
        ZStack {
            FaceTrackingView(
                acquisition: $acquisition,
                completedScan: $completedScan,
                captureRequestID: captureRequestID
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(scanLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                ScanDebugOverlay(acquisition: acquisition)
                Spacer()
                ScanGuidancePanel(
                    acquisition: acquisition,
                    startCapture: startCapture,
                    useCompletedScan: useCompletedScan
                )
            }
            .padding()
        }
        .background(.black)
    }

    private func startCapture() {
        captureRequestID += 1
    }

    private func useCompletedScan() {
        guard let completedScan else { return }
        onScanCompleted?(completedScan)
    }
}

private struct ScanGuidancePanel: View {
    let acquisition: ScanAcquisitionUpdate
    let startCapture: () -> Void
    let useCompletedScan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label(acquisition.guidance.rawValue, systemImage: guidanceSymbol)
                .font(.headline)
                .foregroundStyle(.white)

            if acquisition.phase == .capturing {
                ProgressView(
                    value: Double(acquisition.acceptedFrameCount),
                    total: Double(acquisition.requiredFrameCount)
                )
                .tint(.cyan)
            }

            if acquisition.phase == .capturing || acquisition.phase == .complete {
                Text(
                    "\(acquisition.acceptedFrameCount) accepted · "
                        + "\(acquisition.rejectedFrameCount) rejected"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.secondary)
            }

            if acquisition.phase == .complete {
                Button("Use Completed Scan", action: useCompletedScan)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                Button("Retake", action: startCapture)
                    .buttonStyle(.bordered)
                    .tint(.white)
            } else {
                Button("Start Scan", action: startCapture)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(acquisition.phase == .capturing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var guidanceSymbol: String {
        switch acquisition.guidance {
        case .scanComplete:
            return "checkmark.circle.fill"
        case .capturing:
            return "dot.radiowaves.left.and.right"
        case .holdStill:
            return "hand.raised.fill"
        case .moveCloser, .moveFarther:
            return "arrow.left.and.right"
        case .lookStraightAhead, .centerFace:
            return "viewfinder"
        case .keepNeutralExpression:
            return "face.smiling.inverse"
        case .ready:
            return "circle.inset.filled"
        case .trackingUnavailable:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct ScanDebugOverlay: View {
    let acquisition: ScanAcquisitionUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Acquisition Metrics")
                .font(.headline)

            LabeledContent("State", value: phaseDescription)
            LabeledContent("Vertices", value: acquisition.vertexCount.formatted())

            if let metrics = displayedMetrics {
                LabeledContent(
                    "Metric source",
                    value: acquisition.completedScan == nil
                        ? "Latest frame"
                        : "Accepted-frame median"
                )
                LabeledContent(
                    "Yaw",
                    value: angleWithLimit(
                        metrics.yaw,
                        limit: ScanQualityConfiguration.engineeringDefault.maximumAbsoluteYaw
                    )
                )
                LabeledContent(
                    "Pitch",
                    value: angleWithLimit(
                        metrics.pitch,
                        limit: ScanQualityConfiguration.engineeringDefault.maximumAbsolutePitch
                    )
                )
                LabeledContent(
                    "Roll",
                    value: angleWithTarget(
                        metrics.roll,
                        target: ScanQualityConfiguration.engineeringDefault.targetRoll,
                        tolerance: ScanQualityConfiguration.engineeringDefault.maximumRollDeviation
                    )
                )
                LabeledContent(
                    "Distance",
                    value: distanceWithRange(metrics.distance)
                )
                LabeledContent(
                    "Horizontal center",
                    value: offsetWithLimit(
                        metrics.horizontalOffset,
                        maximum: ScanQualityConfiguration.engineeringDefault.maximumAbsoluteHorizontalOffset
                    )
                )
                LabeledContent(
                    "Vertical center",
                    value: offsetWithLimit(
                        metrics.verticalOffset,
                        maximum: ScanQualityConfiguration.engineeringDefault.maximumAbsoluteVerticalOffset
                    )
                )
                LabeledContent(
                    "Mesh RMS",
                    value: valueWithMaximum(
                        sqrt(metrics.meshVariance),
                        maximum: ScanQualityConfiguration.engineeringDefault.maximumMeshRMS
                    )
                )
                LabeledContent(
                    "Expression Δ",
                    value: String(
                        format: "%.4f / %.4f",
                        metrics.expressionRMSDelta,
                        ScanQualityConfiguration.engineeringDefault.maximumExpressionRMSDelta
                    )
                )
                LabeledContent(
                    "Tracking stable",
                    value: metrics.trackingStable ? "Yes" : "No"
                )
                LabeledContent(
                    "Expression stable",
                    value: metrics.expressionStable ? "Yes" : "No"
                )
            }

            if let scan = acquisition.completedScan {
                Divider()
                LabeledContent(
                    "Scan ID",
                    value: String(scan.id.uuidString.prefix(8))
                )
                LabeledContent(
                    "Representative vertices",
                    value: scan.mesh.vertices.count.formatted()
                )
                LabeledContent(
                    "Aggregation",
                    value: "Coordinate median"
                )
            }

            if !acquisition.rejectionReasons.isEmpty {
                LabeledContent(
                    "Rejected because",
                    value: acquisition.rejectionReasons
                        .map(rejectionDescription)
                        .joined(separator: ", ")
                )
                .foregroundStyle(.yellow)
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 330, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displayedMetrics: ScanQualityMetrics? {
        acquisition.completedScan?.qualityMetrics ?? acquisition.qualityMetrics
    }

    private var phaseDescription: String {
        switch acquisition.phase {
        case .monitoring:
            return "Monitoring"
        case .capturing:
            return "Capturing"
        case .complete:
            return "Complete"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private func degrees(_ radians: Float) -> String {
        String(format: "%.1f°", radians * 180 / .pi)
    }

    private func angleWithLimit(_ radians: Float, limit: Float) -> String {
        "\(degrees(radians)) / ±\(degrees(limit))"
    }

    private func angleWithTarget(
        _ radians: Float,
        target: Float,
        tolerance: Float
    ) -> String {
        "\(degrees(radians)) / \(degrees(target)) ±\(degrees(tolerance))"
    }

    private func distanceWithRange(_ meters: Float) -> String {
        let configuration = ScanQualityConfiguration.engineeringDefault
        return "\(millimeters(meters)) / target \(millimeters(configuration.targetDistance)) · "
            + "\(millimeters(configuration.minimumDistance))–"
            + "\(millimeters(configuration.maximumDistance))"
    }

    private func offsetWithLimit(_ meters: Float, maximum: Float) -> String {
        "\(millimeters(meters)) / ±\(millimeters(maximum))"
    }

    private func valueWithMaximum(_ meters: Float, maximum: Float) -> String {
        "\(millimeters(meters)) / ≤\(millimeters(maximum))"
    }

    private func rejectionDescription(
        _ reason: ScanFrameRejectionReason
    ) -> String {
        switch reason {
        case .trackingLimited:
            return "tracking limited"
        case .trackingUnavailable:
            return "tracking unavailable"
        case .yawOutsideRange:
            return "yaw"
        case .pitchOutsideRange:
            return "pitch"
        case .rollOutsideRange:
            return "roll"
        case .faceOffCenter:
            return "face off center"
        case .tooClose:
            return "too close"
        case .tooFar:
            return "too far"
        case .meshMotion:
            return "mesh motion"
        case .expressionChange:
            return "expression change"
        }
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.2f mm", meters * 1_000)
    }
}

private struct FaceTrackingView: UIViewRepresentable {
    @Binding var acquisition: ScanAcquisitionUpdate
    @Binding var completedScan: FaceScan?
    let captureRequestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            acquisition: $acquisition,
            completedScan: $completedScan
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.scene = SCNScene()
        sceneView.automaticallyUpdatesLighting = true
        sceneView.delegate = context.coordinator

        context.coordinator.startSession(in: sceneView)
        return sceneView
    }

    func updateUIView(_ sceneView: ARSCNView, context: Context) {
        context.coordinator.handleCaptureRequest(captureRequestID)
    }

    static func dismantleUIView(_ sceneView: ARSCNView, coordinator: Coordinator) {
        sceneView.session.pause()
        sceneView.delegate = nil
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        private let acquisition: Binding<ScanAcquisitionUpdate>
        private let completedScan: Binding<FaceScan?>
        private let scanManager: FaceScanManager
        private let frameGateLock = NSLock()
        private var frameProcessingPending = false
        private var lastSubmittedFrameTimestamp = -TimeInterval.infinity
        private var lastCaptureRequestID = 0

        init(
            acquisition: Binding<ScanAcquisitionUpdate>,
            completedScan: Binding<FaceScan?>
        ) {
            self.acquisition = acquisition
            self.completedScan = completedScan
            scanManager = FaceScanManager(
                deviceInformation: Self.deviceInformation()
            )
        }

        func startSession(in sceneView: ARSCNView) {
            guard ARFaceTrackingConfiguration.isSupported else {
                let unavailableUpdate = scanManager.markFaceNotDetected(
                    trackingState: .unavailable
                )

                DispatchQueue.main.async { [weak self] in
                    self?.acquisition.wrappedValue = unavailableUpdate
                }
                return
            }

            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            sceneView.session.run(
                configuration,
                options: [.resetTracking, .removeExistingAnchors]
            )
        }

        func handleCaptureRequest(_ requestID: Int) {
            guard requestID != lastCaptureRequestID else {
                return
            }

            lastCaptureRequestID = requestID
            let captureUpdate = scanManager.beginCapture()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                acquisition.wrappedValue = captureUpdate
                completedScan.wrappedValue = nil
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor,
                  let sceneView = renderer as? ARSCNView,
                  let device = sceneView.device,
                  let geometry = ARSCNFaceGeometry(device: device, fillMesh: false) else {
                return nil
            }

            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemCyan
            material.emission.contents = UIColor.systemCyan
            material.lightingModel = .constant
            material.fillMode = .lines
            material.isDoubleSided = true
            material.transparency = 0.85
            geometry.materials = [material]

            return SCNNode(geometry: geometry)
        }

        func renderer(
            _ renderer: SCNSceneRenderer,
            didUpdate node: SCNNode,
            for anchor: ARAnchor
        ) {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let faceGeometry = node.geometry as? ARSCNFaceGeometry,
                  let sceneView = renderer as? ARSCNView,
                  let frame = sceneView.session.currentFrame else {
                return
            }

            faceGeometry.update(from: faceAnchor.geometry)

            guard reserveFrameProcessing(at: frame.timestamp) else {
                return
            }

            let mesh = FaceMesh(
                vertices: faceAnchor.geometry.vertices,
                triangleIndices: faceAnchor.geometry.triangleIndices
            )
            let blendShapes = Dictionary(
                uniqueKeysWithValues: faceAnchor.blendShapes.map {
                    ($0.key.rawValue, $0.value.floatValue)
                }
            )
            let faceTransform = faceAnchor.transform
            let cameraTransform = frame.camera.transform
            let trackingState = Self.trackingState(from: frame.camera.trackingState)
            let frameTimestamp = frame.timestamp

            DispatchQueue.main.async {
                defer { self.finishFrameProcessing() }

                let update = self.scanManager.processFrame(
                    mesh: mesh,
                    blendShapes: blendShapes,
                    faceTransform: faceTransform,
                    cameraTransform: cameraTransform,
                    trackingState: trackingState,
                    frameTimestamp: frameTimestamp
                )
                self.acquisition.wrappedValue = update

                if let scan = update.completedScan {
                    self.completedScan.wrappedValue = scan
                }
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async {
                var update = self.scanManager.markFaceNotDetected(
                    trackingState: .unavailable
                )
                update = ScanAcquisitionUpdate(
                    phase: .failed(error.localizedDescription),
                    guidance: update.guidance,
                    qualityMetrics: update.qualityMetrics,
                    rejectionReasons: update.rejectionReasons,
                    acceptedFrameCount: update.acceptedFrameCount,
                    requiredFrameCount: update.requiredFrameCount,
                    rejectedFrameCount: update.rejectedFrameCount,
                    vertexCount: update.vertexCount,
                    completedScan: nil
                )
                self.acquisition.wrappedValue = update
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async {
                self.acquisition.wrappedValue = self.scanManager.markFaceNotDetected(
                    trackingState: .limited
                )
            }
        }

        private func reserveFrameProcessing(
            at timestamp: TimeInterval
        ) -> Bool {
            frameGateLock.lock()
            defer { frameGateLock.unlock() }

            let minimumInterval = 1.0 / 30.0
            guard !frameProcessingPending,
                  timestamp - lastSubmittedFrameTimestamp >= minimumInterval else {
                return false
            }

            frameProcessingPending = true
            lastSubmittedFrameTimestamp = timestamp
            return true
        }

        private func finishFrameProcessing() {
            frameGateLock.lock()
            frameProcessingPending = false
            frameGateLock.unlock()
        }

        private static func trackingState(
            from state: ARCamera.TrackingState
        ) -> ScanTrackingState {
            switch state {
            case .normal:
                return .normal
            case .limited:
                return .limited
            case .notAvailable:
                return .unavailable
            }
        }

        private static func deviceInformation() -> ScanDeviceInformation {
            let device = UIDevice.current
            let info = Bundle.main.infoDictionary
            return ScanDeviceInformation(
                model: device.model,
                systemName: device.systemName,
                systemVersion: device.systemVersion,
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "Unknown",
                appBuild: info?["CFBundleVersion"] as? String ?? "Unknown"
            )
        }
    }
}
