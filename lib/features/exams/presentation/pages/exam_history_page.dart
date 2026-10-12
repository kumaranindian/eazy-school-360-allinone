import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../providers/exam_providers.dart';

/// `/exams/history/:examId` — every recorded change to an examination and
/// its marks sheets: who, what, when and (for withdrawals, reopenings,
/// cancellations and returns) why. Append-only; nothing here is editable.
class ExamHistoryPage extends ConsumerWidget {
  final String examId;
  const ExamHistoryPage({super.key, required this.examId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (schoolId: schoolId, branchId: branchId, examId: examId);
          final audit = ref.watch(examAuditProvider(key));
          return audit.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(examAuditProvider(key)),
            ),
            data: (entries) => entries.isEmpty
                ? const EmptyView(
                    icon: Icons.history,
                    message: 'No history recorded yet.',
                  )
                : PageColumn(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        for (final e in entries.reversed)
                          ListTile(
                            leading: Icon(
                              e.scope == 'EXAM'
                                  ? Icons.assignment_outlined
                                  : Icons.fact_check_outlined,
                            ),
                            title: Text(
                              '${e.scope == 'EXAM' ? 'Examination' : 'Marks sheet'}'
                              ' — ${e.event.replaceAll('_', ' ').toLowerCase()}'
                              '${e.toStatus == null ? '' : ' → ${e.toStatus}'}',
                            ),
                            subtitle: Text(
                              '${e.actorName} · ${formatInstant(e.at)}'
                              '${e.scope == 'SHEET' ? '\n${e.refId.split('__').skip(1).join(' / ')}' : ''}'
                              '${e.note == null ? '' : '\nReason: ${e.note}'}',
                            ),
                            isThreeLine: e.note != null || e.scope == 'SHEET',
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}
