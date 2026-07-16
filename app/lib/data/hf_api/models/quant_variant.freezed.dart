// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quant_variant.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QuantVariant {

/// e.g. "Q4_K_M", "Q8_0", "F16".
 String get label; HfRepoFile get file;
/// Create a copy of QuantVariant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuantVariantCopyWith<QuantVariant> get copyWith => _$QuantVariantCopyWithImpl<QuantVariant>(this as QuantVariant, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuantVariant&&(identical(other.label, label) || other.label == label)&&(identical(other.file, file) || other.file == file));
}


@override
int get hashCode => Object.hash(runtimeType,label,file);

@override
String toString() {
  return 'QuantVariant(label: $label, file: $file)';
}


}

/// @nodoc
abstract mixin class $QuantVariantCopyWith<$Res>  {
  factory $QuantVariantCopyWith(QuantVariant value, $Res Function(QuantVariant) _then) = _$QuantVariantCopyWithImpl;
@useResult
$Res call({
 String label, HfRepoFile file
});


$HfRepoFileCopyWith<$Res> get file;

}
/// @nodoc
class _$QuantVariantCopyWithImpl<$Res>
    implements $QuantVariantCopyWith<$Res> {
  _$QuantVariantCopyWithImpl(this._self, this._then);

  final QuantVariant _self;
  final $Res Function(QuantVariant) _then;

/// Create a copy of QuantVariant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? file = null,}) {
  return _then(_self.copyWith(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as HfRepoFile,
  ));
}
/// Create a copy of QuantVariant
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HfRepoFileCopyWith<$Res> get file {
  
  return $HfRepoFileCopyWith<$Res>(_self.file, (value) {
    return _then(_self.copyWith(file: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuantVariant].
extension QuantVariantPatterns on QuantVariant {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuantVariant value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuantVariant() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuantVariant value)  $default,){
final _that = this;
switch (_that) {
case _QuantVariant():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuantVariant value)?  $default,){
final _that = this;
switch (_that) {
case _QuantVariant() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  HfRepoFile file)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuantVariant() when $default != null:
return $default(_that.label,_that.file);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  HfRepoFile file)  $default,) {final _that = this;
switch (_that) {
case _QuantVariant():
return $default(_that.label,_that.file);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  HfRepoFile file)?  $default,) {final _that = this;
switch (_that) {
case _QuantVariant() when $default != null:
return $default(_that.label,_that.file);case _:
  return null;

}
}

}

/// @nodoc


class _QuantVariant implements QuantVariant {
  const _QuantVariant({required this.label, required this.file});
  

/// e.g. "Q4_K_M", "Q8_0", "F16".
@override final  String label;
@override final  HfRepoFile file;

/// Create a copy of QuantVariant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuantVariantCopyWith<_QuantVariant> get copyWith => __$QuantVariantCopyWithImpl<_QuantVariant>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuantVariant&&(identical(other.label, label) || other.label == label)&&(identical(other.file, file) || other.file == file));
}


@override
int get hashCode => Object.hash(runtimeType,label,file);

@override
String toString() {
  return 'QuantVariant(label: $label, file: $file)';
}


}

/// @nodoc
abstract mixin class _$QuantVariantCopyWith<$Res> implements $QuantVariantCopyWith<$Res> {
  factory _$QuantVariantCopyWith(_QuantVariant value, $Res Function(_QuantVariant) _then) = __$QuantVariantCopyWithImpl;
@override @useResult
$Res call({
 String label, HfRepoFile file
});


@override $HfRepoFileCopyWith<$Res> get file;

}
/// @nodoc
class __$QuantVariantCopyWithImpl<$Res>
    implements _$QuantVariantCopyWith<$Res> {
  __$QuantVariantCopyWithImpl(this._self, this._then);

  final _QuantVariant _self;
  final $Res Function(_QuantVariant) _then;

/// Create a copy of QuantVariant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? file = null,}) {
  return _then(_QuantVariant(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as HfRepoFile,
  ));
}

/// Create a copy of QuantVariant
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HfRepoFileCopyWith<$Res> get file {
  
  return $HfRepoFileCopyWith<$Res>(_self.file, (value) {
    return _then(_self.copyWith(file: value));
  });
}
}

// dart format on
