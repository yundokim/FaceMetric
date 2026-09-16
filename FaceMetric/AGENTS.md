# FaceMetric

Native iOS application for research-based 3D facial analysis.

## Stack
- Swift
- SwiftUI
- ARKit
- Vision where necessary
- Core ML only where justified
- XCTest
- No third-party dependency unless necessary

## Architecture
Feature-oriented MVVM.

Features:
- Home
- Face Scan
- Facial Analysis
- Result
- Scan History

Core modules:
- Camera
- Face Geometry
- Facial Measurements
- Scoring

## Principles
- Prefer deterministic geometric measurements over AI inference.
- Separate raw measurements from aesthetic scoring.
- Never fabricate medical or scientific reference ranges.
- Each score must be traceable to underlying measurements.
- Keep facial data on-device by default.
- Do not add backend services unless explicitly requested.

## Development
- Make small testable changes.
- Build after significant changes.
- Do not suppress compiler warnings to fix errors.
- Add unit tests for geometry and scoring logic.
