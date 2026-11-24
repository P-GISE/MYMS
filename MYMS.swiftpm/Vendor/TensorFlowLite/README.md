# TensorFlowLite 2.4.0 package

The Swift wrapper and static C runtime come from the official Google LiteRT-Swift 2.4.0 release. The upstream archives were downloaded and checksum-verified by SwiftPM. See `PROVENANCE.json` for revision and hashes; see `LICENSE` for Apache 2.0 terms.

The upstream XCFramework packages static archives inside `.framework` directories without per-framework Info.plists. Xcode 26.5 attempted to embed these as dynamic frameworks, failing app bundle validation. This package preserves the archive bytes and exposes them as `.a` XCFramework slices with `HeadersPath` and a C module map. Header files are unchanged, nested under `TensorFlowLiteC/` to retain their original include paths. The Swift wrapper product is dynamic so its native runtime stays isolated from the MediaPipe runtime in the app. The underlying C archives remain unchanged and are linked into that framework. Xcode explicitly embeds/signs the generated TensorFlowLite.framework and uses @executable_path/Frameworks.

Supported slices: physical iOS arm64 and Apple silicon iOS Simulator arm64. No runtime network download is needed. Swift Playground receives this folder together with the app project. Swift Playground builds still require verification on that app; Xcode installation alone does not verify Playground package loading.
