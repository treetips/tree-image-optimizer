/// 処理結果を表す。成功時は [T] の値を、失敗時は例外を保持する。
class Result<T> {
  const Result._(this._value, this._error, this._isOk);

  const Result.ok(T value) : this._(value, null, true);

  const Result.fail(Object error) : this._(null, error, false);

  final T? _value;
  final Object? _error;
  final bool _isOk;

  /// 成功したかどうか。
  bool get isOk => _isOk;

  /// 失敗したかどうか。
  bool get isFail => !_isOk;

  /// 値。失敗時は例外を投げる。
  T get value {
    if (!_isOk) {
      throw _error!;
    }
    return _value as T;
  }

  /// 値。失敗時は null。
  T? get asOk => _isOk ? _value : null;

  /// エラー。成功時は null。
  Object? get asFail => _error;
}
