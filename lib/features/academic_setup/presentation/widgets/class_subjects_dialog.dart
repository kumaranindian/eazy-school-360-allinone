import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/class_subject_link.dart';
import '../../domain/school_class.dart';
import '../../domain/subject.dart';
import '../providers/academic_structure_providers.dart';

/// Checklist of every subject in the academic year, toggled on/off for
/// [schoolClass] — see `ClassSubjectLink` for why this is a reference
/// (doc id = subjectId), not a duplicated subject document.
class ClassSubjectsDialog extends ConsumerWidget {
  final SchoolClass schoolClass;
  final List<Subject> allSubjects;
  final String currentUserId;

  const ClassSubjectsDialog({
    super.key,
    required this.schoolClass,
    required this.allSubjects,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classKey = (
      schoolId: schoolClass.schoolId,
      branchId: schoolClass.branchId,
      academicYearId: schoolClass.academicYearId,
      classId: schoolClass.classId,
    );
    final linksAsync = ref.watch(classSubjectsProvider(classKey));
    final repository = ref.read(academicStructureRepositoryProvider);

    Future<void> toggle(Subject subject, bool linked) async {
      try {
        if (linked) {
          await repository.linkSubjectToClass(
            ClassSubjectLink(
              subjectId: subject.subjectId,
              schoolId: schoolClass.schoolId,
              branchId: schoolClass.branchId,
              academicYearId: schoolClass.academicYearId,
              classId: schoolClass.classId,
              subjectName: subject.name,
              subjectCode: subject.code,
              subjectType: subject.type,
            ),
            createdBy: currentUserId,
          );
        } else {
          await repository.unlinkSubjectFromClass(
            schoolClass.schoolId,
            schoolClass.branchId,
            schoolClass.academicYearId,
            schoolClass.classId,
            subject.subjectId,
          );
        }
      } catch (error) {
        if (context.mounted) {
          context.showSnackBar(userMessageFor(error), isError: true);
        }
      }
    }

    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Subjects for ${schoolClass.name}',
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose which subjects are taught in this class.',
            style: context.textStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          linksAsync.when(
            data: (links) {
              if (allSubjects.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text('No subjects exist yet for this academic year.'),
                );
              }
              final linkedIds = links.map((l) => l.subjectId).toSet();
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final subject in allSubjects)
                      CheckboxListTile(
                        value: linkedIds.contains(subject.subjectId),
                        title: Text(subject.name),
                        subtitle: Text(subject.type.displayName),
                        onChanged: (value) => toggle(subject, value ?? false),
                      ),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(userMessageFor(error)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
