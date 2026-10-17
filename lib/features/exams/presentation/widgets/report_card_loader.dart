import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/result_summary.dart';
import 'exam_widgets.dart';
import 'report_card_pdf.dart';

/// Resolves the display names a report card needs (academic year, class,
/// section) and shows the report card. The marks, grades, remarks and
/// attendance come only from the [summary] it is given.
class ReportCardLoader extends ConsumerWidget {
  final String schoolName;
  final String branchName;
  final ResultSummary summary;
  final DateTime? publishedAt;
  final bool provisional;

  const ReportCardLoader({
    super.key,
    required this.schoolName,
    required this.branchName,
    required this.summary,
    this.publishedAt,
    this.provisional = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One year document (a family may read that, never the year list).
    final yearDoc = ref
        .watch(
          academicYearProvider((
            schoolId: summary.schoolId,
            branchId: summary.branchId,
            academicYearId: summary.academicYearId,
          )),
        )
        .value;
    final classes = ref
        .watch(
          classesProvider((
            schoolId: summary.schoolId,
            branchId: summary.branchId,
            academicYearId: summary.academicYearId,
          )),
        )
        .value;
    final sections = ref
        .watch(
          sectionsProvider((
            schoolId: summary.schoolId,
            branchId: summary.branchId,
            academicYearId: summary.academicYearId,
            classId: summary.classId,
          )),
        )
        .value;
    final year = yearDoc?.name;
    final className = classes
        ?.where((c) => c.classId == summary.classId)
        .firstOrNull
        ?.name;
    final sectionName = sections
        ?.where((s) => s.sectionId == summary.sectionId)
        .firstOrNull
        ?.name;
    return ReportCardPanel(
      data: ReportCardData(
        schoolName: schoolName,
        branchName: branchName,
        academicYearName: year ?? summary.academicYearId,
        className: className ?? summary.classLabel ?? summary.classId,
        sectionName: sectionName ?? summary.sectionId,
        summary: summary,
        publishedAt: publishedAt,
        provisional: provisional,
      ),
    );
  }
}
