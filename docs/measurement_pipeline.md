# FaceMetric Measurement Pipeline

## Scope and scientific status

FaceMetric is currently an engineering research prototype. M4 standardized acquisition and M5 rigid registration are implemented. Surface-change measurement, regional measurement, reliability analysis, and clinical interpretation are not yet implemented.

No current metric is a medical conclusion, diagnostic result, treatment outcome, attractiveness score, or validated clinical threshold.

## Pipeline separation

1. Acquisition — ARKit TrueDepth observations and raw face-anchor geometry.
2. Standardization — M4 quality monitoring, frame rejection, and robust aggregation.
3. Registration — M5 rigid alignment only, with no deformation.
4. Surface Measurement — planned M6 objective geometric differences.
5. Regional Measurement — planned M6B region summaries.
6. Reliability — planned M8 scan-to-scan descriptive statistics.
7. Clinical Interpretation — explicitly not implemented.

Raw accepted meshes are stored separately from the representative mesh and future derived comparisons. A baseline mesh must never be overwritten by a comparison or registration result.

## Coordinate systems and units

ARKit face geometry vertices are stored in the face anchor's local, right-handed coordinate system. Vertex and translation units are meters.

For acquisition quality only, camera-relative face pose is:

T_camera_face = inverse(T_world_camera) × T_world_face

Camera-to-face distance is the Euclidean norm of the translation component of T_camera_face.

Angles use a yaw-Y, pitch-X, roll-Z decomposition and are stored in radians. The UI converts angles to degrees and distances to millimeters for readability. Pose is used to standardize acquisition; it does not alter raw face-local vertices.

## M4 scan-quality definitions

ScanQualityMetrics.meshVariance is the mean squared Euclidean distance between topology-matched vertices in the current and preceding observed frame:

meshVariance = (1/N) Σ ||v_i(t) - v_i(t-1)||²

It has units of square meters. Mesh RMS is sqrt(meshVariance) and has units of meters.

expressionRMSDelta is the root mean square change across the union of ARKit blend-shape coefficient keys in consecutive observed frames:

expressionRMSDelta = sqrt((1/K) Σ (b_k(t) - b_k(t-1))²)

This measures temporal expression stability. It does not prove that an expression is clinically neutral. The interface instructs the participant to maintain a neutral expression, while the implementation only rejects rapid coefficient change.

Each completed scan also stores the coordinate-wise median coefficient for every blend shape observed in accepted frames. Baseline and follow-up representative coefficients are compared with an RMS difference and ranked per-coefficient deltas. An engineering warning is shown above RMS 0.05. This is an unvalidated expression-consistency flag, not a clinical expression classifier.

trackingStable means all of the following engineering checks passed for the frame:

- ARKit camera tracking state is normal.
- Absolute yaw, pitch, and roll are within configured bounds.
- Camera-to-face distance is within configured bounds.
- Consecutive-frame mesh RMS is within its configured bound.

expressionStable is separately reported and requires the temporal blend-shape RMS change to be within its configured bound. A frame is accepted only when both flags are true.

All limits are centralized in ScanQualityConfiguration.engineeringDefault. They are engineering starting values, not medical limits, and require empirical physical-device validation.

The current stricter composition defaults target a 0.40 m camera-to-face-origin distance, accept 0.37–0.43 m, and require horizontal and vertical face-origin offsets within ±0.025 m. Yaw, pitch, and roll deviation are limited to 7°. These are acquisition-standardization settings selected for the prototype; they are not calibrated clinical thresholds and should be revised from physical-device test-retest distributions.

## Scan aggregation

A final scan is not a single AR frame. The scanner collects topology-compatible frames that pass the quality checks until both a configured valid-frame count and minimum accepted-frame interval are satisfied.

For every vertex index, the representative mesh takes the median x, median y, and median z coordinate across accepted frames. ARKit face mesh topology is constant, so topology-matched aggregation is valid within a supported ARKit face-tracking session. Coordinate-wise median aggregation reduces the influence of transient outliers while retaining the original topology. It is not registration and does not deform one independent scan to fit another.

The scan retains:

