import 'package:eazy_school_360/features/announcements/domain/audience_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

class _Denied implements Exception {}

void main() {
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
