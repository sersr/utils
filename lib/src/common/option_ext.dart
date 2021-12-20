import 'dart:async';

import '../option.dart';
import '../../future_or_ext.dart';

/// 将其他任何类型转化为[Option]类型
extension OptionFutureExt<T> on FutureOr<T?> {
  FutureOr<Option<T>> optionFut() {
    return then((value) {
      return value == null ? None<T>() : Some(value);
    }, onError: (e) => None<T>());
  }

  FutureOr<S> mapOption<S>(
      {required S Function() ifNone, required S Function(T v) ifSome}) {
    return then((value) {
      return value == null ? ifNone() : ifSome(value);
    }, onError: (e) => ifNone());
  }
}

/// 将[Option?]转化为[Option]
extension MapOnOption<T> on FutureOr<Option<T>?> {
  FutureOr<Option<T>> optionFut() {
    return then((value) => value ?? None<T>(), onError: (e) => None<T>());
  }

  FutureOr<S> mapOption<S>(
      {required S Function() ifNone, required S Function(T v) ifSome}) {
    return then((value) {
      return value == null
          ? ifNone()
          : value.map(ifNone: ifNone, ifSome: ifSome);
    }, onError: (e) => ifNone());
  }
}
