import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/password_reset.dart';

/// In-memory [LoginAccessRepository]. Records writes; can be told to refuse.
class FakeLoginAccessRepository implements LoginAccessRepository {
  LoginAccess access;
  SchoolAuthSettings settings;
  Object? setError;
  Object? settingsError;
  final List<({bool enabled, List<LoginMethod> methods, bool revokeSessions})>
  writes = [];
  final List<SchoolAuthSettings> settingsWrites = [];

  FakeLoginAccessRepository({
    required this.access,
    this.settings = const SchoolAuthSettings(
      emailPassword: true,
      google: true,
      phoneOtp: false,
      phoneOtpConfigured: false,
    ),
  });

  @override
  Future<LoginAccess> getAccess({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
  }) async => access;

  @override
  Future<LoginAccessResult> setAccess({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
    required bool enabled,
    required List<LoginMethod> methods,
    bool revokeSessions = false,
  }) async {
    if (setError != null) throw setError!;
    writes.add((
      enabled: enabled,
      methods: methods,
      revokeSessions: revokeSessions,
    ));
    access = LoginAccess(
      id: access.id,
      kind: access.kind,
      name: access.name,
      userType: access.userType,
      registeredEmail: access.registeredEmail,
      registeredPhone: access.registeredPhone,
      schoolMethods: access.schoolMethods,
      hasAccount: true,
      enabled: enabled,
      methods: methods,
      effective: enabled ? methods : const [],
      activation: access.activation,
      emailVerified: access.emailVerified,
      phoneVerified: access.phoneVerified,
      lastLogin: access.lastLogin,
      legacy: false,
      manageable: access.manageable,
    );
    return LoginAccessResult(
      created: false,
      enabled: enabled,
      methods: methods,
      revoked: revokeSessions || !enabled,
    );
  }

  final List<PasswordSetup> resets = [];
  Object? resetError;

  @override
  Future<String?> resetPassword({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required String id,
    required PasswordSetup passwordSetup,
  }) async {
    if (resetError != null) throw resetError!;
    resets.add(passwordSetup);
    return passwordSetup.option == PasswordSetupOption.randomTemp
        ? 'Temp1234Pass'
        : null;
  }

  final List<({List<String> ids, PasswordSetup setup})> bulkResets = [];

  /// Ids the fake reports as having no login.
  Set<String> noLoginIds = {};

  @override
  Future<List<PasswordResetResult>> resetPasswords({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    required PasswordSetup passwordSetup,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (resetError != null) throw resetError!;
    bulkResets.add((ids: ids, setup: passwordSetup));
    onProgress?.call(ids.length, ids.length);
    return [
      for (final id in ids)
        PasswordResetResult(
          id: id,
          name: 'Person $id',
          outcome: noLoginIds.contains(id)
              ? PasswordResetOutcome.noAccount
              : PasswordResetOutcome.reset,
          tempPassword:
              !noLoginIds.contains(id) &&
                  passwordSetup.option == PasswordSetupOption.randomTemp
              ? 'Temp-$id-Pass1'
              : null,
        ),
    ];
  }

  AccessDiagnosis diagnosis = const AccessDiagnosis(healthy: true, checks: []);

  @override
  Future<AccessDiagnosis> diagnose({
    required String schoolId,
    required String branchId,
    required String uid,
  }) async => diagnosis;

  int teacherAccessRefreshes = 0;

  @override
  Future<({int teachers, int written})> refreshTeacherAccess({
    required String schoolId,
    required String branchId,
  }) async {
    teacherAccessRefreshes++;
    return (teachers: 3, written: 2);
  }

  final List<({String branchId, String uid, UserRole? role})>
  branchAccessCalls = [];
  Object? branchAccessError;

  @override
  Future<Map<String, UserRole>> setBranchAccess({
    required String schoolId,
    required String branchId,
    required String uid,
    required UserRole? role,
  }) async {
    if (branchAccessError != null) throw branchAccessError!;
    branchAccessCalls.add((branchId: branchId, uid: uid, role: role));
    return {if (role != null) branchId: role};
  }

  @override
  Future<SchoolAuthSettings> getSchoolSettings(String schoolId) async =>
      settings;

  @override
  Future<int> updateSchoolSettings(
    String schoolId,
    SchoolAuthSettings next,
  ) async {
    if (settingsError != null) throw settingsError!;
    settingsWrites.add(next);
    settings = next;
    return 3;
  }
}
