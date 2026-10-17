import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../../domain/leave_units.dart';
import '../../domain/leave_workflow.dart';
import '../providers/leave_providers.dart';
import 'leave_apply_form.dart';
import 'leave_widgets.dart';

/// One application: details, decision history, and the actions the signed-in
/// person is allowed. The buttons mirror the permissions; `firestore.rules`
/// is what actually enforces them.
class LeaveApplicationDetail extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final String applicationId;

  const LeaveApplicationDetail({
    super.key,
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.applicationId,
  });

  @override
  ConsumerState<LeaveApplicationDetail> createState() =>
      _LeaveApplicationDetailState();
}

class _LeaveApplicationDetailState
    extends ConsumerState<LeaveApplicationDetail> {
  bool _busy = false;

  LeaveActor get _actor => LeaveActor(
    userId: widget.tenant.user.userId,
    name: widget.tenant.user.name,
  );

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      ref.invalidate(leavePendingCountProvider);
      ref.invalidate(subjectLeaveProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The login behind a staff applicant, so a reviewer who IS that person gets
  /// a clear message. Only a courtesy: `firestore.rules` refuses a self-decision
  /// regardless, so a record that cannot be loaded must not block the decision.
  Future<String?> _subjectUserId(LeaveApplication a) async {
    if (a.kind != LeaveKind.staff) return null;
    try {
      final staff = await ref.read(
        staffProvider((
          schoolId: a.schoolId,
          branchId: a.branchId,
          staffId: a.subjectId,
        )).future,
      );
      return staff?.userId;
    } catch (error) {
      AppLogger.warning(
        'Could not load the staff record of leave ${a.applicationId}: $error',
        tag: 'Leave',
      );
      return null;
    }
  }

  Future<void> _decide(LeaveApplication a, LeaveStatus target) async {
    final needsRemarks = target != LeaveStatus.approved;
    final remarks = await askLeaveRemarks(
      context,
      title: switch (target) {
        LeaveStatus.approved => 'Approve this leave?',
        LeaveStatus.rejected => 'Reject this leave?',
        _ => 'Return for correction?',
      },
      message:
          '${LeavePathsLabel.describe(a)}\n'
          '${LeaveUnits.formatDays(a.units)}'
          '${a.balanceId != null && target == LeaveStatus.approved ? ' will be deducted from the staff leave balance.' : ''}',
      confirmLabel: switch (target) {
        LeaveStatus.approved => 'Approve',
        LeaveStatus.rejected => 'Reject',
        _ => 'Return',
      },
      required: needsRemarks,
      destructive: target == LeaveStatus.rejected,
    );
    if (remarks == null || !mounted) return;
    await _run(
      () async => ref
          .read(leaveApplicationRepositoryProvider)
          .decide(
            application: a,
            target: target,
            reviewer: _actor,
            remarks: remarks,
            subjectUserId: await _subjectUserId(a),
            todayKey: AttendanceDate.key(DateTime.now()),
          ),
      switch (target) {
        LeaveStatus.approved => 'Leave approved.',
        LeaveStatus.rejected => 'Leave rejected.',
        _ => 'Application returned for correction.',
      },
    );
  }

  Future<void> _cancel(LeaveApplication a) async {
    final remarks = await askLeaveRemarks(
      context,
      title: 'Cancel approved leave?',
      message:
          '${LeavePathsLabel.describe(a)}\nThe leave is removed from the '
          'calendar${a.balanceId != null ? ' and ${LeaveUnits.formatDays(a.units)} is restored to the balance' : ''}. '
          'Attendance already recorded is not changed.',
      confirmLabel: 'Cancel leave',
      destructive: true,
    );
    if (remarks == null || !mounted) return;
    await _run(
      () async => ref
          .read(leaveApplicationRepositoryProvider)
          .cancelApproved(
            application: a,
            reviewer: _actor,
            remarks: remarks,
            subjectUserId: await _subjectUserId(a),
          ),
      'Approved leave cancelled.',
    );
  }

  Future<void> _withdraw(LeaveApplication a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: Text(LeavePathsLabel.describe(a)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(leaveApplicationRepositoryProvider)
          .withdraw(a, actor: _actor),
      'Application withdrawn.',
    );
  }

  Future<void> _correct(LeaveApplication a) async {
    final years = ref
        .read(
          academicYearsProvider((schoolId: a.schoolId, branchId: a.branchId)),
        )
        .value;
    final year = years
        ?.where((y) => y.academicYearId == a.academicYearId)
        .firstOrNull;
    if (year == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The academic year could not be found.')),
      );
      return;
    }
    await showAdaptiveAppDialog<void>(
      context: context,
      builder: (dialogContext) => LeaveApplyForm(
        schoolId: a.schoolId,
        branchId: a.branchId,
        year: year,
        subject: LeaveSubject(
          kind: a.kind,
          id: a.subjectId,
          name: a.subjectName,
          code: a.subjectCode,
          classId: a.classId,
          className: a.className,
          sectionId: a.sectionId,
          sectionName: a.sectionName,
        ),
        actor: _actor,
        applicantRole: widget.tenant.role.wireValue,
        relation: a.relation,
        resubmitting: a,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _open(LeaveAttachment f) async {
    try {
      final url = await ref
          .read(leaveAttachmentStoreProvider)
          .downloadUrl(f.path);
      if (!await launchUrl(Uri.parse(url))) {
        throw StateError('Could not open the file.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      applicationId: widget.applicationId,
    );
    final appAsync = ref.watch(leaveApplicationProvider(key));
    return appAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(leaveApplicationProvider(key)),
      ),
      data: (a) {
        if (a == null) {
          return const EmptyView(
            icon: Icons.search_off,
            message: 'This leave application could not be found.',
          );
        }
        return _body(context, a, key);
      },
    );
  }

  Widget _body(BuildContext context, LeaveApplication a, LeaveAppKey key) {
    final theme = Theme.of(context);
    final tenant = widget.tenant;
    final isReviewer = tenant.can(Permission.reviewLeave);
    final isApplicant = a.applicantUserId == tenant.user.userId;
    final history =
        ref
            .watch(
              leaveHistoryProvider((
                schoolId: key.schoolId,
                branchId: key.branchId,
                applicationId: key.applicationId,
                kind: a.kind,
                subjectId: a.subjectId,
              )),
            )
            .value ??
        const [];

    final actions = <Widget>[];
    if (isReviewer && !isApplicant) {
      if (a.status == LeaveStatus.pending) {
        actions.addAll([
          FilledButton.icon(
            onPressed: _busy ? null : () => _decide(a, LeaveStatus.approved),
            icon: const Icon(Icons.check),
            label: const Text('Approve'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _decide(a, LeaveStatus.returned),
            icon: const Icon(Icons.undo),
            label: const Text('Return'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _decide(a, LeaveStatus.rejected),
            icon: const Icon(Icons.close),
            label: const Text('Reject'),
          ),
        ]);
      } else if (a.status == LeaveStatus.approved) {
        actions.add(
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _cancel(a),
            icon: const Icon(Icons.event_busy),
            label: const Text('Cancel approved leave'),
          ),
        );
      }
    }
    if (isApplicant && a.status.isOpen) {
      if (a.status == LeaveStatus.returned) {
        actions.add(
          FilledButton.icon(
            onPressed: _busy ? null : () => _correct(a),
            icon: const Icon(Icons.edit),
            label: const Text('Correct and resubmit'),
          ),
        );
      }
      actions.add(
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _withdraw(a),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Withdraw'),
        ),
      );
    }

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      a.subjectName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  LeaveStatusChip(a.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row(
                        'Leave type',
                        '${a.typeName} (${a.payType.displayName})',
                      ),
                      row(
                        'Dates',
                        '${leaveRange(a)}${leaveSession(a.halfDay)}',
                      ),
                      row('Leave days', LeaveUnits.formatDays(a.units)),
                      if (a.className != null)
                        row(
                          'Class',
                          '${a.className}${a.sectionName == null ? '' : ' ${a.sectionName}'}',
                        ),
                      if (a.subjectCode != null)
                        row('Reference', a.subjectCode!),
                      row(
                        'Applied by',
                        '${a.applicantName} (${a.relation.wireValue.toLowerCase()})',
                      ),
                      if ((a.reason ?? '').isNotEmpty) row('Reason', a.reason!),
                      if (a.decidedByName != null)
                        row('Decided by', a.decidedByName!),
                      if ((a.decisionRemarks ?? '').isNotEmpty)
                        row('Reviewer remarks', a.decisionRemarks!),
                    ],
                  ),
                ),
              ),
              if (a.attachments.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Documents', style: theme.textTheme.titleSmall),
                for (final f in a.attachments)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(f.name, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: () => _open(f),
                      child: const Text('Open'),
                    ),
                  ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: actions,
                ),
              ],
              if (isReviewer && isApplicant && a.status == LeaveStatus.pending)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'You filed this application, so another reviewer must decide it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text('History', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              if (history.isEmpty)
                Text('No history yet.', style: theme.textTheme.bodySmall)
              else
                for (final h in history)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(
                      '${h.from == null ? 'Submitted' : '${h.from!.displayName} → ${h.to.displayName}'}'
                      ' · ${h.actorName}',
                    ),
                    subtitle: (h.remarks ?? '').isEmpty
                        ? null
                        : Text(h.remarks!),
                    trailing: h.at == null
                        ? null
                        : Text(
                            leaveDate(AttendanceDate.key(h.at!)),
                            style: theme.textTheme.bodySmall,
                          ),
                  ),
              if (LeaveWorkflow.reviewerMayMove(
                a.status,
                LeaveStatus.cancelled,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    'Approved leave appears on the attendance screens as an '
                    'annotation. Attendance records are never changed by leave.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short "who · when" label for dialogs.
abstract final class LeavePathsLabel {
  static String describe(LeaveApplication a) =>
      '${a.subjectName} · ${leaveRange(a)}${leaveSession(a.halfDay)}';
}
