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
  static const VerificationMeta _mmprojPathMeta = const VerificationMeta(
    'mmprojPath',
  );
  @override
  late final GeneratedColumn<String> mmprojPath = GeneratedColumn<String>(
    'mmproj_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isVisionMeta = const VerificationMeta(
    'isVision',
  );
  @override
  late final GeneratedColumn<bool> isVision = GeneratedColumn<bool>(
    'is_vision',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_vision" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
    mmprojPath,
    isVision,
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
    if (data.containsKey('mmproj_path')) {
      context.handle(
        _mmprojPathMeta,
        mmprojPath.isAcceptableOrUnknown(data['mmproj_path']!, _mmprojPathMeta),
      );
    }
    if (data.containsKey('is_vision')) {
      context.handle(
        _isVisionMeta,
        isVision.isAcceptableOrUnknown(data['is_vision']!, _isVisionMeta),
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
      mmprojPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mmproj_path'],
      ),
      isVision: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_vision'],
      )!,
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

  /// Local path of the mmproj projector paired with this installed vision
  /// model (Loop-7 `vision_pairing.dart`'s matching rule), or null.
  ///
  /// `isVision && mmprojPath == null` is the "needs projector" half-state: the
  /// model file downloaded and verified fine, but its paired projector
  /// download hasn't landed yet (still in flight, or failed after the model
  /// succeeded — see `download_actions_controller.dart`'s
  /// `enqueueVisionQuant`). The row exists and the model is usable text-only
  /// in that state; nothing is silently lost, but it isn't vision-ready.
  /// `isVision && mmprojPath != null` is fully vision-ready — the engine
  /// loads it with `EngineLoadParams.mmprojPath` set (Loop-7 T1).
  final String? mmprojPath;

  /// True when this row IS a vision model (paired with a projector at
  /// download-enqueue time — see `DownloadRequest.isVision`), independent of
  /// whether [mmprojPath] has landed yet — see its doc for the two-state
  /// meaning of the pair.
  final bool isVision;
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
    this.mmprojPath,
    required this.isVision,
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
    if (!nullToAbsent || mmprojPath != null) {
      map['mmproj_path'] = Variable<String>(mmprojPath);
    }
    map['is_vision'] = Variable<bool>(isVision);
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
      mmprojPath: mmprojPath == null && nullToAbsent
          ? const Value.absent()
          : Value(mmprojPath),
      isVision: Value(isVision),
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
      mmprojPath: serializer.fromJson<String?>(json['mmprojPath']),
      isVision: serializer.fromJson<bool>(json['isVision']),
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
      'mmprojPath': serializer.toJson<String?>(mmprojPath),
      'isVision': serializer.toJson<bool>(isVision),
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
    Value<String?> mmprojPath = const Value.absent(),
    bool? isVision,
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
    mmprojPath: mmprojPath.present ? mmprojPath.value : this.mmprojPath,
    isVision: isVision ?? this.isVision,
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
      mmprojPath: data.mmprojPath.present
          ? data.mmprojPath.value
          : this.mmprojPath,
      isVision: data.isVision.present ? data.isVision.value : this.isVision,
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
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('mmprojPath: $mmprojPath, ')
          ..write('isVision: $isVision')
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
    mmprojPath,
    isVision,
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
          other.lastUsedAt == this.lastUsedAt &&
          other.mmprojPath == this.mmprojPath &&
          other.isVision == this.isVision);
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
  final Value<String?> mmprojPath;
  final Value<bool> isVision;
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
    this.mmprojPath = const Value.absent(),
    this.isVision = const Value.absent(),
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
    this.mmprojPath = const Value.absent(),
    this.isVision = const Value.absent(),
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
    Expression<String>? mmprojPath,
    Expression<bool>? isVision,
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
      if (mmprojPath != null) 'mmproj_path': mmprojPath,
      if (isVision != null) 'is_vision': isVision,
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
    Value<String?>? mmprojPath,
    Value<bool>? isVision,
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
      mmprojPath: mmprojPath ?? this.mmprojPath,
      isVision: isVision ?? this.isVision,
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
    if (mmprojPath.present) {
      map['mmproj_path'] = Variable<String>(mmprojPath.value);
    }
    if (isVision.present) {
      map['is_vision'] = Variable<bool>(isVision.value);
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
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('mmprojPath: $mmprojPath, ')
          ..write('isVision: $isVision')
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
  static const VerificationMeta _reportedMeta = const VerificationMeta(
    'reported',
  );
  @override
  late final GeneratedColumn<bool> reported = GeneratedColumn<bool>(
    'reported',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reported" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _sourcesJsonMeta = const VerificationMeta(
    'sourcesJson',
  );
  @override
  late final GeneratedColumn<String> sourcesJson = GeneratedColumn<String>(
    'sources_json',
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
    reported,
    genMs,
    sourcesJson,
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
    if (data.containsKey('reported')) {
      context.handle(
        _reportedMeta,
        reported.isAcceptableOrUnknown(data['reported']!, _reportedMeta),
      );
    }
    if (data.containsKey('gen_ms')) {
      context.handle(
        _genMsMeta,
        genMs.isAcceptableOrUnknown(data['gen_ms']!, _genMsMeta),
      );
    }
    if (data.containsKey('sources_json')) {
      context.handle(
        _sourcesJsonMeta,
        sourcesJson.isAcceptableOrUnknown(
          data['sources_json']!,
          _sourcesJsonMeta,
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
      reported: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reported'],
      )!,
      genMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gen_ms'],
      ),
      sourcesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sources_json'],
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

  /// True once the user reported this reply (v5); the UI hides it behind a
  /// "Show" placeholder. The report itself lives in [ContentReports].
  final bool reported;
  final int? genMs;

  /// JSON list of the document citations a reply was grounded in (v6, see
  /// `data/docs/grounding.dart`'s `encodeSources`), or null for an ordinary
  /// reply. Drives the collapsible "Sources" row under the bubble.
  final String? sourcesJson;
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
    required this.reported,
    this.genMs,
    this.sourcesJson,
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
    map['reported'] = Variable<bool>(reported);
    if (!nullToAbsent || genMs != null) {
      map['gen_ms'] = Variable<int>(genMs);
    }
    if (!nullToAbsent || sourcesJson != null) {
      map['sources_json'] = Variable<String>(sourcesJson);
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
      reported: Value(reported),
      genMs: genMs == null && nullToAbsent
          ? const Value.absent()
          : Value(genMs),
      sourcesJson: sourcesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcesJson),
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
      reported: serializer.fromJson<bool>(json['reported']),
      genMs: serializer.fromJson<int?>(json['genMs']),
      sourcesJson: serializer.fromJson<String?>(json['sourcesJson']),
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
      'reported': serializer.toJson<bool>(reported),
      'genMs': serializer.toJson<int?>(genMs),
      'sourcesJson': serializer.toJson<String?>(sourcesJson),
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
    bool? reported,
    Value<int?> genMs = const Value.absent(),
    Value<String?> sourcesJson = const Value.absent(),
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
    reported: reported ?? this.reported,
    genMs: genMs.present ? genMs.value : this.genMs,
    sourcesJson: sourcesJson.present ? sourcesJson.value : this.sourcesJson,
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
      reported: data.reported.present ? data.reported.value : this.reported,
      genMs: data.genMs.present ? data.genMs.value : this.genMs,
      sourcesJson: data.sourcesJson.present
          ? data.sourcesJson.value
          : this.sourcesJson,
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
          ..write('reported: $reported, ')
          ..write('genMs: $genMs, ')
          ..write('sourcesJson: $sourcesJson, ')
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
    reported,
    genMs,
    sourcesJson,
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
          other.reported == this.reported &&
          other.genMs == this.genMs &&
          other.sourcesJson == this.sourcesJson &&
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
  final Value<bool> reported;
  final Value<int?> genMs;
  final Value<String?> sourcesJson;
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
    this.reported = const Value.absent(),
    this.genMs = const Value.absent(),
    this.sourcesJson = const Value.absent(),
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
    this.reported = const Value.absent(),
    this.genMs = const Value.absent(),
    this.sourcesJson = const Value.absent(),
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
    Expression<bool>? reported,
    Expression<int>? genMs,
    Expression<String>? sourcesJson,
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
      if (reported != null) 'reported': reported,
      if (genMs != null) 'gen_ms': genMs,
      if (sourcesJson != null) 'sources_json': sourcesJson,
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
    Value<bool>? reported,
    Value<int?>? genMs,
    Value<String?>? sourcesJson,
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
      reported: reported ?? this.reported,
      genMs: genMs ?? this.genMs,
      sourcesJson: sourcesJson ?? this.sourcesJson,
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
    if (reported.present) {
      map['reported'] = Variable<bool>(reported.value);
    }
    if (genMs.present) {
      map['gen_ms'] = Variable<int>(genMs.value);
    }
    if (sourcesJson.present) {
      map['sources_json'] = Variable<String>(sourcesJson.value);
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
          ..write('reported: $reported, ')
          ..write('genMs: $genMs, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('parentMessageId: $parentMessageId')
          ..write(')'))
        .toString();
  }
}

class $ContentReportsTable extends ContentReports
    with TableInfo<$ContentReportsTable, ContentReport> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentReportsTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelNameMeta = const VerificationMeta(
    'modelName',
  );
  @override
  late final GeneratedColumn<String> modelName = GeneratedColumn<String>(
    'model_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _excerptMeta = const VerificationMeta(
    'excerpt',
  );
  @override
  late final GeneratedColumn<String> excerpt = GeneratedColumn<String>(
    'excerpt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    conversationId,
    messageId,
    modelName,
    reason,
    note,
    excerpt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_reports';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentReport> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('model_name')) {
      context.handle(
        _modelNameMeta,
        modelName.isAcceptableOrUnknown(data['model_name']!, _modelNameMeta),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('excerpt')) {
      context.handle(
        _excerptMeta,
        excerpt.isAcceptableOrUnknown(data['excerpt']!, _excerptMeta),
      );
    } else if (isInserting) {
      context.missing(_excerptMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContentReport map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentReport(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      modelName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_name'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      excerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excerpt'],
      )!,
    );
  }

  @override
  $ContentReportsTable createAlias(String alias) {
    return $ContentReportsTable(attachedDatabase, alias);
  }
}

class ContentReport extends DataClass implements Insertable<ContentReport> {
  final int id;
  final DateTime createdAt;
  final int conversationId;
  final int messageId;
  final String? modelName;

  /// `ReportReason.name` (see `data/safety/report_repository.dart`).
  final String reason;
  final String? note;

  /// The reported reply's text, capped at 2000 chars.
  final String excerpt;
  const ContentReport({
    required this.id,
    required this.createdAt,
    required this.conversationId,
    required this.messageId,
    this.modelName,
    required this.reason,
    this.note,
    required this.excerpt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['conversation_id'] = Variable<int>(conversationId);
    map['message_id'] = Variable<int>(messageId);
    if (!nullToAbsent || modelName != null) {
      map['model_name'] = Variable<String>(modelName);
    }
    map['reason'] = Variable<String>(reason);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['excerpt'] = Variable<String>(excerpt);
    return map;
  }

  ContentReportsCompanion toCompanion(bool nullToAbsent) {
    return ContentReportsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      conversationId: Value(conversationId),
      messageId: Value(messageId),
      modelName: modelName == null && nullToAbsent
          ? const Value.absent()
          : Value(modelName),
      reason: Value(reason),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      excerpt: Value(excerpt),
    );
  }

  factory ContentReport.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentReport(
      id: serializer.fromJson<int>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      messageId: serializer.fromJson<int>(json['messageId']),
      modelName: serializer.fromJson<String?>(json['modelName']),
      reason: serializer.fromJson<String>(json['reason']),
      note: serializer.fromJson<String?>(json['note']),
      excerpt: serializer.fromJson<String>(json['excerpt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'conversationId': serializer.toJson<int>(conversationId),
      'messageId': serializer.toJson<int>(messageId),
      'modelName': serializer.toJson<String?>(modelName),
      'reason': serializer.toJson<String>(reason),
      'note': serializer.toJson<String?>(note),
      'excerpt': serializer.toJson<String>(excerpt),
    };
  }

  ContentReport copyWith({
    int? id,
    DateTime? createdAt,
    int? conversationId,
    int? messageId,
    Value<String?> modelName = const Value.absent(),
    String? reason,
    Value<String?> note = const Value.absent(),
    String? excerpt,
  }) => ContentReport(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    conversationId: conversationId ?? this.conversationId,
    messageId: messageId ?? this.messageId,
    modelName: modelName.present ? modelName.value : this.modelName,
    reason: reason ?? this.reason,
    note: note.present ? note.value : this.note,
    excerpt: excerpt ?? this.excerpt,
  );
  ContentReport copyWithCompanion(ContentReportsCompanion data) {
    return ContentReport(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      modelName: data.modelName.present ? data.modelName.value : this.modelName,
      reason: data.reason.present ? data.reason.value : this.reason,
      note: data.note.present ? data.note.value : this.note,
      excerpt: data.excerpt.present ? data.excerpt.value : this.excerpt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentReport(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('modelName: $modelName, ')
          ..write('reason: $reason, ')
          ..write('note: $note, ')
          ..write('excerpt: $excerpt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    conversationId,
    messageId,
    modelName,
    reason,
    note,
    excerpt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentReport &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.conversationId == this.conversationId &&
          other.messageId == this.messageId &&
          other.modelName == this.modelName &&
          other.reason == this.reason &&
          other.note == this.note &&
          other.excerpt == this.excerpt);
}

class ContentReportsCompanion extends UpdateCompanion<ContentReport> {
  final Value<int> id;
  final Value<DateTime> createdAt;
  final Value<int> conversationId;
  final Value<int> messageId;
  final Value<String?> modelName;
  final Value<String> reason;
  final Value<String?> note;
  final Value<String> excerpt;
  const ContentReportsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.modelName = const Value.absent(),
    this.reason = const Value.absent(),
    this.note = const Value.absent(),
    this.excerpt = const Value.absent(),
  });
  ContentReportsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime createdAt,
    required int conversationId,
    required int messageId,
    this.modelName = const Value.absent(),
    required String reason,
    this.note = const Value.absent(),
    required String excerpt,
  }) : createdAt = Value(createdAt),
       conversationId = Value(conversationId),
       messageId = Value(messageId),
       reason = Value(reason),
       excerpt = Value(excerpt);
  static Insertable<ContentReport> custom({
    Expression<int>? id,
    Expression<DateTime>? createdAt,
    Expression<int>? conversationId,
    Expression<int>? messageId,
    Expression<String>? modelName,
    Expression<String>? reason,
    Expression<String>? note,
    Expression<String>? excerpt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (conversationId != null) 'conversation_id': conversationId,
      if (messageId != null) 'message_id': messageId,
      if (modelName != null) 'model_name': modelName,
      if (reason != null) 'reason': reason,
      if (note != null) 'note': note,
      if (excerpt != null) 'excerpt': excerpt,
    });
  }

  ContentReportsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? createdAt,
    Value<int>? conversationId,
    Value<int>? messageId,
    Value<String?>? modelName,
    Value<String>? reason,
    Value<String?>? note,
    Value<String>? excerpt,
  }) {
    return ContentReportsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      modelName: modelName ?? this.modelName,
      reason: reason ?? this.reason,
      note: note ?? this.note,
      excerpt: excerpt ?? this.excerpt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (modelName.present) {
      map['model_name'] = Variable<String>(modelName.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (excerpt.present) {
      map['excerpt'] = Variable<String>(excerpt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentReportsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('modelName: $modelName, ')
          ..write('reason: $reason, ')
          ..write('note: $note, ')
          ..write('excerpt: $excerpt')
          ..write(')'))
        .toString();
  }
}

class $AttachedDocumentsTable extends AttachedDocuments
    with TableInfo<$AttachedDocumentsTable, AttachedDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachedDocumentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charCountMeta = const VerificationMeta(
    'charCount',
  );
  @override
  late final GeneratedColumn<int> charCount = GeneratedColumn<int>(
    'char_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    name,
    mime,
    pageCount,
    charCount,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attached_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachedDocument> instance, {
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
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('char_count')) {
      context.handle(
        _charCountMeta,
        charCount.isAcceptableOrUnknown(data['char_count']!, _charCountMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttachedDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachedDocument(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      charCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AttachedDocumentsTable createAlias(String alias) {
    return $AttachedDocumentsTable(attachedDatabase, alias);
  }
}

class AttachedDocument extends DataClass
    implements Insertable<AttachedDocument> {
  final int id;
  final int conversationId;
  final String name;
  final String mime;

  /// Real page count for a PDF; 0 for a page-less TXT/MD file.
  final int pageCount;

  /// Characters of extracted text (before chunk overlap).
  final int charCount;
  final DateTime createdAt;
  const AttachedDocument({
    required this.id,
    required this.conversationId,
    required this.name,
    required this.mime,
    required this.pageCount,
    required this.charCount,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    map['name'] = Variable<String>(name);
    map['mime'] = Variable<String>(mime);
    map['page_count'] = Variable<int>(pageCount);
    map['char_count'] = Variable<int>(charCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AttachedDocumentsCompanion toCompanion(bool nullToAbsent) {
    return AttachedDocumentsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      name: Value(name),
      mime: Value(mime),
      pageCount: Value(pageCount),
      charCount: Value(charCount),
      createdAt: Value(createdAt),
    );
  }

  factory AttachedDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachedDocument(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      name: serializer.fromJson<String>(json['name']),
      mime: serializer.fromJson<String>(json['mime']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      charCount: serializer.fromJson<int>(json['charCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'name': serializer.toJson<String>(name),
      'mime': serializer.toJson<String>(mime),
      'pageCount': serializer.toJson<int>(pageCount),
      'charCount': serializer.toJson<int>(charCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AttachedDocument copyWith({
    int? id,
    int? conversationId,
    String? name,
    String? mime,
    int? pageCount,
    int? charCount,
    DateTime? createdAt,
  }) => AttachedDocument(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    name: name ?? this.name,
    mime: mime ?? this.mime,
    pageCount: pageCount ?? this.pageCount,
    charCount: charCount ?? this.charCount,
    createdAt: createdAt ?? this.createdAt,
  );
  AttachedDocument copyWithCompanion(AttachedDocumentsCompanion data) {
    return AttachedDocument(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      name: data.name.present ? data.name.value : this.name,
      mime: data.mime.present ? data.mime.value : this.mime,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      charCount: data.charCount.present ? data.charCount.value : this.charCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachedDocument(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('pageCount: $pageCount, ')
          ..write('charCount: $charCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    name,
    mime,
    pageCount,
    charCount,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachedDocument &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.name == this.name &&
          other.mime == this.mime &&
          other.pageCount == this.pageCount &&
          other.charCount == this.charCount &&
          other.createdAt == this.createdAt);
}

class AttachedDocumentsCompanion extends UpdateCompanion<AttachedDocument> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<String> name;
  final Value<String> mime;
  final Value<int> pageCount;
  final Value<int> charCount;
  final Value<DateTime> createdAt;
  const AttachedDocumentsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.name = const Value.absent(),
    this.mime = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.charCount = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AttachedDocumentsCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required String name,
    required String mime,
    this.pageCount = const Value.absent(),
    this.charCount = const Value.absent(),
    required DateTime createdAt,
  }) : conversationId = Value(conversationId),
       name = Value(name),
       mime = Value(mime),
       createdAt = Value(createdAt);
  static Insertable<AttachedDocument> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<String>? name,
    Expression<String>? mime,
    Expression<int>? pageCount,
    Expression<int>? charCount,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (name != null) 'name': name,
      if (mime != null) 'mime': mime,
      if (pageCount != null) 'page_count': pageCount,
      if (charCount != null) 'char_count': charCount,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AttachedDocumentsCompanion copyWith({
    Value<int>? id,
    Value<int>? conversationId,
    Value<String>? name,
    Value<String>? mime,
    Value<int>? pageCount,
    Value<int>? charCount,
    Value<DateTime>? createdAt,
  }) {
    return AttachedDocumentsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      name: name ?? this.name,
      mime: mime ?? this.mime,
      pageCount: pageCount ?? this.pageCount,
      charCount: charCount ?? this.charCount,
      createdAt: createdAt ?? this.createdAt,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (charCount.present) {
      map['char_count'] = Variable<int>(charCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachedDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('pageCount: $pageCount, ')
          ..write('charCount: $charCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DocumentChunksTable extends DocumentChunks
    with TableInfo<$DocumentChunksTable, DocumentChunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentChunksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES attached_documents (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chunkIndexMeta = const VerificationMeta(
    'chunkIndex',
  );
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
    'chunk_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    documentId,
    chunkIndex,
    page,
    body,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_chunks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentChunk> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('chunk_index')) {
      context.handle(
        _chunkIndexMeta,
        chunkIndex.isAcceptableOrUnknown(data['chunk_index']!, _chunkIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkIndexMeta);
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    } else if (isInserting) {
      context.missing(_pageMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DocumentChunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentChunk(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      chunkIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_index'],
      )!,
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $DocumentChunksTable createAlias(String alias) {
    return $DocumentChunksTable(attachedDatabase, alias);
  }
}

class DocumentChunk extends DataClass implements Insertable<DocumentChunk> {
  final int id;
  final int documentId;
  final int chunkIndex;
  final int page;
  final String body;
  const DocumentChunk({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.page,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['document_id'] = Variable<int>(documentId);
    map['chunk_index'] = Variable<int>(chunkIndex);
    map['page'] = Variable<int>(page);
    map['body'] = Variable<String>(body);
    return map;
  }

  DocumentChunksCompanion toCompanion(bool nullToAbsent) {
    return DocumentChunksCompanion(
      id: Value(id),
      documentId: Value(documentId),
      chunkIndex: Value(chunkIndex),
      page: Value(page),
      body: Value(body),
    );
  }

  factory DocumentChunk.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentChunk(
      id: serializer.fromJson<int>(json['id']),
      documentId: serializer.fromJson<int>(json['documentId']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      page: serializer.fromJson<int>(json['page']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'documentId': serializer.toJson<int>(documentId),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'page': serializer.toJson<int>(page),
      'body': serializer.toJson<String>(body),
    };
  }

  DocumentChunk copyWith({
    int? id,
    int? documentId,
    int? chunkIndex,
    int? page,
    String? body,
  }) => DocumentChunk(
    id: id ?? this.id,
    documentId: documentId ?? this.documentId,
    chunkIndex: chunkIndex ?? this.chunkIndex,
    page: page ?? this.page,
    body: body ?? this.body,
  );
  DocumentChunk copyWithCompanion(DocumentChunksCompanion data) {
    return DocumentChunk(
      id: data.id.present ? data.id.value : this.id,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      chunkIndex: data.chunkIndex.present
          ? data.chunkIndex.value
          : this.chunkIndex,
      page: data.page.present ? data.page.value : this.page,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentChunk(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('page: $page, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, documentId, chunkIndex, page, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentChunk &&
          other.id == this.id &&
          other.documentId == this.documentId &&
          other.chunkIndex == this.chunkIndex &&
          other.page == this.page &&
          other.body == this.body);
}

class DocumentChunksCompanion extends UpdateCompanion<DocumentChunk> {
  final Value<int> id;
  final Value<int> documentId;
  final Value<int> chunkIndex;
  final Value<int> page;
  final Value<String> body;
  const DocumentChunksCompanion({
    this.id = const Value.absent(),
    this.documentId = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.page = const Value.absent(),
    this.body = const Value.absent(),
  });
  DocumentChunksCompanion.insert({
    this.id = const Value.absent(),
    required int documentId,
    required int chunkIndex,
    required int page,
    required String body,
  }) : documentId = Value(documentId),
       chunkIndex = Value(chunkIndex),
       page = Value(page),
       body = Value(body);
  static Insertable<DocumentChunk> custom({
    Expression<int>? id,
    Expression<int>? documentId,
    Expression<int>? chunkIndex,
    Expression<int>? page,
    Expression<String>? body,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (documentId != null) 'document_id': documentId,
      if (chunkIndex != null) 'chunk_index': chunkIndex,
      if (page != null) 'page': page,
      if (body != null) 'body': body,
    });
  }

  DocumentChunksCompanion copyWith({
    Value<int>? id,
    Value<int>? documentId,
    Value<int>? chunkIndex,
    Value<int>? page,
    Value<String>? body,
  }) {
    return DocumentChunksCompanion(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      page: page ?? this.page,
      body: body ?? this.body,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (chunkIndex.present) {
      map['chunk_index'] = Variable<int>(chunkIndex.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentChunksCompanion(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('page: $page, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }
}

class $ConnectorAccountsTable extends ConnectorAccounts
    with TableInfo<$ConnectorAccountsTable, ConnectorAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConnectorAccountsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _connectorMeta = const VerificationMeta(
    'connector',
  );
  @override
  late final GeneratedColumn<String> connector = GeneratedColumn<String>(
    'connector',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _connectedAtMeta = const VerificationMeta(
    'connectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> connectedAt = GeneratedColumn<DateTime>(
    'connected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    connector,
    status,
    label,
    configJson,
    lastError,
    connectedAt,
    lastSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'connector_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConnectorAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('connector')) {
      context.handle(
        _connectorMeta,
        connector.isAcceptableOrUnknown(data['connector']!, _connectorMeta),
      );
    } else if (isInserting) {
      context.missing(_connectorMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('connected_at')) {
      context.handle(
        _connectedAtMeta,
        connectedAt.isAcceptableOrUnknown(
          data['connected_at']!,
          _connectedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectedAtMeta);
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConnectorAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConnectorAccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      connector: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connector'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      connectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}connected_at'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
    );
  }

  @override
  $ConnectorAccountsTable createAlias(String alias) {
    return $ConnectorAccountsTable(attachedDatabase, alias);
  }
}

class ConnectorAccountRow extends DataClass
    implements Insertable<ConnectorAccountRow> {
  final int id;
  final String connector;
  final String status;
  final String? label;
  final String? configJson;
  final String? lastError;
  final DateTime connectedAt;
  final DateTime? lastSyncAt;
  const ConnectorAccountRow({
    required this.id,
    required this.connector,
    required this.status,
    this.label,
    this.configJson,
    this.lastError,
    required this.connectedAt,
    this.lastSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['connector'] = Variable<String>(connector);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    if (!nullToAbsent || configJson != null) {
      map['config_json'] = Variable<String>(configJson);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['connected_at'] = Variable<DateTime>(connectedAt);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    return map;
  }

  ConnectorAccountsCompanion toCompanion(bool nullToAbsent) {
    return ConnectorAccountsCompanion(
      id: Value(id),
      connector: Value(connector),
      status: Value(status),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      configJson: configJson == null && nullToAbsent
          ? const Value.absent()
          : Value(configJson),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      connectedAt: Value(connectedAt),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
    );
  }

  factory ConnectorAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConnectorAccountRow(
      id: serializer.fromJson<int>(json['id']),
      connector: serializer.fromJson<String>(json['connector']),
      status: serializer.fromJson<String>(json['status']),
      label: serializer.fromJson<String?>(json['label']),
      configJson: serializer.fromJson<String?>(json['configJson']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      connectedAt: serializer.fromJson<DateTime>(json['connectedAt']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'connector': serializer.toJson<String>(connector),
      'status': serializer.toJson<String>(status),
      'label': serializer.toJson<String?>(label),
      'configJson': serializer.toJson<String?>(configJson),
      'lastError': serializer.toJson<String?>(lastError),
      'connectedAt': serializer.toJson<DateTime>(connectedAt),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
    };
  }

  ConnectorAccountRow copyWith({
    int? id,
    String? connector,
    String? status,
    Value<String?> label = const Value.absent(),
    Value<String?> configJson = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? connectedAt,
    Value<DateTime?> lastSyncAt = const Value.absent(),
  }) => ConnectorAccountRow(
    id: id ?? this.id,
    connector: connector ?? this.connector,
    status: status ?? this.status,
    label: label.present ? label.value : this.label,
    configJson: configJson.present ? configJson.value : this.configJson,
    lastError: lastError.present ? lastError.value : this.lastError,
    connectedAt: connectedAt ?? this.connectedAt,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
  );
  ConnectorAccountRow copyWithCompanion(ConnectorAccountsCompanion data) {
    return ConnectorAccountRow(
      id: data.id.present ? data.id.value : this.id,
      connector: data.connector.present ? data.connector.value : this.connector,
      status: data.status.present ? data.status.value : this.status,
      label: data.label.present ? data.label.value : this.label,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      connectedAt: data.connectedAt.present
          ? data.connectedAt.value
          : this.connectedAt,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConnectorAccountRow(')
          ..write('id: $id, ')
          ..write('connector: $connector, ')
          ..write('status: $status, ')
          ..write('label: $label, ')
          ..write('configJson: $configJson, ')
          ..write('lastError: $lastError, ')
          ..write('connectedAt: $connectedAt, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    connector,
    status,
    label,
    configJson,
    lastError,
    connectedAt,
    lastSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConnectorAccountRow &&
          other.id == this.id &&
          other.connector == this.connector &&
          other.status == this.status &&
          other.label == this.label &&
          other.configJson == this.configJson &&
          other.lastError == this.lastError &&
          other.connectedAt == this.connectedAt &&
          other.lastSyncAt == this.lastSyncAt);
}

class ConnectorAccountsCompanion extends UpdateCompanion<ConnectorAccountRow> {
  final Value<int> id;
  final Value<String> connector;
  final Value<String> status;
  final Value<String?> label;
  final Value<String?> configJson;
  final Value<String?> lastError;
  final Value<DateTime> connectedAt;
  final Value<DateTime?> lastSyncAt;
  const ConnectorAccountsCompanion({
    this.id = const Value.absent(),
    this.connector = const Value.absent(),
    this.status = const Value.absent(),
    this.label = const Value.absent(),
    this.configJson = const Value.absent(),
    this.lastError = const Value.absent(),
    this.connectedAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
  });
  ConnectorAccountsCompanion.insert({
    this.id = const Value.absent(),
    required String connector,
    required String status,
    this.label = const Value.absent(),
    this.configJson = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime connectedAt,
    this.lastSyncAt = const Value.absent(),
  }) : connector = Value(connector),
       status = Value(status),
       connectedAt = Value(connectedAt);
  static Insertable<ConnectorAccountRow> custom({
    Expression<int>? id,
    Expression<String>? connector,
    Expression<String>? status,
    Expression<String>? label,
    Expression<String>? configJson,
    Expression<String>? lastError,
    Expression<DateTime>? connectedAt,
    Expression<DateTime>? lastSyncAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (connector != null) 'connector': connector,
      if (status != null) 'status': status,
      if (label != null) 'label': label,
      if (configJson != null) 'config_json': configJson,
      if (lastError != null) 'last_error': lastError,
      if (connectedAt != null) 'connected_at': connectedAt,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
    });
  }

  ConnectorAccountsCompanion copyWith({
    Value<int>? id,
    Value<String>? connector,
    Value<String>? status,
    Value<String?>? label,
    Value<String?>? configJson,
    Value<String?>? lastError,
    Value<DateTime>? connectedAt,
    Value<DateTime?>? lastSyncAt,
  }) {
    return ConnectorAccountsCompanion(
      id: id ?? this.id,
      connector: connector ?? this.connector,
      status: status ?? this.status,
      label: label ?? this.label,
      configJson: configJson ?? this.configJson,
      lastError: lastError ?? this.lastError,
      connectedAt: connectedAt ?? this.connectedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (connector.present) {
      map['connector'] = Variable<String>(connector.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (connectedAt.present) {
      map['connected_at'] = Variable<DateTime>(connectedAt.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConnectorAccountsCompanion(')
          ..write('id: $id, ')
          ..write('connector: $connector, ')
          ..write('status: $status, ')
          ..write('label: $label, ')
          ..write('configJson: $configJson, ')
          ..write('lastError: $lastError, ')
          ..write('connectedAt: $connectedAt, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }
}

class $ItemsTable extends Items with TableInfo<$ItemsTable, ItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ItemKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ItemKind>($ItemsTable.$converterkind);
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
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _peopleJsonMeta = const VerificationMeta(
    'peopleJson',
  );
  @override
  late final GeneratedColumn<String> peopleJson = GeneratedColumn<String>(
    'people_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _startsAtMeta = const VerificationMeta(
    'startsAt',
  );
  @override
  late final GeneratedColumn<DateTime> startsAt = GeneratedColumn<DateTime>(
    'starts_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _flagsJsonMeta = const VerificationMeta(
    'flagsJson',
  );
  @override
  late final GeneratedColumn<String> flagsJson = GeneratedColumn<String>(
    'flags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryModelMeta = const VerificationMeta(
    'summaryModel',
  );
  @override
  late final GeneratedColumn<String> summaryModel = GeneratedColumn<String>(
    'summary_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    source,
    externalId,
    kind,
    title,
    body,
    peopleJson,
    startsAt,
    sentAt,
    flagsJson,
    summary,
    summaryModel,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_externalIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('people_json')) {
      context.handle(
        _peopleJsonMeta,
        peopleJson.isAcceptableOrUnknown(data['people_json']!, _peopleJsonMeta),
      );
    }
    if (data.containsKey('starts_at')) {
      context.handle(
        _startsAtMeta,
        startsAt.isAcceptableOrUnknown(data['starts_at']!, _startsAtMeta),
      );
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    if (data.containsKey('flags_json')) {
      context.handle(
        _flagsJsonMeta,
        flagsJson.isAcceptableOrUnknown(data['flags_json']!, _flagsJsonMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('summary_model')) {
      context.handle(
        _summaryModelMeta,
        summaryModel.isAcceptableOrUnknown(
          data['summary_model']!,
          _summaryModelMeta,
        ),
      );
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {source, externalId},
  ];
  @override
  ItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      )!,
      kind: $ItemsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      peopleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}people_json'],
      )!,
      startsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}starts_at'],
      ),
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
      flagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}flags_json'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      summaryModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_model'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ItemsTable createAlias(String alias) {
    return $ItemsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ItemKind, String, String> $converterkind =
      const EnumNameConverter<ItemKind>(ItemKind.values);
}

class ItemRow extends DataClass implements Insertable<ItemRow> {
  final int id;
  final String source;
  final String externalId;
  final ItemKind kind;
  final String title;
  final String body;

  /// JSON list of `{name, email}` objects (attendees, sender).
  final String peopleJson;
  final DateTime? startsAt;
  final DateTime? sentAt;

  /// JSON object of small per-kind facts (all-day, package, mime, ...).
  final String flagsJson;
  final String? summary;
  final String? summaryModel;
  final DateTime updatedAt;
  const ItemRow({
    required this.id,
    required this.source,
    required this.externalId,
    required this.kind,
    required this.title,
    required this.body,
    required this.peopleJson,
    this.startsAt,
    this.sentAt,
    required this.flagsJson,
    this.summary,
    this.summaryModel,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source'] = Variable<String>(source);
    map['external_id'] = Variable<String>(externalId);
    {
      map['kind'] = Variable<String>($ItemsTable.$converterkind.toSql(kind));
    }
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['people_json'] = Variable<String>(peopleJson);
    if (!nullToAbsent || startsAt != null) {
      map['starts_at'] = Variable<DateTime>(startsAt);
    }
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    map['flags_json'] = Variable<String>(flagsJson);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || summaryModel != null) {
      map['summary_model'] = Variable<String>(summaryModel);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ItemsCompanion toCompanion(bool nullToAbsent) {
    return ItemsCompanion(
      id: Value(id),
      source: Value(source),
      externalId: Value(externalId),
      kind: Value(kind),
      title: Value(title),
      body: Value(body),
      peopleJson: Value(peopleJson),
      startsAt: startsAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startsAt),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
      flagsJson: Value(flagsJson),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      summaryModel: summaryModel == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryModel),
      updatedAt: Value(updatedAt),
    );
  }

  factory ItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemRow(
      id: serializer.fromJson<int>(json['id']),
      source: serializer.fromJson<String>(json['source']),
      externalId: serializer.fromJson<String>(json['externalId']),
      kind: $ItemsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      peopleJson: serializer.fromJson<String>(json['peopleJson']),
      startsAt: serializer.fromJson<DateTime?>(json['startsAt']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
      flagsJson: serializer.fromJson<String>(json['flagsJson']),
      summary: serializer.fromJson<String?>(json['summary']),
      summaryModel: serializer.fromJson<String?>(json['summaryModel']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'source': serializer.toJson<String>(source),
      'externalId': serializer.toJson<String>(externalId),
      'kind': serializer.toJson<String>(
        $ItemsTable.$converterkind.toJson(kind),
      ),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'peopleJson': serializer.toJson<String>(peopleJson),
      'startsAt': serializer.toJson<DateTime?>(startsAt),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
      'flagsJson': serializer.toJson<String>(flagsJson),
      'summary': serializer.toJson<String?>(summary),
      'summaryModel': serializer.toJson<String?>(summaryModel),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ItemRow copyWith({
    int? id,
    String? source,
    String? externalId,
    ItemKind? kind,
    String? title,
    String? body,
    String? peopleJson,
    Value<DateTime?> startsAt = const Value.absent(),
    Value<DateTime?> sentAt = const Value.absent(),
    String? flagsJson,
    Value<String?> summary = const Value.absent(),
    Value<String?> summaryModel = const Value.absent(),
    DateTime? updatedAt,
  }) => ItemRow(
    id: id ?? this.id,
    source: source ?? this.source,
    externalId: externalId ?? this.externalId,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    body: body ?? this.body,
    peopleJson: peopleJson ?? this.peopleJson,
    startsAt: startsAt.present ? startsAt.value : this.startsAt,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
    flagsJson: flagsJson ?? this.flagsJson,
    summary: summary.present ? summary.value : this.summary,
    summaryModel: summaryModel.present ? summaryModel.value : this.summaryModel,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ItemRow copyWithCompanion(ItemsCompanion data) {
    return ItemRow(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      peopleJson: data.peopleJson.present
          ? data.peopleJson.value
          : this.peopleJson,
      startsAt: data.startsAt.present ? data.startsAt.value : this.startsAt,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      flagsJson: data.flagsJson.present ? data.flagsJson.value : this.flagsJson,
      summary: data.summary.present ? data.summary.value : this.summary,
      summaryModel: data.summaryModel.present
          ? data.summaryModel.value
          : this.summaryModel,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemRow(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('peopleJson: $peopleJson, ')
          ..write('startsAt: $startsAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('flagsJson: $flagsJson, ')
          ..write('summary: $summary, ')
          ..write('summaryModel: $summaryModel, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    source,
    externalId,
    kind,
    title,
    body,
    peopleJson,
    startsAt,
    sentAt,
    flagsJson,
    summary,
    summaryModel,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemRow &&
          other.id == this.id &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.body == this.body &&
          other.peopleJson == this.peopleJson &&
          other.startsAt == this.startsAt &&
          other.sentAt == this.sentAt &&
          other.flagsJson == this.flagsJson &&
          other.summary == this.summary &&
          other.summaryModel == this.summaryModel &&
          other.updatedAt == this.updatedAt);
}

class ItemsCompanion extends UpdateCompanion<ItemRow> {
  final Value<int> id;
  final Value<String> source;
  final Value<String> externalId;
  final Value<ItemKind> kind;
  final Value<String> title;
  final Value<String> body;
  final Value<String> peopleJson;
  final Value<DateTime?> startsAt;
  final Value<DateTime?> sentAt;
  final Value<String> flagsJson;
  final Value<String?> summary;
  final Value<String?> summaryModel;
  final Value<DateTime> updatedAt;
  const ItemsCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.peopleJson = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.flagsJson = const Value.absent(),
    this.summary = const Value.absent(),
    this.summaryModel = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ItemsCompanion.insert({
    this.id = const Value.absent(),
    required String source,
    required String externalId,
    required ItemKind kind,
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.peopleJson = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.flagsJson = const Value.absent(),
    this.summary = const Value.absent(),
    this.summaryModel = const Value.absent(),
    required DateTime updatedAt,
  }) : source = Value(source),
       externalId = Value(externalId),
       kind = Value(kind),
       updatedAt = Value(updatedAt);
  static Insertable<ItemRow> custom({
    Expression<int>? id,
    Expression<String>? source,
    Expression<String>? externalId,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? peopleJson,
    Expression<DateTime>? startsAt,
    Expression<DateTime>? sentAt,
    Expression<String>? flagsJson,
    Expression<String>? summary,
    Expression<String>? summaryModel,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (peopleJson != null) 'people_json': peopleJson,
      if (startsAt != null) 'starts_at': startsAt,
      if (sentAt != null) 'sent_at': sentAt,
      if (flagsJson != null) 'flags_json': flagsJson,
      if (summary != null) 'summary': summary,
      if (summaryModel != null) 'summary_model': summaryModel,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? source,
    Value<String>? externalId,
    Value<ItemKind>? kind,
    Value<String>? title,
    Value<String>? body,
    Value<String>? peopleJson,
    Value<DateTime?>? startsAt,
    Value<DateTime?>? sentAt,
    Value<String>? flagsJson,
    Value<String?>? summary,
    Value<String?>? summaryModel,
    Value<DateTime>? updatedAt,
  }) {
    return ItemsCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      body: body ?? this.body,
      peopleJson: peopleJson ?? this.peopleJson,
      startsAt: startsAt ?? this.startsAt,
      sentAt: sentAt ?? this.sentAt,
      flagsJson: flagsJson ?? this.flagsJson,
      summary: summary ?? this.summary,
      summaryModel: summaryModel ?? this.summaryModel,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $ItemsTable.$converterkind.toSql(kind.value),
      );
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (peopleJson.present) {
      map['people_json'] = Variable<String>(peopleJson.value);
    }
    if (startsAt.present) {
      map['starts_at'] = Variable<DateTime>(startsAt.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (flagsJson.present) {
      map['flags_json'] = Variable<String>(flagsJson.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (summaryModel.present) {
      map['summary_model'] = Variable<String>(summaryModel.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('peopleJson: $peopleJson, ')
          ..write('startsAt: $startsAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('flagsJson: $flagsJson, ')
          ..write('summary: $summary, ')
          ..write('summaryModel: $summaryModel, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $LedgerTable extends Ledger with TableInfo<$LedgerTable, LedgerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _connectorMeta = const VerificationMeta(
    'connector',
  );
  @override
  late final GeneratedColumn<String> connector = GeneratedColumn<String>(
    'connector',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, connector, action, count, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger';
  @override
  VerificationContext validateIntegrity(
    Insertable<LedgerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('connector')) {
      context.handle(
        _connectorMeta,
        connector.isAcceptableOrUnknown(data['connector']!, _connectorMeta),
      );
    } else if (isInserting) {
      context.missing(_connectorMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LedgerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      connector: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connector'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $LedgerTable createAlias(String alias) {
    return $LedgerTable(attachedDatabase, alias);
  }
}

class LedgerRow extends DataClass implements Insertable<LedgerRow> {
  final int id;
  final String connector;
  final String action;
  final int count;
  final DateTime at;
  const LedgerRow({
    required this.id,
    required this.connector,
    required this.action,
    required this.count,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['connector'] = Variable<String>(connector);
    map['action'] = Variable<String>(action);
    map['count'] = Variable<int>(count);
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  LedgerCompanion toCompanion(bool nullToAbsent) {
    return LedgerCompanion(
      id: Value(id),
      connector: Value(connector),
      action: Value(action),
      count: Value(count),
      at: Value(at),
    );
  }

  factory LedgerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerRow(
      id: serializer.fromJson<int>(json['id']),
      connector: serializer.fromJson<String>(json['connector']),
      action: serializer.fromJson<String>(json['action']),
      count: serializer.fromJson<int>(json['count']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'connector': serializer.toJson<String>(connector),
      'action': serializer.toJson<String>(action),
      'count': serializer.toJson<int>(count),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  LedgerRow copyWith({
    int? id,
    String? connector,
    String? action,
    int? count,
    DateTime? at,
  }) => LedgerRow(
    id: id ?? this.id,
    connector: connector ?? this.connector,
    action: action ?? this.action,
    count: count ?? this.count,
    at: at ?? this.at,
  );
  LedgerRow copyWithCompanion(LedgerCompanion data) {
    return LedgerRow(
      id: data.id.present ? data.id.value : this.id,
      connector: data.connector.present ? data.connector.value : this.connector,
      action: data.action.present ? data.action.value : this.action,
      count: data.count.present ? data.count.value : this.count,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerRow(')
          ..write('id: $id, ')
          ..write('connector: $connector, ')
          ..write('action: $action, ')
          ..write('count: $count, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, connector, action, count, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerRow &&
          other.id == this.id &&
          other.connector == this.connector &&
          other.action == this.action &&
          other.count == this.count &&
          other.at == this.at);
}

class LedgerCompanion extends UpdateCompanion<LedgerRow> {
  final Value<int> id;
  final Value<String> connector;
  final Value<String> action;
  final Value<int> count;
  final Value<DateTime> at;
  const LedgerCompanion({
    this.id = const Value.absent(),
    this.connector = const Value.absent(),
    this.action = const Value.absent(),
    this.count = const Value.absent(),
    this.at = const Value.absent(),
  });
  LedgerCompanion.insert({
    this.id = const Value.absent(),
    required String connector,
    required String action,
    this.count = const Value.absent(),
    required DateTime at,
  }) : connector = Value(connector),
       action = Value(action),
       at = Value(at);
  static Insertable<LedgerRow> custom({
    Expression<int>? id,
    Expression<String>? connector,
    Expression<String>? action,
    Expression<int>? count,
    Expression<DateTime>? at,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (connector != null) 'connector': connector,
      if (action != null) 'action': action,
      if (count != null) 'count': count,
      if (at != null) 'at': at,
    });
  }

  LedgerCompanion copyWith({
    Value<int>? id,
    Value<String>? connector,
    Value<String>? action,
    Value<int>? count,
    Value<DateTime>? at,
  }) {
    return LedgerCompanion(
      id: id ?? this.id,
      connector: connector ?? this.connector,
      action: action ?? this.action,
      count: count ?? this.count,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (connector.present) {
      map['connector'] = Variable<String>(connector.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerCompanion(')
          ..write('id: $id, ')
          ..write('connector: $connector, ')
          ..write('action: $action, ')
          ..write('count: $count, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

class $SavedAnswersTable extends SavedAnswers
    with TableInfo<$SavedAnswersTable, SavedAnswer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedAnswersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
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
  static const VerificationMeta _sourceConnectorsMeta = const VerificationMeta(
    'sourceConnectors',
  );
  @override
  late final GeneratedColumn<String> sourceConnectors = GeneratedColumn<String>(
    'source_connectors',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    conversationId,
    createdAt,
    sourceConnectors,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_answers';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedAnswer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
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
    if (data.containsKey('source_connectors')) {
      context.handle(
        _sourceConnectorsMeta,
        sourceConnectors.isAcceptableOrUnknown(
          data['source_connectors']!,
          _sourceConnectorsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedAnswer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedAnswer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sourceConnectors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_connectors'],
      )!,
    );
  }

  @override
  $SavedAnswersTable createAlias(String alias) {
    return $SavedAnswersTable(attachedDatabase, alias);
  }
}

class SavedAnswer extends DataClass implements Insertable<SavedAnswer> {
  final int id;
  final String content;
  final int? conversationId;
  final DateTime createdAt;

  /// Connector ids the source conversation cited when this was saved, as
  /// `,calendar,notifications,` (empty when none). Derived data: revoking one
  /// of these connectors, or clearing all chat history, deletes this row
  /// (v9; see `LibraryStore`). `content` is unique via an index (v9).
  final String sourceConnectors;
  const SavedAnswer({
    required this.id,
    required this.content,
    this.conversationId,
    required this.createdAt,
    required this.sourceConnectors,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || conversationId != null) {
      map['conversation_id'] = Variable<int>(conversationId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['source_connectors'] = Variable<String>(sourceConnectors);
    return map;
  }

  SavedAnswersCompanion toCompanion(bool nullToAbsent) {
    return SavedAnswersCompanion(
      id: Value(id),
      content: Value(content),
      conversationId: conversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(conversationId),
      createdAt: Value(createdAt),
      sourceConnectors: Value(sourceConnectors),
    );
  }

  factory SavedAnswer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedAnswer(
      id: serializer.fromJson<int>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      conversationId: serializer.fromJson<int?>(json['conversationId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sourceConnectors: serializer.fromJson<String>(json['sourceConnectors']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'content': serializer.toJson<String>(content),
      'conversationId': serializer.toJson<int?>(conversationId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sourceConnectors': serializer.toJson<String>(sourceConnectors),
    };
  }

  SavedAnswer copyWith({
    int? id,
    String? content,
    Value<int?> conversationId = const Value.absent(),
    DateTime? createdAt,
    String? sourceConnectors,
  }) => SavedAnswer(
    id: id ?? this.id,
    content: content ?? this.content,
    conversationId: conversationId.present
        ? conversationId.value
        : this.conversationId,
    createdAt: createdAt ?? this.createdAt,
    sourceConnectors: sourceConnectors ?? this.sourceConnectors,
  );
  SavedAnswer copyWithCompanion(SavedAnswersCompanion data) {
    return SavedAnswer(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sourceConnectors: data.sourceConnectors.present
          ? data.sourceConnectors.value
          : this.sourceConnectors,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedAnswer(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('conversationId: $conversationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('sourceConnectors: $sourceConnectors')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, content, conversationId, createdAt, sourceConnectors);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedAnswer &&
          other.id == this.id &&
          other.content == this.content &&
          other.conversationId == this.conversationId &&
          other.createdAt == this.createdAt &&
          other.sourceConnectors == this.sourceConnectors);
}

class SavedAnswersCompanion extends UpdateCompanion<SavedAnswer> {
  final Value<int> id;
  final Value<String> content;
  final Value<int?> conversationId;
  final Value<DateTime> createdAt;
  final Value<String> sourceConnectors;
  const SavedAnswersCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sourceConnectors = const Value.absent(),
  });
  SavedAnswersCompanion.insert({
    this.id = const Value.absent(),
    required String content,
    this.conversationId = const Value.absent(),
    required DateTime createdAt,
    this.sourceConnectors = const Value.absent(),
  }) : content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<SavedAnswer> custom({
    Expression<int>? id,
    Expression<String>? content,
    Expression<int>? conversationId,
    Expression<DateTime>? createdAt,
    Expression<String>? sourceConnectors,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (conversationId != null) 'conversation_id': conversationId,
      if (createdAt != null) 'created_at': createdAt,
      if (sourceConnectors != null) 'source_connectors': sourceConnectors,
    });
  }

  SavedAnswersCompanion copyWith({
    Value<int>? id,
    Value<String>? content,
    Value<int?>? conversationId,
    Value<DateTime>? createdAt,
    Value<String>? sourceConnectors,
  }) {
    return SavedAnswersCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      conversationId: conversationId ?? this.conversationId,
      createdAt: createdAt ?? this.createdAt,
      sourceConnectors: sourceConnectors ?? this.sourceConnectors,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sourceConnectors.present) {
      map['source_connectors'] = Variable<String>(sourceConnectors.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedAnswersCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('conversationId: $conversationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('sourceConnectors: $sourceConnectors')
          ..write(')'))
        .toString();
  }
}

class $TodosTable extends Todos with TableInfo<$TodosTable, Todo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodosTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _taskMeta = const VerificationMeta('task');
  @override
  late final GeneratedColumn<String> task = GeneratedColumn<String>(
    'task',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
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
  static const VerificationMeta _sourceConnectorsMeta = const VerificationMeta(
    'sourceConnectors',
  );
  @override
  late final GeneratedColumn<String> sourceConnectors = GeneratedColumn<String>(
    'source_connectors',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    task,
    done,
    createdAt,
    sourceConnectors,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Todo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('task')) {
      context.handle(
        _taskMeta,
        task.isAcceptableOrUnknown(data['task']!, _taskMeta),
      );
    } else if (isInserting) {
      context.missing(_taskMeta);
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
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
    if (data.containsKey('source_connectors')) {
      context.handle(
        _sourceConnectorsMeta,
        sourceConnectors.isAcceptableOrUnknown(
          data['source_connectors']!,
          _sourceConnectorsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Todo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Todo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      task: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sourceConnectors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_connectors'],
      )!,
    );
  }

  @override
  $TodosTable createAlias(String alias) {
    return $TodosTable(attachedDatabase, alias);
  }
}

class Todo extends DataClass implements Insertable<Todo> {
  final int id;
  final String task;
  final bool done;
  final DateTime createdAt;

  /// Same meaning as [SavedAnswers.sourceConnectors] (v9).
  final String sourceConnectors;
  const Todo({
    required this.id,
    required this.task,
    required this.done,
    required this.createdAt,
    required this.sourceConnectors,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['task'] = Variable<String>(task);
    map['done'] = Variable<bool>(done);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['source_connectors'] = Variable<String>(sourceConnectors);
    return map;
  }

  TodosCompanion toCompanion(bool nullToAbsent) {
    return TodosCompanion(
      id: Value(id),
      task: Value(task),
      done: Value(done),
      createdAt: Value(createdAt),
      sourceConnectors: Value(sourceConnectors),
    );
  }

  factory Todo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Todo(
      id: serializer.fromJson<int>(json['id']),
      task: serializer.fromJson<String>(json['task']),
      done: serializer.fromJson<bool>(json['done']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sourceConnectors: serializer.fromJson<String>(json['sourceConnectors']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'task': serializer.toJson<String>(task),
      'done': serializer.toJson<bool>(done),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sourceConnectors': serializer.toJson<String>(sourceConnectors),
    };
  }

  Todo copyWith({
    int? id,
    String? task,
    bool? done,
    DateTime? createdAt,
    String? sourceConnectors,
  }) => Todo(
    id: id ?? this.id,
    task: task ?? this.task,
    done: done ?? this.done,
    createdAt: createdAt ?? this.createdAt,
    sourceConnectors: sourceConnectors ?? this.sourceConnectors,
  );
  Todo copyWithCompanion(TodosCompanion data) {
    return Todo(
      id: data.id.present ? data.id.value : this.id,
      task: data.task.present ? data.task.value : this.task,
      done: data.done.present ? data.done.value : this.done,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sourceConnectors: data.sourceConnectors.present
          ? data.sourceConnectors.value
          : this.sourceConnectors,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Todo(')
          ..write('id: $id, ')
          ..write('task: $task, ')
          ..write('done: $done, ')
          ..write('createdAt: $createdAt, ')
          ..write('sourceConnectors: $sourceConnectors')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, task, done, createdAt, sourceConnectors);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Todo &&
          other.id == this.id &&
          other.task == this.task &&
          other.done == this.done &&
          other.createdAt == this.createdAt &&
          other.sourceConnectors == this.sourceConnectors);
}

class TodosCompanion extends UpdateCompanion<Todo> {
  final Value<int> id;
  final Value<String> task;
  final Value<bool> done;
  final Value<DateTime> createdAt;
  final Value<String> sourceConnectors;
  const TodosCompanion({
    this.id = const Value.absent(),
    this.task = const Value.absent(),
    this.done = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sourceConnectors = const Value.absent(),
  });
  TodosCompanion.insert({
    this.id = const Value.absent(),
    required String task,
    this.done = const Value.absent(),
    required DateTime createdAt,
    this.sourceConnectors = const Value.absent(),
  }) : task = Value(task),
       createdAt = Value(createdAt);
  static Insertable<Todo> custom({
    Expression<int>? id,
    Expression<String>? task,
    Expression<bool>? done,
    Expression<DateTime>? createdAt,
    Expression<String>? sourceConnectors,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (task != null) 'task': task,
      if (done != null) 'done': done,
      if (createdAt != null) 'created_at': createdAt,
      if (sourceConnectors != null) 'source_connectors': sourceConnectors,
    });
  }

  TodosCompanion copyWith({
    Value<int>? id,
    Value<String>? task,
    Value<bool>? done,
    Value<DateTime>? createdAt,
    Value<String>? sourceConnectors,
  }) {
    return TodosCompanion(
      id: id ?? this.id,
      task: task ?? this.task,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      sourceConnectors: sourceConnectors ?? this.sourceConnectors,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (task.present) {
      map['task'] = Variable<String>(task.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sourceConnectors.present) {
      map['source_connectors'] = Variable<String>(sourceConnectors.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodosCompanion(')
          ..write('id: $id, ')
          ..write('task: $task, ')
          ..write('done: $done, ')
          ..write('createdAt: $createdAt, ')
          ..write('sourceConnectors: $sourceConnectors')
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
  late final $ContentReportsTable contentReports = $ContentReportsTable(this);
  late final $AttachedDocumentsTable attachedDocuments =
      $AttachedDocumentsTable(this);
  late final $DocumentChunksTable documentChunks = $DocumentChunksTable(this);
  late final $ConnectorAccountsTable connectorAccounts =
      $ConnectorAccountsTable(this);
  late final $ItemsTable items = $ItemsTable(this);
  late final $LedgerTable ledger = $LedgerTable(this);
  late final $SavedAnswersTable savedAnswers = $SavedAnswersTable(this);
  late final $TodosTable todos = $TodosTable(this);
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
    contentReports,
    attachedDocuments,
    documentChunks,
    connectorAccounts,
    items,
    ledger,
    savedAnswers,
    todos,
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('attached_documents', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'attached_documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('document_chunks', kind: UpdateKind.delete)],
    ),
  ]);
}
