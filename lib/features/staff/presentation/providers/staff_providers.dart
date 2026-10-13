import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_providers.dart';

import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../school_setup/domain/branch.dart';
import '../../../school_setup/presentation/providers/school_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_staff_repository.dart';
import '../../data/firebase_staff_setup_repository.dart';
import '../../data/firebase_teacher_assignment_repository.dart';
import '../../domain/department.dart';
import '../../domain/designation.dart';
import '../../domain/staff.dart';
import '../../domain/staff_document.dart';
import '../../domain/staff_repository.dart';
import '../../domain/staff_setup_repository.dart';
import '../../domain/staff_status.dart';
import '../../domain/teacher_assignment.dart';
import '../../domain/teacher_assignment_repository.dart';
import 'staff_keys.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return FirebaseStaffRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
  );
});

final staffSetupRepositoryProvider = Provider<StaffSetupRepository>((ref) {
  return FirebaseStaffSetupRepository(ref.watch(firestoreProvider));
});

final teacherAssignmentRepositoryProvider =
    Provider<TeacherAssignmentRepository>((ref) {
      return FirebaseTeacherAssignmentRepository(ref.watch(firestoreProvider));
    });

final staffProvider = StreamProvider.autoDispose.family<Staff?, StaffKey>((
  ref,
  key,
) {
  return ref
      .watch(staffRepositoryProvider)
      .watchStaff(key.schoolId, key.branchId, key.staffId);
});

/// The staff record linked to the signed-in user's account — null when the
/// account has no linked staff record (which is normal: a staff member
/// need not have a login, and a login need not be staff).
final ownStaffProvider = FutureProvider.autoDispose.family<Staff?, OwnStaffKey>(
  (ref, key) {
    return ref
        .watch(staffRepositoryProvider)
        .findStaffByUserId(key.schoolId, key.branchId, key.userId);
  },
);

final staffDocumentsProvider = StreamProvider.autoDispose
    .family<List<StaffDocument>, StaffKey>((ref, key) {
      return ref
          .watch(staffRepositoryProvider)
          .watchDocuments(key.schoolId, key.branchId, key.staffId);
    });

final departmentsProvider = StreamProvider.autoDispose
    .family<List<Department>, BranchKey>((ref, key) {
      return ref
          .watch(staffSetupRepositoryProvider)
          .watchDepartments(key.schoolId, key.branchId);
    });

final designationsProvider = StreamProvider.autoDispose
    .family<List<Designation>, BranchKey>((ref, key) {
      return ref
          .watch(staffSetupRepositoryProvider)
          .watchDesignations(key.schoolId, key.branchId);
    });

final teacherAssignmentsProvider = StreamProvider.autoDispose
    .family<List<TeacherAssignment>, StaffKey>((ref, key) {
      return ref
          .watch(teacherAssignmentRepositoryProvider)
          .watchTeacherAssignments(key.schoolId, key.branchId, key.staffId);
    });

/// Branches of a school, for the branch filter shown to roles that are not
/// tied to one branch.
final schoolBranchesProvider = StreamProvider.autoDispose
    .family<List<Branch>, String>((ref, schoolId) {
      return ref.watch(schoolRepositoryProvider).watchBranches(schoolId);
    });

/// Which branch the staff screens are showing, for school-level roles that
/// can switch (null = their own default). Branch-scoped roles ignore it.
class SelectedStaffBranch extends Notifier<String?> {
  @override
  String? build() {
    // Re-evaluated when the signed-in account changes, so one user's branch
    // choice never carries over to the next user of the same session.
    ref.watch(authStateChangesProvider.select((a) => a.value?.uid));
    return null;
  }

  void select(String? branchId) => state = branchId;
}

final selectedStaffBranchIdProvider =
    NotifierProvider<SelectedStaffBranch, String?>(SelectedStaffBranch.new);

