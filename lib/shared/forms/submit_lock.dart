/// Runs one save at a time (STU-01-DEF-01). The lock is taken synchronously,
/// before the first `await`, so a second tap that reaches the handler before
/// the button has rebuilt as disabled (a web double click, Enter + click)
/// does nothing instead of starting a second save.
class SubmitLock {
  bool _busy = false;

  bool get busy => _busy;

  /// Runs [action] unless a run is already in progress; returns null then.
  Future<T?> run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}
