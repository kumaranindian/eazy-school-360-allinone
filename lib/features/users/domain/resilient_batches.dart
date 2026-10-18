import 'dart:async';
import 'dart:math';

/// Waits between retries; replaced in tests so they never really sleep.
typedef Sleeper = Future<void> Function(Duration);

/// Exponential back-off for transient failures (network blips, a busy server,
/// rate limits): 1s, 2s, 4s … capped, each with up to 25% random jitter so a
/// crowd of retries does not arrive together.
class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  const RetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 20),
  });

  Duration delayBefore(int retryNumber, Random random) {
    final exp = baseDelay * pow(2, retryNumber - 1).toInt();
    final capped = exp > maxDelay ? maxDelay : exp;
    return capped +
        Duration(milliseconds: random.nextInt(capped.inMilliseconds ~/ 4 + 1));
  }
}

Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

/// Runs [run]; on an error [isTransient] accepts, waits and tries again, up to
/// [RetryPolicy.maxAttempts] in total. Any other error — and the last
/// transient one — is rethrown untouched.
Future<T> withRetry<T>(
  Future<T> Function() run, {
  required bool Function(Object error) isTransient,
  RetryPolicy policy = const RetryPolicy(),
  Sleeper sleep = _realSleep,
  Random? random,
}) async {
  final rng = random ?? Random();
  for (var attempt = 1; ; attempt++) {
    try {
      return await run();
    } catch (error) {
      if (attempt >= policy.maxAttempts || !isTransient(error)) rethrow;
      await sleep(policy.delayBefore(attempt, rng));
    }
  }
}

/// Splits [items] into batches of [batchSize] and sends them through [call],
/// at most [concurrency] at a time, so a long list is never one giant request
/// and never a burst that trips rate limits.
///
/// * A transient failure of one batch is retried with back-off; if it still
///   fails, only that batch is reported through [onGaveUp] — the others
///   carry on and nothing already done is repeated or lost.
/// * A permanent error (permission, bad request) is rethrown at once: it would
///   fail every batch the same way.
/// * [isCancelled] is checked before each batch; batches not yet started are
///   reported through [onGaveUp] as well, so the caller can offer "try again".
/// * Results come back in the order of [items].
Future<List<R>> runResilientBatches<I, R>({
  required List<I> items,
  required int batchSize,
  required Future<List<R>> Function(List<I> batch) call,
  required List<R> Function(List<I> batch) onGaveUp,
  required bool Function(Object error) isTransient,
  int concurrency = 2,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  RetryPolicy policy = const RetryPolicy(),
  Sleeper sleep = _realSleep,
  Random? random,
}) async {
  final batches = <List<I>>[
    for (var i = 0; i < items.length; i += batchSize)
      items.sublist(i, min(i + batchSize, items.length)),
  ];
  final results = List<List<R>?>.filled(batches.length, null);
  var next = 0;
  var done = 0;
  Object? fatal;
  StackTrace? fatalTrace;
  onProgress?.call(0, items.length);

  Future<void> worker() async {
    while (fatal == null) {
      final index = next++;
      if (index >= batches.length) return;
      final batch = batches[index];
      if (isCancelled?.call() == true) {
        results[index] = onGaveUp(batch);
      } else {
        try {
          results[index] = await withRetry(
            () => call(batch),
            isTransient: isTransient,
            policy: policy,
            sleep: sleep,
            random: random,
          );
        } catch (error, stackTrace) {
          if (isTransient(error)) {
            results[index] = onGaveUp(batch);
          } else {
            fatal = error;
            fatalTrace = stackTrace;
            return;
          }
        }
      }
      done += batch.length;
      onProgress?.call(done, items.length);
    }
  }

  await Future.wait([for (var i = 0; i < max(1, concurrency); i++) worker()]);
  if (fatal != null) {
    Error.throwWithStackTrace(fatal!, fatalTrace ?? StackTrace.current);
  }
  return [for (final r in results) ...?r];
}

/// Calls [send] for each item one after another, [spacing] apart (e-mail
/// providers throttle bursts), retrying transient failures with back-off.
/// Returns the items that still failed — never throws for one bad item.
Future<List<T>> sendThrottled<T>({
  required List<T> items,
  required Future<void> Function(T item) send,
  required bool Function(Object error) isTransient,
  Duration spacing = const Duration(milliseconds: 350),
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  RetryPolicy policy = const RetryPolicy(
    maxAttempts: 3,
    baseDelay: Duration(seconds: 2),
  ),
  Sleeper sleep = _realSleep,
  Random? random,
}) async {
  final failed = <T>[];
  for (var i = 0; i < items.length; i++) {
    if (isCancelled?.call() == true) {
      failed.addAll(items.sublist(i));
      break;
    }
    try {
      await withRetry(
        () => send(items[i]),
        isTransient: isTransient,
        policy: policy,
        sleep: sleep,
        random: random,
      );
    } catch (_) {
      failed.add(items[i]);
    }
    onProgress?.call(i + 1, items.length);
    if (i < items.length - 1 && spacing > Duration.zero) await sleep(spacing);
  }
  return failed;
}
