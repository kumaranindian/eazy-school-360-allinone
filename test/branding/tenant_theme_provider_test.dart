import 'dart:async';

import 'package:flutter/painting.dart';

import 'package:eazy_school_360/core/branding/tenant_branding.dart';
import 'package:eazy_school_360/features/branding/domain/branding_repository.dart';
import 'package:eazy_school_360/features/branding/presentation/providers/branding_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements BrandingRepository {
  final schools = <String, StreamController<TenantBranding?>>{};
  final platform = StreamController<PlatformBranding>.broadcast();
  final watched = <String>[];

  StreamController<TenantBranding?> _c(String id) =>
      schools.putIfAbsent(id, () => StreamController.broadcast());

  @override
  Stream<TenantBranding?> watchSchool(String id) {
    watched.add(id);
    return _c(id).stream;
  }

  @override
  Stream<PlatformBranding> watchPlatform() => platform.stream;

  TenantBranding? fetched;
  @override
  Future<TenantBranding?> fetchSchool(String id) async => fetched;

  void school(String id, TenantBranding? b) => _c(id).add(b);

  @override
  Future<int> saveSchool({
    required String schoolId,
    required String presetId,
    required BrandColors colors,
    required BrandingAppearance appearance,
    int? baseVersion,
  }) async => 0;
  @override
  Future<int> resetSchool({required String schoolId, int? baseVersion}) async =>
      0;
  @override
  Future<int> savePlatform(PlatformBranding branding) async => 0;
}

class _Cache implements BrandingCache {
  final schoolsData = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? platformData;

  @override
  Future<Map<String, dynamic>?> readSchool(String id) async => schoolsData[id];
  @override
  Future<void> writeSchool(String id, Map<String, dynamic> d) async =>
      schoolsData[id] = d;
  @override
  Future<Map<String, dynamic>?> readPlatform() async => platformData;
  @override
  Future<void> writePlatform(Map<String, dynamic> d) async => platformData = d;
}

class _Session extends Notifier<({bool signedIn, String? schoolId})> {
  @override
  ({bool signedIn, String? schoolId}) build() =>
      (signedIn: false, schoolId: null);
  void set(({bool signedIn, String? schoolId}) v) => state = v;
}

final _sessionProvider =
    NotifierProvider<_Session, ({bool signedIn, String? schoolId})>(
      _Session.new,
    );

final _indigo = BrandPresets.builtIn[1].colors;
final _crimson = BrandPresets.builtIn[2].colors;

TenantBranding _b(
  String school,
  int version,
  BrandColors? colors, {
  BrandingAppearance appearance = BrandingAppearance.system,
}) => TenantBranding(
  schoolId: school,
  version: version,
  presetId: 'x',
  colors: colors,
  appearance: appearance,
);

