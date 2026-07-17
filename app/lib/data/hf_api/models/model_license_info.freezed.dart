// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_license_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelLicenseInfo {

/// `cardData.license` (falls back to the `license:*` tag) e.g.
/// "apache-2.0", "llama2". Null when the repo declares none.
 String? get license; HfGatedStatus get gatedStatus;
/// Create a copy of ModelLicenseInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelLicenseInfoCopyWith<ModelLicenseInfo> get copyWith => _$ModelLicenseInfoCopyWithImpl<ModelLicenseInfo>(this as ModelLicenseInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelLicenseInfo&&(identical(other.license, license) || other.license == license)&&(identical(other.gatedStatus, gatedStatus) || other.gatedStatus == gatedStatus));
}


@override
int get hashCode => Object.hash(runtimeType,license,gatedStatus);

@override
String toString() {
  return 'ModelLicenseInfo(license: $license, gatedStatus: $gatedStatus)';
}


}

/// @nodoc
abstract mixin class $ModelLicenseInfoCopyWith<$Res>  {
  factory $ModelLicenseInfoCopyWith(ModelLicenseInfo value, $Res Function(ModelLicenseInfo) _then) = _$ModelLicenseInfoCopyWithImpl;
@useResult
$Res call({
 String? license, HfGatedStatus gatedStatus
});




}
/// @nodoc
class _$ModelLicenseInfoCopyWithImpl<$Res>
    implements $ModelLicenseInfoCopyWith<$Res> {
  _$ModelLicenseInfoCopyWithImpl(this._self, this._then);

  final ModelLicenseInfo _self;
  final $Res Function(ModelLicenseInfo) _then;

/// Create a copy of ModelLicenseInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? license = freezed,Object? gatedStatus = null,}) {
  return _then(_self.copyWith(
license: freezed == license ? _self.license : license // ignore: cast_nullable_to_non_nullable
as String?,gatedStatus: null == gatedStatus ? _self.gatedStatus : gatedStatus // ignore: cast_nullable_to_non_nullable
as HfGatedStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelLicenseInfo].
extension ModelLicenseInfoPatterns on ModelLicenseInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelLicenseInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelLicenseInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelLicenseInfo value)  $default,){
final _that = this;
switch (_that) {
case _ModelLicenseInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelLicenseInfo value)?  $default,){
final _that = this;
switch (_that) {
case _ModelLicenseInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? license,  HfGatedStatus gatedStatus)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelLicenseInfo() when $default != null:
return $default(_that.license,_that.gatedStatus);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? license,  HfGatedStatus gatedStatus)  $default,) {final _that = this;
switch (_that) {
case _ModelLicenseInfo():
return $default(_that.license,_that.gatedStatus);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? license,  HfGatedStatus gatedStatus)?  $default,) {final _that = this;
switch (_that) {
case _ModelLicenseInfo() when $default != null:
return $default(_that.license,_that.gatedStatus);case _:
  return null;

}
}

}

/// @nodoc


class _ModelLicenseInfo extends ModelLicenseInfo {
  const _ModelLicenseInfo({this.license, required this.gatedStatus}): super._();
  

/// `cardData.license` (falls back to the `license:*` tag) e.g.
/// "apache-2.0", "llama2". Null when the repo declares none.
@override final  String? license;
@override final  HfGatedStatus gatedStatus;

/// Create a copy of ModelLicenseInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelLicenseInfoCopyWith<_ModelLicenseInfo> get copyWith => __$ModelLicenseInfoCopyWithImpl<_ModelLicenseInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelLicenseInfo&&(identical(other.license, license) || other.license == license)&&(identical(other.gatedStatus, gatedStatus) || other.gatedStatus == gatedStatus));
}


@override
int get hashCode => Object.hash(runtimeType,license,gatedStatus);

@override
String toString() {
  return 'ModelLicenseInfo(license: $license, gatedStatus: $gatedStatus)';
}


}

/// @nodoc
abstract mixin class _$ModelLicenseInfoCopyWith<$Res> implements $ModelLicenseInfoCopyWith<$Res> {
  factory _$ModelLicenseInfoCopyWith(_ModelLicenseInfo value, $Res Function(_ModelLicenseInfo) _then) = __$ModelLicenseInfoCopyWithImpl;
@override @useResult
$Res call({
 String? license, HfGatedStatus gatedStatus
});




}
/// @nodoc
class __$ModelLicenseInfoCopyWithImpl<$Res>
    implements _$ModelLicenseInfoCopyWith<$Res> {
  __$ModelLicenseInfoCopyWithImpl(this._self, this._then);

  final _ModelLicenseInfo _self;
  final $Res Function(_ModelLicenseInfo) _then;

/// Create a copy of ModelLicenseInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? license = freezed,Object? gatedStatus = null,}) {
  return _then(_ModelLicenseInfo(
license: freezed == license ? _self.license : license // ignore: cast_nullable_to_non_nullable
as String?,gatedStatus: null == gatedStatus ? _self.gatedStatus : gatedStatus // ignore: cast_nullable_to_non_nullable
as HfGatedStatus,
  ));
}


}

// dart format on
