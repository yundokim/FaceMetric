import SceneKit
import SwiftUI

private enum FMTab {
    case timeline
    case trends
}

private enum TimelineDensity: Int, CaseIterable {
    case years = 6
    case months = 3
    case detail = 1

    var columns: Int { rawValue }
    var spacing: CGFloat {
        switch self {
        case .years: 2
        case .months: 5
        case .detail: 16
        }
    }
}

private struct TimelineScan: Identifiable, Hashable {
    let id: Int
    let month: String
    let date: String
    let relativeLabel: String
    let treatment: String?
    let tone: Double
}

private let sampleScans: [TimelineScan] = [
    .init(id: 1, month: "September 2026", date: "Sep 18", relativeLabel: "Day 30", treatment: nil, tone: 0.02),
    .init(id: 2, month: "September 2026", date: "Sep 11", relativeLabel: "Day 23", treatment: nil, tone: 0.08),
    .init(id: 3, month: "September 2026", date: "Sep 4", relativeLabel: "Day 16", treatment: nil, tone: 0.14),
    .init(id: 4, month: "August 2026", date: "Aug 29", relativeLabel: "Day 10", treatment: nil, tone: 0.18),
    .init(id: 5, month: "August 2026", date: "Aug 26", relativeLabel: "Day 7", treatment: nil, tone: 0.22),
    .init(id: 6, month: "August 2026", date: "Aug 19", relativeLabel: "Baseline", treatment: "Masseter Botox", tone: 0.29),
    .init(id: 7, month: "July 2026", date: "Jul 22", relativeLabel: "Check-in", treatment: nil, tone: 0.35),
    .init(id: 8, month: "July 2026", date: "Jul 8", relativeLabel: "Check-in", treatment: nil, tone: 0.4),
    .init(id: 9, month: "June 2026", date: "Jun 20", relativeLabel: "Day 30", treatment: nil, tone: 0.47),
    .init(id: 10, month: "June 2026", date: "Jun 5", relativeLabel: "Day 14", treatment: nil, tone: 0.52),
    .init(id: 11, month: "May 2026", date: "May 22", relativeLabel: "Baseline", treatment: "Gua sha routine", tone: 0.57),
    .init(id: 12, month: "April 2026", date: "Apr 14", relativeLabel: "Check-in", treatment: nil, tone: 0.62),
    .init(id: 13, month: "March 2026", date: "Mar 12", relativeLabel: "Check-in", treatment: nil, tone: 0.67),
    .init(id: 14, month: "February 2026", date: "Feb 8", relativeLabel: "Check-in", treatment: nil, tone: 0.71),
    .init(id: 15, month: "January 2026", date: "Jan 5", relativeLabel: "First scan", treatment: nil, tone: 0.76),
    .init(id: 16, month: "December 2025", date: "Dec 3", relativeLabel: "Check-in", treatment: nil, tone: 0.8),
    .init(id: 17, month: "November 2025", date: "Nov 5", relativeLabel: "Check-in", treatment: nil, tone: 0.85),
    .init(id: 18, month: "October 2025", date: "Oct 2", relativeLabel: "First scan", treatment: nil, tone: 0.9)
]

