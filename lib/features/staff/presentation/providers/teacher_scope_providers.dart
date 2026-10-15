import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../data/firebase_teacher_scope_repository.dart';
import '../../domain/teacher_scope.dart';

final teacherScopeRepositoryProvider = Provider<TeacherScopeRepository>(
  (ref) => FirebaseTeacherScopeRepository(FirebaseFirestore.instance),
);

/// The signed-in teacher's assigned sections; null while none is provisioned
/// (no `teacherAccess` document) and for every non-teacher. Watches the
/// document, so a new assignment shows up without a re-login.
final teacherScopeProvider = StreamProvider.autoDispose<TeacherScope?>((
  ref,
) async* {
  final tenant = await ref.watch(tenantContextProvider.future);
  final schoolId = tenant?.school?.schoolId;
  final branchId = tenant?.user.branchId ?? tenant?.branch?.branchId;
  if (tenant == null ||
      tenant.role != UserRole.teacher ||
      schoolId == null ||
      branchId == null) {
    yield null;
    return;
  }
  yield* ref
      .watch(teacherScopeRepositoryProvider)
      .watchScope(
        schoolId: schoolId,
        branchId: branchId,
        userId: tenant.user.userId,
      );
});

/// "Class 5 – A" for one of the teacher's sections, from the academic
/// structure (the teacher may read it), falling back to the raw ids while it
/// loads or if it cannot be read.
final teacherSectionLabelProvider = Provider.autoDispose
    .family<
      String,
      ({String schoolId, String branchId, TeacherSection section})
    >((ref, key) {
      final s = key.section;
      final year = s.academicYearId;
      if (year == null) return '${s.classId} – ${s.sectionId}';
      final classes = ref
          .watch(
            classesProvider((
              schoolId: key.schoolId,
              branchId: key.branchId,
              academicYearId: year,
            )),
          )
          .value;
      final sections = ref
          .watch(
            sectionsProvider((
              schoolId: key.schoolId,
              branchId: key.branchId,
              academicYearId: year,
              classId: s.classId,
            )),
          )
          .value;
      final className =
          classes?.where((c) => c.classId == s.classId).firstOrNull?.name ??
          s.classId;
      final sectionName =
          sections
              ?.where((x) => x.sectionId == s.sectionId)
              .firstOrNull
              ?.name ??
          s.sectionId;
      return '$className – $sectionName';
    });
