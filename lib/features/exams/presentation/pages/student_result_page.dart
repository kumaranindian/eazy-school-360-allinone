import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/exam_enums.dart';
import '../../domain/result_summary.dart';
import '../providers/exam_providers.dart';
import '../widgets/report_card_loader.dart';

/// `/exams/results/:examId/:studentId` — one student's result and report
/// card for staff. A finalised result is read from its stored, versioned
/// document; before finalisation the figures are computed on the spot and
/// labelled provisional.
class StudentResultPage extends ConsumerWidget {
  final String examId;
  final String studentId;

  const StudentResultPage({
    super.key,
    required this.examId,
    required this.studentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student result')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (schoolId: schoolId, branchId: branchId, examId: examId);
          final exam = ref.watch(examProvider(key));
          if (exam.hasError) {
            return ErrorView(message: userMessageFor(exam.error!));
          }
          final e = exam.value;
          if (!exam.hasValue) {
            return const Center(child: CircularProgressIndicator());
          }
          if (e == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This examination could not be found.',
            );
          }
          final finalised =
              e.resultVersion > 0 &&
              (e.status == ExamStatus.completed ||
                  e.status == ExamStatus.published ||
                  e.status == ExamStatus.withdrawn);
          final schoolName = tenant.school?.name ?? '';
          final branchName = tenant.branch?.name ?? '';
          if (finalised) {
            final stored = ref.watch(
              childResultProvider((
                schoolId: schoolId,
                branchId: branchId,
                examId: examId,
                studentId: studentId,
                version: e.resultVersion,
              )),
            );
            return stored.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorView(message: userMessageFor(err)),
              data: (s) => s == null
                  ? const EmptyView(
                      icon: Icons.hourglass_empty,
                      message:
                          'This result has not been written yet. Finish '
                          'writing the results from the Results screen.',
                    )
                  : PageColumn(
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        children: [
                          Text(
                            'Version ${s.version} · ${e.status.displayName}',
                          ),
                          ReportCardLoader(
                            schoolName: schoolName,
                            branchName: branchName,
                            summary: s,
                            publishedAt: e.publishedAt,
                          ),
                        ],
                      ),
                    ),
            );
          }
          final prov = ref.watch(provisionalResultsProvider(key));
          final remarks = ref.watch(examRemarksProvider(key)).value;
          return prov.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => ErrorView(message: userMessageFor(err)),
            data: (p) {
              final r = p.results
                  .where((x) => x.studentId == studentId)
                  .firstOrNull;
              if (r == null) {
                return const EmptyView(
                  icon: Icons.person_off_outlined,
                  message: 'This student is not enrolled for the examination.',
                );
              }
              final remark = remarks?[studentId];
              return PageColumn(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    ReportCardLoader(
                      schoolName: schoolName,
                      branchName: branchName,
                      provisional: true,
                      summary: ResultSummary(
                        examId: e.examId,
                        examName: e.name,
                        studentId: studentId,
                        version: 0,
                        schoolId: e.schoolId,
                        branchId: e.branchId,
                        academicYearId: e.academicYearId,
                        classId: e.classId,
                        sectionId: r.sectionId,
                        classLabel: e.classLabel,
                        result: r,
                        schemeSnapshot: p.scheme.policyMap(),
                        teacherRemark: remark?.teacherRemark ?? '',
                        principalRemark: remark?.principalRemark ?? '',
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
