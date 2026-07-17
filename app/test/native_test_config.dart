// Shared resolver for the native (real-model) tests. Not a `*_test.dart`
// file, so `flutter test` does not run it directly.
//
// Paths come from env vars first (CI / other machines), then fall back to the
// Loop-2 dev-native layout on this build machine. When either artifact is
// absent the native tests skip, keeping `make verify` green without them.

import 'dart:io';

const _defaultLibDir =
    '/Users/ansh/AppuInsideEngineering/dhruva-app/app/.dev-native/macos';
const _defaultModel =
    '/Users/ansh/AppuInsideEngineering/dhruva-app/app/.dev-native/models/'
    'SmolLM2-135M-Instruct-Q4_K_M.gguf';

// This repo lives under .../engineering/AppuInsideEngineering/...; the paths
// above are the original build-machine layout. Fall back to the models
// directory relative to this test file so the vision artifacts resolve
// wherever the checkout sits.
const _visionModel = '.dev-native/models/SmolVLM-500M-Instruct-Q8_0.gguf';
const _visionMmproj =
    '.dev-native/models/mmproj-SmolVLM-500M-Instruct-Q8_0.gguf';

class NativePaths {
  final String libraryPath;
  final String modelPath;
  const NativePaths(this.libraryPath, this.modelPath);
}

/// Returns resolved, existing paths or null if the native artifacts are
/// missing on this machine.
NativePaths? resolveNativePaths() {
  final lib =
      Platform.environment['LLAMA_CPP_DART_LIB'] ??
      '$_defaultLibDir/libllama.dylib';
  final model = Platform.environment['DHRUVA_TEST_MODEL'] ?? _defaultModel;
  if (!File(lib).existsSync() || !File(model).existsSync()) return null;
  return NativePaths(lib, model);
}

class VisionPaths {
  final String libraryPath;
  final String modelPath;
  final String mmprojPath;
  const VisionPaths(this.libraryPath, this.modelPath, this.mmprojPath);
}

/// Resolve the vision model + projector for the multimodal round-trip test.
/// Uses the same dylib as [resolveNativePaths]; the model + mmproj come from
/// env (CI) or the local `.dev-native/models/` SmolVLM pair. Null when any
/// artifact is missing so the test skips cleanly.
VisionPaths? resolveVisionPaths() {
  final lib =
      Platform.environment['LLAMA_CPP_DART_LIB'] ??
      '$_defaultLibDir/libllama.dylib';
  final model = Platform.environment['DHRUVA_VISION_MODEL'] ?? _visionModel;
  final mmproj = Platform.environment['DHRUVA_VISION_MMPROJ'] ?? _visionMmproj;
  if (!File(lib).existsSync() ||
      !File(model).existsSync() ||
      !File(mmproj).existsSync()) {
    return null;
  }
  return VisionPaths(lib, model, mmproj);
}
