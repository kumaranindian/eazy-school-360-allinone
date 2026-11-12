import 'package:flutter/material.dart';

import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_activity.dart';
import 'admission_widgets.dart';

IconData activityIcon(ActivityType t) => switch (t) {
  ActivityType.phoneCall => Icons.call_outlined,
  ActivityType.whatsapp => Icons.chat_outlined,
  ActivityType.email => Icons.mail_outline,
  ActivityType.schoolVisit => Icons.school_outlined,
  ActivityType.meeting => Icons.groups_2_outlined,
  ActivityType.other => Icons.event_note_outlined,
};

/// "10:30 AM" style from hh:mm (24h), or the text itself.
String timeText(String? hhmm) {
  if (hhmm == null || hhmm.length != 5) return hhmm ?? '';
  final h = int.tryParse(hhmm.substring(0, 2));
  if (h == null) return hhmm;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${hhmm.substring(3)} ${h < 12 ? 'AM' : 'PM'}';
}

/// One follow-up: what, when, who, and (when finished) what came of it.
/// [showEnquiry] adds the student and enquiry number (dashboard lists).
class ActivityCard extends StatelessWidget {
  final AdmissionActivity activity;
  final String todayKey;
  final String? assigneeName;
  final bool showEnquiry;
  final VoidCallback? onTap;
  final List<Widget> actions;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.todayKey,
    this.assigneeName,
    this.showEnquiry = false,
    this.onTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    final a = activity;
    final overdue = a.isOverdue(todayKey);
    final when = [
      shortDate(a.scheduledDate),
      if (a.scheduledTime != null) timeText(a.scheduledTime),
    ].join(' · ');
    return ParentsCard(
      onTap: onTap,
      semanticLabel:
          '${a.type.label}, ${a.status.label}, $when'
          '${overdue ? ', overdue' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.tint(overdue ? p.warning : p.primary),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  activityIcon(a.type),
                  color: overdue ? p.warning : p.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          a.isVisit && a.purpose != null
                              ? 'School visit · ${a.purpose!.label}'
                              : a.type.label,
                          style: t.titleMedium?.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        ParentsBadge(
                          overdue ? 'Overdue' : a.status.label,
                          tone: switch (a.status) {
                            ActivityStatus.completed => ParentsTone.success,
                            ActivityStatus.cancelled => ParentsTone.neutral,
                            ActivityStatus.scheduled =>
                              overdue
                                  ? ParentsTone.warning
                                  : ParentsTone.neutral,
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      when,
                      style: t.bodyMedium?.copyWith(
                        color: overdue ? p.warning : p.textSecondary,
                        fontWeight: overdue ? FontWeight.w700 : null,
                      ),
                    ),
                    if (showEnquiry)
                      Text(
                        '${a.studentName} · ${a.enquiryNumber}',
                        style: t.bodyMedium?.copyWith(color: p.textPrimary),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: p.textSecondary),
            ],
          ),
          if (a.isOpen || a.assignedTo != null)
            ParentsFactRow(
              icon: Icons.support_agent_outlined,
              text: a.assignedTo == null
                  ? 'Unassigned'
                  : (assigneeName ?? 'Assigned'),
            ),
          if (a.remarks != null)
            ParentsFactRow(icon: Icons.notes_outlined, text: a.remarks!),
          if (a.outcome != null)
            ParentsFactRow(
              icon: Icons.check_circle_outline,
              label: 'Outcome',
              text: a.outcome!,
            ),
          if (a.parentFeedback != null)
            ParentsFactRow(
              icon: Icons.record_voice_over_outlined,
              label: 'Parent feedback',
              text: a.parentFeedback!,
            ),
          if (a.cancelReason != null)
            ParentsFactRow(
              icon: Icons.cancel_outlined,
              label: 'Cancelled',
              text: a.cancelReason!,
            ),
          if (a.rescheduleCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Rescheduled ${a.rescheduleCount} '
                '${a.rescheduleCount == 1 ? 'time' : 'times'}',
                style: t.bodySmall?.copyWith(color: p.textSecondary),
              ),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: actions),
          ],
        ],
      ),
    );
  }
}

/// A plain-language line for one activity event (the timeline).
String describeActivityEvent(ActivityHistoryEntry e) {
  final what = e.isVisit
      ? (e.purpose == null
            ? 'School visit'
            : 'School visit (${e.purpose!.label.toLowerCase()})')
      : e.type.label;
  final when = e.toDate == null
      ? ''
      : ' for ${shortDate(e.toDate)}'
            '${e.toTime == null ? '' : ' at ${timeText(e.toTime)}'}';
  return switch (e.event) {
    ActivityEvent.created => '$what scheduled$when',
    ActivityEvent.rescheduled =>
      '$what rescheduled from ${shortDate(e.fromDate)} to ${shortDate(e.toDate)}',
    ActivityEvent.reassigned => '$what reassigned',
    ActivityEvent.completed => '$what completed',
    ActivityEvent.cancelled => '$what cancelled',
  };
}
