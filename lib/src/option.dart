abstract class Option<V> {
  const Option();
  S map<S>({required S Function() ifNone, required S Function(V v) ifSome});
}

class None<V> extends Option<V> {
  const None();

  @override
  S map<S>({required S Function() ifNone, required S Function(V v) ifSome}) =>
      ifNone();
}

class Some<V> extends Option<V> {
  const Some(this.v);
  final V v;
  @override
  S map<S>({required S Function() ifNone, required S Function(V v) ifSome}) =>
      ifSome(v);
}
