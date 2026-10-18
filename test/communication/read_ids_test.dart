import 'package:eazy_school_360/features/notifications/domain/read_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new ids are appended once, old order kept', () {
    expect(mergeReadIds(['a', 'b'], ['b', 'c', 'c']), ['a', 'b', 'c']);
  });

  test('the oldest ids fall off beyond the cap', () {
    final merged = mergeReadIds(List.generate(500, (i) => 'o$i'), ['n1', 'n2']);
    expect(merged.length, 500);
    expect(merged.first, 'o2');
    expect(merged.last, 'n2');
  });

  test('two devices merging into the same base both survive', () {
    // What the transaction guarantees by re-reading: the second merge starts
    // from the first one's result, so neither device's ids are lost.
    final afterA = mergeReadIds(['x'], ['a']);
    final afterB = mergeReadIds(afterA, ['b']);
    expect(afterB, ['x', 'a', 'b']);
  });
}
