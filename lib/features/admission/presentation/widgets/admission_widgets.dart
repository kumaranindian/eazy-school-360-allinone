import 'package:flutter/material.dart';

import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_status.dart';

/// The status pill of an enquiry, coloured by what the status means.
class AdmissionStatusBadge extends StatelessWidget {
  final AdmissionStatus status;
  const AdmissionStatusBadge(this.status, {super.key});

  static ParentsTone toneOf(AdmissionStatus s) => switch (s) {
    AdmissionStatus.approved ||
    AdmissionStatus.admissionConfirmed => ParentsTone.success,
    AdmissionStatus.rejected => ParentsTone.danger,
    AdmissionStatus.onHold ||
    AdmissionStatus.visitScheduled ||
    AdmissionStatus.underReview => ParentsTone.warning,
    _ => ParentsTone.neutral,
  };

  @override
  Widget build(BuildContext context) =>
      ParentsBadge(status.label, tone: toneOf(status));
}

/// "dd Mon yyyy" from a yyyy-mm-dd string, or the text itself when unparsable.
String shortDate(String? iso) {
  if (iso == null || iso.length != 10) return iso ?? '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final m = int.tryParse(iso.substring(5, 7));
  if (m == null || m < 1 || m > 12) return iso;
  return '${iso.substring(8, 10)} ${months[m - 1]} ${iso.substring(0, 4)}';
}

/// One enquiry in the list: number and date, student, primary contact,
/// status and the follow-up date when there is one.
class EnquiryCard extends StatelessWidget {
  final AdmissionEnquiry enquiry;
  final String? className;
  final VoidCallback onTap;

  const EnquiryCard({
    super.key,
    required this.enquiry,
    required this.onTap,
    this.className,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    final guardian = enquiry.primaryGuardian;
    return ParentsCard(
      onTap: onTap,
      semanticLabel:
          '${enquiry.studentName}, ${enquiry.status.label}, '
          'enquiry ${enquiry.enquiryNumber}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ParentsAvatar(name: enquiry.studentName),
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
                      enquiry.studentName,
                      style: t.titleMedium?.copyWith(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AdmissionStatusBadge(enquiry.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${enquiry.enquiryNumber} · ${shortDate(enquiry.enquiryDate)}',
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 4),
                if (className != null)
                  ParentsFactRow(
                    icon: Icons.class_outlined,
                    text: 'Class $className',
                  ),
                if (guardian != null)
                  ParentsFactRow(
                    icon: Icons.person_outline,
                    text: '${guardian.name} · ${guardian.phone}',
                  ),
                if (enquiry.nextFollowUpDate != null)
                  ParentsFactRow(
                    icon: Icons.event_outlined,
                    text: 'Follow up ${shortDate(enquiry.nextFollowUpDate)}',
                  ),
                if (enquiry.duplicateOf.isNotEmpty)
                  ParentsFactRow(
                    icon: Icons.warning_amber_outlined,
                    text: 'Possible duplicate',
                    valueColor: p.warning,
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: p.textSecondary),
        ],
      ),
    );
  }
}

/// A headline number on the admission dashboard.
class AdmissionStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const AdmissionStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    return ParentsCard(
      onTap: onTap,
      semanticLabel: '$label: $value',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.tint(p.primary),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: p.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: t.headlineSmall?.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