({ProviderContainer c, _Repo repo, _Cache cache}) _make({
  ({bool signedIn, String? schoolId}) session = (signedIn: true, schoolId: 'A'),
}) {
  final repo = _Repo();
  final cache = _Cache();
  final c = ProviderContainer(
    overrides: [
      brandingRepositoryProvider.overrideWithValue(repo),
      brandingCacheProvider.overrideWithValue(cache),
      themeSessionProvider.overrideWith((ref) => ref.watch(_sessionProvider)),
    ],
  );
  c.read(_sessionProvider.notifier).set(session);
  addTearDown(c.dispose);
  // Keep the (auto-managed) notifier alive and subscribed.
  c.listen(tenantThemeProvider, (_, _) {});
  return (c: c, repo: repo, cache: cache);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'signed out: the platform default, and nothing is listened to',
    () async {
      final m = _make(session: (signedIn: false, schoolId: null));
      await _settle();
      expect(m.c.read(tenantThemeProvider), ResolvedTheme.platformDefault);
      expect(m.repo.watched, isEmpty);
    },
  );

  test('a school without branding paints the default', () async {
    final m = _make();
    await _settle();
    m.repo.school('A', null);
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, BrandColors.emerald);
  });

  test(
    "a school's saved colours reach the app live (every role reads the same)",
    () async {
      final m = _make();
      await _settle();
      m.repo.school('A', _b('A', 1, _indigo));
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, _indigo);
      m.repo.school(
        'A',
        _b('A', 2, _crimson, appearance: BrandingAppearance.dark),
      );
      await _settle();
      final t = m.c.read(tenantThemeProvider);
      expect(t.colors, _crimson);
      expect(t.appearance, BrandingAppearance.dark);
      expect(t.version, 2);
    },
  );

  test('a stale (older) snapshot is ignored', () async {
    final m = _make();
    await _settle();
    m.repo.school('A', _b('A', 5, _indigo));
    await _settle();
    m.repo.school('A', _b('A', 4, _crimson));
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, _indigo);
  });

  test(
    'refresh applies a server read even if the live listener is silent',
    () async {
      final m = _make();
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, isNot(_indigo));
      m.repo.fetched = _b('A', 3, _indigo);
      await m.c.read(tenantThemeProvider.notifier).refresh();
      expect(m.c.read(tenantThemeProvider).colors, _indigo);
      // An older server read never replaces a newer applied theme.
      m.repo.fetched = _b('A', 2, _crimson);
      await m.c.read(tenantThemeProvider.notifier).refresh();
      expect(m.c.read(tenantThemeProvider).colors, _indigo);
    },
  );

  test('a missing document never clobbers an applied theme', () async {
    final m = _make();
    await _settle();
    m.repo.school('A', _b('A', 1, _indigo));
    await _settle();
    m.repo.school('A', null);
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, _indigo);
  });

  test("a branding document for another school is never applied", () async {
    final m = _make();
    await _settle();
    // The repository maps by expected id; a doc naming another school arrives as null.
    m.repo.school(
      'A',
      TenantBranding.fromMap(
        _b('B', 3, _crimson).toMap(),
        expectedSchoolId: 'A',
      ),
    );
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, BrandColors.emerald);
  });

  test('reset returns to the platform default and propagates', () async {
    final m = _make();
    await _settle();
    m.repo.school('A', _b('A', 1, _indigo));
    await _settle();
    m.repo.school('A', _b('A', 2, null));
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, BrandColors.emerald);
    expect(m.c.read(tenantThemeProvider).version, 2);
  });

  test(
    'the platform default applies to a school with no theme of its own',
    () async {
      final m = _make();
      await _settle();
      m.repo.platform.add(
        const PlatformBranding(version: 1, defaultPreset: 'plum'),
      );
      await _settle();
      expect(
        m.c.read(tenantThemeProvider).colors,
        BrandPresets.builtIn[4].colors,
      );
      // ...and does not override a school that has its own.
      m.repo.school('A', _b('A', 1, _indigo));
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, _indigo);
    },
  );

  test('an unreadable stored set never makes the app unreadable', () async {
    final m = _make();
    await _settle();
    m.repo.school(
      'A',
      _b('A', 1, _indigo.with_(BrandToken.text, const Color(0xFFDDDDDD))),
    );
    await _settle();
    final t = m.c.read(tenantThemeProvider);
    expect(t.colors.isReadable, isTrue);
    expect(t.colors.primary, _indigo.primary);
  });

  test(
    'the last valid theme is cached and painted at the next start, offline',
    () async {
      final first = _make();
      await _settle();
      first.repo.school('A', _b('A', 3, _indigo));
      await _settle();
      expect(first.cache.schoolsData['A'], isNotNull);

      // New launch: no network events at all, only the cache.
      final second = _make();
      second.cache.schoolsData.addAll(first.cache.schoolsData);
      // The cache is read asynchronously after build; give it a moment.
      second.c.invalidate(tenantThemeProvider);
      second.c.listen(tenantThemeProvider, (_, _) {});
      await _settle();
      await _settle();
      expect(second.c.read(tenantThemeProvider).colors, _indigo);
    },
  );

  test("another school's cache is never used", () async {
    final m = _make(session: (signedIn: true, schoolId: 'B'));
    m.cache.schoolsData['A'] = _b('A', 9, _indigo).toMap();
    m.c.invalidate(tenantThemeProvider);
    m.c.listen(tenantThemeProvider, (_, _) {});
    await _settle();
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, BrandColors.emerald);
  });

  test('a cached document that names another school is rejected', () async {
    final m = _make();
    m.cache.schoolsData['A'] = _b('B', 9, _crimson).toMap(); // tampered
    m.c.invalidate(tenantThemeProvider);
    m.c.listen(tenantThemeProvider, (_, _) {});
    await _settle();
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, BrandColors.emerald);
  });

  test('a network error keeps whatever is showing', () async {
    final m = _make();
    await _settle();
    m.repo.school('A', _b('A', 1, _indigo));
    await _settle();
    m.repo.schools['A']!.addError(StateError('offline'));
    await _settle();
    expect(m.c.read(tenantThemeProvider).colors, _indigo);
  });

  test(
    'switching accounts: School A\'s theme is gone before School B\'s arrives',
    () async {
      final m = _make();
      await _settle();
      m.repo.school('A', _b('A', 1, _indigo));
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, _indigo);

      // Between accounts: nobody's tenant is applied.
      m.c.read(_sessionProvider.notifier).set((
        signedIn: false,
        schoolId: null,
      ));
      await _settle();
      expect(m.c.read(tenantThemeProvider), ResolvedTheme.platformDefault);

      m.c.read(_sessionProvider.notifier).set((signedIn: true, schoolId: 'B'));
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, BrandColors.emerald);
      m.repo.school('B', _b('B', 1, _crimson));
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, _crimson);
      // A late event for school A must not leak into B.
      m.repo.school('A', _b('A', 7, _indigo));
      await _settle();
      expect(m.c.read(tenantThemeProvider).colors, _crimson);
    },
  );

  test('two schools are independent', () async {
    final a = _make(session: (signedIn: true, schoolId: 'A'));
    final b = _make(session: (signedIn: true, schoolId: 'B'));
    await _settle();
    a.repo.school('A', _b('A', 1, _indigo));
    b.repo.school('B', _b('B', 1, _crimson));
    await _settle();
    expect(a.c.read(tenantThemeProvider).colors, _indigo);
    expect(b.c.read(tenantThemeProvider).colors, _crimson);
  });
}
