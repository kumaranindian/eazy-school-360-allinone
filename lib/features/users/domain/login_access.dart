import '../../authentication/domain/login_method.dart';
import 'login_provisioning.dart';

enum LoginActivation {
  noAccount('NO_ACCOUNT', 'No login yet'),
  pendingActivation('PENDING_ACTIVATION', 'Not activated yet'),
  active('ACTIVE', 'Activated');

  final String wireValue;
  final String label;
  const LoginActivation(this.wireValue, this.label);

  static LoginActivation fromWire(String? v) => values.firstWhere(
    (a) => a.wireValue == v,
    orElse: () => LoginActivation.noAccount,
  );
}

/// One staff or parent record's login access, as reported by the server.
class LoginAccess {
  final String id;

  /// The Firebase Auth uid of the linked login, or null when none exists.
  final String? uid;
  final LoginKind kind;
  final String name;

  /// PARENT, TEACHER or STAFF.
  final String userType;
  final String? registeredEmail;
  final String? registeredPhone;
  final List<LoginMethod> schoolMethods;
  final bool hasAccount;
  final bool enabled;
  final List<LoginMethod> methods;
  final List<LoginMethod> effective;
  final LoginActivation activation;
  final bool emailVerified;
  final bool phoneVerified;
  final DateTime? lastLogin;

  /// True for accounts that predate login-access management (no explicit
  /// grant yet; they keep working as before).
  final bool legacy;

  /// False when the current admin may not change this account (their own
  /// account, or an administrator).
  final bool manageable;

  const LoginAccess({
    required this.id,
    this.uid,
    required this.kind,
    required this.name,
    required this.userType,
    required this.registeredEmail,
    required this.registeredPhone,
    required this.schoolMethods,
    required this.hasAccount,
    required this.enabled,
    required this.methods,
    required this.effective,
    required this.activation,
    required this.emailVerified,
    required this.phoneVerified,
    required this.lastLogin,
    required this.legacy,
    required this.manageable,
  });

  factory LoginAccess.fromMap(Map<dynamic, dynamic> m, LoginKind kind) =>
      LoginAccess(
        id: m['id'] as String? ?? '',
        uid: m['uid'] as String?,
        kind: kind,
        name: m['name'] as String? ?? '',
        userType: m['userType'] as String? ?? 'STAFF',
        registeredEmail: m['registeredEmail'] as String?,
        registeredPhone: m['registeredPhone'] as String?,
        schoolMethods: LoginMethod.listFromWire(m['schoolMethods']),
        hasAccount: m['hasAccount'] == true,
        enabled: m['enabled'] == true,
        methods: LoginMethod.listFromWire(m['methods']),
        effective: LoginMethod.listFromWire(m['effective']),
        activation: LoginActivation.fromWire(m['activation'] as String?),
        emailVerified: m['emailVerified'] == true,
        phoneVerified: m['phoneVerified'] == true,
        lastLogin: DateTime.tryParse(
          m['lastLogin'] as String? ?? '',
        )?.toLocal(),
        legacy: m['legacy'] == true,
        manageable: m['manageable'] != false,
      );

  String get userTypeLabel => switch (userType) {
    'PARENT' => 'Parent',
    'TEACHER' => 'Teacher',
    _ => 'Staff',
  };
}

/// One prerequisite the Firestore rules / app rely on for this person, as
/// checked by the `diagnoseAccess` function.
class AccessCheck {
  final String id;
  final bool ok;
  final String severity;
  final String message;
  final String? fix;
  const AccessCheck({
    required this.id,
    required this.ok,
    required this.severity,
    required this.message,
    this.fix,
  });

  factory AccessCheck.fromMap(Map<dynamic, dynamic> m) => AccessCheck(
    id: m['id'] as String? ?? '',
    ok: m['ok'] == true,
    severity: m['severity'] as String? ?? 'OK',
    message: m['message'] as String? ?? '',
    fix: m['fix'] as String?,
  );
}

class AccessDiagnosis {
  final bool healthy;
  final List<AccessCheck> checks;
  const AccessDiagnosis({required this.healthy, required this.checks});

  List<AccessCheck> get problems => [
    for (final c in checks)
      if (!c.ok) c,
  ];
}

class LoginAccessResult {
  final bool created;
  final bool enabled;
  final List<LoginMethod> methods;
  final bool revoked;
  const LoginAccessResult({
    required this.created,
    required this.enabled,
    required this.methods,
    required this.revoked,
  });
}

/// The school's own switches, plus whether the server can honour them.
class SchoolAuthSettings {
  final bool emailPassword;
  final bool google;
  final bool phoneOtp;

