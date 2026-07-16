// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hf_model_summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HfModelSummary {

/// "namespace/model-name".
 String get id; int get likes; int get downloads; List<String> get tags; String? get pipelineTag; ModelLicenseInfo get license;
/// Create a copy of HfModelSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HfModelSummaryCopyWith<HfModelSummary> get copyWith => _$HfModelSummaryCopyWithImpl<HfModelSummary>(this as HfModelSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HfModelSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.likes, likes) || other.likes == likes)&&(identical(other.downloads, downloads) || other.downloads == downloads)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.pipelineTag, pipelineTag) || other.pipelineTag == pipelineTag)&&(identical(other.license, license) || other.license == license));
}


@override
int get hashCode => Object.hash(runtimeType,id,likes,downloads,const DeepCollectionEquality().hash(tags),pipelineTag,license);

@override
String toString() {
  return 'HfModelSummary(id: $id, likes: $likes, downloads: $downloads, tags: $tags, pipelineTag: $pipelineTag, license: $license)';
}


}

/// @nodoc
abstract mixin class $HfModelSummaryCopyWith<$Res>  {
  factory $HfModelSummaryCopyWith(HfModelSummary value, $Res Function(HfModelSummary) _then) = _$HfModelSummaryCopyWithImpl;
@useResult
$Res call({
 String id, int likes, int downloads, List<String> tags, String? pipelineTag, ModelLicenseInfo license
});


$ModelLicenseInfoCopyWith<$Res> get license;

}
/// @nodoc
class _$HfModelSummaryCopyWithImpl<$Res>
    implements $HfModelSummaryCopyWith<$Res> {
  _$HfModelSummaryCopyWithImpl(this._self, this._then);

  final HfModelSummary _self;
  final $Res Function(HfModelSummary) _then;

/// Create a copy of HfModelSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? likes = null,Object? downloads = null,Object? tags = null,Object? pipelineTag = freezed,Object? license = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,likes: null == likes ? _self.likes : likes // ignore: cast_nullable_to_non_nullable
as int,downloads: null == downloads ? _self.downloads : downloads // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,pipelineTag: freezed == pipelineTag ? _self.pipelineTag : pipelineTag // ignore: cast_nullable_to_non_nullable
as String?,license: null == license ? _self.license : license // ignore: cast_nullable_to_non_nullable
as ModelLicenseInfo,
  ));
}
/// Create a copy of HfModelSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelLicenseInfoCopyWith<$Res> get license {
  
  return $ModelLicenseInfoCopyWith<$Res>(_self.license, (value) {
    return _then(_self.copyWith(license: value));
  });
}
}


/// Adds pattern-matching-related methods to [HfModelSummary].
extension HfModelSummaryPatterns on HfModelSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HfModelSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HfModelSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HfModelSummary value)  $default,){
final _that = this;
switch (_that) {
case _HfModelSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HfModelSummary value)?  $default,){
final _that = this;
switch (_that) {
case _HfModelSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int likes,  int downloads,  List<String> tags,  String? pipelineTag,  ModelLicenseInfo license)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HfModelSummary() when $default != null:
return $default(_that.id,_that.likes,_that.downloads,_that.tags,_that.pipelineTag,_that.license);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int likes,  int downloads,  List<String> tags,  String? pipelineTag,  ModelLicenseInfo license)  $default,) {final _that = this;
switch (_that) {
case _HfModelSummary():
return $default(_that.id,_that.likes,_that.downloads,_that.tags,_that.pipelineTag,_that.license);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int likes,  int downloads,  List<String> tags,  String? pipelineTag,  ModelLicenseInfo license)?  $default,) {final _that = this;
switch (_that) {
case _HfModelSummary() when $default != null:
return $default(_that.id,_that.likes,_that.downloads,_that.tags,_that.pipelineTag,_that.license);case _:
  return null;

}
}

}

/// @nodoc


class _HfModelSummary implements HfModelSummary {
  const _HfModelSummary({required this.id, required this.likes, required this.downloads, required final  List<String> tags, this.pipelineTag, required this.license}): _tags = tags;
  

/// "namespace/model-name".
@override final  String id;
@override final  int likes;
@override final  int downloads;
 final  List<String> _tags;
@override List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override final  String? pipelineTag;
@override final  ModelLicenseInfo license;

/// Create a copy of HfModelSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HfModelSummaryCopyWith<_HfModelSummary> get copyWith => __$HfModelSummaryCopyWithImpl<_HfModelSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HfModelSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.likes, likes) || other.likes == likes)&&(identical(other.downloads, downloads) || other.downloads == downloads)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.pipelineTag, pipelineTag) || other.pipelineTag == pipelineTag)&&(identical(other.license, license) || other.license == license));
}


@override
int get hashCode => Object.hash(runtimeType,id,likes,downloads,const DeepCollectionEquality().hash(_tags),pipelineTag,license);

@override
String toString() {
  return 'HfModelSummary(id: $id, likes: $likes, downloads: $downloads, tags: $tags, pipelineTag: $pipelineTag, license: $license)';
}


}

/// @nodoc
abstract mixin class _$HfModelSummaryCopyWith<$Res> implements $HfModelSummaryCopyWith<$Res> {
  factory _$HfModelSummaryCopyWith(_HfModelSummary value, $Res Function(_HfModelSummary) _then) = __$HfModelSummaryCopyWithImpl;
@override @useResult
$Res call({
 String id, int likes, int downloads, List<String> tags, String? pipelineTag, ModelLicenseInfo license
});


@override $ModelLicenseInfoCopyWith<$Res> get license;

}
/// @nodoc
class __$HfModelSummaryCopyWithImpl<$Res>
    implements _$HfModelSummaryCopyWith<$Res> {
  __$HfModelSummaryCopyWithImpl(this._self, this._then);

  final _HfModelSummary _self;
  final $Res Function(_HfModelSummary) _then;

/// Create a copy of HfModelSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? likes = null,Object? downloads = null,Object? tags = null,Object? pipelineTag = freezed,Object? license = null,}) {
  return _then(_HfModelSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,likes: null == likes ? _self.likes : likes // ignore: cast_nullable_to_non_nullable
as int,downloads: null == downloads ? _self.downloads : downloads // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,pipelineTag: freezed == pipelineTag ? _self.pipelineTag : pipelineTag // ignore: cast_nullable_to_non_nullable
as String?,license: null == license ? _self.license : license // ignore: cast_nullable_to_non_nullable
as ModelLicenseInfo,
  ));
}

/// Create a copy of HfModelSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelLicenseInfoCopyWith<$Res> get license {
  
  return $ModelLicenseInfoCopyWith<$Res>(_self.license, (value) {
    return _then(_self.copyWith(license: value));
  });
}
}

// dart format on
