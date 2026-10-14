/// The ways a person can sign in. A school enables a subset; an administrator
/// permits a subset per user; the effective methods are the intersection
/// (computed and enforced on the server — see functions/access.js).
enum LoginMethod {
  password(
    'PASSWORD',
    'Email & password',
    'Sign in with the registered email and a password.',
  ),
  google(
    'GOOGLE',
    'Google',
    'Sign in with the Google account that uses the registered email.',
  ),
  phoneOtp(
    'PHONE_OTP',
    'Phone (WhatsApp code)',
    'Sign in with a one-time code sent by WhatsApp to the registered mobile.',
  );

  final String wireValue;
  final String label;
  final String description;
  const LoginMethod(this.wireValue, this.label, this.description);

  static LoginMethod? tryFromWire(String? v) {
    for (final m in values) {
      if (m.wireValue == v) return m;
    }
    return null;
  }

  /// Parses a list from Firestore/callable data, dropping unknown values.
  static List<LoginMethod> listFromWire(Object? raw) => [
    if (raw is List)
      for (final v in raw)
        if (tryFromWire(v as String?) case final m?) m,
  ];
}
