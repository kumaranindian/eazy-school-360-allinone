import 'package:flutter/material.dart';

import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_application.dart';

class ApplicationStatusBadge extends StatelessWidget {
  final ApplicationStatus status;
  const ApplicationStatusBadge(this.status, {super.key});

  static ParentsTone toneOf(ApplicationStatus s) => switch (s) {
    ApplicationStatus.approved => ParentsTone.success,
    ApplicationStatus.rejected => ParentsTone.danger,
    ApplicationStatus.underReview ||
    ApplicationStatus.submitted => ParentsTone.warning,
    _ => ParentsTone.neutral,
  };

  @override
  Widget build(BuildContext context) =>
      ParentsBadge(status.label, tone: toneOf(status));
}

class DocumentStatusBadge extends StatelessWidget {
  final DocumentStatus status;
  const DocumentStatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) => ParentsBadge(
    status.label,
    tone: switch (status) {
      DocumentStatus.verified => ParentsTone.success,
      DocumentStatus.rejected => ParentsTone.danger,
      DocumentStatus.uploaded => ParentsTone.warning,
      _ => ParentsTone.neutral,
    },
  );
}

/// "1.2 MB" / "340 KB".
String fileSizeText(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// A plain-language line for one application event (the timeline).
String describeApplicationEvent(
  ApplicationEvent e,
  Map<String, String> documentLabels,
) {
  final doc = documentLabels[e.documentType] ?? e.documentType ?? 'Document';
  return switch (e.event) {
    'CREATED' => 'Application started',
    'SUBMITTED' => 'Application submitted',
    'REVIEW_STARTED' => 'Application taken into review',
    'COMMENTED' => 'Review comment added',
    'APPROVED' => 'Application approved',
    'REJECTED' => 'Application rejected',
    'CLOSED_WITH_ENQUIRY' =>
      e.to == ApplicationStatus.rejected
          ? 'Application rejected (enquiry closed)'
          : 'Application withdrawn (enquiry closed)',
    'DOCUMENT_UPLOADED' => '$doc uploaded',
    'DOCUMENT_VERIFIED' => '$doc verified',
    'DOCUMENT_REJECTED' => '$doc rejected',
    'DOCUMENT_REMOVED' => '$doc removed',
    _ => e.event,
  };
}
