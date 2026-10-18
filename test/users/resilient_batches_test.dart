import 'dart:math';

import 'package:eazy_school_360/features/users/domain/resilient_batches.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transient implements Exception {}

class _Permanent implements Exception {}

bool _isTransient(Object e) => e is _Transient;

void main() {
  final slept = <Duration>[];
  Future<void> noSleep(Duration d) async => slept.add(d);
  setUp(slept.clear);

  group('withRetry', () {
    test(
      'retries transient errors with growing delays, then succeeds',
      () async {
        var n = 0;
        final v = await withRetry(
          () async {
            if (++n < 3) throw _Transient();
            return 'ok';
          },
          isTransient: _isTransient,
          sleep: noSleep,
          random: Random(1),
        );
        expect(v, 'ok');
        expect(n, 3);
        expect(slept.length, 2);
        expect(slept[1], greaterThan(slept[0]));
      },
    );

    test('gives up after maxAttempts and rethrows the last error', () async {
      var n = 0;
      await expectLater(
        withRetry(
          () async {
            n++;
            throw _Transient();
          },
          isTransient: _isTransient,
          policy: const RetryPolicy(maxAttempts: 3),
          sleep: noSleep,
        ),
        throwsA(isA<_Transient>()),
      );
      expect(n, 3);
    });

    test('does not retry a permanent error', () async {
      var n = 0;
      await expectLater(
        withRetry(
          () async {
            n++;
            throw _Permanent();
          },
          isTransient: _isTransient,
          sleep: noSleep,
        ),
        throwsA(isA<_Permanent>()),
      );
      expect(n, 1);
      expect(slept, isEmpty);
    });
  });

  group('runResilientBatches', () {
    final items = List.generate(25, (i) => i);

    Future<List<String>> run({
      required Future<List<String>> Function(List<int>) call,
      bool Function()? isCancelled,
      void Function(int, int)? onProgress,
      int concurrency = 2,
    }) => runResilientBatches<int, String>(
      items: items,
      batchSize: 10,
      concurrency: concurrency,
      call: call,
      onGaveUp: (b) => [for (final i in b) 'later$i'],
      isTransient: _isTransient,
      onProgress: onProgress,
      isCancelled: isCancelled,
      sleep: noSleep,
    );

    test(
      'splits into batches of the given size, keeps order, reports progress',
      () async {
        final sizes = <int>[];
        final progress = <int>[];
        final out = await run(
          call: (b) async {
            sizes.add(b.length);
            return [for (final i in b) 'ok$i'];
          },
          onProgress: (d, t) => progress.add(d),
        );
        expect(sizes..sort(), [5, 10, 10]);
        expect(out, [for (final i in items) 'ok$i']);
        expect(progress.first, 0);
        expect(progress.last, 25);
        expect(progress, orderedEquals([...progress]..sort()));
      },
    );

    test(
      'a batch that keeps failing is reported alone; the rest finish',
      () async {
        final out = await run(
          call: (b) async {
            if (b.first == 10) throw _Transient();
            return [for (final i in b) 'ok$i'];
          },
        );
        expect(out.where((e) => e.startsWith('later')).length, 10);
        expect(out.where((e) => e.startsWith('ok')).length, 15);
        expect(out[10], 'later10');
      },
    );

    test(
      'a batch that fails once is retried and its people are not duplicated',
      () async {
        final seen = <int>[];
        var failedOnce = false;
        final out = await run(
          call: (b) async {
            if (b.first == 10 && !failedOnce) {
              failedOnce = true;
              throw _Transient();
            }
            seen.addAll(b);
            return [for (final i in b) 'ok$i'];
          },
        );
        expect(out, [for (final i in items) 'ok$i']);
        expect(seen.toSet().length, 25);
        expect(seen.length, 25);
      },
    );

    test('a permanent error aborts instead of retrying every batch', () async {
      var calls = 0;
      await expectLater(
        run(
          concurrency: 1,
          call: (b) async {
            calls++;
            throw _Permanent();
          },
        ),
        throwsA(isA<_Permanent>()),
      );
      expect(calls, 1);
    });

    test(
      'cancelling stops new batches and reports the unstarted ones',
      () async {
        var cancelled = false;
        final out = await run(
          concurrency: 1,
          isCancelled: () => cancelled,
          call: (b) async {
            cancelled = true;
            return [for (final i in b) 'ok$i'];
          },
        );
        expect(out.where((e) => e.startsWith('ok')).length, 10);
        expect(out.where((e) => e.startsWith('later')).length, 15);
      },
    );

    test(
      'never runs more than the allowed number of requests at once',
      () async {
        var live = 0;
        var peak = 0;
        await run(
          call: (b) async {
            live++;
            peak = max(peak, live);
            await Future<void>.delayed(const Duration(milliseconds: 5));
            live--;
            return [for (final i in b) 'ok$i'];
          },
        );
        expect(peak, lessThanOrEqualTo(2));
      },
    );
  });

  group('sendThrottled', () {
    test(
      'spaces sends, retries transient failures, returns only the ones that still fail',
      () async {
        final sent = <String>[];
        var flaky = 0;
        final failed = await sendThrottled<String>(
          items: ['a', 'b', 'c'],
          send: (s) async {
            if (s == 'a' && flaky++ < 1) throw _Transient();
            if (s == 'b') throw _Transient();
            sent.add(s);
          },
          isTransient: _isTransient,
          sleep: noSleep,
        );
        expect(sent, ['a', 'c']);
        expect(failed, ['b']);
        expect(
          slept.where((d) => d == const Duration(milliseconds: 350)).length,
          2,
        );
      },
    );

    test('stopping returns the unsent ones as failed', () async {
      var n = 0;
      final failed = await sendThrottled<int>(
        items: [1, 2, 3, 4],
        send: (_) async => n++,
        isTransient: _isTransient,
        isCancelled: () => n >= 2,
        sleep: noSleep,
      );
      expect(failed, [3, 4]);
    });
  });
}
