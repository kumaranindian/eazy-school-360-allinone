import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_academic_structure_repository.dart';
import '../../data/firebase_school_year_repository.dart';
import '../../domain/academic_structure_repository.dart';
import '../../domain/academic_year.dart';
import '../../domain/class_subject_link.dart';
import '../../domain/school_academic_year.dart';
import '../../domain/school_class.dart';
import '../../domain/school_year_repository.dart';
import '../../domain/section.dart';
import '../../domain/subject.dart';
import 'academic_setup_keys.dart';

final academicStructureRepositoryProvider =
    Provider<AcademicStructureRepository>((ref) {
      return FirebaseAcademicStructureRepository(ref.watch(firestoreProvider));
    });

final schoolYearRepositoryProvider = Provider<SchoolYearRepository>((ref) {
  return FirebaseSchoolYearRepository(ref.watch(firestoreProvider));
});

/// The school-wide academic years (the registry branches open from).
final schoolYearsProvider = StreamProvider.autoDispose
    .family<List<SchoolAcademicYear>, String>((ref, schoolId) {
      return ref.watch(schoolYearRepositoryProvider).watchSchoolYears(schoolId);
    });

/// Which branches (comma-joined ids) already hold the branch copy of a
/// school-wide year.
final schoolYearOpenedProvider = FutureProvider.autoDispose
    .family<Set<String>, ({String schoolId, String yearId, String branchIds})>((
      ref,
      key,
    ) {
      if (key.branchIds.isEmpty) return <String>{};
      return ref
          .watch(schoolYearRepositoryProvider)
          .openedIn(key.schoolId, key.yearId, key.branchIds.split(','));
    });

final academicYearsProvider = StreamProvider.autoDispose
    .family<List<AcademicYear>, BranchKey>((ref, key) {
      return ref
          .watch(academicStructureRepositoryProvider)
          .watchAcademicYears(key.schoolId, key.branchId);
    });

final classesProvider = StreamProvider.autoDispose
    .family<List<SchoolClass>, AcademicYearKey>((ref, key) {
      return ref
          .watch(academicStructureRepositoryProvider)
          .watchClasses(key.schoolId, key.branchId, key.academicYearId);
    });

final sectionsProvider = StreamProvider.autoDispose
    .family<List<Section>, ClassKey>((ref, key) {
      return ref
          .watch(academicStructureRepositoryProvider)
          .watchSections(
            key.schoolId,
            key.branchId,
            key.academicYearId,
            key.classId,
          );
    });

final subjectsProvider = StreamProvider.autoDispose
    .family<List<Subject>, AcademicYearKey>((ref, key) {
      return ref
          .watch(academicStructureRepositoryProvider)
          .watchSubjects(key.schoolId, key.branchId, key.academicYearId);
    });

final classSubjectsProvider = StreamProvider.autoDispose
    .family<List<ClassSubjectLink>, ClassKey>((ref, key) {
      return ref
          .watch(academicStructureRepositoryProvider)
          .watchClassSubjects(
            key.schoolId,
            key.branchId,
            key.academicYearId,
            key.classId,
          );
    });

/// Drives every academic-year/class/section/subject create-or-edit dialog
/// in this feature — one small AsyncNotifier reused across all of them
/// rather than one per entity type, since the shape (run an async write,
/// surface a `ValidationFailure`/`AppFailure` message) is identical.
class AcademicStructureWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final academicStructureWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<AcademicStructureWriteController, void>(
      AcademicStructureWriteController.new,
    );

/// One academic year by id. Families may read only this single document (never
/// the list) — see the `academicYears` rule — so screens that run for a parent
/// use the child's own `currentAcademicYearId` with this, not
/// [academicYearsProvider].
final academicYearProvider = FutureProvider.autoDispose
    .family<
      AcademicYear?,
      ({String schoolId, String branchId, String academicYearId})
    >((ref, key) {
      return ref
          .watch(academicStructureRepositoryProvider)
          .getAcademicYear(key.schoolId, key.branchId, key.academicYearId);
    });
