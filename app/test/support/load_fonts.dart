// Widget tests render with the Ahem box font by default, which hides width
// problems. Loads the bundled Manrope + Fraunces so a 360dp render measures
// like the device.

import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadAppFonts() async {
  for (final (family, file) in [
    ('Manrope', 'Manrope-Variable.ttf'),
    ('Fraunces', 'Fraunces-Variable.ttf'),
  ]) {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  }
}
