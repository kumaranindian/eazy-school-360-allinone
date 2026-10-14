import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tenant/tenant_context_provider.dart';

/// The signed-in user's school identity, as the shared UI needs it: who the
/// tenant is and which logo (if any) represents it.
@immutable
class SchoolBranding {
  final String schoolId;
  final String name;

  /// A usable http(s) logo URL, or null when the school has none (or the
  /// stored value is not a loadable URL).
  final String? logoUrl;

  const SchoolBranding({
    required this.schoolId,
    required this.name,
    this.logoUrl,
  });

  bool get hasLogo => logoUrl != null;

  @override
  bool operator ==(Object other) =>
      other is SchoolBranding &&
      other.schoolId == schoolId &&
      other.name == name &&
      other.logoUrl == logoUrl;

  @override
  int get hashCode => Object.hash(schoolId, name, logoUrl);
}

/// Only an absolute http(s) URL can be loaded as an image; anything else
/// (empty string, a bare storage path, junk) is treated as "no logo" so the
/// UI falls back to the product mark instead of throwing in the image layer.
String? usableLogoUrl(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return value;
}

/// The current tenant's branding, derived from [tenantContextProvider].
///
/// There is deliberately no second Firestore read or listener: the school
/// document is already resolved once per sign-in as part of the tenant
/// context, and every logo/profile write invalidates that provider, so a new
/// logo reaches every shared widget without a reload. The tenant context is
/// built from the signed-in user's own profile, so the school can never be
/// chosen by a client-side value, and signing out (or in as someone else)
/// replaces it, so one school's logo cannot linger for another.
///
/// Null while signed out, while a tenant is still loading for the first time,
/// or for an account with no school.
final schoolBrandingProvider = Provider<SchoolBranding?>((ref) {
  final school = ref.watch(
    tenantContextProvider.select((tenant) => tenant.value?.school),
  );
  if (school == null) return null;
  return SchoolBranding(
    schoolId: school.schoolId,
    name: school.name,
    logoUrl: usableLogoUrl(school.logoUrl),
  );
});
