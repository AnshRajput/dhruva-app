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

class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta(
    'sortIndex',
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, sortIndex];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final int id;
  final String name;
  final int sortIndex;
  const Folder({required this.id, required this.name, required this.sortIndex});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['sort_index'] = Variable<int>(sortIndex);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      name: Value(name),
      sortIndex: Value(sortIndex),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'sortIndex': serializer.toJson<int>(sortIndex),
    };
  }

  Folder copyWith({int? id, String? name, int? sortIndex}) => Folder(
    id: id ?? this.id,
    name: name ?? this.name,
    sortIndex: sortIndex ?? this.sortIndex,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortIndex: $sortIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortIndex == this.sortIndex);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> sortIndex;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortIndex = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.sortIndex = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Folder> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? sortIndex,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortIndex != null) 'sort_index': sortIndex,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? sortIndex,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortIndex: $sortIndex')
          ..write(')'))
        .toString();
  }
}

class $CharactersTable extends Characters
    with TableInfo<$CharactersTable, Character> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharactersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarEmojiMeta = const VerificationMeta(
    'avatarEmoji',
  );
  @override
  late final GeneratedColumn<String> avatarEmoji = GeneratedColumn<String>(
    'avatar_emoji',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarPathMeta = const VerificationMeta(
    'avatarPath',
  );
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
    'avatar_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _personaSystemPromptMeta =
      const VerificationMeta('personaSystemPrompt');
  @override
  late final GeneratedColumn<String> personaSystemPrompt =
      GeneratedColumn<String>(
        'persona_system_prompt',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _greetingMeta = const VerificationMeta(
    'greeting',
  );
  @override
  late final GeneratedColumn<String> greeting = GeneratedColumn<String>(
    'greeting',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exampleDialoguesMeta = const VerificationMeta(
    'exampleDialogues',
  );
  @override
  late final GeneratedColumn<String> exampleDialogues = GeneratedColumn<String>(
    'example_dialogues',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultModelIdMeta = const VerificationMeta(
    'defaultModelId',
  );
  @override
  late final GeneratedColumn<int> defaultModelId = GeneratedColumn<int>(
    'default_model_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES installed_models (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _samplingParamsJsonMeta =
      const VerificationMeta('samplingParamsJson');
  @override
  late final GeneratedColumn<String> samplingParamsJson =
      GeneratedColumn<String>(
        'sampling_params_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isBuiltInMeta = const VerificationMeta(
    'isBuiltIn',
  );
  @override
  late final GeneratedColumn<bool> isBuiltIn = GeneratedColumn<bool>(
    'is_built_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_built_in" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatarEmoji,
    avatarPath,
    personaSystemPrompt,
    greeting,
    exampleDialogues,
    defaultModelId,
    samplingParamsJson,
    isBuiltIn,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'characters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Character> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar_emoji')) {
      context.handle(
        _avatarEmojiMeta,
        avatarEmoji.isAcceptableOrUnknown(
          data['avatar_emoji']!,
          _avatarEmojiMeta,
        ),
      );
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
        _avatarPathMeta,
        avatarPath.isAcceptableOrUnknown(data['avatar_path']!, _avatarPathMeta),
      );
    }
    if (data.containsKey('persona_system_prompt')) {
      context.handle(
        _personaSystemPromptMeta,
        personaSystemPrompt.isAcceptableOrUnknown(
          data['persona_system_prompt']!,
          _personaSystemPromptMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_personaSystemPromptMeta);
    }
    if (data.containsKey('greeting')) {
      context.handle(
        _greetingMeta,
        greeting.isAcceptableOrUnknown(data['greeting']!, _greetingMeta),
      );
    }
    if (data.containsKey('example_dialogues')) {
      context.handle(
        _exampleDialoguesMeta,
        exampleDialogues.isAcceptableOrUnknown(
          data['example_dialogues']!,
          _exampleDialoguesMeta,
        ),
      );
    }
    if (data.containsKey('default_model_id')) {
      context.handle(
        _defaultModelIdMeta,
        defaultModelId.isAcceptableOrUnknown(
          data['default_model_id']!,
          _defaultModelIdMeta,
        ),
      );
    }
    if (data.containsKey('sampling_params_json')) {
      context.handle(
        _samplingParamsJsonMeta,
        samplingParamsJson.isAcceptableOrUnknown(
          data['sampling_params_json']!,
          _samplingParamsJsonMeta,
        ),
      );
    }
    if (data.containsKey('is_built_in')) {
      context.handle(
        _isBuiltInMeta,
        isBuiltIn.isAcceptableOrUnknown(data['is_built_in']!, _isBuiltInMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Character map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Character(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatarEmoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_emoji'],
      ),
      avatarPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_path'],
      ),
      personaSystemPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}persona_system_prompt'],
      )!,
      greeting: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}greeting'],
      ),
      exampleDialogues: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}example_dialogues'],
      ),
      defaultModelId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_model_id'],
      ),
      samplingParamsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sampling_params_json'],
      ),
      isBuiltIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_built_in'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CharactersTable createAlias(String alias) {
    return $CharactersTable(attachedDatabase, alias);
  }
}