/// Drives create/edit/status/link/photo/document writes for staff. One
/// AsyncNotifier reused across the staff dialogs and pages, same shape as
/// the Milestone 3 write controllers.
class StaffWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> createStaff(Staff staff, {required String createdBy}) async {
    String? newId;
    final ok = await _run(() async {
      newId = await ref
          .read(staffRepositoryProvider)
          .createStaff(staff: staff, createdBy: createdBy);
    });
    return ok ? newId : null;
  }

  Future<bool> updateStaff(Staff staff, {required String updatedBy}) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .updateStaff(staff: staff, updatedBy: updatedBy),
  );

  Future<bool> changeStatus({
    required Staff staff,
    required StaffStatus status,
    required DateTime effectiveDate,
    String? reason,
    String? notes,
    required String updatedBy,
  }) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .changeStaffStatus(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          staffId: staff.staffId,
          status: status,
          effectiveDate: effectiveDate,
          reason: reason,
          notes: notes,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> linkUser(
    Staff staff,
    String? userId, {
    required String updatedBy,
  }) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .linkUserAccount(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          staffId: staff.staffId,
          userId: userId,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> uploadPhoto(
    Staff staff,
    List<int> bytes,
    String extension, {
    required String updatedBy,
  }) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .uploadStaffPhoto(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          staffId: staff.staffId,
          fileBytes: bytes,
          fileExtension: extension,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> removePhoto(Staff staff, {required String updatedBy}) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .removeStaffPhoto(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          staffId: staff.staffId,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> uploadDocument(
    Staff staff, {
    required StaffDocumentType type,
    required String title,
    required String fileName,
    required List<int> bytes,
    required String createdBy,
  }) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .uploadDocument(
          schoolId: staff.schoolId,
          branchId: staff.branchId,
          staffId: staff.staffId,
          type: type,
          title: title,
          fileName: fileName,
          fileBytes: bytes,
          createdBy: createdBy,
        ),
  );

  Future<bool> removeDocument(
    StaffDocument document, {
    required String updatedBy,
  }) => _run(
    () => ref
        .read(staffRepositoryProvider)
        .removeDocument(
          schoolId: document.schoolId,
          branchId: document.branchId,
          staffId: document.staffId,
          documentId: document.documentId,
          updatedBy: updatedBy,
        ),
  );

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final staffWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<StaffWriteController, void>(
      StaffWriteController.new,
    );

/// Department + designation create/edit.
class StaffSetupWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> run(
    Future<void> Function(StaffSetupRepository repository) action,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => action(ref.read(staffSetupRepositoryProvider)),
    );
    return !state.hasError;
  }
}

final staffSetupWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<StaffSetupWriteController, void>(
      StaffSetupWriteController.new,
    );

/// Assign / end teacher assignments.
class TeacherAssignmentWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> assign({
    required Staff teacher,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? subjectId,
    required bool isClassTeacher,
    required DateTime startDate,
    required String createdBy,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(teacherAssignmentRepositoryProvider)
          .assignTeacher(
            schoolId: teacher.schoolId,
            branchId: teacher.branchId,
            academicYearId: academicYearId,
            teacherStaffId: teacher.staffId,
            classId: classId,
            sectionId: sectionId,
            subjectId: subjectId,
            isClassTeacher: isClassTeacher,
            startDate: startDate,
            createdBy: createdBy,
          ),
    );
    return !state.hasError;
  }

  Future<bool> end(
    TeacherAssignment assignment, {
    required DateTime endDate,
    required String updatedBy,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(teacherAssignmentRepositoryProvider)
          .endAssignment(
            assignment: assignment,
            endDate: endDate,
            updatedBy: updatedBy,
          ),
    );
    return !state.hasError;
  }
}

final teacherAssignmentWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<TeacherAssignmentWriteController, void>(
      TeacherAssignmentWriteController.new,
    );

/// Headcount per status for the directory's stat chips. Server-side counts
/// (four aggregate reads), recomputed each time the directory is opened.
typedef StaffCounts = ({int total, int active, int onNotice, int inactive});

final staffCountsProvider = FutureProvider.autoDispose
    .family<StaffCounts, StaffCountsKey>((ref, key) async {
      final repository = ref.watch(staffRepositoryProvider);
      Future<int> count([StaffStatus? status]) => repository.countStaff(
        schoolId: key.schoolId,
        branchId: key.branchId,
        status: status,
        isTeacher: key.teachersOnly ? true : null,
      );
      final results = await Future.wait([
        count(),
        count(StaffStatus.active),
        count(StaffStatus.onNotice),
        count(StaffStatus.inactive),
      ]);
      return (
        total: results[0],
        active: results[1],
        onNotice: results[2],
        inactive: results[3],
      );
    });
