import SceneKit
import SwiftUI

struct RegistrationDebugView: View {
    let baseline: FaceMesh
    let followup: FaceMesh
    let profile: RegistrationProfile
    let comparison: RegistrationComparisonResult

    @State private var selectedStrategy: RegistrationStrategy = .anchorAndStableROI
    @State private var showUnregistered = true
    @State private var showRegions = true
    @State private var showHeatmap = true

    private var selectedResult: StrategyRegistrationResult? {
        comparison.result(for: selectedStrategy)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Strategy", selection: $selectedStrategy) {
                ForEach(RegistrationStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)

            if let selectedResult {
                RegistrationSceneView(
                    baseline: baseline,
                    followup: followup,
                    result: selectedResult,
                    profile: profile,
                    showUnregistered: showUnregistered,
                    showRegions: showRegions,
                    showHeatmap: showHeatmap
                )

                List {
                    Section("Visualization") {
                        Toggle("Follow-up before registration", isOn: $showUnregistered)
                        Toggle("Reference / excluded / treatment regions", isOn: $showRegions)
                        Toggle("Signed displacement heatmap", isOn: $showHeatmap)
                    }

                    RegistrationMetricSection(result: selectedResult)

                    if let anchorResult = selectedResult.anchorRegistration {
                        Section("Per-anchor residuals") {
                            ForEach(anchorResult.anchorResiduals) { residual in
                                LabeledContent(
                                    residual.id.rawValue,
                                    value: String(
                                        format: "%.3f mm · %@",
                                        residual.residualMeters * 1_000,
                                        residual.decision.rawValue
                                    )
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .navigationTitle("Registration Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RegistrationMetricSection: View {
    let result: StrategyRegistrationResult

    var body: some View {
        Section("Calculated Metrics") {
            if let anchors = result.anchorRegistration {
                LabeledContent("Anchor RMS", value: millimeters(anchors.anchorRMSError))
                LabeledContent("Anchor maximum", value: millimeters(anchors.anchorMaxError))
                LabeledContent("Anchor count", value: anchors.numberOfAnchors.formatted())
                LabeledContent(
                    "Rotation determinant",
                    value: String(format: "%.6f", anchors.qualityMetadata.rotationDeterminant)
                )
            } else {
                LabeledContent("Anchor metrics", value: "Not applicable to control")
            }

            LabeledContent(
                "Stable mean signed",
                value: millimeters(result.stableROIResiduals.meanSignedResidual)
            )
            LabeledContent(
                "Stable mean absolute",
                value: millimeters(result.stableROIResiduals.meanAbsoluteResidual)
            )
            LabeledContent(
                "Stable RMS",
                value: millimeters(result.stableROIResiduals.rmsResidual)
            )
            LabeledContent(
                "Stable P95",
                value: millimeters(result.stableROIResiduals.p95AbsoluteResidual)
            )
            Divider()
            LabeledContent(
                "Treatment mean signed",
                value: signedMillimeters(
                    result.treatmentSurfaceDifference.metrics.meanSignedResidual
                )
            )
            LabeledContent(
                "Treatment mean absolute",
                value: millimeters(
                    result.treatmentSurfaceDifference.metrics.meanAbsoluteResidual
                )
            )
            LabeledContent(
                "Treatment RMS",
                value: millimeters(result.treatmentSurfaceDifference.metrics.rmsResidual)
            )
            LabeledContent(
                "Treatment P95",
                value: millimeters(
                    result.treatmentSurfaceDifference.metrics.p95AbsoluteResidual
                )
            )
            LabeledContent(
                "Treatment maximum",
                value: millimeters(
                    result.treatmentSurfaceDifference.metrics.maximumAbsoluteResidual
                )
            )
            LabeledContent("Rigid refinement iterations", value: result.refinementIterations.formatted())
        }
        .font(.caption.monospaced())
    }

    private func millimeters(_ meters: Float) -> String {
        String(format: "%.3f mm", meters * 1_000)
    }

    private func signedMillimeters(_ meters: Float) -> String {
        String(format: "%+.3f mm", meters * 1_000)
    }
}

private struct RegistrationSceneView: UIViewRepresentable {
    let baseline: FaceMesh
    let followup: FaceMesh
    let result: StrategyRegistrationResult
    let profile: RegistrationProfile
    let showUnregistered: Bool
    let showRegions: Bool
    let showHeatmap: Bool

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
        let aligned = result.finalTransform.applying(to: followup)
        let baselineNode = meshNode(mesh: baseline, color: .cyan, opacity: 0.55)
        scene.rootNode.addChildNode(baselineNode)

        if showUnregistered {
            scene.rootNode.addChildNode(
                meshNode(mesh: followup, color: .gray, opacity: 0.35)
            )
        }

        if showHeatmap,
           let heatmap = try? SurfaceDifferenceAnalyzer().analyze(
                baseline: baseline,
                alignedFollowup: aligned,
                sampleIndices: Array(aligned.vertices.indices)
           ) {
            scene.rootNode.addChildNode(
                heatmapNode(mesh: aligned, samples: heatmap.samples)
            )
        } else {
            scene.rootNode.addChildNode(
                meshNode(mesh: aligned, color: .systemPink, opacity: 0.70)
            )
        }

        if showRegions {
            addRegionNodes(to: scene)
        }
        addAnchorNodes(to: scene, transform: result.finalTransform)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 2
        cameraNode.position = SCNVector3(0, 0, 0.35)
        cameraNode.constraints = [SCNLookAtConstraint(target: baselineNode)]
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    private func addRegionNodes(to scene: SCNScene) {
        let stable = profile.stableVertexIndices(in: baseline)
        let treatment = profile.treatmentVertexIndices(in: baseline)
        let excluded = profile.excludedRegions.reduce(into: Set<Int>()) {
            $0.formUnion($1.selectedIndices(in: baseline.simdVertices))
        }

        scene.rootNode.addChildNode(
            pointNode(vertices: stable.map { baseline.simdVertices[$0] }, color: .yellow)
        )
        scene.rootNode.addChildNode(
            pointNode(vertices: excluded.map { baseline.simdVertices[$0] }, color: .orange)
        )
        scene.rootNode.addChildNode(
            pointNode(vertices: treatment.map { baseline.simdVertices[$0] }, color: .green)
        )
    }

    private func addAnchorNodes(to scene: SCNScene, transform: RigidTransform) {
        let baselinePositions = result.baselineAnchors.map { $0.position.simdValue }
        let followupByID = Dictionary(
            uniqueKeysWithValues: result.followupAnchors.map { ($0.id, $0) }
        )
        let alignedFollowup = result.baselineAnchors.compactMap { anchor in
            followupByID[anchor.id].map {
                transform.applying(to: $0.position.simdValue)
            }
        }
        scene.rootNode.addChildNode(pointNode(vertices: baselinePositions, color: .cyan, size: 8))
        scene.rootNode.addChildNode(pointNode(vertices: alignedFollowup, color: .systemPink, size: 8))
        scene.rootNode.addChildNode(
            correspondenceNode(baseline: baselinePositions, followup: alignedFollowup)
        )
    }

    private func meshNode(mesh: FaceMesh, color: UIColor, opacity: CGFloat) -> SCNNode {
        let geometry = meshGeometry(mesh: mesh, additionalSources: [])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.25)
        material.fillMode = .lines
        material.isDoubleSided = true
        material.transparency = opacity
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func heatmapNode(
        mesh: FaceMesh,
        samples: [SurfaceDistanceSample]
    ) -> SCNNode {
        let byIndex = Dictionary(uniqueKeysWithValues: samples.map {
            ($0.vertexIndex, $0.signedDistanceMeters)
        })
        let absolute = samples.map { abs($0.signedDistanceMeters) }.sorted()
        let range = max(absolute.isEmpty ? 0 : absolute[Int(Float(absolute.count - 1) * 0.95)], 0.000_1)
        let colors: [SIMD4<Float>] = mesh.vertices.indices.map { index in
            let normalized = min(1, max(-1, (byIndex[index] ?? 0) / range))
            if normalized >= 0 {
                return SIMD4<Float>(1, 1 - normalized, 1 - normalized, 0.82)
            }
            return SIMD4<Float>(1 + normalized, 1 + normalized, 1, 0.82)
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
        let geometry = meshGeometry(mesh: mesh, additionalSources: [colorSource])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func meshGeometry(
        mesh: FaceMesh,
        additionalSources: [SCNGeometrySource]
    ) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: mesh.simdVertices.map(SCNVector3.init))
        let indices = mesh.triangleIndices.map(UInt16.init(bitPattern:))
        let indexData = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt16>.size
        )
        return SCNGeometry(sources: [source] + additionalSources, elements: [element])
    }

    private func pointNode(
        vertices: [SIMD3<Float>],
        color: UIColor,
        size: CGFloat = 3
    ) -> SCNNode {
        let source = SCNGeometrySource(vertices: vertices.map(SCNVector3.init))
        let indices = Array(UInt32.zero..<UInt32(vertices.count))
        let element = SCNGeometryElement(
            data: indices.withUnsafeBytes { Data($0) },
            primitiveType: .point,
            primitiveCount: indices.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = size
        element.minimumPointScreenSpaceRadius = size / 2
        element.maximumPointScreenSpaceRadius = size
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func correspondenceNode(
        baseline: [SIMD3<Float>],
        followup: [SIMD3<Float>]
    ) -> SCNNode {
        let vertices = zip(baseline, followup).flatMap { [$0.0, $0.1] }
        let source = SCNGeometrySource(vertices: vertices.map(SCNVector3.init))
        let indices = Array(UInt32.zero..<UInt32(vertices.count))
        let element = SCNGeometryElement(
            data: indices.withUnsafeBytes { Data($0) },
            primitiveType: .line,
            primitiveCount: vertices.count / 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor.white
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
