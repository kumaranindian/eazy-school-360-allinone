import 'dart:async';

import 'package:eazy_school_360/core/branding/tenant_branding.dart';
import 'package:eazy_school_360/features/branding/domain/branding_repository.dart';

/// A live branding store: one document per school plus the platform default.
/// `set` pushes to every open listener, like Firestore does.
class FakeBrandingRepository implements BrandingRepository {
  final _schools = <String, TenantBranding>{};
  final _controllers = <String, StreamController<TenantBranding?>>{};
  final _platform = StreamController<PlatformBranding>.broadcast();
  PlatformBranding platformValue = PlatformBranding.builtIn;
  final saved = <Map<String, Object?>>[];

  FakeBrandingRepository([Map<String, TenantBranding> initial = const {}]) {
    _schools.addAll(initial);
  }

  StreamController<TenantBranding?> _c(String id) =>
      _controllers.putIfAbsent(id, () => StreamController.broadcast());

  void set(TenantBranding b) {
    _schools[b.schoolId] = b;
    _c(b.schoolId).add(b);
  }

  @override
  Stream<TenantBranding?> watchSchool(String schoolId) async* {
    yield _schools[schoolId];
    yield* _c(schoolId).stream;
  }

  @override
  Stream<PlatformBranding> watchPlatform() async* {
    yield platformValue;
    yield* _platform.stream;
  }

  @override
  Future<int> saveSchool({
    required String schoolId,
    required String presetId,
    required BrandColors colors,
    required BrandingAppearance appearance,
    int? baseVersion,
  }) async {
    final v = (_schools[schoolId]?.version ?? 0) + 1;
    saved.add({
      'schoolId': schoolId,
      'preset': presetId,
      'appearance': appearance,
      'baseVersion': baseVersion,
    });
    set(
      TenantBranding(
        schoolId: schoolId,
        version: v,
        presetId: presetId,
        colors: colors,
        appearance: appearance,
      ),
    );
    return v;
  }

  @override
  Future<int> resetSchool({required String schoolId, int? baseVersion}) async {
    final v = (_schools[schoolId]?.version ?? 0) + 1;
    saved.add({'schoolId': schoolId, 'reset': true});
    set(TenantBranding(schoolId: schoolId, version: v));
    return v;
  }

  @override
  Future<int> savePlatform(PlatformBranding branding) async {
    platformValue = PlatformBranding(
      version: branding.version + 1,
      defaultPreset: branding.defaultPreset,
      customPresets: branding.customPresets,
    );
    _platform.add(platformValue);
    return platformValue.version;
  }
}

/// In-memory [BrandingCache].
class MemoryBrandingCache implements BrandingCache {
  final schools = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? platform;

  @override
  Future<Map<String, dynamic>?> readSchool(String id) async => schools[id];
  @override
  Future<void> writeSchool(String id, Map<String, dynamic> d) async =>
      schools[id] = d;
  @override
  Future<Map<String, dynamic>?> readPlatform() async => platform;
  @override
  Future<void> writePlatform(Map<String, dynamic> d) async => platform = d;
}
