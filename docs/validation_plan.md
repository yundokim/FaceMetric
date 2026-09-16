# FaceMetric Validation Plan

## Current evidence

Completed software-level M4 checks cover:

- coordinate-wise median aggregation and transient-outlier resistance;
- topology mismatch rejection;
- the mathematical definition of per-vertex mesh variance;
- acceptance of a stable centered synthetic frame;
- rejection of excessive synthetic yaw;
- rejection of temporal blend-shape change.

The M4 acquisition flow has also been functionally verified by the developer on a physical TrueDepth-supported iPhone. This confirms device operation, not calibrated accuracy or repeatability.

Completed software-level M5 checks cover:

- identical-mesh registration;
- removal of known rigid translation;
- removal of known rigid rotation;
- removal of combined known translation and rotation.

The Xcode project builds successfully. These checks validate implementation behavior only. Cross-device M4 calibration, independent-scan M5 registration performance, scan repeatability, minimum detectable change, and surface displacement are not yet validated.

## Phase 1 — Synthetic mesh validation

Planned M7 work will introduce known local normal-direction deformations into baseline meshes and run the complete registration and surface-analysis pipeline. Tests will cover configurable small millimeter-scale values, rigid translations, rotations, combined pose changes, and noise. These values are engineering stimuli and will not be described as typical procedure outcomes.

Outputs will include peak and mean displacement error, localization error where defined, and experimental volume error only if a defensible volume method exists.

## Phase 2 — Physical facial phantom

Use a stable face-shaped phantom with independently measured, removable or adjustable surface changes. Repeat scans across distances, poses, devices, operators, lighting conditions, and sessions. Compare recovered geometry with traceable physical measurements.

## Phase 3 — Healthy-volunteer test-retest reliability

Acquire fully separate scans after complete repositioning, including repeated sessions and days. Quantify within-scan, between-scan, and between-day distributions globally and by region. Pre-specify any ICC model before calculating ICC; also evaluate absolute differences, RMS differences, SEM/TEM candidates, and Bland–Altman limits without inventing clinical acceptability cutoffs.

## Phase 4 — Professional 3D imaging comparison

Compare FaceMetric scans with a validated professional 3D facial imaging system using a pre-specified acquisition protocol, rigid registration strategy, correspondence method, and error analysis. Account for differences in coordinate systems, coverage, resolution, and capture timing.

## Phase 5 — Pre/post aesthetic-procedure study

Only after earlier phases establish sufficient technical performance, conduct an ethically approved study with real pre/post procedure scans. Pre-register procedure-specific registration exclusions, regions, time points, and statistical analysis. Continue reporting objective geometry separately from clinical interpretation.

## Phase 6 — Patient- and clinician-reported outcome validation

Evaluate whether validated geometric measurements relate to patient-reported and clinician-reported outcomes. This phase is required before attaching interpretive claims to measurements. Correlation would not by itself establish causation, treatment success, normality, or attractiveness.
