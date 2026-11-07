import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/branding/tenant_branding.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../data/firebase_branding_repository.dart';
import '../../data/shared_prefs_branding_cache.dart';
import '../../domain/branding_repository.dart';

final brandingRepositoryProvider = Provider<BrandingRepository>(
  (ref) => FirebaseBrandingRepository(),
  retry: (retryCount, error) => null,
);

final brandingCacheProvider = Provider<BrandingCache>(
  (ref) => SharedPrefsBrandingCache(),
  retry: (retryCount, error) => null,
);

/// Whether a user is signed in AND their tenant is the one loaded for them.
/// Between two accounts the loaded tenant still belongs to the previous user,
/// so nothing is applied until it matches: one school's colours can never
/// show for another school's user while accounts switch.
final themeSessionProvider = Provider<({bool signedIn, String? schoolId})>((
  ref,
) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  final tenant = ref.watch(tenantContextProvider).value;
  if (uid == null || tenant == null || tenant.user.userId != uid) {
    return (signedIn: false, schoolId: null);
  }
  return (signedIn: true, schoolId: tenant.school?.schoolId);
});

/// The one source of the app's colours: the signed-in school's branding (every
/// role and branch of the school gets the same), over the platform default.
///
/// * Live: a Firestore listener on the school's `branding/config` and on
///   `platformBranding/default`, so an admin's save reaches every open session.
/// * Safe: a snapshot older than the one applied is ignored (the `version`
///   only grows), a branding document that names another school is rejected,
///   and an unreadable colour set falls back (see [BrandingResolver]).
/// * Offline: the last valid configuration is cached per school and applied at
///   start-up; a listener error keeps whatever is showing.
/// * No tenant (signed out / between accounts): the platform default.
class TenantThemeNotifier extends Notifier<ResolvedTheme> {
  String? _schoolId;
  TenantBranding? _school;
  PlatformBranding _platform = PlatformBranding.builtIn;
  BrandingCache? _cache;

  @override
  ResolvedTheme build() {
    final session = ref.watch(themeSessionProvider);
    _schoolId = session.schoolId;
    _school = null;
    _platform = PlatformBranding.builtIn;
    _cache = null;
    if (!session.signedIn) return ResolvedTheme.platformDefault;

    final BrandingRepository repo;
    try {
      repo = ref.read(brandingRepositoryProvider);
      _cache = ref.read(brandingCacheProvider);
    } catch (_) {
      return ResolvedTheme.platformDefault;
    }
    final subs = <StreamSubscription<Object?>>[];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    try {
      subs.add(repo.watchPlatform().listen(_onPlatform, onError: _ignore));
      final id = _schoolId;
      if (id != null) {
        subs.add(repo.watchSchool(id).listen(_onSchool, onError: _ignore));
      }
    } catch (_) {
      // Keep the default; the cache below may still help.
    }
    unawaited(_loadCache());
    return _resolve();
  }

  void _ignore(Object _, [StackTrace? _]) {}

  ResolvedTheme _resolve() => BrandingResolver.resolve(
    schoolId: _schoolId,
    school: _school,
    platform: _platform,
  );

  void _publish() {
    if (!ref.mounted) return;
    final next = _resolve();
    if (next != state) state = next;
  }

  void _onSchool(TenantBranding? b) {
    if (!ref.mounted || b == null) return; // a missing doc never clobbers
    final cur = _school;
    if (cur != null && b.version < cur.version) return; // stale
    _school = b;
    final id = _schoolId;
    if (id != null && b.version > 0) {
      unawaited(_cache?.writeSchool(id, b.toMap()));
    }
    _publish();
  }

  void _onPlatform(PlatformBranding p) {
    if (!ref.mounted) return;
    if (p.version < _platform.version) return; // stale
    _platform = p;
    if (p.version > 0) unawaited(_cache?.writePlatform(p.toMap()));
    _publish();
  }

  Future<void> _loadCache() async {
    final cache = _cache;
    if (cache == null) return;
    final id = _schoolId;
    final platform = await cache.readPlatform();
    if (ref.mounted && platform != null) {
      final p = PlatformBranding.fromMap(platform);
      if (p.version > _platform.version) {
        _platform = p;
        _publish();
      }
    }
    if (id == null) return;
    final school = await cache.readSchool(id);
    if (!ref.mounted || school == null || id != _schoolId) return;
    final b = TenantBranding.fromMap(school, expectedSchoolId: id);
    if (b != null && b.version > (_school?.version ?? 0)) {
      _school = b;
      _publish();
    }
  }
}

final tenantThemeProvider =
    NotifierProvider<TenantThemeNotifier, ResolvedTheme>(
      TenantThemeNotifier.new,
      retry: (retryCount, error) => null,
    );

extension BrandingAppearanceMode on BrandingAppearance {
  ThemeMode get themeMode => switch (this) {
    BrandingAppearance.system => ThemeMode.system,
    BrandingAppearance.light => ThemeMode.light,
    BrandingAppearance.dark => ThemeMode.dark,
  };
}

/// The school's saved branding (for the editor): live, null while none.
final schoolBrandingConfigProvider = StreamProvider.autoDispose
    .family<TenantBranding?, String>(
      (ref, schoolId) =>
          ref.watch(brandingRepositoryProvider).watchSchool(schoolId),
      retry: (retryCount, error) => null,
    );

/// Presets (built-in plus the platform's custom ones) and the platform
/// default, live.
final platformBrandingProvider = StreamProvider.autoDispose<PlatformBranding>(
  (ref) => ref.watch(brandingRepositoryProvider).watchPlatform(),
  retry: (retryCount, error) => null,
);
