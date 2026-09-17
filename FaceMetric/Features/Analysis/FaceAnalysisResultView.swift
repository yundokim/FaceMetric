import SceneKit
import SwiftUI

private struct SavedScanPair: Identifiable {
    let baseline: FaceScan
    let followup: FaceScan

    var id: String {
        baseline.id.uuidString + followup.id.uuidString
    }
}

private struct ScanHistoryGroup: Identifiable {
    let date: Date
    let records: [SavedFaceAnalysis]

    var id: Date { date }
}

struct FaceMetricHomeView: View {
    @State private var savedAnalyses = [SavedFaceAnalysis]()
    @State private var historyGroups = [ScanHistoryGroup]()
    @State private var isPresentingScan = false
    @State private var navigationPath = NavigationPath()
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var isSelectingForComparison = false
    @State private var comparisonSelection = Set<UUID>()
    @State private var comparisonPair: SavedScanPair?
    @State private var pendingDeletion: SavedFaceAnalysis?
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ScanCallToActionSection(
                    isAnalyzing: isAnalyzing,
                    startScan: { isPresentingScan = true }
                )

                if let latest = savedAnalyses.first {
                    LatestAnalysisSection(record: latest)
                }

                CompareScansSection(
                    scanCount: savedAnalyses.count,
                    selectedCount: comparisonSelection.count,
                    isSelecting: isSelectingForComparison,
                    toggleSelectionMode: toggleComparisonMode,
                    compare: compareSelectedScans
                )

