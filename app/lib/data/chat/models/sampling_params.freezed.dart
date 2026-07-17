// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sampling_params.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SamplingParams {

 double get temperature; double get topP; int get topK; int get contextLength; int get maxTokens; int? get seed;
/// Create a copy of SamplingParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SamplingParamsCopyWith<SamplingParams> get copyWith => _$SamplingParamsCopyWithImpl<SamplingParams>(this as SamplingParams, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SamplingParams&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.topP, topP) || other.topP == topP)&&(identical(other.topK, topK) || other.topK == topK)&&(identical(other.contextLength, contextLength) || other.contextLength == contextLength)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.seed, seed) || other.seed == seed));
}


@override
int get hashCode => Object.hash(runtimeType,temperature,topP,topK,contextLength,maxTokens,seed);

@override
String toString() {
  return 'SamplingParams(temperature: $temperature, topP: $topP, topK: $topK, contextLength: $contextLength, maxTokens: $maxTokens, seed: $seed)';
}


}

/// @nodoc
abstract mixin class $SamplingParamsCopyWith<$Res>  {
  factory $SamplingParamsCopyWith(SamplingParams value, $Res Function(SamplingParams) _then) = _$SamplingParamsCopyWithImpl;
@useResult
$Res call({
 double temperature, double topP, int topK, int contextLength, int maxTokens, int? seed
});




}
/// @nodoc
class _$SamplingParamsCopyWithImpl<$Res>
    implements $SamplingParamsCopyWith<$Res> {
  _$SamplingParamsCopyWithImpl(this._self, this._then);

  final SamplingParams _self;
  final $Res Function(SamplingParams) _then;

/// Create a copy of SamplingParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? temperature = null,Object? topP = null,Object? topK = null,Object? contextLength = null,Object? maxTokens = null,Object? seed = freezed,}) {
  return _then(_self.copyWith(
temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,topP: null == topP ? _self.topP : topP // ignore: cast_nullable_to_non_nullable
as double,topK: null == topK ? _self.topK : topK // ignore: cast_nullable_to_non_nullable
as int,contextLength: null == contextLength ? _self.contextLength : contextLength // ignore: cast_nullable_to_non_nullable
as int,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,seed: freezed == seed ? _self.seed : seed // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [SamplingParams].
extension SamplingParamsPatterns on SamplingParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SamplingParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SamplingParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SamplingParams value)  $default,){
final _that = this;
switch (_that) {
case _SamplingParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SamplingParams value)?  $default,){
final _that = this;
switch (_that) {
case _SamplingParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double temperature,  double topP,  int topK,  int contextLength,  int maxTokens,  int? seed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SamplingParams() when $default != null:
return $default(_that.temperature,_that.topP,_that.topK,_that.contextLength,_that.maxTokens,_that.seed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double temperature,  double topP,  int topK,  int contextLength,  int maxTokens,  int? seed)  $default,) {final _that = this;
switch (_that) {
case _SamplingParams():
return $default(_that.temperature,_that.topP,_that.topK,_that.contextLength,_that.maxTokens,_that.seed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double temperature,  double topP,  int topK,  int contextLength,  int maxTokens,  int? seed)?  $default,) {final _that = this;
switch (_that) {
case _SamplingParams() when $default != null:
return $default(_that.temperature,_that.topP,_that.topK,_that.contextLength,_that.maxTokens,_that.seed);case _:
  return null;

}
}

}

/// @nodoc


class _SamplingParams extends SamplingParams {
  const _SamplingParams({this.temperature = 0.8, this.topP = 0.95, this.topK = 40, this.contextLength = 4096, this.maxTokens = 512, this.seed}): super._();
  

@override@JsonKey() final  double temperature;
@override@JsonKey() final  double topP;
@override@JsonKey() final  int topK;
@override@JsonKey() final  int contextLength;
@override@JsonKey() final  int maxTokens;
@override final  int? seed;

/// Create a copy of SamplingParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SamplingParamsCopyWith<_SamplingParams> get copyWith => __$SamplingParamsCopyWithImpl<_SamplingParams>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SamplingParams&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.topP, topP) || other.topP == topP)&&(identical(other.topK, topK) || other.topK == topK)&&(identical(other.contextLength, contextLength) || other.contextLength == contextLength)&&(identical(other.maxTokens, maxTokens) || other.maxTokens == maxTokens)&&(identical(other.seed, seed) || other.seed == seed));
}


@override
int get hashCode => Object.hash(runtimeType,temperature,topP,topK,contextLength,maxTokens,seed);

@override
String toString() {
  return 'SamplingParams(temperature: $temperature, topP: $topP, topK: $topK, contextLength: $contextLength, maxTokens: $maxTokens, seed: $seed)';
}


}

/// @nodoc
abstract mixin class _$SamplingParamsCopyWith<$Res> implements $SamplingParamsCopyWith<$Res> {
  factory _$SamplingParamsCopyWith(_SamplingParams value, $Res Function(_SamplingParams) _then) = __$SamplingParamsCopyWithImpl;
@override @useResult
$Res call({
 double temperature, double topP, int topK, int contextLength, int maxTokens, int? seed
});




}
/// @nodoc
class __$SamplingParamsCopyWithImpl<$Res>
    implements _$SamplingParamsCopyWith<$Res> {
  __$SamplingParamsCopyWithImpl(this._self, this._then);

  final _SamplingParams _self;
  final $Res Function(_SamplingParams) _then;

/// Create a copy of SamplingParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? temperature = null,Object? topP = null,Object? topK = null,Object? contextLength = null,Object? maxTokens = null,Object? seed = freezed,}) {
  return _then(_SamplingParams(
temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,topP: null == topP ? _self.topP : topP // ignore: cast_nullable_to_non_nullable
as double,topK: null == topK ? _self.topK : topK // ignore: cast_nullable_to_non_nullable
as int,contextLength: null == contextLength ? _self.contextLength : contextLength // ignore: cast_nullable_to_non_nullable
as int,maxTokens: null == maxTokens ? _self.maxTokens : maxTokens // ignore: cast_nullable_to_non_nullable
as int,seed: freezed == seed ? _self.seed : seed // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
