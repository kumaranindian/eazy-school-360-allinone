import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/student.dart';

/// Resolves a student's `currentClassId`/`currentSectionId` cache to
/// display names via the already-loaded academic-setup providers (no
/// extra reads beyond what's already cached for that academic year — the
/// `.family` provider is shared across every row needing the same year).
class StudentPlacementLabel extends ConsumerWidget {
  final Student student;

  const StudentPlacementLabel({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (student.currentClassId == null ||
        student.currentAcademicYearId == null) {
      return const Text('—');
    }
    final yearKey = (
      schoolId: student.schoolId,
      branchId: student.branchId,
      academicYearId: student.currentAcademicYearId!,
    );
    final classesAsync = ref.watch(classesProvider(yearKey));

    return classesAsync.when(
      data: (classes) {
        final match = classes
            .where((c) => c.classId == student.currentClassId)
            .toList();
        if (match.isEmpty) return const Text('—');
        final classKey = (
          schoolId: yearKey.schoolId,
          branchId: yearKey.branchId,
          academicYearId: yearKey.academicYearId,
          classId: match.first.classId,
        );
        final sectionsAsync = ref.watch(sectionsProvider(classKey));
        return sectionsAsync.when(
          data: (sections) {
            final section = sections
                .where((s) => s.sectionId == student.currentSectionId)
                .toList();
            return Text(
              section.isEmpty
                  ? match.first.name
                  : '${match.first.name} - ${section.first.name}',
            );
          },
          loading: () => Text(match.first.name),
          error: (_, __) => Text(match.first.name),
        );
      },
      loading: () => const SizedBox(
        height: 12,
        width: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      error: (_, __) => const Text('—'),
    );
  }
}