struct FaceMetricExperienceView: View {
    @State private var selectedTab = FMTab.timeline
    @State private var isShowingScan = false
    @State private var isShowingProfile = false
    @State private var savedAnalyses = [SavedFaceAnalysis]()
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .timeline:
                    TimelineView(
                        records: savedAnalyses,
                        showProfile: { isShowingProfile = true },
                        startScan: { isShowingScan = true }
                    )
                case .trends:
                    TrendsOverviewView(
                        records: savedAnalyses,
                        showProfile: { isShowingProfile = true }
                    )
                }
            }
            .safeAreaPadding(.bottom, 78)

            FaceMetricTabBar(
                selectedTab: $selectedTab,
                startScan: { isShowingScan = true }
            )
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $isShowingScan) {
            ScanView(scanLabel: "3D Face Scan") { scan in
                isShowingScan = false
                analyzeAndSave(scan)
            }
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfileView()
        }
        .tint(FMStyle.accent)
        .task { await loadArchive() }
        .overlay {
            if isAnalyzing {
                AnalysisProgressOverlay()
            }
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

    private func loadArchive() async {
        savedAnalyses = (try? await Task.detached {
            try FaceAnalysisArchive.loadAll()
        }.value) ?? []
    }

    private func analyzeAndSave(_ scan: FaceScan) {
        isAnalyzing = true
        Task {
            do {
                let analysis = try FacialAnalysisEngine().analyze(scan: scan)
                let configuration = FaceLandmarkConfigStore.load(mesh: scan.mesh)
                let geometryAnalysis = configuration.isCompleteForMVP
                    ? try? FaceGeometryAnalyzer(configuration: configuration).analyze(scan: scan)
                    : nil
                let record = SavedFaceAnalysis(
                    scan: scan,
                    analysis: analysis,
                    geometryAnalysis: geometryAnalysis
                )
                try FaceAnalysisArchive.save(record)
                savedAnalyses.insert(record, at: 0)
                selectedTab = .timeline
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}

private struct AnalysisProgressOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(FMStyle.accent)
            Text("Calculating your measurements…")
                .font(.headline)
            Text("Your scan is saved automatically when analysis finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
        .padding(32)
    }
}

private struct FaceMetricTabBar: View {
    @Binding var selectedTab: FMTab
    let startScan: () -> Void

    var body: some View {
        HStack {
            TabButton(
                title: "Timeline",
                systemImage: "square.grid.2x2",
                isSelected: selectedTab == .timeline,
                action: { selectedTab = .timeline }
            )
            Spacer()
            Button(action: startScan) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(FMStyle.accent)
                            .frame(width: 58, height: 58)
                            .shadow(color: FMStyle.accent.opacity(0.28), radius: 12, y: 5)
                        Image(systemName: "viewfinder")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Scan")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan my face today")
            .offset(y: -13)
            Spacer()
            TabButton(
                title: "Trends",
                systemImage: "chart.xyaxis.line",
                isSelected: selectedTab == .trends,
                action: { selectedTab = .trends }
            )
        }
        .padding(.horizontal, 44)
        .padding(.top, 10)
        .frame(height: 78)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct TabButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? FMStyle.accent : Color.secondary)
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}

private struct TimelineView: View {
    let records: [SavedFaceAnalysis]
    let showProfile: () -> Void
    let startScan: () -> Void
    @State private var density = TimelineDensity.months
    @State private var gestureStartDensity = TimelineDensity.months

    var body: some View {
        NavigationStack {
            ScrollView {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("No scans yet", systemImage: "viewfinder")
                    } description: {
                        Text("Record your first 3D face scan to begin your personal timeline.")
                    } actions: {
                        Button("Start First Scan", action: startScan)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 100)
                } else {
                    TimelineGrid(records: records, density: density, startScan: startScan)
                        .animation(.snappy(duration: 0.32), value: density)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Zoomed out", systemImage: "square.grid.3x3") { density = .years }
                        Button("Default", systemImage: "square.grid.2x2") { density = .months }
                        Button("Zoomed in", systemImage: "rectangle.grid.1x2") { density = .detail }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    ProfileButton(action: showProfile)
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let scale = value.magnification
                        if scale > 1.18 {
                            density = zoomedIn(from: gestureStartDensity)
                        } else if scale < 0.82 {
                            density = zoomedOut(from: gestureStartDensity)
                        }
                    }
                    .onEnded { _ in gestureStartDensity = density }
            )
        }
    }

    private func zoomedIn(from level: TimelineDensity) -> TimelineDensity {
        switch level {
        case .years: .months
        case .months, .detail: .detail
        }
    }

    private func zoomedOut(from level: TimelineDensity) -> TimelineDensity {
        switch level {
        case .years, .months: .years
        case .detail: .months
        }
    }
}