- all accepted raw face-local meshes;
- triangle indices;
- accepted frame timestamps and quality metrics;
- accepted/rejected counts;
- the exact quality configuration;
- observed blend-shape names;
- aggregation and coordinate-system descriptions;
- device OS and app version/build metadata.

Rejected-frame meshes are not currently retained to limit memory use; only their count is retained. This is a known reproducibility limitation.

## Registration rationale

Full-face ICP is not the production registration objective. If a treatment changes the chin, nose, cheek, or lips, minimizing error over the whole face can rotate or translate the follow-up surface toward the changed region. That can attenuate the real treatment displacement and introduce false displacement in unchanged regions. Full-face rigid ICP remains available only as a research control.

Registration instead asks which rigid transform best aligns configured anatomical reference structures expected to remain stable for the selected study. It estimates T_baseline_followup:

p_baseline = R × p_followup + t

R is constrained to a proper rotation with det(R) = +1 and t is a translation. There is no scale, shear, or non-rigid deformation. The transform is frozen before surface differences are calculated. Raw meshes are never overwritten.

## Anatomical anchors

An anchor is a robust local patch summary, not a single ARKit vertex. A versioned normalized baseline patch selects candidate vertices. Their coordinate-wise median is calculated, the configured fraction farthest from that median is removed, and the arithmetic centroid of the retained vertices becomes the anchor position. The anchor stores its semantic ID, confidence, and retained source vertices.

Because compatible ARFaceGeometry meshes have stable topology, the robust source set established on the baseline is reused to calculate the corresponding follow-up patch centroid. The rigid solver receives only corresponding AnatomicalAnchor values; it does not contain hard-coded ARKit vertex indices.

Current engineering anchor IDs are upper forehead, left/right forehead, left/right periorbital, and nasal root. Nose profiles exclude the nasal-root anchor; cheek profiles use forehead and nasal-root anchors to avoid the cheek ROI. These definitions are placeholders and have not been clinically validated.

## Weighted rigid point-set registration

For corresponding follow-up anchors p_i and baseline anchors q_i, the solver minimizes:

Σ w_i ||R p_i + t - q_i||²

where w_i is the minimum confidence of the corresponding pair. Weighted centroids and the weighted cross-covariance are accumulated in Double precision. The proper rotation is obtained with Horn's quaternion eigensystem, which is mathematically equivalent to the proper-rotation Kabsch objective; the symmetric 4 × 4 eigenproblem is solved by Jacobi rotations. Translation is targetCentroid - R × sourceCentroid. The result is stored as Float because ARKit mesh input is Float.

Residuals are calculated after alignment. A median/MAD robust scale identifies outlier residuals. Such anchors are Huber-downweighted, not silently deleted, and every decision is retained in AnchorResidual and quality metadata. Low-confidence anchors are also recorded.

The solver fails instead of returning an ill-conditioned transform when there are fewer than three usable anchors, insufficient spatial spread, near-collinearity, zero weighted geometry, or det(R) differs materially from +1. Numerical thresholds are centralized engineering defaults, not medical acceptability limits.

## Registration profiles and ROI separation

RegistrationProfile keeps four independent concepts:

- referenceAnchors: patches used for anchor registration;
- stableSurfaceRegions: surfaces eligible for optional refinement;
- excludedRegions: expression-sensitive or procedure-sensitive areas;
- treatmentRegions: regions measured after registration.

The stable index set is explicitly reduced by both excludedRegions and treatmentRegions. Tests verify that treatment vertices and anchor source vertices are disjoint for chin, nose, cheek, and lip/perioral profiles.

Profiles currently use a normalized upper-face stable surface. The lower central face is marked expression-sensitive. Treatment masks are configurable normalized boxes. All masks are engineering placeholders and require validation on ARFaceGeometry and clinical study protocols.

## Optional stable-ROI rigid refinement

After anchor initialization, StableROIRegistrationRefiner can run trimmed point-to-point ICP using only the stable reference set. Correspondences beyond the configured distance are omitted, the configured largest-distance fraction is trimmed, and every update is another proper rigid transform. Treatment and excluded regions cannot participate. Refinement can be disabled for anchor-only comparison.

The current engineering defaults are 15 iterations, 0.01 mm change tolerance, 10 mm correspondence distance, 15% trimming, and 60 retained correspondences. They are not validated accuracy thresholds.

