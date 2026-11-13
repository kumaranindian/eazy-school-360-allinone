/// An account-deletion request as the platform reviewer sees it: ids and a
/// role, never a name, email or phone (the server does not send them).
class DeletionReviewItem {
  final String reference;
  final String status;
  final String? reason;
  final String? source;
  final String? role;
  final String schoolName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<DeletionHistoryLine> history;

  const DeletionReviewItem({
    required this.reference,
    required this.status,
    required this.reason,
    required this.source,
    required this.role,
    required this.schoolName,
    required this.createdAt,
    required this.updatedAt,
    required this.history,
  });

  factory DeletionReviewItem.fromMap(Map<String, dynamic> m) {
    DateTime? at(Object? ms) =>
        ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
    return DeletionReviewItem(
      reference: m['reference'] as String,
      status: (m['status'] as String?) ?? '',
      reason: m['reason'] as String?,
      source: m['source'] as String?,
      role: m['role'] as String?,
      schoolName: (m['schoolName'] as String?) ?? '',
      createdAt: at(m['createdAt']),
      updatedAt: at(m['updatedAt']),
      history: [
        for (final h in (m['history'] as List? ?? const []))
          DeletionHistoryLine(
            status: ((h as Map)['status'] as String?) ?? '',
            at: at(h['at']),
          ),
      ],
    );
  }

  /// What the reviewer may do next (mirrors the server's lifecycle table; the
  /// server refuses anything else).
  List<DeletionDecision> get decisions => switch (status) {
    'UNDER_REVIEW' => [
      DeletionDecision.approve,
      DeletionDecision.requestAction,
      DeletionDecision.reject,
    ],
    'ACTION_REQUIRED' => [DeletionDecision.reopen, DeletionDecision.reject],
    'APPROVED' => [DeletionDecision.requestAction, DeletionDecision.reject],
    'PROCESSING' || 'FAILED_RETRYABLE' => [DeletionDecision.requestAction],
    'PENDING_VERIFICATION' => [
      DeletionDecision.requestAction,
      DeletionDecision.reject,
    ],
    _ => const [],
  };
}

class DeletionHistoryLine {
  final String status;
  final DateTime? at;
  const DeletionHistoryLine({required this.status, required this.at});
}

/// A reviewer's decision (the server's `decision` values).
enum DeletionDecision {
  approve('APPROVE', 'Approve', 'Approve deletion'),
  reject('REJECT', 'Reject', 'Reject request'),
  requestAction('REQUEST_ACTION', 'Needs action', 'Ask for action'),
  reopen('REOPEN', 'Reopen', 'Reopen for review');

  final String wire;
  final String label;
  final String title;
  const DeletionDecision(this.wire, this.label, this.title);

  bool get isDestructive => this == approve;
}

/// Reasons a reviewer can record (the server's `reasonCode` values).
const Map<String, String> deletionReasonLabels = {
  'DECLINED': 'Declined by Avail404',
  'DUPLICATE': 'Duplicate request',
  'NO_ACCOUNT': 'No account found',
  'EMAIL_MISMATCH': 'Email does not match',
  'SOLE_ADMIN': 'Only school administrator',
};

String deletionStatusLabel(String status) {
  switch (status) {
    case 'PENDING_VERIFICATION':
      return 'Awaiting email check';
    case 'UNDER_REVIEW':
      return 'Under review';
    case 'ACTION_REQUIRED':
      return 'Action required';
    case 'APPROVED':
      return 'Approved';
    case 'PROCESSING':
      return 'Processing';
    case 'FAILED_RETRYABLE':
      return 'Failed, will retry';
    case 'COMPLETED':
      return 'Completed';
    case 'REJECTED':
      return 'Rejected';
    case 'CANCELLED':
      return 'Cancelled';
    case 'EXPIRED':
      return 'Expired';
  }
  return status;
}