private struct TimelineGrid: View {
    let records: [SavedFaceAnalysis]
    let density: TimelineDensity
    let startScan: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: density == .years ? 22 : 28) {
            ForEach(groupedScans) { group in
                VStack(alignment: .leading, spacing: density == .years ? 6 : 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.date, format: density == .years ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.wide).year())
                            .font(density == .detail ? .title2.bold() : .headline)
                        Spacer()
                        if density != .years {
                            Text("\(group.records.count) scans")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, density == .years ? 8 : 16)

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: density.spacing),
                            count: density.columns
                        ),
                        spacing: density.spacing
                    ) {
                        ForEach(group.records) { record in
                            NavigationLink(value: record) {
                                ScanThumbnail(record: record, density: density)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, density == .years ? 2 : 0)
                }
            }
        }
        .padding(.vertical, 10)
        .navigationDestination(for: SavedFaceAnalysis.self) { record in
            FaceAnalysisResultView(record: record, retake: startScan)
                .toolbar {
                    if let baseline = previousRecord(before: record) {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                FaceComparisonView(
                                    baselineScan: baseline.scan,
                                    followupScan: record.scan
                                )
                            } label: {
                                Label("Compare", systemImage: "square.split.2x1")
                            }
                        }
                    }
                }
        }
    }

    private var groupedScans: [ScanGroup] {
        var groups: [ScanGroup] = []
        let calendar = Calendar.current
        for record in records {
            let components = calendar.dateComponents([.year, .month], from: record.scan.timestamp)
            let date = calendar.date(from: components) ?? record.scan.timestamp
            if let index = groups.firstIndex(where: { $0.date == date }) {
                groups[index].records.append(record)
            } else {
                groups.append(ScanGroup(date: date, records: [record]))
            }
        }
        return groups
    }

    private func previousRecord(before record: SavedFaceAnalysis) -> SavedFaceAnalysis? {
        let chronological = records.sorted { $0.scan.timestamp < $1.scan.timestamp }
        guard let index = chronological.firstIndex(where: { $0.id == record.id }), index > 0 else {
            return nil
        }
        return chronological[index - 1]
    }
}

private struct ScanGroup: Identifiable {
    let date: Date
    var records: [SavedFaceAnalysis]
    var id: Date { date }
}

private struct ScanThumbnail: View {
    let record: SavedFaceAnalysis
    let density: TimelineDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FaceMeshThumbnailView(mesh: record.scan.mesh)
                .aspectRatio(density == .detail ? 1.12 : 0.82, contentMode: .fit)
                .clipShape(density == .detail ? AnyShape(RoundedRectangle(cornerRadius: 20)) : AnyShape(Rectangle()))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(FMStyle.accent)
                        .padding(9)
                }

            if density == .detail {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.scan.timestamp, format: .dateTime.weekday(.wide))
                            .font(.headline)
                        Text(record.scan.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(record.scan.acquisitionMetadata.acceptedFrameCount) frames")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct FacePortrait: View {
    let tone: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hue: 0.57, saturation: 0.08, brightness: 0.96 - tone * 0.06)
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.08, saturation: 0.17, brightness: 0.98 - tone * 0.05),
                                Color(hue: 0.06, saturation: 0.23, brightness: 0.82 - tone * 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 0.78)
                    .overlay {
                        FaceLineArt()
                            .stroke(.white.opacity(0.54), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                            .padding(proxy.size.width * 0.18)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
                Ellipse()
                    .fill(.white.opacity(0.16))
                    .frame(width: proxy.size.width * 0.24, height: proxy.size.height * 0.58)
                    .blur(radius: 12)
                    .offset(x: -proxy.size.width * 0.11)
            }
        }
        .accessibilityLabel("Standardized 3D facial scan")
    }
}

private struct FaceMeshThumbnailView: UIViewRepresentable {
    let mesh: FaceMesh

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor.secondarySystemBackground
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        view.scene = makeScene()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let vertices = mesh.simdVertices
        guard let first = vertices.first else { return scene }

        let bounds = vertices.dropFirst().reduce(
            into: (minimum: first, maximum: first)
        ) { bounds, point in
            bounds.minimum = simd_min(bounds.minimum, point)
            bounds.maximum = simd_max(bounds.maximum, point)
        }
        let center = (bounds.minimum + bounds.maximum) / 2
        let vertexSource = SCNGeometrySource(vertices: vertices.map(SCNVector3.init))
        let indices = mesh.triangleIndices.map(UInt16.init(bitPattern:))
        let element = SCNGeometryElement(
            data: indices.withUnsafeBytes { Data($0) },
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.42, green: 0.72, blue: 0.70, alpha: 1)
        material.metalness.contents = 0.08
        material.roughness.contents = 0.64
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.simdPosition = -center
        scene.rootNode.addChildNode(node)

        let size = bounds.maximum - bounds.minimum
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(size.x, size.y) * 1.18)
        camera.zNear = 0.001
        camera.zFar = 2
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(0, 0, max(size.z * 5, 0.35))
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }
}

