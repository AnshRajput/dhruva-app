import 'dart:io';

import 'package:dhruva/data/downloads/model_file_channel.dart';
import 'package:path/path.dart' as p;

/// Test-only [ModelFileChannel]: the file is already on the device's
/// filesystem (adb push), so "pick" is a path and "copy" is a Dart file copy.
/// Production always uses the native stream copy.
class PathCopyChannel extends ModelFileChannel {
  PathCopyChannel(this.path);
  final String path;

  PickedModelFile get picked => PickedModelFile(
    uri: path,
    name: p.basename(path),
    size: File(path).lengthSync(),
  );

  @override
  Future<int> copy(
    PickedModelFile file,
    String destPath, {
    void Function(int copied, int total)? onProgress,
    Future<void>? cancelled,
  }) async => (await File(file.uri).copy(destPath)).length();
}
