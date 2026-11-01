/// Files/notes folder: the user grants ONE folder through the system picker
/// (Android SAF tree / iOS security-scoped bookmark); `.txt`, `.md` and `.pdf`
/// files under it are read through the OS (never by raw path, never with
/// all-files storage access) and indexed with the doc-chat extractor, which
/// already runs in its own isolate under size, time and memory limits.
///
/// Indexing is heavy, so it runs only when the user asks ([indexNow]) or while
/// the phone is charging ([sync]). Limits: [maxFolderFiles] files, 20 MB per
/// file (`maxDocumentBytes`), [maxSectionsPerFile] 8 KB sections stored per
/// file.
///
/// Safety: the native side lists and reads only inside the granted tree and
/// skips symlinks; this side additionally accepts only plain file names with a
/// supported extension, and copies each file into its own temp path (never a
/// path derived from the file name) before extraction.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../docs/document_extractor.dart';
import 'base_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart';

const maxFolderFiles = 2000;

/// A file section is one `items` row; a file stores at most this many.
const maxSectionsPerFile = 6;

const _supportedExtensions = {'.txt', '.md', '.markdown', '.pdf'};

/// While not charging, re-check the charger every this many files.
const _chargeRecheckEvery = 10;

int _tempCounter = 0;

/// True for a name we are willing to index: no separators, no NUL, supported
/// extension. Public for tests.
bool isIndexableName(String name) {
  if (name.isEmpty || name.length > 255) return false;
  if (name.contains('/') || name.contains('\\') || name.contains('\u0000')) {
    return false;
  }
  if (name == '.' || name == '..') return false;
  return _supportedExtensions.contains(p.extension(name).toLowerCase());
}

class FolderConnector extends BaseConnector {
  FolderConnector({
    required ConnectorStore store,
    required this.source,
    required this.cacheDirectory,
    required this.isCharging,
    DocumentExtractor? extractor,
  }) : extractor = extractor ?? extractDocumentFile,
       super(store);

  final FolderSource source;

  /// Where fetched files are copied for extraction (deleted right after).
  final Directory cacheDirectory;
  final ChargingProbe isCharging;
  final DocumentExtractor extractor;

  @override
  String get id => ConnectorIds.folder;

  @override
  String get displayName => 'Files folder';

  static const _gone =
      'The folder is no longer available. Choose it again to keep searching '
      'your files.';

  String? _grantId(ConnectorAccount? a) => a?.config['grantId'] as String?;

  @override
  Future<ConnectorStatus> evaluate(ConnectorAccount? account) async {
    if (account == null) return ConnectorStatus.notConnected;
    final grant = _grantId(account);
    if (grant == null || !await source.isReachable(grant)) {
      return ConnectorStatus(
        ConnectorState.needsAttention,
        detail: _gone,
        lastSyncAt: account.lastSyncAt,
      );
    }
    if (account.lastError != null) {
      return ConnectorStatus(
        ConnectorState.needsAttention,
        detail: account.lastError,
        lastSyncAt: account.lastSyncAt,
      );
    }
    return ConnectorStatus(
      ConnectorState.connected,
      lastSyncAt: account.lastSyncAt,
    );
  }

  @override
  Future<ConnectorStatus> doConnect() async {
    final FolderGrant? grant;
    try {
      grant = await source.pick();
    } catch (_) {
      return const ConnectorStatus(
        ConnectorState.needsAttention,
        detail: 'Could not open the folder picker. Try again.',
      );
    }
    // Cancelled: nothing changes (a previous grant, if any, stays).
    if (grant == null) {
      return (await store.account(id)) == null
          ? ConnectorStatus.notConnected
          : await evaluate(await store.account(id));
    }
    final previous = _grantId(await store.account(id));
    if (previous != null && previous != grant.id) {
      await source.release(previous).catchError((_) {});
    }
    await store.saveAccount(
      id,
      status: 'connected',
      label: grant.name,
      config: {'grantId': grant.id, 'name': grant.name},
      clearError: true,
    );
    return evaluate(await store.account(id));
  }

  bool _explicit = false;

  /// Explicit "index now" from the Library screen: runs regardless of power.
  Future<SyncResult> indexNow() async {
    _explicit = true;
    try {
      return await sync();
    } finally {
      _explicit = false;
    }
  }

