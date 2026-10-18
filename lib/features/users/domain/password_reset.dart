/// What happened to one person in a password reset. Everything except
/// [reset] means nothing was changed for that person.
enum PasswordResetOutcome {
  reset('RESET', 'Password reset'),
  noAccount('NO_ACCOUNT', 'Has no login yet'),
  notFound('NOT_FOUND', 'Record not found'),
  notAllowed('PERMISSION_DENIED', 'You cannot reset this account'),
  inputMissing(
    'PASSWORD_INPUT_MISSING',
    'Needs a name of 4+ letters and a mobile of 5+ digits for this option',
  ),
  noEmail('NO_EMAIL', 'No email on the record'),
  emailFailed('EMAIL_FAILED', 'The email could not be sent'),
  retryLater(
    'RETRY_LATER',
    'Not completed (network or server busy) — nothing was changed, try again',
  ),
  failed('FAILED', 'Could not be reset');

  final String wireValue;
  final String label;
  const PasswordResetOutcome(this.wireValue, this.label);

  static PasswordResetOutcome fromWire(String? v) => values.firstWhere(
    (o) => o.wireValue == v,
    orElse: () => PasswordResetOutcome.failed,
  );
}

class PasswordResetResult {
  final String id;
  final String? name;
  final PasswordResetOutcome outcome;

  /// Only for the random-password option: shown to the admin once.
  final String? tempPassword;

  const PasswordResetResult({
    required this.id,
    required this.outcome,
    this.name,
    this.tempPassword,
  });

  bool get isReset => outcome == PasswordResetOutcome.reset;

  factory PasswordResetResult.fromMap(Map<dynamic, dynamic> m) =>
      PasswordResetResult(
        id: m['id'] as String? ?? '',
        name: m['name'] as String?,
        outcome: PasswordResetOutcome.fromWire(m['outcome'] as String?),
        tempPassword: m['tempPassword'] as String?,
      );
}