private struct FaceLineArt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.23))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18),
            control1: CGPoint(x: rect.midX - rect.width * 0.07, y: rect.midY),
            control2: CGPoint(x: rect.midX + rect.width * 0.09, y: rect.midY)
        )
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY * 0.9))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.midY * 0.9),
            control: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.midY * 0.82)
        )
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.midY * 0.9))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY * 0.9),
            control: CGPoint(x: rect.maxX - rect.width * 0.34, y: rect.midY * 0.82)
        )
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.17, y: rect.maxY * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + rect.width * 0.17, y: rect.maxY * 0.72),
            control: CGPoint(x: rect.midX, y: rect.maxY * 0.78)
        )
        return path
    }
}

private struct ProfileButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel("Profile")
    }
}

private struct ScanExperienceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0
    @State private var progress = 0.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if phase == 2 {
                    ScanCompletedView(done: { dismiss() })
                } else {
                    GuidedScanView(
                        isScanning: phase == 1,
                        progress: progress,
                        start: beginScan
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func beginScan() {
        phase = 1
        progress = 0.08
        Task {
            for value in 1...12 {
                try? await Task.sleep(for: .milliseconds(130))
                progress = Double(value) / 12
            }
            phase = 2
        }
    }
}

private struct GuidedScanView: View {
    let isScanning: Bool
    let progress: Double
    let start: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(isScanning ? "Hold still" : "Position your face")
                    .font(.title2.bold())
                Text(isScanning ? "We’re capturing your face from every angle." : "Keep a neutral expression and fit your face in the guide.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)

            Spacer()
            ZStack {
                FacePortrait(tone: 0.22)
                    .frame(width: 270, height: 350)
                    .clipShape(Ellipse())
                    .opacity(0.88)
                Ellipse()
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                    .frame(width: 272, height: 354)
                if isScanning {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(FMStyle.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 312, height: 312)
                        .rotationEffect(.degrees(-90))
                }
            }
            Spacer()

            if isScanning {
                VStack(spacing: 12) {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.monospacedDigit().bold())
                    ProgressView(value: progress)
                        .tint(FMStyle.accent)
                        .frame(maxWidth: 240)
                }
                .padding(.bottom, 42)
            } else {
                Button(action: start) {
                    Text("Start Scan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(FMStyle.accent)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            Label("Processed privately on this iPhone", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
    }
}

private struct ScanCompletedView: View {
    let done: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(FMStyle.accent.opacity(0.16))
                    .frame(width: 116, height: 116)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(FMStyle.accent)
            }
            Text("Scan complete")
                .font(.largeTitle.bold())
            Text("Your 3D scan and measurements have been saved to Timeline.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 42)
            VStack(spacing: 0) {
                CompletionRow(icon: "face.smiling.inverse", title: "3D face captured")
                Divider().overlay(.white.opacity(0.12))
                CompletionRow(icon: "ruler", title: "12 measurements recorded")
                Divider().overlay(.white.opacity(0.12))
                CompletionRow(icon: "lock.fill", title: "Stored on this iPhone")
            }
            .padding(.horizontal, 18)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 28)
            Spacer()
            Button(action: done) {
                Text("View in Timeline")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(FMStyle.accent)
            .padding(28)
        }
        .foregroundStyle(.white)
    }
}

private struct CompletionRow: View {
    let icon: String
    let title: LocalizedStringKey

    var body: some View {
        Label(title, systemImage: icon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 15)
    }
}

private struct ScanDetailView: View {
    let scan: TimelineScan

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                FacePortrait(tone: scan.tone)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .overlay(alignment: .bottomLeading) {
                        Label("Drag to explore 3D", systemImage: "rotate.3d")
                            .font(.caption.weight(.medium))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(14)
                    }
                ScanDetailSummary(scan: scan)
                RawMeasurementSection()
                NavigationLink {
                    BeforeAfterCompareView()
                } label: {
                    Label("Compare with another scan", systemImage: "square.split.2x1")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .navigationTitle(scan.date)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScanDetailSummary: View {
    let scan: TimelineScan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.relativeLabel).font(.title2.bold())
                    Text("Captured at 9:41 AM").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(FMStyle.accent)
                    .font(.title2)
            }
            if let treatment = scan.treatment {
                Label(treatment, systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FMStyle.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RawMeasurementSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Measurements").font(.title3.bold())
                Spacer()
                Text("Recorded data").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            MeasurementRow(name: "Jaw Width", value: "121.4 mm", change: "−0.8 mm")
            MeasurementRow(name: "Cheek Projection", value: "18.2 mm", change: "+0.2 mm")
            MeasurementRow(name: "Face Width / Height", value: "0.76", change: "−0.01")
        }
    }
}

private struct MeasurementRow: View {
    let name: String
    let value: String
    let change: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.body.monospacedDigit().weight(.semibold))
                Text(change).font(.caption.monospacedDigit()).foregroundStyle(FMStyle.accent)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct TrendsOverviewView: View {
    let records: [SavedFaceAnalysis]
    let showProfile: () -> Void
    @State private var range = "1M"

    var body: some View {
        NavigationStack {
            ScrollView {
                if let latest = records.first {
                    VStack(spacing: 28) {
                        TrendHero(records: records, range: $range)
                        SectionHeading(title: "Analysis dimensions", subtitle: "Scores traced to your recorded measurements")
                        VStack(spacing: 0) {
                            ForEach(latest.analysis.categoryScores) { categoryScore in
                                NavigationLink {
                                    RealDimensionDetailView(
                                        category: categoryScore.category,
                                        records: records
                                    )
                                } label: {
                                    DimensionScoreRow(
                                        category: categoryScore.category,
                                        score: categoryScore.score,
                                        change: categoryChange(for: categoryScore.category)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                        SectionHeading(title: "Recent measurements", subtitle: "Physical values from your 3D scans")
                        VStack(spacing: 0) {
                            ForEach(latest.analysis.measurements.prefix(4)) { measurement in
                                NavigationLink {
                                    RealMeasurementDetailView(measurement: measurement, records: records)
                                } label: {
                                    MeasurementRow(
                                        name: measurement.name,
                                        value: measurement.formattedValue,
                                        change: measurementChange(for: measurement)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(16)
                } else {
                    ContentUnavailableView(
                        "No trend data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Complete at least one scan to see measurements. Two or more scans reveal change over time.")
                    )
                    .padding(.top, 120)
                }
            }
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileButton(action: showProfile)
                }
            }
        }
    }

    private func categoryChange(for category: FacialScoreCategory) -> Double? {
        guard
            let latest = records.first?.analysis.categoryScores.first(where: { $0.category == category }),
            let oldest = records.last?.analysis.categoryScores.first(where: { $0.category == category }),
            records.count > 1
        else { return nil }
        return latest.score - oldest.score
    }

    private func measurementChange(for measurement: FacialMeasurement) -> String {
        guard
            let oldest = records.last?.analysis.measurements.first(where: { $0.id == measurement.id }),
            records.count > 1
        else { return "Baseline" }
        let change = measurement.value - oldest.value
        let suffix = measurement.unit == .ratio ? "" : " \(measurement.unit.rawValue)"
        return change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + suffix
    }
}

private struct TrendHero: View {
    let records: [SavedFaceAnalysis]
    @Binding var range: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CAT LOOK").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(latestScore, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                        Text(changeText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FMStyle.accent)
                    }
                }
            }
            RangePicker(selection: $range)
            TrendLine(values: normalizedScores)
                .frame(height: 150)
            HStack {
                if let oldest = records.last {
                    Text(oldest.scan.timestamp, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Today").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var latestScore: Double { records.first?.analysis.overallScore ?? 0 }

    private var changeText: String {
        guard let oldest = records.last, records.count > 1 else { return "Baseline" }
        let value = latestScore - oldest.analysis.overallScore
        return value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))) + " since first scan"
    }

    private var normalizedScores: [CGFloat] {
        let values = records.reversed().map { CGFloat($0.analysis.overallScore / 100) }
        return values.count == 1 ? [values[0], values[0]] : values
    }
}

private struct RangePicker: View {
    @Binding var selection: String
    private let ranges = ["1M", "3M", "6M", "1Y", "All"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ranges, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(item)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selection == item ? Color(.tertiarySystemFill) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }
}

private struct TrendLine: View {
    let values: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack {
                    Divider()
                    Spacer()
                    Divider()
                    Spacer()
                    Divider()
                }
                .opacity(0.45)
                Path { path in
                    guard values.count > 1 else { return }
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) / CGFloat(values.count - 1) * proxy.size.width
                        let y = proxy.size.height * (1 - value)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(FMStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(FMStyle.accent)
                    .frame(width: 9, height: 9)
                    .position(x: proxy.size.width * 0.19, y: proxy.size.height * 0.71)
            }
        }
        .accessibilityLabel("Score increased 4.2 points over 30 days")
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, -16)
    }
}

private struct DimensionLink: View {
    let name: String
    let score: String
    let change: String
    let icon: String

    var body: some View {
        NavigationLink {
            DimensionDetailView(name: name, score: score, change: change)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(FMStyle.accent)
                    .background(FMStyle.accent.opacity(0.1), in: Circle())
                Text(name)
                Spacer()
                Text(score).font(.headline.monospacedDigit())
                Text(change).font(.caption.monospacedDigit()).foregroundStyle(FMStyle.accent).frame(width: 38)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Divider().padding(.leading, 46) }
        }
        .buttonStyle(.plain)
    }
}

