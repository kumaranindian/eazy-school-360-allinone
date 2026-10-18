import 'app_routes.dart';

/// Remembering where the user was headed across the sign-in / loading
/// redirects (ROUTE-2): a refresh or a pasted deep link such as
/// `/students/abc` becomes `/login?from=%2Fstudents%2Fabc`, and the same page
/// is opened once the user is signed in and their school is resolved.
class ReturnTo {
  const ReturnTo._();

  static const String param = 'from';

  /// Pages that are part of signing in / onboarding; never a destination.
  static const Set<String> _notDestinations = {
    '/',
    AppRoutes.login,
    AppRoutes.register,
    AppRoutes.forgotPassword,
    AppRoutes.createSchool,
    AppRoutes.accountInactive,
  };

  /// [raw] if it is a safe in-app destination, else null. Only a path on this
  /// app is accepted: no scheme, no host, no protocol-relative `//`, no
  /// backslashes, nothing that is itself a sign-in page.
  static String? safe(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > 500) return null;
    if (!raw.startsWith('/') || raw.startsWith('//')) return null;
    if (raw.contains('\\') || raw.contains('://') || raw.contains('\n')) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    if (_notDestinations.contains(uri.path)) return null;
    return raw;
  }

  /// [base] carrying where the user was going: [current] itself, or the
  /// destination [current] already carries when it is one of the sign-in pages.
  static String redirect(String base, Uri current) {
    final target = _notDestinations.contains(current.path)
        ? safe(current.queryParameters[param])
        : safe(current.toString());
    if (target == null) return base;
    return '$base?$param=${Uri.encodeQueryComponent(target)}';
  }
}