  /// Whether the Meta WhatsApp credentials are set up on the server.
  final bool phoneOtpConfigured;

  const SchoolAuthSettings({
    required this.emailPassword,
    required this.google,
    required this.phoneOtp,
    required this.phoneOtpConfigured,
  });

  bool isEnabled(LoginMethod m) => switch (m) {
    LoginMethod.password => emailPassword,
    LoginMethod.google => google,
    LoginMethod.phoneOtp => phoneOtp,
  };

  SchoolAuthSettings copyWith({
    bool? emailPassword,
    bool? google,
    bool? phoneOtp,
  }) => SchoolAuthSettings(
    emailPassword: emailPassword ?? this.emailPassword,
    google: google ?? this.google,
    phoneOtp: phoneOtp ?? this.phoneOtp,
    phoneOtpConfigured: phoneOtpConfigured,
  );

  SchoolAuthSettings withMethod(LoginMethod m, bool on) => switch (m) {
    LoginMethod.password => copyWith(emailPassword: on),
    LoginMethod.google => copyWith(google: on),
    LoginMethod.phoneOtp => copyWith(phoneOtp: on),
  };

  List<LoginMethod> get enabledMethods => [
    for (final m in LoginMethod.values)
      if (isEnabled(m)) m,
  ];

  @override
  bool operator ==(Object other) =>
      other is SchoolAuthSettings &&
      other.emailPassword == emailPassword &&
      other.google == google &&
      other.phoneOtp == phoneOtp &&
      other.phoneOtpConfigured == phoneOtpConfigured;

  @override
  int get hashCode =>
      Object.hash(emailPassword, google, phoneOtp, phoneOtpConfigured);
}

abstract class LoginAccessRepository {
  Future<LoginAccess> getAccess({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
  });

  /// Throws an AccessPolicyFailure when the server refuses.
  Future<LoginAccessResult> setAccess({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
    required bool enabled,
    required List<LoginMethod> methods,
    bool revokeSessions = false,
  });

  /// Read-only: names the missing prerequisite behind a permission error.
  Future<AccessDiagnosis> diagnose({
    required String schoolId,
    required String branchId,
    required String uid,
  });

  /// Rebuilds every teacher's `teacherAccess` index in the branch (what the
  /// rules use to decide which students a teacher may read). Returns
  /// (teachers found, indexes written).
  Future<({int teachers, int written})> refreshTeacherAccess({
    required String schoolId,
    required String branchId,
  });

  Future<SchoolAuthSettings> getSchoolSettings(String schoolId);

  /// Returns the number of users whose effective methods changed.
  Future<int> updateSchoolSettings(String schoolId, SchoolAuthSettings next);
}

/// Pure rules for the Login Access dialog — the server re-validates all of
/// them; these only give immediate feedback.
class LoginAccessRules {
  const LoginAccessRules._();

  /// Why [method] cannot be granted to this person right now, or null.
  static String? blocker(LoginMethod method, LoginAccess a) {
    if (!a.schoolMethods.contains(method)) {
      return 'Turned off for this school (Settings → Authentication).';
    }
    switch (method) {
      case LoginMethod.password:
      case LoginMethod.google:
        if (a.registeredEmail == null) {
          return 'Add a valid email to the record first.';
        }
      case LoginMethod.phoneOtp:
        if (a.registeredPhone == null) {
          return 'Add a valid mobile number to the record first.';
        }
    }
    return null;
  }

  static String? validate(
    LoginAccess a, {
    required bool enabled,
    required Set<LoginMethod> selected,
  }) {
    if (!enabled) return null;
    if (selected.isEmpty) return 'Choose at least one sign-in method.';
    for (final m in selected) {
      final b = blocker(m, a);
      if (b != null) return '${m.label}: $b';
    }
    return null;
  }

  /// Security-sensitive: switching access off, or taking a method away,
  /// signs the person out and needs an explicit confirmation.
  static bool narrows(
    LoginAccess a, {
    required bool enabled,
    required Set<LoginMethod> selected,
  }) {
    if (!a.hasAccount) return false;
    if (!enabled) return a.enabled;
    return a.enabled && a.effective.any((m) => !selected.contains(m));
  }

  static bool changed(
    LoginAccess a, {
    required bool enabled,
    required Set<LoginMethod> selected,
  }) =>
      enabled != a.enabled ||
      (enabled && !_sameSet(selected, a.methods.toSet()));

  static bool _sameSet(Set<LoginMethod> x, Set<LoginMethod> y) =>
      x.length == y.length && x.containsAll(y);
}
