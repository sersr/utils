import 'dart:async';

import '../match/option.dart';
import 'package:sc_event_queue/future_or.dart';

/// 将其他任何类型转化为[Option]类型
extension OptionFutureExt<T> on FutureOr<T?> {
  FutureOr<Option<T>> optionFut() {
    return then((value) {
      return value == null ? const None() : value.then(Some.wrap);
    }, onError: (e) => const None());
  }

  FutureOr<S> mapOption<S>(
      {required S Function() ifNone, required S Function(T v) ifSome}) {
    return mapOptionFut(ifNone: ifNone, ifSome: ifSome);
  }

  FutureOr<S> mapOptionFut<S>({
    required FutureOr<S> Function() ifNone,
    required FutureOr<S> Function(T v) ifSome,
  }) {
    return optionFut().then((value) {
      return value.map(ifNone: ifNone, ifSome: ifSome);
    });
  }
}

/// 将[Option?]转化为[Option]
extension MapOnOption<T> on FutureOr<Option<T>?> {
  FutureOr<Option<T>> optionFut() {
    return then((value) => value ?? None<T>(), onError: (e) => None<T>());
  }

  FutureOr<S> mapOption<S>(
      {required S Function() ifNone, required S Function(T v) ifSome}) {
    return mapOptionFut(ifNone: ifNone, ifSome: ifSome);
  }

  FutureOr<S> mapOptionFut<S>({
    required FutureOr<S> Function() ifNone,
    required FutureOr<S> Function(T v) ifSome,
  }) {
    return optionFut().then((value) {
      return value.map(ifNone: ifNone, ifSome: ifSome);
    });
  }
}

extension OptionFutureOrNull<T> on FutureOr<T>? {
  FutureOr<Option<T>> andOptionFut() {
    return andThen((value) {
      return value == null ? const None() : value.then(Some.wrap);
    }, onError: (e) => const None());
  }

  FutureOr<S> andMapOption<S>(
      {required S Function() ifNone, required S Function(T v) ifSome}) {
    return andMapOptionFut(ifNone: ifNone, ifSome: ifSome);
  }

  FutureOr<S> andMapOptionFut<S>({
    required FutureOr<S> Function() ifNone,
    required FutureOr<S> Function(T v) ifSome,
  }) {
    return andOptionFut().then((value) {
      return value.map(ifNone: ifNone, ifSome: ifSome);
    });
  }
}
