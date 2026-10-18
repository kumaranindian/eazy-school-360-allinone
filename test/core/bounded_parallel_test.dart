import 'package:eazy_school_360/core/utils/bounded_parallel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never more than the limit in flight, and every item runs', () async {
    var running = 0;
    var peak = 0;
    final done = <int>[];
    await forEachBounded(List.generate(25, (i) => i), 4, (i) async {
      running++;
      if (running > peak) peak = running;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      running--;
      done.add(i);
    });
    expect(peak, lessThanOrEqualTo(4));
    expect(peak, greaterThan(1));
    expect(done.toSet(), List.generate(25, (i) => i).toSet());
  });

  test('an error stops new work and is rethrown', () async {
    final started = <int>[];
    await expectLater(
      forEachBounded(List.generate(100, (i) => i), 2, (i) async {
        started.add(i);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (i == 3) throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(started.length, lessThan(100));
  });
}