## Registration quality metrics

Anchor metrics are weighted RMS, maximum residual, and each individual residual. Stable-surface metrics are signed mean, mean absolute, RMS, and P95 absolute point-to-surface residual. The stable region is observed after registration; it is not numerically forced to zero.

Three strategies are always identified explicitly:

1. Full-face rigid ICP — control only.
2. Anatomical anchors only.
3. Anatomical anchors plus stable-ROI rigid refinement — production default.

The app never chooses a strategy merely because it gives the smallest whole-face RMS.

## Surface distance and sign convention

SurfaceDifferenceAnalyzer is implemented as registration infrastructure. For every requested aligned follow-up vertex it finds the closest point on eligible baseline triangles. Distance sign is determined by dot(alignedPoint - closestPoint, orientedBaselineTriangleNormal). Positive means the direction of the baseline triangle normal and negative means the opposite direction. Neither sign implies improvement or harm.

After the final transform is frozen, every strategy reports treatment-ROI mean signed distance, mean absolute distance, RMS, P95 absolute distance, maximum absolute distance, and the vertex/closest-baseline-point location of the maximum sample. Maximum distance is explicitly noise-sensitive. Stable-ROI residuals are displayed alongside treatment measurements so registration error is not confused with treatment-region displacement.

Region-restricted metrics include only vertices covered by a triangle fully contained in that region. This avoids introducing lateral boundary distance when a boundary vertex has no eligible regional triangle. Comprehensive M6 presentation and global/regional product metrics remain separate future work.

## Region definitions

Not implemented (planned M6B). Region maps will be versioned, configurable geometry definitions independent of clinical interpretation.

## Surface area and volume

Not implemented.

Future changed-area estimates must state how triangles intersect thresholds and region boundaries. Future volume estimates must state the numerical integral and boundary assumptions and will remain marked experimental until phantom and reference-system validation support them.

## Synthetic deformation and registration bias

SyntheticDeformationEngine computes area-weighted vertex normals from adjacent oriented triangles and applies a treatment-mask-limited Gaussian displacement:

d_i = direction × d_max × exp(-||v_i - c||² / (2σ²))

where c is the mean position of treatment vertices, σ is the configured spatial spread, and direction is outward or inward along the vertex normal. The exact displacement for every vertex is retained as ground truth.

After deformation, a known rigid pose is applied and all three registration strategies run through the normal pipeline. Registration attenuation is:

attenuation = |groundTruthPeak| - |recoveredPeak|

relativeAttenuation = attenuation / |groundTruthPeak|

Peak, mean, and RMS recovery errors are recovered minus ground truth. Stable false displacement is the post-registration stable-region point-to-surface RMS. Rotation error is the angle of R_measured × transpose(R_expected); translation error is the Euclidean distance between measured and expected inverse-pose translations. Spatial localization error is the baseline-surface distance between ground-truth and recovered peak vertex locations.

## Known limitations

- M4 acquisition was functionally exercised on a physical TrueDepth iPhone, but its limits have not been calibrated across devices or users.
- Temporal blend-shape stability does not establish a neutral expression.
- Median x/y/z aggregation is robust to outliers but may produce a point not present in any individual frame.
- ARKit face-local topology stability is assumed within compatible face-tracking output.
- Rejected raw frames are not retained.
- Device model currently records UIKit's broad model label rather than a hardware identifier.
- Baseline and follow-up scans can be captured separately for registration, but remain in memory only; no persistent encrypted scan store exists yet.
- Baseline-to-follow-up patch correspondence currently requires compatible, stable ARFaceGeometry topology.
- Anchor patches, profiles, stable ROI, exclusions, and all numerical defaults are engineering placeholders.
- Stable refinement is trimmed point-to-point ICP with brute-force nearest-neighbor search; point-to-plane refinement is not implemented.
- Triangle winding from ARFaceGeometry is assumed consistent for signed distance.
- Synthetic tests use an analytic face-like mesh and do not reproduce TrueDepth noise, missing data, expression, or tissue mechanics.
- The current research heatmap is exploratory; comprehensive M6 analysis is not complete.
- Simulator builds cannot validate TrueDepth behavior.
- Successful software tests do not establish measurement accuracy or clinical validity.
