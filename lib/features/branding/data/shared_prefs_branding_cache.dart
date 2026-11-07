import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/branding_repository.dart';

/// [BrandingCache] on `shared_preferences`. Reads and writes never throw: a
/// broken store just means "no cache".
class SharedPrefsBrandingCache implements BrandingCache {
  static const _platformKey = 'branding.platform.v1';
  static String _schoolKey(String id) => 'branding.school.v1.$id';

  Future<Map<String, dynamic>?> _read(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, dynamic> data) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode(data),
      );
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>?> readSchool(String schoolId) =>
      _read(_schoolKey(schoolId));

  @override
  Future<void> writeSchool(String schoolId, Map<String, dynamic> data) =>
      _write(_schoolKey(schoolId), data);

  @override
  Future<Map<String, dynamic>?> readPlatform() => _read(_platformKey);

  @override
  Future<void> writePlatform(Map<String, dynamic> data) =>
      _write(_platformKey, data);
}