private struct DimensionScoreRow: View {
    let category: FacialScoreCategory
    let score: Double
    let change: Double?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .foregroundStyle(FMStyle.accent)
                .background(FMStyle.accent.opacity(0.1), in: Circle())
            Text(category.rawValue)
            Spacer()
            Text(score, format: .number.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
            Text(changeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(FMStyle.accent)
                .frame(width: 46)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 46) }
    }

    private var changeText: String {
        guard let change else { return "—" }
        return change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))
    }

    private var symbol: String {
        switch category {
        case .balance: "circle.lefthalf.filled"
        case .proportion: "rectangle.split.2x1"
        case .symmetry: "arrow.left.and.right"
        case .profile: "person.crop.circle"
        }
    }
}

private struct RealDimensionDetailView: View {
    let category: FacialScoreCategory
    let records: [SavedFaceAnalysis]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 4) {
                    Text(latestScore, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                    Text(changeText)
                        .foregroundStyle(FMStyle.accent)
                        .font(.headline)
                    Text("Measurement-derived score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TrendLine(values: scoreSeries)
                    .frame(height: 180)
                Text("This score is calculated from the raw 3D measurements listed below. It is not a beauty or medical rating.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                SectionHeading(title: "Underlying measurements", subtitle: "Recorded values used by this dimension")
                VStack(spacing: 0) {
                    ForEach(latestMeasurements) { measurement in
                        NavigationLink {
                            RealMeasurementDetailView(measurement: measurement, records: records)
                        } label: {
                            MeasurementRow(
                                name: measurement.name,
                                value: measurement.formattedValue,
                                change: measurementChange(for: measurement)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var latestScore: Double {
        records.first?.analysis.categoryScores.first(where: { $0.category == category })?.score ?? 0
    }

    private var changeText: String {
        guard
            let oldest = records.last?.analysis.categoryScores.first(where: { $0.category == category }),
            records.count > 1
        else { return "Baseline" }
        let change = latestScore - oldest.score
        return change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))) + " since first scan"
    }

    private var scoreSeries: [CGFloat] {
        let values = records.reversed().compactMap { record in
            record.analysis.categoryScores.first(where: { $0.category == category }).map {
                CGFloat($0.score / 100)
            }
        }
        return values.count == 1 ? [values[0], values[0]] : values
    }

    private var latestMeasurements: [FacialMeasurement] {
        records.first?.analysis.measurements.filter { $0.category == category } ?? []
    }

    private func measurementChange(for measurement: FacialMeasurement) -> String {
        guard
            let oldest = records.last?.analysis.measurements.first(where: { $0.id == measurement.id }),
            records.count > 1
        else { return "Baseline" }
        return (measurement.value - oldest.value)
            .formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }
}

private struct RealMeasurementDetailView: View {
    let measurement: FacialMeasurement
    let records: [SavedFaceAnalysis]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(measurement.formattedValue)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(changeText)
                        .font(.headline)
                        .foregroundStyle(FMStyle.accent)
                    if let date = records.first?.scan.timestamp {
                        Text(date, format: .dateTime.day().month(.wide).year())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                TrendLine(values: normalizedValues)
                    .frame(height: 190)
                Text(measurement.reference.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                SectionHeading(title: "Recorded points", subtitle: "Physical measurements, not aesthetic scores")
                ForEach(points) { point in
                    HStack {
                        Text(point.date, format: .dateTime.month(.abbreviated).day())
                        Spacer()
                        Text(point.valueText)
                            .font(.headline.monospacedDigit())
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
        .navigationTitle(measurement.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var points: [MeasurementHistoryPoint] {
        records.reversed().compactMap { record in
            guard let value = record.analysis.measurements.first(where: { $0.id == measurement.id }) else {
                return nil
            }
            return MeasurementHistoryPoint(date: record.scan.timestamp, measurement: value)
        }
    }

    private var normalizedValues: [CGFloat] {
        let rawValues = points.map { $0.measurement.value }
        guard let minimum = rawValues.min(), let maximum = rawValues.max() else { return [] }
        let span = max(maximum - minimum, 0.000_001)
        let values = rawValues.map { CGFloat(0.2 + (($0 - minimum) / span) * 0.6) }
        return values.count == 1 ? [values[0], values[0]] : values
    }

    private var changeText: String {
        guard let first = points.first, points.count > 1 else { return "Baseline measurement" }
        let change = measurement.value - first.measurement.value
        let suffix = measurement.unit == .ratio ? "" : " \(measurement.unit.rawValue)"
        return change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + suffix + " since first scan"
    }
}

private struct MeasurementHistoryPoint: Identifiable {
    let date: Date
    let measurement: FacialMeasurement
    var id: Date { date }
    var valueText: String { measurement.formattedValue }
}

private struct DimensionDetailView: View {
    let name: String
    let score: String
    let change: String

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 4) {
                    Text(score).font(.system(size: 60, weight: .bold, design: .rounded))
                    Text("\(change) over 30 days").foregroundStyle(FMStyle.accent).font(.headline)
                    Text("Cat Look interpretation").font(.caption).foregroundStyle(.secondary)
                }
                TrendLine(values: [0.28, 0.34, 0.32, 0.47, 0.51, 0.61, 0.69])
                    .frame(height: 180)
                Text("This score interprets your recorded measurements against your selected look. It is not a beauty or health rating.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                SectionHeading(title: "Underlying measurements", subtitle: "The physical data behind this score")
                NavigationLink {
                    MeasurementDetailView()
                } label: {
                    MeasurementRow(name: "Jaw Width", value: "121.4 mm", change: "−2.7 mm")
                }
                .buttonStyle(.plain)
                MeasurementRow(name: "Lower-face Taper", value: "0.82", change: "+0.02")
            }
            .padding(20)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MeasurementDetailView: View {
    @State private var range = "3M"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("121.4 mm").font(.system(size: 46, weight: .bold, design: .rounded))
                    Text("−2.7 mm since baseline").font(.headline).foregroundStyle(FMStyle.accent)
                    Text("Measured 18 Sep 2026").font(.subheadline).foregroundStyle(.secondary)
                }
                RangePicker(selection: $range)
                TrendLine(values: [0.76, 0.69, 0.61, 0.5, 0.42, 0.31, 0.23])
                    .frame(height: 190)
                TreatmentEventCard()
                SectionHeading(title: "Recorded points", subtitle: "Measurements, not aesthetic scores")
                MeasurementPoint(label: "Baseline", date: "Aug 19", value: "124.1 mm")
                MeasurementPoint(label: "Day 14", date: "Sep 2", value: "122.8 mm")
                MeasurementPoint(label: "Day 30", date: "Sep 18", value: "121.4 mm")
            }
            .padding(20)
        }
        .navigationTitle("Jaw Width")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TreatmentEventCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .foregroundStyle(FMStyle.accent)
                .frame(width: 38, height: 38)
                .background(FMStyle.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Masseter Botox").font(.headline)
                Text("Aug 19 · Treatment marker").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MeasurementPoint: View {
    let label: String
    let date: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label).font(.headline)
                Text(date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.headline.monospacedDigit())
        }
        .padding(.vertical, 8)
    }
}

private struct BeforeAfterCompareView: View {
    @State private var showingAfter = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Picker("Scan", selection: $showingAfter) {
                    Text("Aug 19").tag(false)
                    Text("Sep 18").tag(true)
                }
                .pickerStyle(.segmented)
                ZStack {
                    FacePortrait(tone: showingAfter ? 0.02 : 0.29)
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(FMStyle.accent.opacity(0.5), lineWidth: 1)
                }
                .animation(.easeInOut(duration: 0.25), value: showingAfter)
                HStack {
                    ComparisonStat(title: "Jaw Width", value: "−2.7 mm")
                    Divider().frame(height: 42)
                    ComparisonStat(title: "Projection", value: "+0.6 mm")
                    Divider().frame(height: 42)
                    ComparisonStat(title: "30 days", value: "2 scans")
                }
                Text("Surface differences are aligned to stable facial regions. Treatment markers show timing, not medical causality.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(16)
        }
        .navigationTitle("Before & After")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ComparisonStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.monospacedDigit().bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum DesiredLook: String, CaseIterable, Identifiable {
    case dog = "Dog Look"
    case cat = "Cat Look"
    case fox = "Fox Look"
    case rabbit = "Rabbit Look"
    var id: String { rawValue }
}

private struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.look") private var look = DesiredLook.cat.rawValue
    @AppStorage("settings.language") private var languageRawValue = AppLanguage.system.rawValue
    @AppStorage("settings.theme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage("settings.gender") private var sex = "Female"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LookSelectionView(selection: $look)
                    } label: {
                        ProfileRow(icon: "sparkles", title: "My Look", value: look)
                    }
                    Picker("Sex", selection: $sex) {
                        Text("Female").tag("Female")
                        Text("Male").tag("Male")
                    }
                } header: {
                    Text("Personal model")
                } footer: {
                    Text("Your look changes score interpretation only. Original scans and measurements never change.")
                }

                Section("Preferences") {
                    Picker("Theme", selection: $themeRawValue) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    Picker("Language", selection: $languageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        PremiumView()
                    } label: {
                        ProfileRow(icon: "crown.fill", title: "FaceMetric Premium", value: "Free")
                    }
                }

                Section("Privacy & Data") {
                    Label("Manage Facial Data", systemImage: "faceid")
                    Label("Export My Data", systemImage: "square.and.arrow.up")
                    Label("Account", systemImage: "person.crop.circle")
                    Label("Privacy Information", systemImage: "hand.raised")
                    Label("Delete Data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct LookSelectionView: View {
    @Binding var selection: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose the direction that feels most like you. This reinterprets your history without changing the underlying data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(DesiredLook.allCases) { look in
                    Button {
                        selection = look.rawValue
                    } label: {
                        LookCard(
                            title: look.rawValue,
                            subtitle: subtitle(for: look),
                            symbol: symbol(for: look),
                            isSelected: selection == look.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Raw measurements → Selected Look Model → Personalized scores")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(16)
            }
            .padding(20)
        }
        .navigationTitle("My Look")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subtitle(for look: DesiredLook) -> String {
        switch look {
        case .dog: "Soft, balanced, and approachable"
        case .cat: "Defined contour with lifted emphasis"
        case .fox: "Refined angles and tapered proportions"
        case .rabbit: "Gentle curves and compact balance"
        }
    }

    private func symbol(for look: DesiredLook) -> String {
        switch look {
        case .dog: "dog.fill"
        case .cat: "cat.fill"
        case .fox: "hare.fill"
        case .rabbit: "pawprint.fill"
        }
    }
}

private struct LookCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 54, height: 54)
                .foregroundStyle(isSelected ? .white : FMStyle.accent)
                .background(isSelected ? FMStyle.accent : FMStyle.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? FMStyle.accent : Color.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct PremiumView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(FMStyle.accent)
                    .frame(width: 92, height: 92)
                    .background(FMStyle.accent.opacity(0.1), in: Circle())
                VStack(spacing: 8) {
                    Text("FaceMetric Premium").font(.largeTitle.bold())
                    Text("More history, deeper comparisons, and export tools for your personal facial record.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 16) {
                    PremiumBenefit(icon: "calendar", title: "Unlimited scan history")
                    PremiumBenefit(icon: "square.split.2x1", title: "Advanced before & after")
                    PremiumBenefit(icon: "chart.xyaxis.line", title: "Long-range measurement trends")
                    PremiumBenefit(icon: "square.and.arrow.up", title: "3D and CSV data export")
                }
                .padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                Button("Upgrade to Premium") {}
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Manage Subscription") {}
                    .font(.subheadline.weight(.semibold))
            }
            .padding(24)
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PremiumBenefit: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum FMStyle {
    static let accent = Color(red: 0.14, green: 0.48, blue: 0.48)
}

#Preview {
    FaceMetricExperienceView()
}
