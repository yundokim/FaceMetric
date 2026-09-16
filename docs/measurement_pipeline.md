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

trackingStable means all of the following engineering checks passed for the frame:

- ARKit camera tracking state is normal.
- Absolute yaw, pitch, and roll are within configured bounds.
- Camera-to-face distance is within configured bounds.
- Consecutive-frame mesh RMS is within its configured bound.

expressionStable is separately reported and requires the temporal blend-shape RMS change to be within its configured bound. A frame is accepted only when both flags are true.

All limits are centralized in ScanQualityConfiguration.engineeringDefault. They are engineering starting values, not medical limits, and require empirical physical-device validation.

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

## Registration algorithm

Both representative meshes remain in ARKit face-anchor local coordinates. Registration estimates a transform T_baseline_followup that maps follow-up face-local points into baseline face-local coordinates:

p_baseline = R × p_followup + t

The initial transform is a least-squares rigid fit between topology-matched vertices selected by the registration ROI. This is justified for compatible ARFaceGeometry outputs with the same topology and provides deterministic initial alignment. A quaternion form of the orthogonal Procrustes/Horn solution estimates rotation; translation is the difference between the target centroid and rotated source centroid.

The initial transform is refined with point-to-point ICP. Each transformed follow-up ROI vertex is paired with its nearest baseline ROI vertex within the configured maximum correspondence distance. A new rigid transform is fitted to those pairs and composed with the accumulated transform. Iteration stops when the absolute change in RMS is no greater than the configured tolerance or when the iteration limit is reached.

Registration RMS is:

RMS = sqrt((1/N) Σ ||R p_i + t - q_i||²)

where p_i is an aligned follow-up correspondence and q_i is its baseline correspondence. RMS is stored in meters and displayed in millimeters. The result also records correspondence count, iteration count, convergence status, ROI identifier, and the rigid transform. `converged` describes numerical convergence only; it is not a claim of anatomical or clinical accuracy.

No scale, shear, per-vertex offsets, or other non-rigid deformation is estimated. Raw baseline and follow-up meshes are not modified.

## Registration ROI

RegistrationRegionMask defines versioned inclusion and exclusion boxes in normalized baseline face bounds. Normalized coordinates are calculated independently per axis as (v - boundsMinimum) / (boundsMaximum - boundsMinimum). The follow-up uses the same selected topology indices.

The `generic-stable-v1-engineering-default` mask includes an upper central face box and two lateral mid-face boxes. These are engineering defaults intended to reduce reliance on central lower-face areas. They are not validated anatomical or medical regions. Inclusion and exclusion boxes are configurable so future procedure-specific pipelines can exclude a measurement ROI from registration without changing the registration algorithm.

The current engineering defaults are 20 iterations, 0.01 mm RMS-change convergence tolerance, 10 mm maximum correspondence distance, and at least 80 correspondences. These values require empirical validation on independent scans.

## Surface distance and sign convention

Not implemented (planned M6).

The intended metric is signed point-to-surface distance after rigid registration, not unverified index-to-index distance. The sign convention will be defined relative to the oriented baseline surface: positive will mean outward displacement and negative inward displacement. Neither sign implies improvement or harm.

## Region definitions

Not implemented (planned M6B). Region maps will be versioned, configurable geometry definitions independent of clinical interpretation.

## Surface area and volume

Not implemented.

Future changed-area estimates must state how triangles intersect thresholds and region boundaries. Future volume estimates must state the numerical integral and boundary assumptions and will remain marked experimental until phantom and reference-system validation support them.

## Synthetic deformation

Not implemented (planned M7).

The planned deformation is a configurable Gaussian spatial weight applied along an explicitly chosen mesh-normal direction. Formula, normal estimation, boundary handling, and ground-truth integration will be documented with that implementation.

## Known limitations

- M4 acquisition was functionally exercised on a physical TrueDepth iPhone, but its limits have not been calibrated across devices or users.
- Temporal blend-shape stability does not establish a neutral expression.
- Median x/y/z aggregation is robust to outliers but may produce a point not present in any individual frame.
- ARKit face-local topology stability is assumed within compatible face-tracking output.
- Rejected raw frames are not retained.
- Device model currently records UIKit's broad model label rather than a hardware identifier.
- Baseline and follow-up scans can be captured separately for registration, but remain in memory only; no persistent encrypted scan store exists yet.
- Registration currently requires identical vertex counts/topology for deterministic initial alignment.
- The generic registration ROI and ICP defaults are not empirically validated.
- ICP is point-to-point with a brute-force nearest-neighbor search; robust weighting and point-to-plane refinement are not implemented.
- No surface-change measurement exists yet.
- Simulator builds cannot validate TrueDepth behavior.
- Successful software tests do not establish measurement accuracy or clinical validity.