                ScanHistorySection(
                    groups: historyGroups,
                    isSelectingForComparison: isSelectingForComparison,
                    selection: comparisonSelection,
                    toggleSelection: toggleSelection,
                    requestDelete: { pendingDeletion = $0 },
                    requestDeleteAll: { isConfirmingDeleteAll = true }
                )
            }
            .navigationTitle("FaceMetric")
            .navigationDestination(for: SavedFaceAnalysis.self) { record in
                FaceAnalysisResultView(record: record) {
                    isPresentingScan = true
                }
            }
            .sheet(isPresented: $isPresentingScan) {
                ScanView(scanLabel: "3D Face Scan") { scan in
                    isPresentingScan = false
                    analyzeAndSave(scan)
                }
            }
            .sheet(item: $comparisonPair) { pair in
                FaceComparisonView(
                    baselineScan: pair.baseline,
                    followupScan: pair.followup
                )
            }
            .task {
                loadArchive()
            }
            .confirmationDialog(
                "Delete this scan?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Scan", role: .destructive) {
                    if let pendingDeletion {
                        delete(pendingDeletion)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the saved scan and its analysis.")
            }
            .confirmationDialog(
                "Delete All Scans?",
                isPresented: $isConfirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive, action: deleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All saved face scans will be permanently deleted. This action cannot be undone.")
            }
            .alert("FaceMetric", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func analyzeAndSave(_ scan: FaceScan) {
        isAnalyzing = true
        let landmarkConfiguration = FaceLandmarkConfigStore.load(mesh: scan.mesh)
        Task {
            do {
                let analysis = try FacialAnalysisEngine().analyze(scan: scan)
                let geometryAnalysis = landmarkConfiguration.isCompleteForMVP
                    ? try? FaceGeometryAnalyzer(configuration: landmarkConfiguration).analyze(scan: scan)
                    : nil
                let record = SavedFaceAnalysis(
                    scan: scan,
                    analysis: analysis,
                    geometryAnalysis: geometryAnalysis
                )
                try FaceAnalysisArchive.save(record)
                savedAnalyses.insert(record, at: 0)
                refreshHistoryGroups()
                navigationPath.append(record)
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    private func loadArchive() {
        Task {
            savedAnalyses = (try? await Task.detached {
                try FaceAnalysisArchive.loadAll()
            }.value) ?? []
            refreshHistoryGroups()
        }
    }

    private func toggleComparisonMode() {
        isSelectingForComparison.toggle()
        comparisonSelection.removeAll()
    }

    private func toggleSelection(_ record: SavedFaceAnalysis) {
        if comparisonSelection.contains(record.id) {
            comparisonSelection.remove(record.id)
        } else if comparisonSelection.count < 2 {
            comparisonSelection.insert(record.id)
        }
    }

    private func compareSelectedScans() {
        let selected = savedAnalyses
            .filter { comparisonSelection.contains($0.id) }
            .sorted { $0.scan.timestamp < $1.scan.timestamp }
        guard selected.count == 2 else { return }
        comparisonPair = SavedScanPair(
            baseline: selected[0].scan,
            followup: selected[1].scan
        )
        isSelectingForComparison = false
        comparisonSelection.removeAll()
    }

    private func delete(_ record: SavedFaceAnalysis) {
        pendingDeletion = nil
        Task {
            do {
                try await Task.detached {
                    try FaceAnalysisArchive.delete(record)
                }.value
                savedAnalyses.removeAll { $0.id == record.id }
                refreshHistoryGroups()
                comparisonSelection.remove(record.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAll() {
        Task {
            do {
                try await Task.detached {
                    try FaceAnalysisArchive.deleteAll()
                }.value
                savedAnalyses.removeAll()
                refreshHistoryGroups()
                comparisonSelection.removeAll()
                isSelectingForComparison = false
                navigationPath = NavigationPath()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshHistoryGroups() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: savedAnalyses) {
            calendar.startOfDay(for: $0.scan.timestamp)
        }
        historyGroups = grouped
            .map { ScanHistoryGroup(date: $0.key, records: $0.value) }
            .sorted { $0.date > $1.date }
    }
}

private struct ScanCallToActionSection: View {
    let isAnalyzing: Bool
    let startScan: () -> Void

    var body: some View {
        Section {
            Button(action: startScan) {
                Label("Start 3D Face Scan", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAnalyzing)

            if isAnalyzing {
                HStack {
                    ProgressView()
                    Text("Calculating 3D measurements…")
                }
            }

            Text("Measurements stay on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LatestAnalysisSection: View {
    let record: SavedFaceAnalysis

    var body: some View {
        Section("Latest Result") {
            NavigationLink(value: record) {
                LatestResultContent(record: record)
            }
        }
    }
}

private struct LatestResultContent: View {
    let record: SavedFaceAnalysis
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    score
                    timestamp
                }
            } else {
                HStack {
                    score
                    timestamp
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var score: some View {
        if let geometry = record.geometryAnalysis {
            ScoreRing(score: Double(geometry.geometryScore.overall), label: "Geometry")
        } else {
            Image(systemName: "scope")
                .font(.title)
                .foregroundStyle(.orange)
                .frame(minWidth: 82, minHeight: 82)
                .accessibilityLabel("Landmark calibration required")
        }
    }

    private var timestamp: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Latest Result")
                .font(.headline)
            RelativeTimestampText(date: record.scan.timestamp)
        }
    }
}

private struct RelativeTimestampText: View {
    let date: Date

    var body: some View {
        if Calendar.current.isDateInToday(date) {
            Text("Today · \(date, format: .dateTime.hour().minute())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if Calendar.current.isDateInYesterday(date) {
            Text("Yesterday · \(date, format: .dateTime.hour().minute())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompareScansSection: View {
    let scanCount: Int
    let selectedCount: Int
    let isSelecting: Bool
    let toggleSelectionMode: () -> Void
    let compare: () -> Void

    var body: some View {
        Section("Compare") {
            if isSelecting {
                Button("Compare Selected Scans (\(selectedCount)/2)", action: compare)
                    .disabled(selectedCount != 2)
                    .frame(minHeight: 44)
                Button("Cancel Comparison", action: toggleSelectionMode)
                    .frame(minHeight: 44)
            } else {
                Button(action: toggleSelectionMode) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Compare Two Scans")
                                .font(.headline)
                            Text("Track changes between two scans")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(scanCount < 2)
                .accessibilityHint("Select two scans from History to compare")
            }
        }
    }
}

private struct ScanHistorySection: View {
    let groups: [ScanHistoryGroup]
    let isSelectingForComparison: Bool
    let selection: Set<UUID>
    let toggleSelection: (SavedFaceAnalysis) -> Void
    let requestDelete: (SavedFaceAnalysis) -> Void
    let requestDeleteAll: () -> Void

    var body: some View {
        if groups.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Scan History",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Complete a scan to save its mesh and measurements.")
                )
            } header: {
                HistoryHeader(
                    canDelete: false,
                    requestDeleteAll: requestDeleteAll
                )
            }
        } else {
            ForEach(groups) { group in
                HistoryDateSection(
                    group: group,
                    showsHistoryHeader: group.id == groups.first?.id,
                    isSelectingForComparison: isSelectingForComparison,
                    selection: selection,
                    toggleSelection: toggleSelection,
                    requestDelete: requestDelete,
                    requestDeleteAll: requestDeleteAll
                )
            }
        }
    }
}

private struct HistoryDateSection: View {
    let group: ScanHistoryGroup
    let showsHistoryHeader: Bool
    let isSelectingForComparison: Bool
    let selection: Set<UUID>
    let toggleSelection: (SavedFaceAnalysis) -> Void
    let requestDelete: (SavedFaceAnalysis) -> Void
    let requestDeleteAll: () -> Void

    var body: some View {
        Section {
            ForEach(group.records) { record in
                ScanHistoryRow(
                    record: record,
                    isSelectingForComparison: isSelectingForComparison,
                    isSelected: selection.contains(record.id),
                    toggleSelection: { toggleSelection(record) },
                    requestDelete: { requestDelete(record) }
                )
            }
        } header: {
            VStack(alignment: .leading, spacing: 10) {
                if showsHistoryHeader {
                    HistoryHeader(
                        canDelete: true,
                        requestDeleteAll: requestDeleteAll
                    )
                }
                HistoryDateHeader(date: group.date)
            }
        }
    }
}

private struct HistoryHeader: View {
    let canDelete: Bool
    let requestDeleteAll: () -> Void

    var body: some View {
        HStack {
            Text("History")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button(role: .destructive, action: requestDeleteAll) {
                    Label("Delete All Scans", systemImage: "trash")
                }
                .disabled(!canDelete)
            } label: {
                Label("History Actions", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("History Actions")
        }
    }
}

private struct HistoryDateHeader: View {
    let date: Date

    var body: some View {
        if Calendar.current.isDateInToday(date) {
            Text("Today")
                .accessibilityAddTraits(.isHeader)
        } else if Calendar.current.isDateInYesterday(date) {
            Text("Yesterday")
                .accessibilityAddTraits(.isHeader)
        } else {
            Text(date, format: .dateTime.month(.abbreviated).day())
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct ScanHistoryRow: View {
    let record: SavedFaceAnalysis
    let isSelectingForComparison: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
    let requestDelete: () -> Void

    var body: some View {
        VStack {
            if isSelectingForComparison {
                Button(action: toggleSelection) {
                    HStack {
                        ScanHistoryRowContent(record: record)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                NavigationLink(value: record) {
                    ScanHistoryRowContent(record: record)
                }
                .swipeActions {
                    Button(role: .destructive, action: requestDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .accessibilityAction(named: "Delete Scan", requestDelete)
            }
        }
    }
}

private struct ScanHistoryRowContent: View {
    let record: SavedFaceAnalysis

    var body: some View {
        LabeledContent {
            if let geometry = record.geometryAnalysis {
                Text(geometry.geometryScore.overall, format: .number.precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
            } else {
                Text("Calibrate")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } label: {
            Text(record.scan.timestamp, format: .dateTime.hour().minute())
                .font(.body)
        }
    }
}

struct FaceAnalysisResultView: View {
    let record: SavedFaceAnalysis
    let retake: () -> Void
    @State private var landmarkConfiguration: FaceLandmarkConfig
    @State private var geometryAnalysis: FaceGeometryAnalysisResult?
    @State private var geometryError: String?
    @State private var isCalibrating = false

    init(record: SavedFaceAnalysis, retake: @escaping () -> Void) {
        self.record = record
        self.retake = retake
        _landmarkConfiguration = State(initialValue: FaceLandmarkConfigStore.load(mesh: record.scan.mesh))
        _geometryAnalysis = State(initialValue: record.geometryAnalysis)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                FaceMeshMeasurementView(
                    mesh: record.scan.mesh,
                    landmarks: calibratedLandmarks,
                    overlays: []
                )
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .bottomTrailing) {
                    Label("Drag to rotate", systemImage: "rotate.3d")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }

                GeometryAnalysisSection(
                    result: geometryAnalysis,
                    error: geometryError,
                    isConfigurationComplete: landmarkConfiguration.isCompleteForMVP,
                    calibrate: { isCalibrating = true }
                )

                if geometryAnalysis != nil {
                    MethodologySection(note: "Geometry metrics use the manually verified ARKit landmark configuration shown above. Directional morphology metrics are not attractiveness scores.")
                }

                Button(action: retake) {
                    Label("Measure Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: landmarkConfiguration) {
            calculateGeometryAnalysis()
        }
        .sheet(isPresented: $isCalibrating) {
            LandmarkCalibrationView(
                mesh: record.scan.mesh,
                configuration: $landmarkConfiguration
            )
        }
    }

    private func calculateGeometryAnalysis() {
        guard landmarkConfiguration.isCompleteForMVP else {
            geometryAnalysis = nil
            geometryError = "Assign every required landmark and ROI using the calibration mode."
            return
        }
        do {
            geometryAnalysis = try FaceGeometryAnalyzer(configuration: landmarkConfiguration).analyze(scan: record.scan)
            geometryError = nil
            if let geometryAnalysis {
                try? FaceAnalysisArchive.save(SavedFaceAnalysis(
                    scan: record.scan,
                    analysis: record.analysis,
                    geometryAnalysis: geometryAnalysis
                ))
            }
        } catch {
            geometryAnalysis = nil
            geometryError = error.localizedDescription
        }
    }

    private var calibratedLandmarks: [FacialLandmark] {
        FaceAnatomicalLandmark.allCases.compactMap { landmark in
            guard let index = landmarkConfiguration.vertexIndex(for: landmark),
                  record.scan.mesh.vertices.indices.contains(index) else { return nil }
            return FacialLandmark(
                id: landmark.rawValue,
                name: landmark.rawValue,
                position: record.scan.mesh.vertices[index]
            )
        }
    }
}

private struct GeometryAnalysisSection: View {
    let result: FaceGeometryAnalysisResult?
    let error: String?
    let isConfigurationComplete: Bool
    let calibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("3D Face Geometry Analysis")
                .font(.title2.bold())

            if let result {
                GeometryScoreSummary(score: result.geometryScore)

                ForEach(FaceGeometryCategory.allCases) { category in
                    GeometryCategorySection(
                        category: category,
                        score: score(for: category, in: result.geometryScore),
                        metrics: result.metrics.values.filter { $0.id.category == category }
                    )
                }
            } else {
                Label(
                    isConfigurationComplete ? "Geometry analysis unavailable" : "Manual ARKit landmark calibration required",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .font(.headline)
                Text(error ?? "Assign verified mesh vertices and ROIs before calculating evidence-based metrics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: calibrate) {
                    Label("Open Calibration Mode", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func score(for category: FaceGeometryCategory, in score: FaceGeometryScore) -> Float {
        switch category {
        case .facial:
            score.facialProportion
        case .symmetry:
            score.symmetry
        case .eyeAndMidface:
            score.eyeAndMidface
        case .lowerFace:
            score.lowerFace
        }
    }
}

private struct GeometryScoreSummary: View {
    let score: FaceGeometryScore

    var body: some View {
        LabeledContent("Geometry Score") {
            Text(score.overall, format: .number.precision(.fractionLength(0)))
                .font(.title.bold().monospacedDigit())
        }
    }
}

private struct GeometryCategorySection: View {
    let category: FaceGeometryCategory
    let score: Float
    let metrics: [FaceGeometryMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text(category.rawValue)
                    .font(.headline)
                Spacer()
                Text(score, format: .number.precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
            }

            ForEach(metrics) { metric in
                GeometryMetricRow(metric: metric)
            }
        }
    }
}

private struct GeometryMetricRow: View {
    let metric: FaceGeometryMetric

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 5) {
                if let reference = metric.referenceText {
                    Text("Reference: \(reference)")
                } else {
                    Text("Reference: no established numeric optimum")
                }
                Text(metric.interpretation)
                Text("Evidence level \(metric.evidenceLevel.rawValue)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } label: {
            HStack {
                Text(metric.id.rawValue)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(metric.value, format: .number.precision(.fractionLength(3)))
                            .monospacedDigit()
                        Text(metric.unit)
                            .foregroundStyle(.secondary)
                    }
                    if let score = metric.componentScore {
                        Text("Score \(score.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }
}

private struct OverallScoreSection: View {
    let overallScore: Double
    let categoryScores: [FacialCategoryScore]

    var body: some View {
        VStack(spacing: 16) {
            Text("Legacy MVP Score")
                .font(.headline)
            Text("Retained for previously saved analyses. This is separate from the calibrated Geometry Score above.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScoreRing(score: overallScore, label: "Overall")
                .scaleEffect(1.35)
                .padding()

            Grid(horizontalSpacing: 24, verticalSpacing: 12) {
                ForEach(categoryScores) { category in
                    GridRow {
                        Text(category.category.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(category.score, format: .number.precision(.fractionLength(0)))
                            .font(.headline.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ScoreRing: View {
    let score: Double
    let label: String
    @ScaledMetric(relativeTo: .title2) private var ringSize: CGFloat = 82

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: score / 100)
                .stroke(.cyan, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score, format: .number.precision(.fractionLength(0)))
                    .font(.title2.bold().monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) score")
        .accessibilityValue(score.formatted(.number.precision(.fractionLength(0))) + " out of 100")
    }
}

private struct MeasurementListSection: View {
    let measurements: [FacialMeasurement]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurements")
                .font(.title2.bold())

            ForEach(measurements) { measurement in
                MeasurementRow(measurement: measurement)
            }
        }
    }
}

private struct MeasurementRow: View {
    let measurement: FacialMeasurement

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(measurement.reference.summary)
                Text(measurement.reference.citation)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(measurement.name)
                    .font(.headline)
                HStack {
                    Text(measurement.formattedValue)
                    Spacer()
                    Text("Score \(measurement.score.formatted(.number.precision(.fractionLength(0))))")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MethodologySection: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to read this result", systemImage: "info.circle")
                .font(.headline)
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct FaceMeshMeasurementView: UIViewRepresentable {
    let mesh: FaceMesh
    let landmarks: [FacialLandmark]
    let overlays: [FacialOverlay]

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .secondarySystemBackground
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let scene = SCNScene()
        let root = SCNNode()
        scene.rootNode.addChildNode(root)
        root.addChildNode(meshNode())
        addOverlays(to: root)

        let bounds = meshBounds()
        let center = (bounds.minimum + bounds.maximum) / 2
        root.simdPosition = -center

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        let size = bounds.maximum - bounds.minimum
        camera.orthographicScale = Double(max(size.x, size.y) * 1.25)
        camera.zNear = 0.001
        camera.zFar = 2
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(0, 0, max(size.z * 4, 0.35))
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 650
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 1_100
        let keyLightNode = SCNNode()
        keyLightNode.light = keyLight
        keyLightNode.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(keyLightNode)

        view.scene = scene
        view.pointOfView = cameraNode
    }

    private func meshNode() -> SCNNode {
        let vertices = mesh.simdVertices.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: vertices)
        let indices = mesh.triangleIndices.map { UInt16(bitPattern: $0) }
        let data = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .triangles,
            primitiveCount: mesh.triangleIndices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.82)
        material.roughness.contents = 0.72
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        let wireframeGeometry = geometry.copy() as? SCNGeometry
        let wireframeMaterial = SCNMaterial()
        wireframeMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.18)
        wireframeMaterial.fillMode = .lines
        wireframeMaterial.isDoubleSided = true
        wireframeGeometry?.materials = [wireframeMaterial]
        if let wireframeGeometry {
            node.addChildNode(SCNNode(geometry: wireframeGeometry))
        }
        return node
    }

    private func meshBounds() -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        guard let first = mesh.simdVertices.first else {
            return (SIMD3<Float>(repeating: -0.1), SIMD3<Float>(repeating: 0.1))
        }

        return mesh.simdVertices.dropFirst().reduce(into: (minimum: first, maximum: first)) { bounds, point in
            bounds.minimum = simd_min(bounds.minimum, point)
            bounds.maximum = simd_max(bounds.maximum, point)
        }
    }

    private func addOverlays(to root: SCNNode) {
        let points = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.id, $0.position.simdValue) })

        for landmark in landmarks {
            let sphere = SCNSphere(radius: 0.0018)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow
            let node = SCNNode(geometry: sphere)
            node.simdPosition = landmark.position.simdValue
            root.addChildNode(node)
        }

        for overlay in overlays {
            let overlayPoints = overlay.landmarkIDs.compactMap { points[$0] }
            for pair in zip(overlayPoints, overlayPoints.dropFirst()) {
                root.addChildNode(lineNode(from: pair.0, to: pair.1))
            }
        }
    }

    private func lineNode(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SCNNode {
        let direction = end - start
        let length = simd_length(direction)
        let cylinder = SCNCylinder(radius: 0.0007, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemOrange
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (start + end) / 2
        if length > .ulpOfOne {
            node.simdOrientation = simd_quatf(
                from: SIMD3<Float>(0, 1, 0),
                to: simd_normalize(direction)
            )
        }
        return node
    }
}
