import '../../../core/permissions/user_role.dart';

enum LoginKind {
  staff('STAFF'),
  parent('PARENT');

  final String wireValue;
  const LoginKind(this.wireValue);
}

/// How the first password is set when logins are created. The two link
/// options set no password anyone knows; the other three set one on the
/// server (never stored, never logged) and ask the person to change it at
/// first sign-in.
enum PasswordSetupOption {
  nameMobile(
    'NAME_MOBILE',
    'Name + mobile number',
    'First 4 letters of the name (capitals) + last 5 digits of the mobile, '
        'e.g. KART43210. Easy to guess — less secure.',
  ),
  randomTemp(
    'RANDOM_TEMP',
    'Random temporary password',
    'A secure random password per person, shown to you once to download. '
        'They must change it at first sign-in.',
  ),
  activationEmail(
    'ACTIVATION_EMAIL',
    'Activation email',
    'Each person gets an email with a secure link to set their own password.',
  ),
  resetLink(
    'RESET_LINK',
    'Password set/reset link',
    'Same secure link, sent to existing logins too (e.g. when an email changes).',
  ),
  adminDefined(
    'ADMIN_DEFINED',
    'One password set by you',
    'A single temporary password for everyone in this batch — less secure. '
        'They must change it at first sign-in.',
  );

  final String wireValue;
  final String label;
  final String description;
  const PasswordSetupOption(this.wireValue, this.label, this.description);

  /// Whether people are sent a set-password link.
  bool get sendsEmail => this == activationEmail || this == resetLink;
}

/// The chosen option plus, for [PasswordSetupOption.adminDefined] only, the
/// password. Lives in memory for one call; never persisted.
class PasswordSetup {
  final PasswordSetupOption option;
  final String? password;
  const PasswordSetup(this.option, {this.password});
}

/// What happened to one record. Everything except [created] means nothing
/// was changed for that person.
enum ProvisionOutcome {
  created('CREATED', 'Login created'),
  emailUpdated('EMAIL_UPDATED', 'Email changed — the new email is active'),
  passwordInputMissing(
    'PASSWORD_INPUT_MISSING',
    'Needs a name of 4+ letters and a mobile of 5+ digits for this option',
  ),
  alreadyLinked('ALREADY_LINKED', 'Already has a login'),
  noEmail('NO_EMAIL', 'No email on the record'),
  invalidEmail('INVALID_EMAIL', 'Email is not valid'),
  emailInUse(
    'EMAIL_IN_USE',
    'Email already belongs to another login (use a different email)',
  ),
  inactive('INACTIVE', 'Record is inactive'),
  notFound('NOT_FOUND', 'Record not found'),
  retryLater(
    'RETRY_LATER',
    'Not completed (network or server busy) — nothing was changed, try again',
  ),
  failed('FAILED', 'Could not be created');

  final String wireValue;
  final String label;
  const ProvisionOutcome(this.wireValue, this.label);

  static ProvisionOutcome fromWire(String? v) => values.firstWhere(
    (o) => o.wireValue == v,
    orElse: () => ProvisionOutcome.failed,
  );
}

class ProvisionResult {
  final String id;
  final String? name;
  final String? email;
  final ProvisionOutcome outcome;

  /// True when a brand-new sign-in account was made (and so needs a
  /// set-password email).
  final bool newAccount;

  /// True when a password was set on the server for this account.
  final bool passwordSet;

  /// Only for [PasswordSetupOption.randomTemp]: shown to the admin once.
  final String? tempPassword;

  final String? previousEmail;

  const ProvisionResult({
    required this.id,
    required this.outcome,
    this.name,
    this.email,
    this.newAccount = false,
    this.passwordSet = false,
    this.tempPassword,
    this.previousEmail,
  });

  factory ProvisionResult.fromMap(Map<dynamic, dynamic> m) => ProvisionResult(
    id: m['id'] as String? ?? '',
    name: m['name'] as String?,
    email: m['email'] as String?,
    outcome: ProvisionOutcome.fromWire(m['outcome'] as String?),
    newAccount: m['newAccount'] == true,
    passwordSet: m['passwordSet'] == true,
    tempPassword: m['tempPassword'] as String?,
    previousEmail: m['previousEmail'] as String?,
  );
}

abstract class LoginProvisioner {
  /// Works through the ids in small batches with retries; [onProgress] counts
  /// people handled so far. A batch that cannot be completed comes back as
  /// [ProvisionOutcome.retryLater] for its people (nothing changed — safe to
  /// send again); [isCancelled] stops before the next batch.
  ///
  /// Creates sign-in accounts for the given staff/parent record ids and links
  /// them. [staffRole] applies to non-teaching staff; [enablePortal] to
  /// parents (turns on portal access for their linked children). [emails]
  /// maps record id → email to use: for records with none it is saved on the
  /// record; for someone who already has a login it MOVES the login to the new
  /// email (new one active, old one stopped).
  Future<List<ProvisionResult>> provision({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    UserRole? staffRole,
    bool enablePortal = false,
    Map<String, String> emails = const {},
    PasswordSetup? passwordSetup,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  });
}
