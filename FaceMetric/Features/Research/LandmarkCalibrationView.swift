import SceneKit
import SwiftUI

struct LandmarkCalibrationView: View {
    let mesh: FaceMesh
    @Binding var configuration: FaceLandmarkConfig
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLandmark = FaceAnatomicalLandmark.trichionOrForeheadBoundary
    @State private var selectedVertexIndex: Int?
    @State private var errorMessage: String?
    @State private var exportJSON = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Anatomical landmark", selection: $selectedLandmark) {
                    ForEach(FaceAnatomicalLandmark.allCases) { landmark in
                        Text(landmark.rawValue).tag(landmark)
                    }
                }

                Text("Tap the anatomically verified mesh vertex for the selected landmark. Surface ROIs are generated automatically from these landmarks for every scan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VertexCalibrationScene(
                    mesh: mesh,
                    highlightedIndices: highlightedIndices,
                    selectedVertexIndex: $selectedVertexIndex
                )
                .frame(maxWidth: .infinity, minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack {
                    Text(selectionStatus)
                        .font(.caption.monospacedDigit())
                    Spacer()
                }

                if configuration.isCompleteForMVP {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Developer Export")
                            .font(.headline)
                        Text("Export this topology-specific configuration and add it to BundledFaceLandmarkConfigs after review.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Copy JSON", systemImage: "doc.on.doc") {
                                copyConfiguration()
                            }
                            .buttonStyle(.bordered)
                            ShareLink(item: exportJSON) {
                                Label("Share JSON", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .disabled(exportJSON.isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .navigationTitle("Landmark Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onChange(of: selectedVertexIndex) { _, index in
                guard let index else { return }
                assign(index)
            }
            .onChange(of: configuration) { _, config in
                exportJSON = (try? FaceLandmarkConfigStore.exportJSON(config)) ?? ""
            }
            .task {
                exportJSON = (try? FaceLandmarkConfigStore.exportJSON(configuration)) ?? ""
            }
            .alert("Calibration", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var highlightedIndices: Set<Int> {
        Set(configuration.vertexIndex(for: selectedLandmark).map { [$0] } ?? [])
    }

    private var selectionStatus: String {
        configuration.vertexIndex(for: selectedLandmark).map { "Vertex #\($0)" } ?? "Not calibrated"
    }

    private func assign(_ index: Int) {
        configuration.landmarkVertexIndices[selectedLandmark.rawValue] = index
        selectedVertexIndex = nil
    }

    private func save() {
        do {
            try FaceLandmarkConfigStore.save(configuration)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyConfiguration() {
        do {
            let json = try FaceLandmarkConfigStore.exportJSON(configuration)
            UIPasteboard.general.string = json
            exportJSON = json
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VertexCalibrationScene: UIViewRepresentable {
    let mesh: FaceMesh
    let highlightedIndices: Set<Int>
    @Binding var selectedVertexIndex: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .secondarySystemBackground
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:))))
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        let scene = SCNScene()
        let contentNode = SCNNode()
        scene.rootNode.addChildNode(contentNode)
        let faceNode = makeFaceNode()
        faceNode.name = "calibrationFace"
        contentNode.addChildNode(faceNode)
        contentNode.addChildNode(makePointNode(indices: Array(mesh.vertices.indices), color: .white, size: 2))
        contentNode.addChildNode(makePointNode(indices: Array(highlightedIndices), color: .systemYellow, size: 10))

        let bounds = boundsOfMesh()
        let center = (bounds.minimum + bounds.maximum) / 2
        contentNode.simdPosition = -center
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(bounds.maximum.x - bounds.minimum.x, bounds.maximum.y - bounds.minimum.y) * 1.25)
        camera.zNear = 0.001
        camera.zFar = 2
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 0.4)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 700
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 1_100
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(keyNode)
        view.scene = scene
        view.pointOfView = cameraNode
    }

    private func makeFaceNode() -> SCNNode {
        let geometry = meshGeometry()
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.78)
        material.roughness.contents = 0.72
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func makePointNode(indices: [Int], color: UIColor, size: CGFloat) -> SCNNode {
        let valid = indices.filter(mesh.vertices.indices.contains)
        let points = valid.map { mesh.simdVertices[$0] }
        let source = SCNGeometrySource(vertices: points.map(SCNVector3.init))
        let pointIndices = Array(UInt32.zero..<UInt32(points.count))
        let element = SCNGeometryElement(data: pointIndices.withUnsafeBytes { Data($0) }, primitiveType: .point, primitiveCount: points.count, bytesPerIndex: MemoryLayout<UInt32>.size)
        element.pointSize = size
        element.minimumPointScreenSpaceRadius = size / 2
        element.maximumPointScreenSpaceRadius = size
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func meshGeometry() -> SCNGeometry {
        let source = SCNGeometrySource(vertices: mesh.simdVertices.map(SCNVector3.init))
        let indices = mesh.triangleIndices.map(UInt16.init(bitPattern:))
        let element = SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: MemoryLayout<UInt16>.size)
        return SCNGeometry(sources: [source], elements: [element])
    }

    private func boundsOfMesh() -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        guard let first = mesh.simdVertices.first else { return (.zero, SIMD3(repeating: 0.2)) }
        return mesh.simdVertices.dropFirst().reduce(into: (minimum: first, maximum: first)) {
            $0.minimum = simd_min($0.minimum, $1)
            $0.maximum = simd_max($0.maximum, $1)
        }
    }

    final class Coordinator: NSObject {
        var parent: VertexCalibrationScene

        init(parent: VertexCalibrationScene) {
            self.parent = parent
        }

        @objc func didTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView,
                  let hit = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue]).first(where: { $0.node.name == "calibrationFace" }) else { return }
            let local = SIMD3<Float>(hit.localCoordinates)
            parent.selectedVertexIndex = parent.mesh.simdVertices.indices.min {
                simd_length_squared(parent.mesh.simdVertices[$0] - local) < simd_length_squared(parent.mesh.simdVertices[$1] - local)
            }
        }
    }
}
