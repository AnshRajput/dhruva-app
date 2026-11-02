import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// A model file the user chose in the system picker. [uri] is an opaque
/// handle for the native side (an Android content URI, an iOS file URL); the
/// bytes are never read in Dart or held in memory.
final class PickedModelFile {
  final String uri;
  final String name;

  /// Bytes, or 0 when the provider didn't say.
  final int size;
  const PickedModelFile({
    required this.uri,
    required this.name,
    required this.size,
  });
}

/// Native error from the import channel; [code] is one of `no_space`,
/// `cancelled`, `unreadable`, `no_picker`, `no_activity`, `failed`.
final class ModelFileException implements Exception {
  final String code;
  final String message;
  const ModelFileException(this.code, this.message);
  @override
  String toString() => 'ModelFileException($code): $message';
}

/// Picks a model file with the system picker (SAF / UIDocumentPicker) and
/// stream-copies it into app storage natively. This replaces `file_selector`
/// for GGUFs: that plugin reads the whole file into a Java byte[] on Android
/// and dies with OutOfMemoryError on any realistic model.
///
/// Native side: `third_party/dhruva_connectors` (ModelImport.kt, the iOS
/// plugin), channel `app.dhruva/model_import`.
class ModelFileChannel {
  ModelFileChannel({MethodChannel? channel})
    : _ch = channel ?? const MethodChannel(channelName) {
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'progress') return null;
      final a = call.arguments;
      if (a is Map && a['copied'] is int && a['total'] is int) {
        _onProgress?.call(a['copied'] as int, a['total'] as int);
      }
      return null;
    });
  }

  static const channelName = 'app.dhruva/model_import';
  final MethodChannel _ch;
  void Function(int copied, int total)? _onProgress;

  /// Null when the user cancels the picker.
  Future<PickedModelFile?> pick() async {
    try {
      final raw = await _ch.invokeMapMethod<String, Object?>('pick');
      if (raw == null) return null;
      final uri = raw['uri'];
      final name = raw['name'];
      final size = raw['size'];
      if (uri is! String || uri.isEmpty) return null;
      final base = name is String ? p.basename(name) : '';
      return PickedModelFile(
        uri: uri,
        name: base == '.' || base == '..' ? '' : base,
        size: size is int && size > 0 ? size : 0,
      );
    } on PlatformException catch (e) {
      throw ModelFileException(e.code, e.message ?? 'Could not pick a file.');
    }
  }

  /// Streams [file] to [destPath] in native chunks; resolves with the bytes
  /// written. [cancelled] completing stops the copy (native then rejects with
  /// `cancelled` and removes the partial file).
  Future<int> copy(
    PickedModelFile file,
    String destPath, {
    void Function(int copied, int total)? onProgress,
    Future<void>? cancelled,
  }) async {
    _onProgress = onProgress;
    if (cancelled != null) {
      unawaited(cancelled.then((_) => _ch.invokeMethod<void>('cancel')));
    }
    try {
      final n = await _ch.invokeMethod<int>('copy', {
        'uri': file.uri,
        'dest': destPath,
      });
      return n ?? 0;
    } on PlatformException catch (e) {
      throw ModelFileException(e.code, e.message ?? 'Could not copy the file.');
    } finally {
      _onProgress = null;
    }
  }
}
