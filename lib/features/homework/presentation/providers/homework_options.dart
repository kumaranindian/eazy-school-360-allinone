import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../timetable/domain/substitution.dart' show StaffLite;
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';

/// One section + subject a person may set homework for, with display names.
class HomeworkOption {
  final String classId;
  final String sectionId;
  final String subjectId;
  final String teacherStaffId;
  final String classLabel;
  final String subjectName;
  final String teacherName;

  const HomeworkOption({
    required this.classId,
    required this.sectionId,
    required this.subjectId,
    required this.teacherStaffId,
    required this.classLabel,
    required this.subjectName,
    required this.teacherName,
  });

  String get key => '$classId/$sectionId/$subjectId';
}

typedef HomeworkOptionsKey = ({
  String schoolId,
  String branchId,
  String academicYearId,

  /// When set, only this teacher's assignments (a teacher's own list); null
  /// for an admin, who may set homework on behalf of any assigned teacher.
  String? teacherStaffId,
});

/// The sections and subjects a person may set homework for: ACTIVE subject
/// assignments of the year (class-teacher-only assignments carry no subject
/// and are not homework targets). The same assignments the rules check when
/// the homework is written — this list is a convenience, not the guard.
final homeworkOptionsProvider = FutureProvider.autoDispose
    .family<List<HomeworkOption>, HomeworkOptionsKey>((ref, key) async {
      final yearKey = (
        schoolId: key.schoolId,
        branchId: key.branchId,
        academicYearId: key.academicYearId,
      );
      final facts = await ref.watch(yearAssignmentsProvider(yearKey).future);
      final classes = await ref.watch(classesProvider(yearKey).future);
      final subjectList = await ref.watch(
        subjectsProvider((
          schoolId: key.schoolId,
          branchId: key.branchId,
          academicYearId: key.academicYearId,
        )).future,
      );
      final subjects = {for (final s in subjectList) s.subjectId: s};
      // Teacher names only matter to an admin choosing a teacher. A teacher
      // (teacherStaffId set) may not list colleagues' staff records, and the
      // list is only used to label their own options anyway.
      final teachers = key.teacherStaffId != null
          ? const <StaffLite>[]
          : await ref.watch(
              activeTeachersProvider((
                schoolId: key.schoolId,
                branchId: key.branchId,
              )).future,
            );
      final className = {for (final c in classes) c.classId: c.name};
      final teacherName = {for (final t in teachers) t.staffId: t.name};

      final wanted = [
        for (final f in facts)
          if (f.subjectId != null &&
              !f.isClassTeacher &&
              (key.teacherStaffId == null ||
                  f.teacherStaffId == key.teacherStaffId))
            f,
      ];
      final sectionNames = <String, String>{};
      for (final classId in {for (final f in wanted) f.classId}) {
        final sections = await ref.watch(
          sectionsProvider((
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            classId: classId,
          )).future,
        );
        for (final s in sections) {
          sectionNames['$classId/${s.sectionId}'] = s.name;
        }
      }
      final seen = <String>{};
      final options = <HomeworkOption>[];
      for (final f in wanted) {
        final o = HomeworkOption(
          classId: f.classId,
          sectionId: f.sectionId,
          subjectId: f.subjectId!,
          teacherStaffId: f.teacherStaffId,
          classLabel:
              '${className[f.classId] ?? f.classId} – '
              '${sectionNames['${f.classId}/${f.sectionId}'] ?? f.sectionId}',
          subjectName: subjects[f.subjectId]?.name ?? f.subjectId!,
          teacherName: teacherName[f.teacherStaffId] ?? '',
        );
        if (seen.add('${o.key}/${o.teacherStaffId}')) options.add(o);
      }
      options.sort((a, b) {
        final c = a.classLabel.compareTo(b.classLabel);
        return c != 0 ? c : a.subjectName.compareTo(b.subjectName);
      });
      return options;
    });
