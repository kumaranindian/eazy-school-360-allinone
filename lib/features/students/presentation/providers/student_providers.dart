import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_student_repository.dart';
import '../../data/parent_access_repair.dart';
import '../../data/parent_access_sync.dart';
import '../../domain/academic_record_status.dart';
import '../../domain/parent_student_link.dart';
import '../../domain/relationship_type.dart';
import '../../domain/student.dart';
import '../../domain/student_academic_record.dart';
import '../../domain/student_repository.dart';
import '../../domain/student_status.dart';
import 'student_keys.dart';

/// Rebuilds the family-access index used by the security rules (see
/// `ParentAccessSync`). Overridable in tests.
final parentAccessSyncProvider = Provider<ParentAccessSync>(
  (ref) => ParentAccessSync(ref.watch(firestoreProvider)),
);

/// Self-heal for the signed-in parent's own access index. Overridable in tests.
final parentAccessRepairProvider = Provider<ParentAccessRepair>(
  (ref) => ParentAccessRepair(),
  retry: (retryCount, error) => null,
);

/// Runs once per parent per session, before their children are loaded, so the
/// screens that depend on the index never race the repair.
final parentAccessEnsuredProvider = FutureProvider.family<void, String>(
  (ref, parentId) => ref.read(parentAccessRepairProvider).ensure(),
  retry: (retryCount, error) => null,
);

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return FirebaseStudentRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
  );
});

final studentProvider = StreamProvider.autoDispose.family<Student?, StudentKey>(
  (ref, key) {
    return ref
        .watch(studentRepositoryProvider)
        .watchStudent(key.schoolId, key.branchId, key.studentId);
  },
);

final academicHistoryProvider = StreamProvider.autoDispose
    .family<List<StudentAcademicRecord>, StudentKey>((ref, key) {
      return ref
          .watch(studentRepositoryProvider)
          .watchAcademicHistory(key.schoolId, key.branchId, key.studentId);
    });

final studentParentLinksProvider = StreamProvider.autoDispose
    .family<List<ParentStudentLink>, StudentKey>((ref, key) {
      return ref
          .watch(studentRepositoryProvider)
          .watchParentLinks(key.schoolId, key.branchId, key.studentId);
    });

/// Drives admission, profile edits, photo upload, status changes,
/// transfers, and parent-link management — one AsyncNotifier reused
/// across every student dialog/page, same shape as the Milestone 2
/// write controllers.
class StudentWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> admitStudent({
    required Student student,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    required String createdBy,
  }) async {
    String? newId;
    final ok = await _run(() async {
      newId = await ref
          .read(studentRepositoryProvider)
          .admitStudent(
            student: student,
            academicYearId: academicYearId,
            classId: classId,
            sectionId: sectionId,
            rollNumber: rollNumber,
            createdBy: createdBy,
          );
    });
    return ok ? newId : null;
  }

  Future<bool> updateProfile(Student student, {required String updatedBy}) =>
      _run(
        () => ref
            .read(studentRepositoryProvider)
            .updateStudentProfile(student, updatedBy: updatedBy),
      );

  Future<bool> uploadPhoto({
    required String schoolId,
    required String branchId,
    required String studentId,
    required List<int> fileBytes,
    required String fileExtension,
    required String updatedBy,
  }) => _run(
    () => ref
        .read(studentRepositoryProvider)
        .uploadStudentPhoto(
          schoolId: schoolId,
          branchId: branchId,
          studentId: studentId,
          fileBytes: fileBytes,
          fileExtension: fileExtension,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> changeStatus({
    required String schoolId,
    required String branchId,
    required String studentId,
    required StudentStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  }) => _run(
    () => ref
        .read(studentRepositoryProvider)
        .changeStudentStatus(
          schoolId: schoolId,
          branchId: branchId,
          studentId: studentId,
          status: status,
          effectiveDate: effectiveDate,
          reason: reason,
          notes: notes,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> transferStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String newAcademicYearId,
    required String newClassId,
    required String newSectionId,
    String? newRollNumber,
    required AcademicRecordStatus closeOldRecordAs,
    required String updatedBy,
  }) => _run(
    () => ref
        .read(studentRepositoryProvider)
        .transferStudent(
          schoolId: schoolId,
          branchId: branchId,
          studentId: studentId,
          newAcademicYearId: newAcademicYearId,
          newClassId: newClassId,
          newSectionId: newSectionId,
          newRollNumber: newRollNumber,
          closeOldRecordAs: closeOldRecordAs,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> linkParent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String parentId,
    required RelationshipType relationshipType,
    bool isPrimary = false,
    bool isEmergencyContact = false,
    bool canAccessPortal = false,
    required String createdBy,
  }) => _run(
    () => ref
        .read(studentRepositoryProvider)
        .linkParentToStudent(
          schoolId: schoolId,
          branchId: branchId,
          studentId: studentId,
          parentId: parentId,
          relationshipType: relationshipType,
          isPrimary: isPrimary,
          isEmergencyContact: isEmergencyContact,
          canAccessPortal: canAccessPortal,
          createdBy: createdBy,
        ),
  );

  Future<bool> updateParentLink(
    ParentStudentLink link, {
    required String updatedBy,
  }) => _run(
    () => ref
        .read(studentRepositoryProvider)
        .updateParentLink(link, updatedBy: updatedBy),
  );

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final studentWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<StudentWriteController, void>(
      StudentWriteController.new,
    );

/// Headcount per status for the roster's stat chips, keyed by status (null =
/// everyone). Server-side counts, recomputed each time the roster is opened.
final studentCountsProvider = FutureProvider.autoDispose
    .family<Map<StudentStatus?, int>, BranchKey>((ref, key) async {
      final repository = ref.watch(studentRepositoryProvider);
      final statuses = <StudentStatus?>[null, ...StudentStatus.values];
      final counts = await Future.wait([
        for (final status in statuses)
          repository.countStudents(
            schoolId: key.schoolId,
            branchId: key.branchId,
            status: status,
          ),
      ]);
      return {for (var i = 0; i < statuses.length; i++) statuses[i]: counts[i]};
    });
