# Registration Validation

## Scientific status

This document separates four evidence levels:

1. Algorithm correctness — deterministic unit tests of rigid mathematics and failure handling.
2. Synthetic validation — recovery of known deformations on an analytic face-like mesh.
3. Test-retest reliability — not yet performed for the new registration profiles.
4. Clinical validation — not performed and no clinical claims are made.

Passing software and synthetic tests does not establish TrueDepth measurement accuracy or suitability for clinical decisions.

## Implemented protocol

The validation mesh is a triangulated 21 × 21 face-like curved surface expressed in meters. Synthetic deformation is limited to a configurable chin, nose, bilateral cheek, or lip/perioral mask. Area-weighted vertex normals define displacement direction, and a Gaussian with configurable maximum magnitude and spatial spread defines each known per-vertex displacement.

Every deformed mesh receives a rigid pose perturbation before registration. Tests use `SyntheticPoseGenerator` with a fixed seed so multiple pseudo-random rotations and translations are reproducible. Each case runs:

- full-face rigid ICP control;
- anatomical anchors only;
- anatomical anchors plus stable-ROI-only rigid refinement.

The frozen transform is followed by signed point-to-baseline-triangle measurement. The validator reports peak, mean, and RMS recovery error; spatial localization error; registration attenuation; stable-region false displacement RMS; rotation error; and translation error.

## Completed matrix

The automated matrix currently contains:

- four treatment regions: chin, nose, cheek, lip/perioral;
- three configured maximum magnitudes: 1 mm, 2 mm, and 3 mm;
- two seeded pseudo-random rigid poses per magnitude and region;
- three registration strategies per case.

This is 24 deformation/pose cases and 72 strategy evaluations. The millimeter values are engineering stimuli only and are not claims about typical procedure outcomes.

## Current automated criteria and result

For anchor + stable-ROI registration, every matrix case passed the following pre-specified software checks:

- absolute peak attenuation less than 35% of configured magnitude plus 0.2 mm;
- stable-region false displacement RMS below 0.5 mm;
- inverse-pose translation error below 1.0 mm;
- inverse-pose rotation error below 0.03 radians.

These are engineering test tolerances for this analytic mesh, not medical or clinical thresholds. The complete project test run contains 23 tests; final run status is recorded in the development handoff.

## Representative calculated result

For the deterministic chin case configured at 3 mm maximum displacement, 18 mm spread, 0.13 rad pose rotation, and translation (6, -5, 10) mm, the closest mesh vertex had 2.907 mm ground-truth displacement. Calculated results were:

| Metric | Full-face ICP control | Anchor only | Anchor + stable ROI |
|---|---:|---:|---:|
| Recovered peak | 2.480 mm | 2.907 mm | 2.907 mm |
| Registration attenuation | 0.428 mm | approximately 0.000 mm | approximately 0.000 mm |
| Stable false displacement RMS | 0.112 mm | 0.000003 mm | 0.000003 mm |
| Rotation recovery error | 0.224° | approximately 0.000° | approximately 0.000° |
| Translation recovery error | 0.188 mm | 0.000002 mm | 0.000002 mm |

This result demonstrates the intended registration-bias measurement on one idealized mesh. It does not establish that the same performance occurs with TrueDepth scans.

## Correctness tests

Implemented tests cover:

- identity, translation, rotation, and combined rigid pose recovery;
- robust trimmed patch extraction;
- bounded error with noisy anchors;
- recorded robust downweighting of one anchor outlier;
- safe failure for collinear anchors;
- programmatic disjointness of treatment ROI from stable and anchor source sets;
- point-to-surface sign convention;
- zero-deformation pose removal for all three strategies;
- quantitative outputs for registration attenuation and stable false displacement.

## Remaining validation

- Run the matrix on captured ARFaceGeometry meshes rather than only the analytic surface.
- Add realistic spatially correlated TrueDepth noise, missing vertices, and expression perturbations.
- Measure repeated independent scans on physical TrueDepth iPhones.
- Validate anchor patches and treatment/stable masks against external anatomical landmarks.
- Test a physical facial phantom with independently measured local changes.
- Compare against a validated professional 3D facial imaging system.
- Perform clinical validation only after technical repeatability and minimum detectable change are established.