  /// Scheduled / on-open sync: indexes only while charging (unless this run
  /// came from [indexNow]).
  @override
  Future<SyncResult> doSync(ConnectorAccount account, DateTime? since) async {
    final isExplicit = _explicit;
    final grant = _grantId(account);
    if (grant == null || !await source.isReachable(grant)) {
      throw const ConnectorException(ConnectorState.needsAttention, _gone);
    }
    if (!isExplicit && !await isCharging()) {
      return const SyncResult.skipped(
        'Your files are indexed while the phone is charging.',
      );
    }

    final List<FolderEntry> listed;
    try {
      listed = await source.list(grant, maxFiles: maxFolderFiles);
    } catch (_) {
      throw const ConnectorException(
        ConnectorState.needsAttention,
        'Could not read the folder. Check that it still exists, then try '
        'again.',
      );
    }
    final entries = [
      for (final e in listed.take(maxFolderFiles))
        if (isIndexableName(e.name) && e.size >= 0) e,
    ];
    final ids = {for (final e in entries) e.id};

    // What is already indexed: file id -> (mtime, size) of its first section.
    final known = <String, ({int mtime, int size})>{};
    final stored = await store.itemsOf(id, kind: ItemKind.file);
    final storedIds = <String>{};
    for (final i in stored) {
      final base = i.externalId.split('#').first;
      storedIds.add(base);
      if (i.externalId == base) {
        known[base] = (
          mtime: (i.flags['mtime'] as int?) ?? -1,
          size: (i.flags['size'] as int?) ?? -1,
        );
      }
    }
    // Files that left the folder leave the index.
    for (final gone in storedIds.where((s) => !ids.contains(s))) {
      await store.removeByIdPrefix(id, gone);
    }

    var read = 0, changed = 0, processed = 0;
    for (final entry in entries) {
      final mtime = entry.modified.millisecondsSinceEpoch ~/ 1000;
      final old = known[entry.id];
      if (old != null && old.mtime == mtime && old.size == entry.size) continue;
      if (!isExplicit &&
          processed > 0 &&
          processed % _chargeRecheckEvery == 0 &&
          !await isCharging()) {
        // Unplugged mid-run: keep what is done, finish next charge.
        break;
      }
      processed++;
      final drafts = await _fetchAndExtract(grant, entry, mtime);
      await store.removeByIdPrefix(id, entry.id);
      final r = await store.upsertItems(id, drafts);
      read++;
      changed += r.changed;
    }
    return SyncResult(read: read, changed: changed);
  }

  Future<List<ItemDraft>> _fetchAndExtract(
    String grant,
    FolderEntry entry,
    int mtime,
  ) async {
    Map<String, Object?> flags(Map<String, Object?> extra) => {
      'mtime': mtime,
      'size': entry.size,
      'name': entry.name,
      ...extra,
    };
    ItemDraft placeholder(String reason) => ItemDraft(
      externalId: entry.id,
      kind: ItemKind.file,
      title: entry.name,
      sentAt: entry.modified,
      flags: flags({'unreadable': reason}),
    );

    if (entry.size > maxDocumentBytes) return [placeholder('tooLarge')];
    await cacheDirectory.create(recursive: true);
    // A fresh random-ish name: never the file's own name (no traversal, no
    // collisions between two files called notes.md).
    final temp = File(
      p.join(
        cacheDirectory.path,
        'f${DateTime.now().microsecondsSinceEpoch}_${_tempCounter++}.bin',
      ),
    );
    try {
      await source.fetch(grant, entry, temp.path, maxBytes: maxDocumentBytes);
      final ExtractedDocument doc;
      try {
        doc = await extractor(temp.path, entry.name);
      } on DocumentException catch (e) {
        return [placeholder(e.kind.name)];
      }
      return _sections(entry, doc, flags);
    } on FolderFetchException {
      return [placeholder('unreadable')];
    } finally {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on FileSystemException {
        // Cleared with the cache.
      }
    }
  }

  List<ItemDraft> _sections(
    FolderEntry entry,
    ExtractedDocument doc,
    Map<String, Object?> Function(Map<String, Object?>) flags,
  ) {
    final sections = <({int page, StringBuffer text})>[];
    for (final c in doc.chunks) {
      if (sections.isEmpty ||
          sections.last.text.length + c.text.length + 1 > maxItemBodyChars) {
        if (sections.length == maxSectionsPerFile) break;
        sections.add((page: c.page, text: StringBuffer()));
      }
      if (sections.last.text.isNotEmpty) sections.last.text.write('\n');
      sections.last.text.write(c.text);
    }
    if (sections.isEmpty) {
      return [
        ItemDraft(
          externalId: entry.id,
          kind: ItemKind.file,
          title: entry.name,
          sentAt: entry.modified,
          flags: flags({'unreadable': 'empty'}),
        ),
      ];
    }
    return [
      for (var i = 0; i < sections.length; i++)
        ItemDraft(
          externalId: i == 0 ? entry.id : '${entry.id}#${i + 1}',
          kind: ItemKind.file,
          title: entry.name,
          body: sections[i].text.toString(),
          sentAt: entry.modified,
          flags: flags({
            'mime': doc.mime,
            'section': i + 1,
            'page': sections[i].page,
            if (doc.paged) 'pages': doc.pageCount,
          }),
        ),
    ];
  }

  @override
  Future<void> onRevoke(ConnectorAccount? account) async {
    final grant = _grantId(account);
    if (grant != null) await source.release(grant);
  }

  @override
  Future<void> openSystemSettings() => source.openSettings();
}
