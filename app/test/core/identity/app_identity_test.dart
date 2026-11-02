// AppIdentity (daily-assistant Wave 1): one file owns the product name, so a
// rename is a one-line change. Guards against hardcoded names creeping back
// into UI strings.

import 'dart:io';

import 'package:dhruva/core/identity/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes name, short name, wordmark and tagline', () {
    expect(AppIdentity.productName, isNotEmpty);
    expect(AppIdentity.shortName, isNotEmpty);
    expect(AppIdentity.wordmark, isNotEmpty);
    expect(AppIdentity.tagline, isNotEmpty);
    expect(AppIdentity.productName, contains(AppIdentity.shortName));
  });

  test('no UI string literal in lib/ hardcodes the product name', () {
    // A string literal containing "Dhruva" (capital D) outside the identity
    // file. The About page's pole-star myth is about the legend, not the
    // product, so that one file is exempt.
    // One pattern per quote style, so a "... can't ..." string (an
    // apostrophe inside double quotes) is still caught.
    final literal = RegExp(
      r'''('[^'\n]*Dhruva[^'\n]*')|("[^"\n]*Dhruva[^"\n]*")''',
    );
    const exempt = {
      'lib/core/identity/app_identity.dart',
      'lib/features/settings/ui/about_screen.dart',
    };
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (exempt.contains(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('import ')) continue;
        // Strip interpolations of AppIdentity before matching.
        final cleaned = line.replaceAll(RegExp(r'\$\{AppIdentity\.\w+\}'), '');
        if (literal.hasMatch(cleaned)) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the About page title and wordmark come from AppIdentity', () {
    final about = File(
      'lib/features/settings/ui/about_screen.dart',
    ).readAsStringSync();
    expect(about, contains('AppIdentity.productName'));
    final today = File(
      'lib/features/today/ui/today_screen.dart',
    ).readAsStringSync();
    expect(today, contains('AppIdentity.wordmark'));
  });
}
