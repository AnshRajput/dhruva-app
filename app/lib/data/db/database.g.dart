// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $InstalledModelsTable extends InstalledModels
    with TableInfo<$InstalledModelsTable, InstalledModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstalledModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _repoIdMeta = const VerificationMeta('repoId');
  @override
  late final GeneratedColumn<String> repoId = GeneratedColumn<String>(
    'repo_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantMeta = const VerificationMeta('quant');
  @override
  late final GeneratedColumn<String> quant = GeneratedColumn<String>(
    'quant',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _licenseMeta = const VerificationMeta(
    'license',
  );
  @override
  late final GeneratedColumn<String> license = GeneratedColumn<String>(
    'license',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gatedMeta = const VerificationMeta('gated');
  @override
  late final GeneratedColumn<bool> gated = GeneratedColumn<bool>(
    'gated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("gated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _downloadedAtMeta = const VerificationMeta(
    'downloadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> downloadedAt = GeneratedColumn<DateTime>(
    'downloaded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    repoId,
    fileName,
    quant,
    sizeBytes,
    sha256,
    localPath,
    license,
    gated,
    downloadedAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installed_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstalledModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('repo_id')) {
      context.handle(
        _repoIdMeta,
        repoId.isAcceptableOrUnknown(data['repo_id']!, _repoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_repoIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('quant')) {
      context.handle(
        _quantMeta,
        quant.isAcceptableOrUnknown(data['quant']!, _quantMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('license')) {
      context.handle(
        _licenseMeta,
        license.isAcceptableOrUnknown(data['license']!, _licenseMeta),
      );
    }
    if (data.containsKey('gated')) {
      context.handle(
        _gatedMeta,
        gated.isAcceptableOrUnknown(data['gated']!, _gatedMeta),
      );
    }
    if (data.containsKey('downloaded_at')) {
      context.handle(
        _downloadedAtMeta,
        downloadedAt.isAcceptableOrUnknown(
          data['downloaded_at']!,
          _downloadedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_downloadedAtMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {repoId, fileName},
  ];
  @override
  InstalledModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstalledModel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      repoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repo_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      quant: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quant'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      license: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license'],
      ),
      gated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}gated'],
      )!,
      downloadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}downloaded_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
    );
  }

  @override
  $InstalledModelsTable createAlias(String alias) {
    return $InstalledModelsTable(attachedDatabase, alias);
  }
}

class InstalledModel extends DataClass implements Insertable<InstalledModel> {
  final int id;
  final String repoId;
  final String fileName;
  final String? quant;
  final int sizeBytes;
  final String? sha256;
  final String localPath;
  final String? license;
  final bool gated;
  final DateTime downloadedAt;
  final DateTime? lastUsedAt;
  const InstalledModel({
    required this.id,
    required this.repoId,
    required this.fileName,
    this.quant,
    required this.sizeBytes,
    this.sha256,
    required this.localPath,
    this.license,
    required this.gated,
    required this.downloadedAt,
    this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['repo_id'] = Variable<String>(repoId);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || quant != null) {
      map['quant'] = Variable<String>(quant);
    }
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || license != null) {
      map['license'] = Variable<String>(license);
    }
    map['gated'] = Variable<bool>(gated);
    map['downloaded_at'] = Variable<DateTime>(downloadedAt);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    return map;
  }

  InstalledModelsCompanion toCompanion(bool nullToAbsent) {
    return InstalledModelsCompanion(
      id: Value(id),
      repoId: Value(repoId),
      fileName: Value(fileName),
      quant: quant == null && nullToAbsent
          ? const Value.absent()
          : Value(quant),
      sizeBytes: Value(sizeBytes),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      localPath: Value(localPath),
      license: license == null && nullToAbsent
          ? const Value.absent()
          : Value(license),
      gated: Value(gated),
      downloadedAt: Value(downloadedAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
    );
  }

  factory InstalledModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstalledModel(
      id: serializer.fromJson<int>(json['id']),
      repoId: serializer.fromJson<String>(json['repoId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      quant: serializer.fromJson<String?>(json['quant']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      localPath: serializer.fromJson<String>(json['localPath']),
      license: serializer.fromJson<String?>(json['license']),
      gated: serializer.fromJson<bool>(json['gated']),
      downloadedAt: serializer.fromJson<DateTime>(json['downloadedAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'repoId': serializer.toJson<String>(repoId),
      'fileName': serializer.toJson<String>(fileName),
      'quant': serializer.toJson<String?>(quant),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'sha256': serializer.toJson<String?>(sha256),
      'localPath': serializer.toJson<String>(localPath),
      'license': serializer.toJson<String?>(license),
      'gated': serializer.toJson<bool>(gated),
      'downloadedAt': serializer.toJson<DateTime>(downloadedAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
    };
  }

  InstalledModel copyWith({
    int? id,
    String? repoId,
    String? fileName,
    Value<String?> quant = const Value.absent(),
    int? sizeBytes,
    Value<String?> sha256 = const Value.absent(),
    String? localPath,
    Value<String?> license = const Value.absent(),
    bool? gated,
    DateTime? downloadedAt,
    Value<DateTime?> lastUsedAt = const Value.absent(),
  }) => InstalledModel(
    id: id ?? this.id,
    repoId: repoId ?? this.repoId,
    fileName: fileName ?? this.fileName,
    quant: quant.present ? quant.value : this.quant,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256.present ? sha256.value : this.sha256,
    localPath: localPath ?? this.localPath,
    license: license.present ? license.value : this.license,
    gated: gated ?? this.gated,
    downloadedAt: downloadedAt ?? this.downloadedAt,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
  );
  InstalledModel copyWithCompanion(InstalledModelsCompanion data) {
    return InstalledModel(
      id: data.id.present ? data.id.value : this.id,
      repoId: data.repoId.present ? data.repoId.value : this.repoId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      quant: data.quant.present ? data.quant.value : this.quant,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      license: data.license.present ? data.license.value : this.license,
      gated: data.gated.present ? data.gated.value : this.gated,
      downloadedAt: data.downloadedAt.present
          ? data.downloadedAt.value
          : this.downloadedAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstalledModel(')
          ..write('id: $id, ')
          ..write('repoId: $repoId, ')
          ..write('fileName: $fileName, ')
          ..write('quant: $quant, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('localPath: $localPath, ')
          ..write('license: $license, ')
          ..write('gated: $gated, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    repoId,
    fileName,
    quant,
    sizeBytes,
    sha256,
    localPath,
    license,
    gated,
    downloadedAt,
    lastUsedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstalledModel &&
          other.id == this.id &&
          other.repoId == this.repoId &&
          other.fileName == this.fileName &&
          other.quant == this.quant &&
          other.sizeBytes == this.sizeBytes &&
          other.sha256 == this.sha256 &&
          other.localPath == this.localPath &&
          other.license == this.license &&
          other.gated == this.gated &&
          other.downloadedAt == this.downloadedAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class InstalledModelsCompanion extends UpdateCompanion<InstalledModel> {
  final Value<int> id;
  final Value<String> repoId;
  final Value<String> fileName;
  final Value<String?> quant;
  final Value<int> sizeBytes;
  final Value<String?> sha256;
  final Value<String> localPath;
  final Value<String?> license;
  final Value<bool> gated;
  final Value<DateTime> downloadedAt;
  final Value<DateTime?> lastUsedAt;
  const InstalledModelsCompanion({
    this.id = const Value.absent(),
    this.repoId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.quant = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.localPath = const Value.absent(),
    this.license = const Value.absent(),
    this.gated = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
  });
  InstalledModelsCompanion.insert({
    this.id = const Value.absent(),
    required String repoId,
    required String fileName,
    this.quant = const Value.absent(),
    required int sizeBytes,
    this.sha256 = const Value.absent(),
    required String localPath,
    this.license = const Value.absent(),
    this.gated = const Value.absent(),
    required DateTime downloadedAt,
    this.lastUsedAt = const Value.absent(),
  }) : repoId = Value(repoId),
       fileName = Value(fileName),
       sizeBytes = Value(sizeBytes),
       localPath = Value(localPath),
       downloadedAt = Value(downloadedAt);
  static Insertable<InstalledModel> custom({
    Expression<int>? id,
    Expression<String>? repoId,
    Expression<String>? fileName,
    Expression<String>? quant,
    Expression<int>? sizeBytes,
    Expression<String>? sha256,
    Expression<String>? localPath,
    Expression<String>? license,
    Expression<bool>? gated,
    Expression<DateTime>? downloadedAt,
    Expression<DateTime>? lastUsedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (repoId != null) 'repo_id': repoId,
      if (fileName != null) 'file_name': fileName,
      if (quant != null) 'quant': quant,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
      if (localPath != null) 'local_path': localPath,
      if (license != null) 'license': license,
      if (gated != null) 'gated': gated,
      if (downloadedAt != null) 'downloaded_at': downloadedAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
    });
  }

  InstalledModelsCompanion copyWith({
    Value<int>? id,
    Value<String>? repoId,
    Value<String>? fileName,
    Value<String?>? quant,
    Value<int>? sizeBytes,
    Value<String?>? sha256,
    Value<String>? localPath,
    Value<String?>? license,
    Value<bool>? gated,
    Value<DateTime>? downloadedAt,
    Value<DateTime?>? lastUsedAt,
  }) {
    return InstalledModelsCompanion(
      id: id ?? this.id,
      repoId: repoId ?? this.repoId,
      fileName: fileName ?? this.fileName,
      quant: quant ?? this.quant,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      localPath: localPath ?? this.localPath,
      license: license ?? this.license,
      gated: gated ?? this.gated,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (repoId.present) {
      map['repo_id'] = Variable<String>(repoId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (quant.present) {
      map['quant'] = Variable<String>(quant.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (license.present) {
      map['license'] = Variable<String>(license.value);
    }
    if (gated.present) {
      map['gated'] = Variable<bool>(gated.value);
    }
    if (downloadedAt.present) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstalledModelsCompanion(')
          ..write('id: $id, ')
          ..write('repoId: $repoId, ')
          ..write('fileName: $fileName, ')
          ..write('quant: $quant, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('localPath: $localPath, ')
          ..write('license: $license, ')
          ..write('gated: $gated, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $InstalledModelsTable installedModels = $InstalledModelsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [installedModels];
}

typedef $$InstalledModelsTableCreateCompanionBuilder =
    InstalledModelsCompanion Function({
      Value<int> id,
      required String repoId,
      required String fileName,
      Value<String?> quant,
      required int sizeBytes,
      Value<String?> sha256,
      required String localPath,
      Value<String?> license,
      Value<bool> gated,
      required DateTime downloadedAt,
      Value<DateTime?> lastUsedAt,
    });
typedef $$InstalledModelsTableUpdateCompanionBuilder =
    InstalledModelsCompanion Function({
      Value<int> id,
      Value<String> repoId,
      Value<String> fileName,
      Value<String?> quant,
      Value<int> sizeBytes,
      Value<String?> sha256,
      Value<String> localPath,
      Value<String?> license,
      Value<bool> gated,
      Value<DateTime> downloadedAt,
      Value<DateTime?> lastUsedAt,
    });

class $$InstalledModelsTableFilterComposer
    extends Composer<_$AppDatabase, $InstalledModelsTable> {
  $$InstalledModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repoId => $composableBuilder(
    column: $table.repoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quant => $composableBuilder(
    column: $table.quant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get gated => $composableBuilder(
    column: $table.gated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstalledModelsTableOrderingComposer
    extends Composer<_$AppDatabase, $InstalledModelsTable> {
  $$InstalledModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repoId => $composableBuilder(
    column: $table.repoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quant => $composableBuilder(
    column: $table.quant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get license => $composableBuilder(
    column: $table.license,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get gated => $composableBuilder(
    column: $table.gated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstalledModelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstalledModelsTable> {
  $$InstalledModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get repoId =>
      $composableBuilder(column: $table.repoId, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get quant =>
      $composableBuilder(column: $table.quant, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get license =>
      $composableBuilder(column: $table.license, builder: (column) => column);

  GeneratedColumn<bool> get gated =>
      $composableBuilder(column: $table.gated, builder: (column) => column);

  GeneratedColumn<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$InstalledModelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InstalledModelsTable,
          InstalledModel,
          $$InstalledModelsTableFilterComposer,
          $$InstalledModelsTableOrderingComposer,
          $$InstalledModelsTableAnnotationComposer,
          $$InstalledModelsTableCreateCompanionBuilder,
          $$InstalledModelsTableUpdateCompanionBuilder,
          (
            InstalledModel,
            BaseReferences<
              _$AppDatabase,
              $InstalledModelsTable,
              InstalledModel
            >,
          ),
          InstalledModel,
          PrefetchHooks Function()
        > {
  $$InstalledModelsTableTableManager(
    _$AppDatabase db,
    $InstalledModelsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstalledModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstalledModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstalledModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> repoId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String?> quant = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String?> license = const Value.absent(),
                Value<bool> gated = const Value.absent(),
                Value<DateTime> downloadedAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
              }) => InstalledModelsCompanion(
                id: id,
                repoId: repoId,
                fileName: fileName,
                quant: quant,
                sizeBytes: sizeBytes,
                sha256: sha256,
                localPath: localPath,
                license: license,
                gated: gated,
                downloadedAt: downloadedAt,
                lastUsedAt: lastUsedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String repoId,
                required String fileName,
                Value<String?> quant = const Value.absent(),
                required int sizeBytes,
                Value<String?> sha256 = const Value.absent(),
                required String localPath,
                Value<String?> license = const Value.absent(),
                Value<bool> gated = const Value.absent(),
                required DateTime downloadedAt,
                Value<DateTime?> lastUsedAt = const Value.absent(),
              }) => InstalledModelsCompanion.insert(
                id: id,
                repoId: repoId,
                fileName: fileName,
                quant: quant,
                sizeBytes: sizeBytes,
                sha256: sha256,
                localPath: localPath,
                license: license,
                gated: gated,
                downloadedAt: downloadedAt,
                lastUsedAt: lastUsedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstalledModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InstalledModelsTable,
      InstalledModel,
      $$InstalledModelsTableFilterComposer,
      $$InstalledModelsTableOrderingComposer,
      $$InstalledModelsTableAnnotationComposer,
      $$InstalledModelsTableCreateCompanionBuilder,
      $$InstalledModelsTableUpdateCompanionBuilder,
      (
        InstalledModel,
        BaseReferences<_$AppDatabase, $InstalledModelsTable, InstalledModel>,
      ),
      InstalledModel,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$InstalledModelsTableTableManager get installedModels =>
      $$InstalledModelsTableTableManager(_db, _db.installedModels);
}
