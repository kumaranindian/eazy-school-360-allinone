/// Runs [action] for every item with at most [limit] in flight at once.
///
/// A sequential loop over hundreds of independent documents is needlessly
/// slow; an unbounded `Future.wait` floods the connection. Results are not
/// collected. If any action throws, the first error is rethrown after the
/// running ones settle and no further item is started.
Future<void> forEachBounded<T>(
  Iterable<T> items,
  int limit,
  Future<void> Function(T item) action,
) async {
  assert(limit > 0);
  final iterator = items.iterator;
  Object? error;
  StackTrace? stack;
  Future<void> worker() async {
    while (error == null && iterator.moveNext()) {
      try {
        await action(iterator.current);
      } catch (e, s) {
        error ??= e;
        stack ??= s;
      }
    }
  }

  await Future.wait([for (var i = 0; i < limit; i++) worker()]);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}
