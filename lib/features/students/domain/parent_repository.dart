import '../../../core/constants/activation_status.dart';
import 'paged_result.dart';
import 'parent.dart';
import 'student.dart';

/// Parent/guardian records, and the "which students belong to this
/// parent" direction of the parent-student relationship (the "which
/// parents belong to this student" direction lives on `StudentRepository`
/// — see that file and `docs/milestone-3-student-parent-management.md`).
abstract class ParentRepository {
  Future<PagedResult<Parent>> fetchParents({
    required String schoolId,
    required String branchId,
    ActivationStatus? status,
    int pageSize = 25,
    Object? cursor,
  });

  Future<PagedResult<Parent>> searchParentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  });

  Future<Parent?> getParent(String schoolId, String branchId, String parentId);

  Stream<Parent?> watchParent(
    String schoolId,
    String branchId,
    String parentId,
  );

  Future<String> createParent(Parent parent, {required String createdBy});

  Future<void> updateParent(Parent parent, {required String updatedBy});

  Future<String> uploadParentPhoto({
    required String schoolId,
    required String branchId,
    required String parentId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  });

  /// A collection-group query across every student's `parentLinks`
  /// (brief §22: "Parent A → Student 1, Student 2, Student 3") — see
  /// `firestore.indexes.json` for the index this needs.
  ///
  /// A parent reads their own links with just [schoolId] + [parentId]. Staff
  /// (who are scoped to a branch by the rules) must also pass [branchId] —
  /// without it the rules cannot prove the query stays inside their branch
  /// and refuse it (needs the `(schoolId, branchId, parentId)` index).
  Future<List<Student>> getChildrenForParent({
    required String schoolId,
    required String parentId,
    String? branchId,
  });

  /// Grants portal-login authorization to an existing `/users/{uid}`
  /// PARENT account by linking it to this parent record, both directions
  /// — see `UserProfile.toFirestoreParentLink`. Does not create the
  /// Firebase Auth account itself; that remains the existing admin-
  /// provisioning / self-signup paths from Milestone 1.
  Future<void> linkPortalAccess({
    required String schoolId,
    required String branchId,
    required String parentId,
    required String userId,
    required String updatedBy,
  });
}
