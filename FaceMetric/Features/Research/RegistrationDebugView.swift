import SceneKit
import SwiftUI

struct RegistrationDebugView: View {
    let baseline: FaceMesh
    let followup: FaceMesh
    let result: RegistrationResult

    var body: some View {
        VStack(spacing: 0) {
            RegistrationSceneView(
                baseline: baseline,
                alignedFollowup: result.transform.applying(to: followup)
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Baseline", systemImage: "circle.fill")
                    .foregroundStyle(.cyan)
                Label("Aligned follow-up", systemImage: "circle.fill")
                    .foregroundStyle(.pink)
                Label("Registration ROI vertices", systemImage: "circle.fill")
                    .foregroundStyle(.yellow)

                Divider()

                LabeledContent(
                    "RMS",
                    value: String(format: "%.3f mm", result.rmsError * 1_000)
                )
                LabeledContent("Correspondences", value: result.correspondenceCount.formatted())
                LabeledContent("Iterations", value: result.iterationCount.formatted())
                LabeledContent("Status", value: result.quality.rawValue)
                LabeledContent("ROI", value: result.regionMaskIdentifier)
            }
            .font(.caption.monospaced())
            .padding()
        }
        .navigationTitle("Registration Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RegistrationSceneView: UIViewRepresentable {
    let baseline: FaceMesh
    let alignedFollowup: FaceMesh

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.scene = makeScene()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        let baselineNode = meshNode(
            mesh: baseline,
            color: .cyan,
            opacity: 0.72
        )
        scene.rootNode.addChildNode(baselineNode)

        let followupNode = meshNode(
            mesh: alignedFollowup,
            color: .systemPink,
            opacity: 0.58
        )
        scene.rootNode.addChildNode(followupNode)

        let roiIndices = RegistrationRegionMask.genericStableRegions.selectedIndices(
            in: baseline.simdVertices
        )
        let roiVertices = roiIndices.map { baseline.simdVertices[$0] }
        scene.rootNode.addChildNode(pointNode(vertices: roiVertices, color: .yellow))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 2
        cameraNode.position = SCNVector3(0, 0, 0.35)
        cameraNode.constraints = [SCNLookAtConstraint(target: baselineNode)]
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private func meshNode(mesh: FaceMesh, color: UIColor, opacity: CGFloat) -> SCNNode {
        let vertices = mesh.simdVertices.map(SCNVector3.init)
        let source = SCNGeometrySource(vertices: vertices)
        let indices = mesh.triangleIndices.map(UInt16.init(bitPattern:))
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.35)
        material.fillMode = .lines
        material.isDoubleSided = true
        material.transparency = opacity
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func pointNode(vertices: [SIMD3<Float>], color: UIColor) -> SCNNode {
        let sceneVertices = vertices.map(SCNVector3.init)
        let source = SCNGeometrySource(vertices: sceneVertices)
        let indices = Array(UInt32.zero..<UInt32(sceneVertices.count))
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: indices.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 4

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
