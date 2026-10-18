import '../../../core/permissions/user_role.dart';

enum LoginKind {
  staff('STAFF'),
  parent('PARENT');

  final String wireValue;
  const LoginKind(this.wireValue);
}

/// What happened to one record. Everything except [created] means nothing
/// was changed for that person.
enum ProvisionOutcome {
  created('CREATED', 'Login created'),
  alreadyLinked('ALREADY_LINKED', 'Already has a login'),
  noEmail('NO_EMAIL', 'No email on the record'),
  invalidEmail('INVALID_EMAIL', 'Email is not valid'),
  emailInUse(
    'EMAIL_IN_USE',
    'Email already belongs to another login (use a different email)',
  ),
  inactive('INACTIVE', 'Record is inactive'),
  notFound('NOT_FOUND', 'Record not found'),
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

  const ProvisionResult({
    required this.id,
    required this.outcome,
    this.name,
    this.email,
    this.newAccount = false,
  });

  factory ProvisionResult.fromMap(Map<dynamic, dynamic> m) => ProvisionResult(
    id: m['id'] as String? ?? '',
    name: m['name'] as String?,
    email: m['email'] as String?,
    outcome: ProvisionOutcome.fromWire(m['outcome'] as String?),
    newAccount: m['newAccount'] == true,
  );
}

abstract class LoginProvisioner {
  /// Creates sign-in accounts for the given staff/parent record ids and links
  /// them. [staffRole] applies to non-teaching staff; [enablePortal] to
  /// parents (turns on portal access for their linked children). [emails]
  /// maps record id → email for records that have none; it is saved on the
  /// record too.
  Future<List<ProvisionResult>> provision({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    UserRole? staffRole,
    bool enablePortal = false,
    Map<String, String> emails = const {},
  });
}
