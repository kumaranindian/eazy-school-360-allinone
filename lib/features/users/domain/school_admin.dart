import 'login_provisioning.dart';

/// A school administrator as listed on the People & access page.
class SchoolAdminSummary {
  final String uid;
  final String name;
  final String email;

  /// The wire status (`ACTIVE`, `DISABLED`, ...), shown as is.
  final String status;

  const SchoolAdminSummary({
    required this.uid,
    required this.name,
    required this.email,
    required this.status,
  });

  bool get isActive => status == 'ACTIVE';
}

/// What the server returns after creating a school admin.
class CreatedSchoolAdmin {
  final String uid;
  final String name;
  final String email;

  /// True when the server set a first password (the person must change it at
  /// first sign-in). False for the activation-email option.
  final bool passwordSet;

  /// Only for the random-temporary-password option, shown once.
  final String? tempPassword;

  const CreatedSchoolAdmin({
    required this.uid,
    required this.name,
    required this.email,
    required this.passwordSet,
    this.tempPassword,
  });
}

/// Lists and creates school admins. Creating one is a server-side action: the
/// Firestore rules forbid any client from granting `SCHOOL_ADMIN`, so the
/// `createSchoolAdmin` Cloud Function does it after checking that the caller
/// is a school admin of the same school.
abstract class SchoolAdminRepository {
  Future<List<SchoolAdminSummary>> list(String schoolId);

  Future<CreatedSchoolAdmin> create({
    required String schoolId,
    required String name,
    required String email,
    String? phone,
    required PasswordSetup passwordSetup,
  });
}
