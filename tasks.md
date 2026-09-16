# FaceMetric Research Prototype Tasks

The pipeline is intentionally staged:

Acquisition → Standardization → Registration → Surface Measurement → Regional Measurement → Reliability → Clinical Interpretation

Clinical interpretation is out of scope until appropriate validation data exists.

## M4 — Standardized Acquisition

- [x] Preserve the working ARKit TrueDepth/ARSCNView pipeline.
- [x] Capture camera-relative yaw, pitch, roll, and face distance.
- [x] Capture ARKit tracking state and temporal blend-shape stability.
- [x] Calculate temporal per-vertex mesh variance.
- [x] Put prototype acceptance limits in one explicitly unvalidated engineering configuration.
- [x] Reject frames that fail tracking, pose, distance, expression-change, or mesh-motion checks.
- [x] Collect multiple valid frames over a minimum interval.
- [x] Produce a representative mesh with coordinate-wise per-vertex median aggregation.
- [x] Retain accepted raw meshes, frame quality, timestamps, configuration, topology, and device/app metadata.
- [x] Provide live positioning, neutral-expression, stillness, capture, and completion guidance.
- [x] Add unit tests for quality evaluation, variance, and robust aggregation.
- [x] Validate M4 acquisition flow and engineering defaults functionally on a physical TrueDepth-supported iPhone.
- [ ] Measure within-scan distributions across devices and users before freezing thresholds.
- [ ] Add encrypted on-device persistence and an explicit baseline-save flow.

## M5 — Registration

- [x] Define a face-centered coordinate-system transform.
- [x] Define a configurable generic stable-region mask.
- [x] Implement rigid initial alignment and ICP-like refinement without deformation.
- [x] Report transform, RMS error, correspondence count, and quality metadata.
- [x] Add aligned baseline/follow-up debug visualization.
- [x] Test translation, rotation, and combined pose recovery.
- [ ] Validate the generic stable-region mask and registration defaults on independent physical-iPhone scans.

## M5A — Anatomical Anchor Abstraction

- [x] Define robust patch-derived anatomical anchors independent of registration internals.
- [x] Record anchor confidence and contributing source vertices.

## M5B — Registration Profiles

- [x] Separate reference anchors, stable surfaces, excluded regions, and treatment ROI.
- [x] Add configurable engineering profiles for chin, nose, lip/perioral, and cheek studies.

## M5C — Weighted Rigid Registration

- [x] Implement confidence-weighted proper rigid point-set alignment with no scale or shear.
- [x] Report transform, rotation, translation, per-anchor residuals, RMS, and maximum residual.

## M5D — Registration Quality Checks

- [x] Detect insufficient, low-confidence, collinear, and poorly distributed anchors.
- [x] Record robustly downweighted/rejected anchor decisions in debug metadata.

## M5E — Stable-ROI Rigid Refinement

- [x] Add optional robust rigid ICP restricted to the stable reference ROI.
- [x] Ensure treatment and excluded regions cannot enter stable-ROI refinement.

## M5F — Registration Quality Metrics

- [x] Calculate signed, absolute, RMS, and P95 residuals over stable ROI surfaces.

## M5G — Surface Difference Integration

- [x] Freeze the final rigid transform before signed point-to-surface analysis.
- [x] Keep treatment measurements outside every registration objective.

## M5H — Registration Strategy Comparison

- [x] Compare full-face ICP control, anchor-only, and anchor + stable-ROI methods explicitly.
- [x] Add research visualization and calculated metrics for each method.

## M7 — Registration Bias Validation

- [x] Generate known local chin, nose, cheek, and lip/perioral deformations.
- [x] Combine each deformation with deterministic rigid pose perturbations.
- [x] Measure treatment attenuation and stable-region false displacement for all strategies.
- [ ] Repeat registration-bias validation on captured ARFaceGeometry meshes and physical phantoms.

## M6 — Surface Change Analysis

- [ ] Implement signed point-to-surface displacement.
- [ ] Define and test sign convention.
- [ ] Calculate global signed, absolute, RMS, median, standard-deviation, P95, and maximum metrics.
- [ ] Add a symmetric displacement color map and interactive 3D inspection.

## M6B — Region Analysis

- [ ] Implement configurable, interpretation-free facial region definitions.
- [ ] Calculate regional displacement metrics.
- [ ] Define triangle-clipped area estimation.
- [ ] Investigate volume estimation and keep it explicitly experimental until validated.

## M7 — Synthetic Validation

- [ ] Implement Gaussian normal-direction synthetic deformation.
- [ ] Support nose, chin, cheeks, and upper/lower lip regions.
- [ ] Test configurable small millimeter-scale magnitudes.
- [ ] Test deformation combined with rigid pose perturbations.
- [ ] Report ground truth versus recovered peak, mean, localization, and any experimental volume errors.

## M8 — Test-Retest Reliability

- [ ] Model separate scan sessions and dates.
- [ ] Distinguish within-scan, between-scan, and between-day variation.
- [ ] Implement descriptive mean, standard deviation, appropriate coefficient of variation, absolute difference, and RMS difference.
- [ ] Design extension points for explicitly specified ICC, SEM, TEM, and Bland–Altman methods.
