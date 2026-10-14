/// A pending phone sign-in code. The code itself is never known to the app
/// until the user types what they received.
class OtpChallenge {
  final String challengeId;
  final Duration expiresIn;
  final Duration resendAfter;

  const OtpChallenge({
    required this.challengeId,
    required this.expiresIn,
    required this.resendAfter,
  });
}

/// Light client-side phone shape check (the server normalises and decides).
String? validatePhoneNumber(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your registered mobile number';
  final digits = v.replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^\+?[\d\s\-().]+$').hasMatch(v) ||
      digits.length < 8 ||
      digits.length > 15) {
    return 'Enter a valid mobile number';
  }
  return null;
}

String? validateOtpCode(String? value) {
  final v = (value ?? '').trim();
  if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Enter the 6-digit code';
  return null;
}
