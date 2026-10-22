import 'dart:io';

import 'package:dhruva/core/crash/crash_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  var t = DateTime.utc(2026, 1, 1);

  CrashLog make({Future<Directory> Function()? dir}) => CrashLog(
    dir: dir ?? () async => tmp,
    now: () => t = t.add(const Duration(minutes: 1)),
    appVersion: '1.2.3',
    appBuild: '9',
    platform: 'testos',
    osVersion: 'v1',
  );

  setUp(() => tmp = Directory.systemTemp.createTempSync('crashlog'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('appends a record with metadata, newest first', () async {
    final log = make();
    await log.record(StateError('boom'), StackTrace.current);
    await log.record(ArgumentError('second'), null);
    final all = await log.readAll();
    expect(all, hasLength(2));
    expect(all.first.errorType, contains('ArgumentError'));
    expect(all.last.errorType, contains('StateError'));
    expect(all.last.appVersion, '1.2.3');
    expect(all.last.appBuild, '9');
    expect(all.last.platform, 'testos');
    expect(all.last.timestamp.isUtc, isTrue);
  });

  test('truncates message and stack', () async {
    final log = make();
    await log.record('x' * 5000, null);
    await log.record(StateError('s'), StackTrace.fromString('y' * 50000));
    final all = await log.readAll();
    expect(all.last.message.length, lessThan(crashMaxMessage + 30));
    expect(all.first.stack.length, lessThan(crashMaxStack + 30));
  });

  test('caps at 20, keeping the newest', () async {
    final log = make();
    for (var i = 0; i < 25; i++) {
      await log.record(StateError('e$i'), null);
    }
    final all = await log.readAll();
    expect(all, hasLength(crashMaxRecords));
    expect(all.first.message, contains('e24'));
    expect(all.last.message, contains('e5'));
  });

  test('tolerates corrupt lines', () async {
    final log = make();
    await log.record(StateError('good'), null);
    final f = File('${tmp.path}/crash_reports.jsonl');
    f.writeAsStringSync('not json\n{"ts":1}\n\n${f.readAsStringSync()}');
    final all = await log.readAll();
    expect(all, hasLength(1));
    await log.record(StateError('after'), null);
    expect(await log.readAll(), hasLength(2));
  });

  test('never throws when the directory is unwritable', () async {
    final log = make(dir: () async => Directory('${tmp.path}/nope/nada'));
    await log.record(StateError('x'), null);
    expect(await log.readAll(), isEmpty);
    await log.markSeen();
    await log.clear();
    final thrower = make(dir: () => throw Exception('no dir'));
    await thrower.record(StateError('x'), null);
    expect(await thrower.unseen(), isEmpty);
  });

  test('unseen / markSeen / clear', () async {
    final log = make();
    await log.record(StateError('a'), null);
    expect(await log.unseen(), hasLength(1));
    await log.markSeen();
    expect(await log.unseen(), isEmpty);
    await log.record(StateError('b'), null);
    expect(await log.unseen(), hasLength(1));
    await log.clear();
    expect(await log.readAll(), isEmpty);
  });

  test('report text has header and records', () async {
    final log = make();
    await log.record(StateError('boom'), null);
    final text = formatCrashReport(await log.readAll());
    expect(text, contains('No chats, prompts or files'));
    expect(text, contains('boom'));
  });
}
