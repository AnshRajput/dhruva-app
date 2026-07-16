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
