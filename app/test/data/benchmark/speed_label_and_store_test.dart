import 'dart:io';

import 'package:dhruva/data/benchmark/speed_label.dart';
import 'package:dhruva/data/benchmark/speed_result.dart';
import 'package:flutter_test/flutter_test.dart';

SpeedResult _result({double decode = 14.5}) => SpeedResult(
  decodeTps: decode,
  prefillTps: 210.25,
  loadMs: 1800,
  measuredAt: DateTime.utc(2026, 11, 1, 9, 30),
  appVersion: '0.6.1',
);

void main() {
  group('speedLabelFor', () {
    test('thresholds: fast >= 12, usable 5-12, slow < 5', () {
      expect(speedLabelFor(12), SpeedLabel.fast);
      expect(speedLabelFor(40), SpeedLabel.fast);
      expect(speedLabelFor(11.99), SpeedLabel.usable);
      expect(speedLabelFor(5), SpeedLabel.usable);
      expect(speedLabelFor(4.99), SpeedLabel.slow);
      expect(speedLabelFor(0), SpeedLabel.slow);
    });

    test('copy is plain language', () {
      expect(SpeedLabel.fast.message, 'Fast on your phone');
      expect(SpeedLabel.usable.message, 'Usable');
      expect(
        SpeedLabel.slow.message,
        'Slow on your phone — try a smaller model',
      );
    });
  });

  group('SpeedResultStore', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('speed_store_test');
      file = File('${dir.path}/nested/speed_results.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('missing file loads empty', () async {
      expect(await SpeedResultStore(file).load(), isEmpty);
    });

    test('round-trips results keyed by repo id + file', () async {
      final store = SpeedResultStore(file);
      final key = speedKey('bartowski/Llama-3.2-1B-GGUF', 'q4.gguf');
      await store.put(key, _result());
      await store.put('other::b.gguf', _result(decode: 3));

      final loaded = await SpeedResultStore(file).load();
      expect(loaded.keys, containsAll([key, 'other::b.gguf']));
      final r = loaded[key]!;
      expect(r.decodeTps, 14.5);
      expect(r.prefillTps, 210.25);
      expect(r.loadMs, 1800);
      expect(r.measuredAt, DateTime.utc(2026, 11, 1, 9, 30));
      expect(r.measuredAt.isUtc, isTrue);
      expect(r.appVersion, '0.6.1');
      expect(r.label, SpeedLabel.fast);
      expect(loaded['other::b.gguf']!.label, SpeedLabel.slow);
    });

    test('put overwrites the same key', () async {
      final store = SpeedResultStore(file);
      await store.put('k', _result(decode: 3));
      await store.put('k', _result(decode: 20));
      expect((await store.load())['k']!.decodeTps, 20);
    });

    test(
      'corrupt file loads empty and is recoverable by the next put',
      () async {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('{ not json ::');
        final store = SpeedResultStore(file);
        expect(await store.load(), isEmpty);
        await store.put('k', _result());
        expect((await store.load()).keys, ['k']);
      },
    );

    test('wrong top-level shape loads empty', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('[1,2,3]');
      expect(await SpeedResultStore(file).load(), isEmpty);
    });

    test('bad entries are dropped, good ones kept', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '{"good": ${_goodJson()}, "missingField": {"decodeTps": 5}, '
        '"badDate": {"decodeTps": 5, "prefillTps": 1, "loadMs": 1, '
        '"measuredAt": "nope", "appVersion": "x"}, "str": "x"}',
      );
      final loaded = await SpeedResultStore(file).load();
      expect(loaded.keys, ['good']);
    });
  });
}

String _goodJson() =>
    '{"decodeTps": 7.5, "prefillTps": 90, "loadMs": 1200, '
    '"measuredAt": "2026-11-01T09:30:00.000Z", "appVersion": "0.6.1"}';
