// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hf_repo_file.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HfRepoFile {

/// Full path within the repo, including subfolder prefix (e.g.
/// `"mmproj/mmproj-Q8_0.gguf"`).
 String get path; int get sizeBytes;/// `lfs.oid` when the tree entry carries a `sha256:`-prefixed oid;
/// null for non-LFS files or when the API omits it.
 String? get sha256;
/// Create a copy of HfRepoFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HfRepoFileCopyWith<HfRepoFile> get copyWith => _$HfRepoFileCopyWithImpl<HfRepoFile>(this as HfRepoFile, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HfRepoFile&&(identical(other.path, path) || other.path == path)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.sha256, sha256) || other.sha256 == sha256));
}


@override
int get hashCode => Object.hash(runtimeType,path,sizeBytes,sha256);

@override
String toString() {
  return 'HfRepoFile(path: $path, sizeBytes: $sizeBytes, sha256: $sha256)';
}


}

/// @nodoc
abstract mixin class $HfRepoFileCopyWith<$Res>  {
  factory $HfRepoFileCopyWith(HfRepoFile value, $Res Function(HfRepoFile) _then) = _$HfRepoFileCopyWithImpl;
@useResult
$Res call({
 String path, int sizeBytes, String? sha256
});




}
/// @nodoc
class _$HfRepoFileCopyWithImpl<$Res>
    implements $HfRepoFileCopyWith<$Res> {
  _$HfRepoFileCopyWithImpl(this._self, this._then);

  final HfRepoFile _self;
  final $Res Function(HfRepoFile) _then;

/// Create a copy of HfRepoFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? sizeBytes = null,Object? sha256 = freezed,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [HfRepoFile].
extension HfRepoFilePatterns on HfRepoFile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HfRepoFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HfRepoFile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HfRepoFile value)  $default,){
final _that = this;
switch (_that) {
case _HfRepoFile():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HfRepoFile value)?  $default,){
final _that = this;
switch (_that) {
case _HfRepoFile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  int sizeBytes,  String? sha256)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HfRepoFile() when $default != null:
return $default(_that.path,_that.sizeBytes,_that.sha256);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  int sizeBytes,  String? sha256)  $default,) {final _that = this;
switch (_that) {
case _HfRepoFile():
return $default(_that.path,_that.sizeBytes,_that.sha256);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  int sizeBytes,  String? sha256)?  $default,) {final _that = this;
switch (_that) {
case _HfRepoFile() when $default != null:
return $default(_that.path,_that.sizeBytes,_that.sha256);case _:
  return null;

}
}

}

/// @nodoc


class _HfRepoFile implements HfRepoFile {
  const _HfRepoFile({required this.path, required this.sizeBytes, this.sha256});
  

/// Full path within the repo, including subfolder prefix (e.g.
/// `"mmproj/mmproj-Q8_0.gguf"`).
@override final  String path;
@override final  int sizeBytes;
/// `lfs.oid` when the tree entry carries a `sha256:`-prefixed oid;
/// null for non-LFS files or when the API omits it.
@override final  String? sha256;

/// Create a copy of HfRepoFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HfRepoFileCopyWith<_HfRepoFile> get copyWith => __$HfRepoFileCopyWithImpl<_HfRepoFile>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HfRepoFile&&(identical(other.path, path) || other.path == path)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.sha256, sha256) || other.sha256 == sha256));
}


@override
int get hashCode => Object.hash(runtimeType,path,sizeBytes,sha256);

@override
String toString() {
  return 'HfRepoFile(path: $path, sizeBytes: $sizeBytes, sha256: $sha256)';
}


}

/// @nodoc
abstract mixin class _$HfRepoFileCopyWith<$Res> implements $HfRepoFileCopyWith<$Res> {
  factory _$HfRepoFileCopyWith(_HfRepoFile value, $Res Function(_HfRepoFile) _then) = __$HfRepoFileCopyWithImpl;
@override @useResult
$Res call({
 String path, int sizeBytes, String? sha256
});




}
/// @nodoc
class __$HfRepoFileCopyWithImpl<$Res>
    implements _$HfRepoFileCopyWith<$Res> {
  __$HfRepoFileCopyWithImpl(this._self, this._then);

  final _HfRepoFile _self;
  final $Res Function(_HfRepoFile) _then;

/// Create a copy of HfRepoFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? sizeBytes = null,Object? sha256 = freezed,}) {
  return _then(_HfRepoFile(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
