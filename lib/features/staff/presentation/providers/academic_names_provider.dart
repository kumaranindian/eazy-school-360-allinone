import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';

/// Id -> display-name lookups for one academic year's classes, sections and
/// subjects. Assignments store only ids (so renaming a class never rewrites
/// history); screens resolve names through this.
class AcademicNames {
  final Map<String, String> _classes;
  final Map<String, Map<String, String>> _sections;
  final Map<String, String> _subjects;

  const AcademicNames({
    required Map<String, String> classes,
    required Map<String, Map<String, String>> sections,
    required Map<String, String> subjects,
  }) : _classes = classes,
       _sections = sections,
       _subjects = subjects;

  String className(String classId) => _classes[classId] ?? 'Unknown class';

  String sectionName(String classId, String sectionId) =>
      _sections[classId]?[sectionId] ?? 'Unknown section';

  String subjectName(String? subjectId) =>
      subjectId == null ? '' : (_subjects[subjectId] ?? 'Unknown subject');

  /// "Class 5-A"
  String classSection(String classId, String sectionId) =>
      '${className(classId)}-${sectionName(classId, sectionId)}';
}

/// Resolves once the year's classes, subjects and every class's sections
/// have loaded, and re-resolves when any of them changes.
final academicNamesProvider = FutureProvider.autoDispose
    .family<AcademicNames, AcademicYearKey>((ref, key) async {
      final classes = await ref.watch(classesProvider(key).future);
      final subjects = await ref.watch(subjectsProvider(key).future);

      final sections = <String, Map<String, String>>{};
      for (final schoolClass in classes) {
        final classSections = await ref.watch(
          sectionsProvider((
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            classId: schoolClass.classId,
          )).future,
        );
        sections[schoolClass.classId] = {
          for (final s in classSections) s.sectionId: s.name,
        };
      }

      return AcademicNames(
        classes: {for (final c in classes) c.classId: c.name},
        sections: sections,
        subjects: {for (final s in subjects) s.subjectId: s.name},
      );
    });
