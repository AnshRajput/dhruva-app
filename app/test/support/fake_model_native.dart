import 'dart:io';

import 'package:dhruva/data/downloads/model_file_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the native half of `app.dhruva/model_import` (Kotlin
/// ModelImport / Swift ModelImport): `pick` answers with [pickResult], `copy`
/// streams a real file to the requested `dest` in small chunks, reporting
/// `progress` back to Dart like the native side does, and honours `cancel`.
class FakeModelNative {
  FakeModelNative({
    this.pickResult,
    this.pickError,
    this.copyError,
    this.failAfterBytes,
    this.chunk = 4,
  });

  /// What `pick` returns (null = user cancelled the picker).
  Map<String, Object?>? pickResult;
  String? pickError;

  /// Native error code `copy` rejects with (e.g. `no_space`, `unreadable`).
  String? copyError;

  /// Reject `copy` with [copyError] only after this many bytes are written
  /// (a disk that fills mid-copy). Null = reject immediately.
  int? failAfterBytes;
  final int chunk;

  final calls = <String>[];
  bool cancelled = false;

  /// Source bytes by uri, so a test never needs a real content provider.
  final sources = <String, File>{};

  ModelFileChannel install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(ModelFileChannel.channelName);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'pick':
          if (pickError != null) {
            throw PlatformException(code: pickError!, message: 'pick failed');
          }
          return pickResult;
        case 'cancel':
          cancelled = true;
          return null;
        case 'copy':
          final args = call.arguments as Map<Object?, Object?>;
          return _copy(
            messenger,
            args['uri']! as String,
            args['dest']! as String,
          );
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return ModelFileChannel();
  }

  Future<int> _copy(
    TestDefaultBinaryMessenger messenger,
    String uri,
    String dest,
  ) async {
    cancelled = false;
    if (copyError != null && failAfterBytes == null) {
      throw PlatformException(code: copyError!, message: 'copy failed');
    }
    final src = sources[uri];
    if (src == null) {
      throw PlatformException(code: 'unreadable', message: 'no such uri');
    }
    final bytes = src.readAsBytesSync();
    final out = File(dest).openSync(mode: FileMode.write);
    try {
      var copied = 0;
      while (copied < bytes.length) {
        // Let the Dart side's cancel call run between chunks.
        await Future<void>.delayed(Duration.zero);
        if (cancelled) {
          out.closeSync();
          File(dest).deleteSync();
          throw PlatformException(code: 'cancelled', message: 'cancelled');
        }
        final end = (copied + chunk).clamp(0, bytes.length);
        out.writeFromSync(bytes, copied, end);
        copied = end;
        if (failAfterBytes != null && copied >= failAfterBytes!) {
          out.closeSync();
          File(dest).deleteSync();
          throw PlatformException(code: copyError!, message: 'disk full');
        }
        await messenger.handlePlatformMessage(
          ModelFileChannel.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('progress', {'copied': copied, 'total': bytes.length}),
          ),
          (_) {},
        );
      }
      return copied;
    } finally {
      try {
        out.closeSync();
      } on FileSystemException {
        // already closed on an error path
      }
    }
  }

  /// A picked file backed by [file]; registers it as the `copy` source.
  PickedModelFile pickFile(File file, {String? name}) {
    final uri = 'content://fake/${file.path.hashCode}';
    sources[uri] = file;
    final picked = {
      'uri': uri,
      'name': name ?? file.uri.pathSegments.last,
      'size': file.lengthSync(),
    };
    pickResult = picked;
    return PickedModelFile(
      uri: uri,
      name: picked['name'] as String,
      size: picked['size'] as int,
    );
  }
}