class Character extends DataClass implements Insertable<Character> {
  final int id;
  final String name;
  final String? avatarEmoji;
  final String? avatarPath;
  final String personaSystemPrompt;
  final String? greeting;

  /// JSON array of example-dialogue strings (see `character_card.dart`'s
  /// `mes_example` mapping), or null for none.
  final String? exampleDialogues;
  final int? defaultModelId;

  /// `SamplingParams.toJson()` (see `data/chat/models/sampling_params.dart`),
  /// or null for no character-level override.
  final String? samplingParamsJson;

  /// True for the shipped starter pack (see `character_repository.dart`'s
  /// `seedBuiltInsIfPresent`); false for user-created characters.
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Character({
    required this.id,
    required this.name,
    this.avatarEmoji,
    this.avatarPath,
    required this.personaSystemPrompt,
    this.greeting,
    this.exampleDialogues,
    this.defaultModelId,
    this.samplingParamsJson,
    required this.isBuiltIn,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || avatarEmoji != null) {
      map['avatar_emoji'] = Variable<String>(avatarEmoji);
    }
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    map['persona_system_prompt'] = Variable<String>(personaSystemPrompt);
    if (!nullToAbsent || greeting != null) {
      map['greeting'] = Variable<String>(greeting);
    }
    if (!nullToAbsent || exampleDialogues != null) {
      map['example_dialogues'] = Variable<String>(exampleDialogues);
    }
    if (!nullToAbsent || defaultModelId != null) {
      map['default_model_id'] = Variable<int>(defaultModelId);
    }
    if (!nullToAbsent || samplingParamsJson != null) {
      map['sampling_params_json'] = Variable<String>(samplingParamsJson);
    }
    map['is_built_in'] = Variable<bool>(isBuiltIn);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CharactersCompanion toCompanion(bool nullToAbsent) {
    return CharactersCompanion(
      id: Value(id),
      name: Value(name),
      avatarEmoji: avatarEmoji == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarEmoji),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      personaSystemPrompt: Value(personaSystemPrompt),
      greeting: greeting == null && nullToAbsent
          ? const Value.absent()
          : Value(greeting),
      exampleDialogues: exampleDialogues == null && nullToAbsent
          ? const Value.absent()
          : Value(exampleDialogues),
      defaultModelId: defaultModelId == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultModelId),
      samplingParamsJson: samplingParamsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(samplingParamsJson),
      isBuiltIn: Value(isBuiltIn),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Character.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Character(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatarEmoji: serializer.fromJson<String?>(json['avatarEmoji']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      personaSystemPrompt: serializer.fromJson<String>(
        json['personaSystemPrompt'],
      ),
      greeting: serializer.fromJson<String?>(json['greeting']),
      exampleDialogues: serializer.fromJson<String?>(json['exampleDialogues']),
      defaultModelId: serializer.fromJson<int?>(json['defaultModelId']),
      samplingParamsJson: serializer.fromJson<String?>(
        json['samplingParamsJson'],
      ),
      isBuiltIn: serializer.fromJson<bool>(json['isBuiltIn']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'avatarEmoji': serializer.toJson<String?>(avatarEmoji),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'personaSystemPrompt': serializer.toJson<String>(personaSystemPrompt),
      'greeting': serializer.toJson<String?>(greeting),
      'exampleDialogues': serializer.toJson<String?>(exampleDialogues),
      'defaultModelId': serializer.toJson<int?>(defaultModelId),
      'samplingParamsJson': serializer.toJson<String?>(samplingParamsJson),
      'isBuiltIn': serializer.toJson<bool>(isBuiltIn),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Character copyWith({
    int? id,
    String? name,
    Value<String?> avatarEmoji = const Value.absent(),
    Value<String?> avatarPath = const Value.absent(),
    String? personaSystemPrompt,
    Value<String?> greeting = const Value.absent(),
    Value<String?> exampleDialogues = const Value.absent(),
    Value<int?> defaultModelId = const Value.absent(),
    Value<String?> samplingParamsJson = const Value.absent(),
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Character(
    id: id ?? this.id,
    name: name ?? this.name,
    avatarEmoji: avatarEmoji.present ? avatarEmoji.value : this.avatarEmoji,
    avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
    personaSystemPrompt: personaSystemPrompt ?? this.personaSystemPrompt,
    greeting: greeting.present ? greeting.value : this.greeting,
    exampleDialogues: exampleDialogues.present
        ? exampleDialogues.value
        : this.exampleDialogues,
    defaultModelId: defaultModelId.present
        ? defaultModelId.value
        : this.defaultModelId,
    samplingParamsJson: samplingParamsJson.present
        ? samplingParamsJson.value
        : this.samplingParamsJson,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Character copyWithCompanion(CharactersCompanion data) {
    return Character(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatarEmoji: data.avatarEmoji.present
          ? data.avatarEmoji.value
          : this.avatarEmoji,
      avatarPath: data.avatarPath.present
          ? data.avatarPath.value
          : this.avatarPath,
      personaSystemPrompt: data.personaSystemPrompt.present
          ? data.personaSystemPrompt.value
          : this.personaSystemPrompt,
      greeting: data.greeting.present ? data.greeting.value : this.greeting,
      exampleDialogues: data.exampleDialogues.present
          ? data.exampleDialogues.value
          : this.exampleDialogues,
      defaultModelId: data.defaultModelId.present
          ? data.defaultModelId.value
          : this.defaultModelId,
      samplingParamsJson: data.samplingParamsJson.present
          ? data.samplingParamsJson.value
          : this.samplingParamsJson,
      isBuiltIn: data.isBuiltIn.present ? data.isBuiltIn.value : this.isBuiltIn,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Character(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarEmoji: $avatarEmoji, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('personaSystemPrompt: $personaSystemPrompt, ')
          ..write('greeting: $greeting, ')
          ..write('exampleDialogues: $exampleDialogues, ')
          ..write('defaultModelId: $defaultModelId, ')
          ..write('samplingParamsJson: $samplingParamsJson, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatarEmoji,
    avatarPath,
    personaSystemPrompt,
    greeting,
    exampleDialogues,
    defaultModelId,
    samplingParamsJson,
    isBuiltIn,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Character &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatarEmoji == this.avatarEmoji &&
          other.avatarPath == this.avatarPath &&
          other.personaSystemPrompt == this.personaSystemPrompt &&
          other.greeting == this.greeting &&
          other.exampleDialogues == this.exampleDialogues &&
          other.defaultModelId == this.defaultModelId &&
          other.samplingParamsJson == this.samplingParamsJson &&
          other.isBuiltIn == this.isBuiltIn &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CharactersCompanion extends UpdateCompanion<Character> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> avatarEmoji;
  final Value<String?> avatarPath;
  final Value<String> personaSystemPrompt;
  final Value<String?> greeting;
  final Value<String?> exampleDialogues;
  final Value<int?> defaultModelId;
  final Value<String?> samplingParamsJson;
  final Value<bool> isBuiltIn;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CharactersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarEmoji = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.personaSystemPrompt = const Value.absent(),
    this.greeting = const Value.absent(),
    this.exampleDialogues = const Value.absent(),
    this.defaultModelId = const Value.absent(),
    this.samplingParamsJson = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CharactersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.avatarEmoji = const Value.absent(),
    this.avatarPath = const Value.absent(),
    required String personaSystemPrompt,
    this.greeting = const Value.absent(),
    this.exampleDialogues = const Value.absent(),
    this.defaultModelId = const Value.absent(),
    this.samplingParamsJson = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       personaSystemPrompt = Value(personaSystemPrompt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Character> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? avatarEmoji,
    Expression<String>? avatarPath,
    Expression<String>? personaSystemPrompt,
    Expression<String>? greeting,
    Expression<String>? exampleDialogues,
    Expression<int>? defaultModelId,
    Expression<String>? samplingParamsJson,
    Expression<bool>? isBuiltIn,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatarEmoji != null) 'avatar_emoji': avatarEmoji,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (personaSystemPrompt != null)
        'persona_system_prompt': personaSystemPrompt,
      if (greeting != null) 'greeting': greeting,
      if (exampleDialogues != null) 'example_dialogues': exampleDialogues,
      if (defaultModelId != null) 'default_model_id': defaultModelId,
      if (samplingParamsJson != null)
        'sampling_params_json': samplingParamsJson,
      if (isBuiltIn != null) 'is_built_in': isBuiltIn,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CharactersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? avatarEmoji,
    Value<String?>? avatarPath,
    Value<String>? personaSystemPrompt,
    Value<String?>? greeting,
    Value<String?>? exampleDialogues,
    Value<int?>? defaultModelId,
    Value<String?>? samplingParamsJson,
    Value<bool>? isBuiltIn,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return CharactersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      avatarPath: avatarPath ?? this.avatarPath,
      personaSystemPrompt: personaSystemPrompt ?? this.personaSystemPrompt,
      greeting: greeting ?? this.greeting,
      exampleDialogues: exampleDialogues ?? this.exampleDialogues,
      defaultModelId: defaultModelId ?? this.defaultModelId,
      samplingParamsJson: samplingParamsJson ?? this.samplingParamsJson,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarEmoji.present) {
      map['avatar_emoji'] = Variable<String>(avatarEmoji.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (personaSystemPrompt.present) {
      map['persona_system_prompt'] = Variable<String>(
        personaSystemPrompt.value,
      );
    }
    if (greeting.present) {
      map['greeting'] = Variable<String>(greeting.value);
    }
    if (exampleDialogues.present) {
      map['example_dialogues'] = Variable<String>(exampleDialogues.value);
    }
    if (defaultModelId.present) {
      map['default_model_id'] = Variable<int>(defaultModelId.value);
    }
    if (samplingParamsJson.present) {
      map['sampling_params_json'] = Variable<String>(samplingParamsJson.value);
    }
    if (isBuiltIn.present) {
      map['is_built_in'] = Variable<bool>(isBuiltIn.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharactersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarEmoji: $avatarEmoji, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('personaSystemPrompt: $personaSystemPrompt, ')
          ..write('greeting: $greeting, ')
          ..write('exampleDialogues: $exampleDialogues, ')
          ..write('defaultModelId: $defaultModelId, ')
          ..write('samplingParamsJson: $samplingParamsJson, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<int> modelId = GeneratedColumn<int>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES installed_models (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _systemPromptMeta = const VerificationMeta(
    'systemPrompt',
  );
  @override
  late final GeneratedColumn<String> systemPrompt = GeneratedColumn<String>(
    'system_prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _samplingParamsJsonMeta =
      const VerificationMeta('samplingParamsJson');
  @override
  late final GeneratedColumn<String> samplingParamsJson =
      GeneratedColumn<String>(
        'sampling_params_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    folderId,
    modelId,
    characterId,
    systemPrompt,
    samplingParamsJson,
    createdAt,
    updatedAt,
    pinned,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('system_prompt')) {
      context.handle(
        _systemPromptMeta,
        systemPrompt.isAcceptableOrUnknown(
          data['system_prompt']!,
          _systemPromptMeta,
        ),
      );
    }
    if (data.containsKey('sampling_params_json')) {
      context.handle(
        _samplingParamsJsonMeta,
        samplingParamsJson.isAcceptableOrUnknown(
          data['sampling_params_json']!,
          _samplingParamsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}model_id'],
      ),
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      ),
      systemPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_prompt'],
      )!,
      samplingParamsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sampling_params_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final int id;
  final String title;
  final int? folderId;
  final int? modelId;

  /// The character (if any) this thread was started with — its persona is
  /// the system prompt, its greeting seeds the thread, its model/sampling
  /// are the defaults (see `data/characters/character_repository.dart`'s
  /// `chatContextFor`). Deleting a character un-sets this (`KeyAction.
  /// setNull`), same "survives deletion" precedent as `modelId`/`folderId`
  /// above — the conversation and its history are untouched.
  final int? characterId;
  final String systemPrompt;

  /// `SamplingParams.toJson()` (see `data/chat/models/sampling_params.dart`),
  /// or null to use `SamplingParams()` defaults.
  final String? samplingParamsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  const Conversation({
    required this.id,
    required this.title,
    this.folderId,
    this.modelId,
    this.characterId,
    required this.systemPrompt,
    this.samplingParamsJson,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<int>(folderId);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<int>(modelId);
    }
    if (!nullToAbsent || characterId != null) {
      map['character_id'] = Variable<int>(characterId);
    }
    map['system_prompt'] = Variable<String>(systemPrompt);
    if (!nullToAbsent || samplingParamsJson != null) {
      map['sampling_params_json'] = Variable<String>(samplingParamsJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['pinned'] = Variable<bool>(pinned);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      title: Value(title),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      characterId: characterId == null && nullToAbsent
          ? const Value.absent()
          : Value(characterId),
      systemPrompt: Value(systemPrompt),
      samplingParamsJson: samplingParamsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(samplingParamsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      pinned: Value(pinned),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      folderId: serializer.fromJson<int?>(json['folderId']),
      modelId: serializer.fromJson<int?>(json['modelId']),
      characterId: serializer.fromJson<int?>(json['characterId']),
      systemPrompt: serializer.fromJson<String>(json['systemPrompt']),
      samplingParamsJson: serializer.fromJson<String?>(
        json['samplingParamsJson'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      pinned: serializer.fromJson<bool>(json['pinned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'folderId': serializer.toJson<int?>(folderId),
      'modelId': serializer.toJson<int?>(modelId),
      'characterId': serializer.toJson<int?>(characterId),
      'systemPrompt': serializer.toJson<String>(systemPrompt),
      'samplingParamsJson': serializer.toJson<String?>(samplingParamsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'pinned': serializer.toJson<bool>(pinned),
    };
  }

  Conversation copyWith({
    int? id,
    String? title,
    Value<int?> folderId = const Value.absent(),
    Value<int?> modelId = const Value.absent(),
    Value<int?> characterId = const Value.absent(),
    String? systemPrompt,
    Value<String?> samplingParamsJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? pinned,
  }) => Conversation(
    id: id ?? this.id,
    title: title ?? this.title,
    folderId: folderId.present ? folderId.value : this.folderId,
    modelId: modelId.present ? modelId.value : this.modelId,
    characterId: characterId.present ? characterId.value : this.characterId,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    samplingParamsJson: samplingParamsJson.present
        ? samplingParamsJson.value
        : this.samplingParamsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pinned: pinned ?? this.pinned,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      systemPrompt: data.systemPrompt.present
          ? data.systemPrompt.value
          : this.systemPrompt,
      samplingParamsJson: data.samplingParamsJson.present
          ? data.samplingParamsJson.value
          : this.samplingParamsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('folderId: $folderId, ')
          ..write('modelId: $modelId, ')
          ..write('characterId: $characterId, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('samplingParamsJson: $samplingParamsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    folderId,
    modelId,
    characterId,
    systemPrompt,
    samplingParamsJson,
    createdAt,
    updatedAt,
    pinned,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.title == this.title &&
          other.folderId == this.folderId &&
          other.modelId == this.modelId &&
          other.characterId == this.characterId &&
          other.systemPrompt == this.systemPrompt &&
          other.samplingParamsJson == this.samplingParamsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.pinned == this.pinned);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<int> id;
  final Value<String> title;
  final Value<int?> folderId;
  final Value<int?> modelId;
  final Value<int?> characterId;
  final Value<String> systemPrompt;
  final Value<String?> samplingParamsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> pinned;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.folderId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.characterId = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.samplingParamsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.pinned = const Value.absent(),
  });
  ConversationsCompanion.insert({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.folderId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.characterId = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.samplingParamsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.pinned = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<int>? folderId,
    Expression<int>? modelId,
    Expression<int>? characterId,
    Expression<String>? systemPrompt,
    Expression<String>? samplingParamsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? pinned,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (folderId != null) 'folder_id': folderId,
      if (modelId != null) 'model_id': modelId,
      if (characterId != null) 'character_id': characterId,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (samplingParamsJson != null)
        'sampling_params_json': samplingParamsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (pinned != null) 'pinned': pinned,
    });
  }

  ConversationsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<int?>? folderId,
    Value<int?>? modelId,
    Value<int?>? characterId,
    Value<String>? systemPrompt,
    Value<String?>? samplingParamsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? pinned,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      folderId: folderId ?? this.folderId,
      modelId: modelId ?? this.modelId,
      characterId: characterId ?? this.characterId,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      samplingParamsJson: samplingParamsJson ?? this.samplingParamsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<int>(modelId.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (systemPrompt.present) {
      map['system_prompt'] = Variable<String>(systemPrompt.value);
    }
    if (samplingParamsJson.present) {
      map['sampling_params_json'] = Variable<String>(samplingParamsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('folderId: $folderId, ')
          ..write('modelId: $modelId, ')
          ..write('characterId: $characterId, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('samplingParamsJson: $samplingParamsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageRole, int> role =
      GeneratedColumn<int>(
        'role',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<MessageRole>($MessagesTable.$converterrole);
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _reasoningContentMeta = const VerificationMeta(
    'reasoningContent',
  );
  @override
  late final GeneratedColumn<String> reasoningContent = GeneratedColumn<String>(
    'reasoning_content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageStatus, int> status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<MessageStatus>($MessagesTable.$converterstatus);
  static const VerificationMeta _errorKindMeta = const VerificationMeta(
    'errorKind',
  );
  @override
  late final GeneratedColumn<String> errorKind = GeneratedColumn<String>(
    'error_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokCountMeta = const VerificationMeta(
    'tokCount',
  );
  @override
  late final GeneratedColumn<int> tokCount = GeneratedColumn<int>(
    'tok_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genMsMeta = const VerificationMeta('genMs');
  @override
  late final GeneratedColumn<int> genMs = GeneratedColumn<int>(
    'gen_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentMessageIdMeta = const VerificationMeta(
    'parentMessageId',
  );
  @override
  late final GeneratedColumn<int> parentMessageId = GeneratedColumn<int>(
    'parent_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (id) ON DELETE SET NULL',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    content,
    reasoningContent,
    status,
    errorKind,
    tokCount,
    genMs,
    createdAt,
    parentMessageId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('reasoning_content')) {
      context.handle(
        _reasoningContentMeta,
        reasoningContent.isAcceptableOrUnknown(
          data['reasoning_content']!,
          _reasoningContentMeta,
        ),
      );
    }
    if (data.containsKey('error_kind')) {
      context.handle(
        _errorKindMeta,
        errorKind.isAcceptableOrUnknown(data['error_kind']!, _errorKindMeta),
      );
    }
    if (data.containsKey('tok_count')) {
      context.handle(
        _tokCountMeta,
        tokCount.isAcceptableOrUnknown(data['tok_count']!, _tokCountMeta),
      );
    }
    if (data.containsKey('gen_ms')) {
      context.handle(
        _genMsMeta,
        genMs.isAcceptableOrUnknown(data['gen_ms']!, _genMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('parent_message_id')) {
      context.handle(
        _parentMessageIdMeta,
        parentMessageId.isAcceptableOrUnknown(
          data['parent_message_id']!,
          _parentMessageIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      role: $MessagesTable.$converterrole.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}role'],
        )!,
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      reasoningContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning_content'],
      ),
      status: $MessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      errorKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_kind'],
      ),
      tokCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tok_count'],
      ),
      genMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gen_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      parentMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_message_id'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MessageRole, int, int> $converterrole =
      const EnumIndexConverter<MessageRole>(MessageRole.values);
  static JsonTypeConverter2<MessageStatus, int, int> $converterstatus =
      const EnumIndexConverter<MessageStatus>(MessageStatus.values);
}

class Message extends DataClass implements Insertable<Message> {
  final int id;
  final int conversationId;
  final MessageRole role;
  final String content;

  /// Extracted `<think>...</think>` text, kept separate from `content` so
  /// the UI can collapse it independently.
  final String? reasoningContent;
  final MessageStatus status;

  /// Free-text failure-kind label (e.g. an `EngineFailure`/`AppFailure`
  /// `runtimeType`). This layer deliberately doesn't depend on
  /// `engine_bindings`'s failure tree (ADR-002 dependency direction) — it
  /// just stores whatever label the caller passed.
  final String? errorKind;
  final int? tokCount;
  final int? genMs;
  final DateTime createdAt;

  /// Enables edit/regenerate history (a regenerated or edited message
  /// points back at the message it replaced) without a full tree UI — this
  /// is linear-history provenance, not a real tree; a deleted parent just
  /// un-sets the pointer.
  final int? parentMessageId;
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.reasoningContent,
    required this.status,
    this.errorKind,
    this.tokCount,
    this.genMs,
    required this.createdAt,
    this.parentMessageId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    {
      map['role'] = Variable<int>($MessagesTable.$converterrole.toSql(role));
    }
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || reasoningContent != null) {
      map['reasoning_content'] = Variable<String>(reasoningContent);
    }
    {
      map['status'] = Variable<int>(
        $MessagesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || errorKind != null) {
      map['error_kind'] = Variable<String>(errorKind);
    }
    if (!nullToAbsent || tokCount != null) {
      map['tok_count'] = Variable<int>(tokCount);
    }
    if (!nullToAbsent || genMs != null) {
      map['gen_ms'] = Variable<int>(genMs);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || parentMessageId != null) {
      map['parent_message_id'] = Variable<int>(parentMessageId);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: Value(content),
      reasoningContent: reasoningContent == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningContent),
      status: Value(status),
      errorKind: errorKind == null && nullToAbsent
          ? const Value.absent()
          : Value(errorKind),
      tokCount: tokCount == null && nullToAbsent
          ? const Value.absent()
          : Value(tokCount),
      genMs: genMs == null && nullToAbsent
          ? const Value.absent()
          : Value(genMs),
      createdAt: Value(createdAt),
      parentMessageId: parentMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentMessageId),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      role: $MessagesTable.$converterrole.fromJson(
        serializer.fromJson<int>(json['role']),
      ),
      content: serializer.fromJson<String>(json['content']),
      reasoningContent: serializer.fromJson<String?>(json['reasoningContent']),
      status: $MessagesTable.$converterstatus.fromJson(
        serializer.fromJson<int>(json['status']),
      ),
      errorKind: serializer.fromJson<String?>(json['errorKind']),
      tokCount: serializer.fromJson<int?>(json['tokCount']),
      genMs: serializer.fromJson<int?>(json['genMs']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      parentMessageId: serializer.fromJson<int?>(json['parentMessageId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'role': serializer.toJson<int>(
        $MessagesTable.$converterrole.toJson(role),
      ),
      'content': serializer.toJson<String>(content),
      'reasoningContent': serializer.toJson<String?>(reasoningContent),
      'status': serializer.toJson<int>(
        $MessagesTable.$converterstatus.toJson(status),
      ),
      'errorKind': serializer.toJson<String?>(errorKind),
      'tokCount': serializer.toJson<int?>(tokCount),
      'genMs': serializer.toJson<int?>(genMs),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'parentMessageId': serializer.toJson<int?>(parentMessageId),
    };
  }

  Message copyWith({
    int? id,
    int? conversationId,
    MessageRole? role,
    String? content,
    Value<String?> reasoningContent = const Value.absent(),
    MessageStatus? status,
    Value<String?> errorKind = const Value.absent(),
    Value<int?> tokCount = const Value.absent(),
    Value<int?> genMs = const Value.absent(),
    DateTime? createdAt,
    Value<int?> parentMessageId = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    content: content ?? this.content,
    reasoningContent: reasoningContent.present
        ? reasoningContent.value
        : this.reasoningContent,
    status: status ?? this.status,
    errorKind: errorKind.present ? errorKind.value : this.errorKind,
    tokCount: tokCount.present ? tokCount.value : this.tokCount,
    genMs: genMs.present ? genMs.value : this.genMs,
    createdAt: createdAt ?? this.createdAt,
    parentMessageId: parentMessageId.present
        ? parentMessageId.value
        : this.parentMessageId,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      reasoningContent: data.reasoningContent.present
          ? data.reasoningContent.value
          : this.reasoningContent,
      status: data.status.present ? data.status.value : this.status,
      errorKind: data.errorKind.present ? data.errorKind.value : this.errorKind,
      tokCount: data.tokCount.present ? data.tokCount.value : this.tokCount,
      genMs: data.genMs.present ? data.genMs.value : this.genMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      parentMessageId: data.parentMessageId.present
          ? data.parentMessageId.value
          : this.parentMessageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('reasoningContent: $reasoningContent, ')
          ..write('status: $status, ')
          ..write('errorKind: $errorKind, ')
          ..write('tokCount: $tokCount, ')
          ..write('genMs: $genMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('parentMessageId: $parentMessageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    content,
    reasoningContent,
    status,
    errorKind,
    tokCount,
    genMs,
    createdAt,
    parentMessageId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.reasoningContent == this.reasoningContent &&
          other.status == this.status &&
          other.errorKind == this.errorKind &&
          other.tokCount == this.tokCount &&
          other.genMs == this.genMs &&
          other.createdAt == this.createdAt &&
          other.parentMessageId == this.parentMessageId);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<MessageRole> role;
  final Value<String> content;
  final Value<String?> reasoningContent;
  final Value<MessageStatus> status;
  final Value<String?> errorKind;
  final Value<int?> tokCount;
  final Value<int?> genMs;
  final Value<DateTime> createdAt;
  final Value<int?> parentMessageId;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.reasoningContent = const Value.absent(),
    this.status = const Value.absent(),
    this.errorKind = const Value.absent(),
    this.tokCount = const Value.absent(),
    this.genMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.parentMessageId = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required MessageRole role,
    this.content = const Value.absent(),
    this.reasoningContent = const Value.absent(),
    required MessageStatus status,
    this.errorKind = const Value.absent(),
    this.tokCount = const Value.absent(),
    this.genMs = const Value.absent(),
    required DateTime createdAt,
    this.parentMessageId = const Value.absent(),
  }) : conversationId = Value(conversationId),
       role = Value(role),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<int>? role,
    Expression<String>? content,
    Expression<String>? reasoningContent,
    Expression<int>? status,
    Expression<String>? errorKind,
    Expression<int>? tokCount,
    Expression<int>? genMs,
    Expression<DateTime>? createdAt,
    Expression<int>? parentMessageId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (reasoningContent != null) 'reasoning_content': reasoningContent,
      if (status != null) 'status': status,
      if (errorKind != null) 'error_kind': errorKind,
      if (tokCount != null) 'tok_count': tokCount,
      if (genMs != null) 'gen_ms': genMs,
      if (createdAt != null) 'created_at': createdAt,
      if (parentMessageId != null) 'parent_message_id': parentMessageId,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? id,
    Value<int>? conversationId,
    Value<MessageRole>? role,
    Value<String>? content,
    Value<String?>? reasoningContent,
    Value<MessageStatus>? status,
    Value<String?>? errorKind,
    Value<int?>? tokCount,
    Value<int?>? genMs,
    Value<DateTime>? createdAt,
    Value<int?>? parentMessageId,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      status: status ?? this.status,
      errorKind: errorKind ?? this.errorKind,
      tokCount: tokCount ?? this.tokCount,
      genMs: genMs ?? this.genMs,
      createdAt: createdAt ?? this.createdAt,
      parentMessageId: parentMessageId ?? this.parentMessageId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(
        $MessagesTable.$converterrole.toSql(role.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (reasoningContent.present) {
      map['reasoning_content'] = Variable<String>(reasoningContent.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $MessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (errorKind.present) {
      map['error_kind'] = Variable<String>(errorKind.value);
    }
    if (tokCount.present) {
      map['tok_count'] = Variable<int>(tokCount.value);
    }
    if (genMs.present) {
      map['gen_ms'] = Variable<int>(genMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (parentMessageId.present) {
      map['parent_message_id'] = Variable<int>(parentMessageId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('reasoningContent: $reasoningContent, ')
          ..write('status: $status, ')
          ..write('errorKind: $errorKind, ')
          ..write('tokCount: $tokCount, ')
          ..write('genMs: $genMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('parentMessageId: $parentMessageId')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $InstalledModelsTable installedModels = $InstalledModelsTable(
    this,
  );
  late final $FoldersTable folders = $FoldersTable(this);
  late final $CharactersTable characters = $CharactersTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    installedModels,
    folders,
    characters,
    conversations,
    messages,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'installed_models',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('characters', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'folders',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'installed_models',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.update)],
    ),
  ]);
}
