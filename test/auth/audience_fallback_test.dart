import 'package:eazy_school_360/features/announcements/domain/audience_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

class _Denied implements Exception {}

void main() {
  scopedTests();
  bool denied(Object e) => e is _Denied;

  test('non-parents run once with no audience constraint', () async {
    final seen = <List<String>>[];
    await runWithParentFallback<int>(
      isParent: false,
      isDenied: denied,
      run: (a) async {
        seen.add(a);
        return 1;
      },
    );
    expect(seen, [<String>[]]);
  });

  test('a parent asks for the wide audience set first', () async {
    final seen = <List<String>>[];
    await runWithParentFallback<int>(
      isParent: true,
      isDenied: denied,
      run: (a) async {
        seen.add(a);
        return 1;
      },
    );
    expect(seen, [parentAudiences]);
  });

  test(
    'a permission refusal falls back to school-wide announcements only',
    () async {
      final seen = <List<String>>[];
      final out = await runWithParentFallback<String>(
        isParent: true,
        isDenied: denied,
        run: (a) async {
          seen.add(a);
          if (a.length > 1) throw _Denied();
          return 'school-wide';
        },
      );
      expect(out, 'school-wide');
      expect(seen, [parentAudiences, schoolWideAudience]);
    },
  );

  test(
    'other errors are not swallowed, and a refused fallback surfaces',
    () async {
      await expectLater(
        runWithParentFallback<int>(
          isParent: true,
          isDenied: denied,
          run: (_) async => throw StateError('network'),
        ),
        throwsStateError,
      );
      await expectLater(
        runWithParentFallback<int>(
          isParent: true,
          isDenied: denied,
          run: (_) async => throw _Denied(),
        ),
        throwsA(isA<_Denied>()),
      );
    },
  );
}

void scopedTests() {
  group('planScopedParentQueries', () {
    test('one query per class and per section', () {
      expect(
        planScopedParentQueries(
          classKeys: ['c5', 'c6'],
          sectionKeys: ['c5__sa', 'c6__sb'],
        ),
        [
          const ScopedAudienceQuery.forClass('c5'),
          const ScopedAudienceQuery.forClass('c6'),
          const ScopedAudienceQuery.forSection('c5', 'sa'),
          const ScopedAudienceQuery.forSection('c6', 'sb'),
        ],
      );
    });

    test('no index keys means no scoped query; malformed keys are skipped', () {
      expect(planScopedParentQueries(classKeys: [], sectionKeys: []), isEmpty);
      expect(
        planScopedParentQueries(
          classKeys: [''],
          sectionKeys: ['__sa', 'c5__', 'nosep'],
        ),
        isEmpty,
      );
    });
  });

  test('mergeNewestFirst de-duplicates, sorts newest first and caps', () {
    final merged = mergeNewestFirst<(String, DateTime?)>(
      [
        [('a', DateTime(2026, 1, 1)), ('b', DateTime(2026, 1, 3))],
        [('b', DateTime(2020, 1, 1)), ('c', null), ('d', DateTime(2026, 1, 2))],
      ],
      idOf: (x) => x.$1,
      instantOf: (x) => x.$2,
      limit: 3,
    );
    expect(merged.map((x) => x.$1), ['b', 'd', 'a']);
  });
}
