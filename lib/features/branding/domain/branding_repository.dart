import '../../../core/branding/tenant_branding.dart';

/// Reads and saves tenant branding. Reads are live (a school's colours reach
/// every signed-in user without a reload); writes go through callables that
/// validate readability and bump the version.
abstract class BrandingRepository {
  /// The school's `branding/config`, or null while it has none.
  Stream<TenantBranding?> watchSchool(String schoolId);

  /// The platform default and presets.
  Stream<PlatformBranding> watchPlatform();

  /// One read straight from the server (not the live listener, not the local
  /// cache); null when the school has none or the read fails.
  Future<TenantBranding?> fetchSchool(String schoolId);

  /// Saves the school's theme; returns the new version. [baseVersion] makes a
  /// concurrent edit fail instead of overwriting.
  Future<int> saveSchool({
    required String schoolId,
    required String presetId,
    required BrandColors colors,
    required BrandingAppearance appearance,
    int? baseVersion,
  });

  /// Back to the platform default.
  Future<int> resetSchool({required String schoolId, int? baseVersion});

  /// Platform admins only.
  Future<int> savePlatform(PlatformBranding branding);
}

/// The last valid configuration, kept on the device so a cold start or a
/// dropped connection still paints the right school's colours. Keyed by
/// school: one school's cache is never read for another.
abstract class BrandingCache {
  Future<Map<String, dynamic>?> readSchool(String schoolId);
  Future<void> writeSchool(String schoolId, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> readPlatform();
  Future<void> writePlatform(Map<String, dynamic> data);
}
