/// User-facing text for the stable `reason` codes returned by the login
/// access / phone-OTP Cloud Functions.
String accessMessageFor(String reason, {String? cause, int? retryAfterSec}) {
  final wait = retryAfterSec == null
      ? ''
      : ' Try again in ${_wait(retryAfterSec)}.';
  switch (reason) {
    case 'PERMISSION_DENIED':
      return "You don't have permission to do that.";
    case 'NOT_FOUND':
      return 'That record could not be found.';
    case 'INVALID_ARGUMENT':
      return 'That request was not valid. Please check it and try again.';
    case 'NO_METHOD':
      return 'Choose at least one sign-in method.';
    case 'METHOD_NOT_ENABLED':
      return 'One of the chosen methods is switched off for this school. '
          'Enable it in Settings → Authentication first.';
    case 'EMAIL_REQUIRED':
      return 'A valid email is needed on the record for email or Google sign-in.';
    case 'PHONE_REQUIRED':
      return 'A valid mobile number is needed on the record for phone sign-in.';
    case 'INVALID_PHONE':
      return 'That mobile number is not valid.';
    case 'PHONE_IN_USE':
      return 'This mobile number is already used for phone sign-in by another account.';
    case 'NO_ACCOUNT':
      return 'This person has no login yet. Enable access to create one.';
    case 'ALREADY_LINKED':
      return 'This record already has a login.';
    case 'EMAIL_IN_USE':
      return 'That email already belongs to another account.';
    case 'RECORD_INACTIVE':
      return 'The record is inactive. Reactivate it before enabling login.';
    case 'CALLER_LOCKOUT':
      return 'That change would stop you from signing in yourself. Keep at '
          'least one method you can use.';
    case 'ADMIN_LOCKOUT':
      return 'That change would leave no administrator able to sign in.';
    case 'PHONE_OTP_NOT_CONFIGURED':
      return 'Phone sign-in is not set up on the server yet '
          '(WhatsApp credentials are missing). See the setup guide.';
    case 'RATE_LIMITED':
      return 'Too many attempts.$wait';
    case 'RESEND_COOLDOWN':
      return 'Please wait before requesting another code.$wait';
    case 'DELIVERY_FAILED':
      return switch (cause) {
        'INVALID_RECIPIENT' =>
          'The code could not be delivered to that number on WhatsApp.',
        'PROVIDER_RATE_LIMIT' =>
          'WhatsApp is busy right now. Please try again shortly.',
        _ =>
          "We couldn't send the code right now. Try again, or use another sign-in method.",
      };
    case 'OTP_UNAVAILABLE':
      return 'Phone sign-in is not available right now. Use another sign-in method.';
    case 'OTP_EXPIRED':
      return 'That code has expired. Request a new one.';
    case 'OTP_LOCKED':
      return 'Too many wrong codes. Request a new code.';
    case 'OTP_INVALID':
      return 'That code is not correct.';
    case 'ACCESS_DISABLED':
      return 'Login access is not enabled for this account.';
    default:
      return 'Something went wrong. Please try again.';
  }
}

String _wait(int sec) =>
    sec >= 120 ? '${(sec / 60).ceil()} minutes' : '$sec seconds';
