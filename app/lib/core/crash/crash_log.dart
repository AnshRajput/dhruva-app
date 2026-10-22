/// Opt-in, local-only crash log. Records uncaught errors to a JSON-lines file
/// in the app support directory. NOTHING here touches the network: a report
/// leaves the phone only when the user taps Share or Email.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const crashMaxRecords = 20;
const crashMaxMessage = 500;
const crashMaxStack = 8 * 1024;

String _cut(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…[truncated]';

@immutable
class CrashRecord {
  const CrashRecord({
    required this.timestamp,
    required this.appVersion,
    required this.appBuild,
    required this.platform,
    required this.osVersion,
    required this.errorType,
    required this.message,
    required this.stack,
  });

  /// UTC.
  final DateTime timestamp;
  final String appVersion;
  final String appBuild;
  final String platform;
  final String osVersion;
  final String errorType;
  final String message;
  final String stack;

  Map<String, Object?> toJson() => {
    'ts': timestamp.toUtc().toIso8601String(),
    'version': appVersion,
    'build': appBuild,
    'platform': platform,
    'os': osVersion,
    'type': errorType,
    'message': message,
    'stack': stack,
  };

  /// Throws on a malformed map; callers skip such lines.
  factory CrashRecord.fromJson(Map<String, dynamic> j) => CrashRecord(
    timestamp: DateTime.parse(j['ts'] as String).toUtc(),
    appVersion: j['version'] as String? ?? '',
    appBuild: j['build'] as String? ?? '',
    platform: j['platform'] as String? ?? '',
    osVersion: j['os'] as String? ?? '',
    errorType: j['type'] as String? ?? 'Error',
    message: j['message'] as String? ?? '',
    stack: j['stack'] as String? ?? '',
  );

  String get firstLine => message.split('\n').first;

  /// Plain text for one record.
  String toText() =>
      '${timestamp.toIso8601String()}\n'
      'Dhruva $appVersion (build $appBuild) · $platform $osVersion\n'
      '$errorType: $message\n$stack';
}

/// Plain-text report: a short header saying exactly what is included.
String formatCrashReport(List<CrashRecord> records) =>
    'Dhruva AI crash report\n'
    'Included: app version, phone OS, error type, error message and stack '
    'trace. No chats, prompts or files.\n'
    'Shared only because you chose to.\n\n'
    '${records.map((r) => r.toText()).join('\n\n---\n\n')}';

class CrashLog {
  CrashLog({
    Future<Directory> Function()? dir,
    DateTime Function()? now,
    this.appVersion = '',
    this.appBuild = '',
    String? platform,
    String? osVersion,
  }) : _dir = dir ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _platform = platform,
       _os = osVersion;

  final Future<Directory> Function() _dir;
  final DateTime Function() _now;
  final String appVersion;
  final String appBuild;
  final String? _platform;
  final String? _os;

  // Serialises writes so two quick errors don't clobber each other.
  Future<void> _queue = Future.value();

  Future<File> _file(String name) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$name');

  /// Never throws.
  Future<void> record(Object error, StackTrace? stack) {
    final next = _queue.then((_) async {
      try {
        final r = CrashRecord(
          timestamp: _now().toUtc(),
          appVersion: appVersion,
          appBuild: appBuild,
          platform: _platform ?? Platform.operatingSystem,
          osVersion: _os ?? Platform.operatingSystemVersion,
          errorType: error.runtimeType.toString(),
          message: _cut(error.toString(), crashMaxMessage),
          stack: _cut((stack ?? StackTrace.empty).toString(), crashMaxStack),
        );
        final keep = (await _readOldestFirst()).toList()..add(r);
        final tail = keep.length > crashMaxRecords
            ? keep.sublist(keep.length - crashMaxRecords)
            : keep;
        final f = await _file('crash_reports.jsonl');
        await f.writeAsString(
          '${tail.map((e) => jsonEncode(e.toJson())).join('\n')}\n',
          flush: true,
        );
      } catch (_) {
        // Crash logging must never crash.
      }
    });
    _queue = next;
    return next;
  }

  /// Oldest first. Corrupt lines are skipped. Never throws.
  Future<List<CrashRecord>> _readOldestFirst() async {
    try {
      final f = await _file('crash_reports.jsonl');
      if (!f.existsSync()) return const [];
      final out = <CrashRecord>[];
      for (final line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          out.add(
            CrashRecord.fromJson(jsonDecode(line) as Map<String, dynamic>),
          );
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Newest first.
  Future<List<CrashRecord>> readAll() async =>
      (await _readOldestFirst()).reversed.toList();

  /// Reports newer than the last one the user saw or dismissed.
  Future<List<CrashRecord>> unseen() async {
    final all = await readAll();
    final seen = await _lastSeen();
    return seen == null
        ? all
        : all.where((r) => r.timestamp.isAfter(seen)).toList();
  }

  Future<DateTime?> _lastSeen() async {
    try {
      final f = await _file('crash_seen.txt');
      if (!f.existsSync()) return null;
      return DateTime.tryParse((await f.readAsString()).trim())?.toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Marks everything currently logged as seen. Never throws.
  Future<void> markSeen() async {
    try {
      final all = await readAll();
      if (all.isEmpty) return;
      final f = await _file('crash_seen.txt');
      await f.writeAsString(all.first.timestamp.toIso8601String());
    } catch (_) {}
  }

  /// Never throws.
  Future<void> clear() async {
    try {
      final f = await _file('crash_reports.jsonl');
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Hooks FlutterError + PlatformDispatcher. Behaviour is otherwise
  /// unchanged: errors still print and still propagate to the engine.
  void install() {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(record(details.exception, details.stack));
      (prevFlutter ?? FlutterError.presentError)(details);
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record(error, stack));
      return prevPlatform?.call(error, stack) ?? false;
    };
  }
}

final crashLogProvider = Provider<CrashLog>((ref) => CrashLog());

/// All reports, newest first. Invalidate after changes.
final crashReportsProvider = FutureProvider<List<CrashRecord>>(
  (ref) => ref.watch(crashLogProvider).readAll(),
);

/// Reports the user hasn't seen yet (drives the Chats banner).
final unseenCrashReportsProvider = FutureProvider<List<CrashRecord>>(
  (ref) => ref.watch(crashLogProvider).unseen(),
);
