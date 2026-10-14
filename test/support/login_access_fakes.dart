import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';

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
