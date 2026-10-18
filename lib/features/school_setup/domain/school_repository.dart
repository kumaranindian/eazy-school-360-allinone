import '../../../core/regional/regional_settings.dart';
import 'branch.dart';
import 'school.dart';

/// Boundary between the rest of the app and wherever school/branch data is
/// actually stored (Firestore + Storage today). Throws an `AppFailure`
/// (via error_mapper) on failure.
abstract class SchoolRepository {
  Future<School?> getSchool(String schoolId);

  /// Updates the editable profile fields of a school — see
  /// `School.toFirestoreProfileUpdate` for exactly which fields that is.
  Future<void> updateSchoolProfile(School school, {required String updatedBy});

  /// Saves the school's country, currency, time zone and date format. The
  /// rules refuse a currency change once the server has locked it.
  Future<void> updateSchoolRegional(School school, {required String updatedBy});

  /// Uploads [fileBytes] as the school's logo to Firebase Storage and
  /// updates `School.logoUrl` to point at it, replacing any existing logo.
  /// Returns the new logo URL. Validate file type/size before calling —
  /// see `Validators.imageFile`.
  Future<String> uploadSchoolLogo({
    required String schoolId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  });

  Future<Branch?> getBranch(String schoolId, String branchId);

  Stream<List<Branch>> watchBranches(String schoolId);

  Future<String> createBranch(Branch branch, {required String createdBy});

  Future<void> updateBranch(Branch branch, {required String updatedBy});

  /// Creates a brand-new school with the caller as its first
  /// [UserRole.schoolAdmin], plus a default branch. Safe to call again if
  /// a previous attempt partially failed — see
  /// FIRESTORE_ARCHITECTURE.md → "School creation" for why.
  ///
  /// Returns the new school's id.
  Future<String> createSchoolForCurrentUser({
    required String userId,
    required String userName,
    required String userEmail,
    required String schoolName,
    required String schoolEmail,
    String? schoolPhone,
    required RegionalSettings regional,
  });
}
