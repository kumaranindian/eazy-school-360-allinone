import 'deletion_request.dart';

/// What the person is told about their request. Never says "deleted" until the
/// server reports COMPLETED, and never promises a date it cannot keep.
class DeletionCopy {
  final String title;
  final String body;
  const DeletionCopy(this.title, this.body);

  /// Avail404's stated review target. A target, not a guarantee.
  static const reviewTarget = '7 days';

  static DeletionCopy forRequest(DeletionRequest r) {
    switch (r.status) {
      case DeletionStatus.pendingVerification:
        return const DeletionCopy(
          'Waiting for confirmation',
          'Open the email we sent you and use its link to confirm.',
        );
      case DeletionStatus.underReview:
        return const DeletionCopy(
          'Request received, under review',
          'Avail404 is reviewing your request and aims to finish within '
              '$reviewTarget. Your account has not been deleted yet and still '
              'works until then.',
        );
      case DeletionStatus.actionRequired:
        return DeletionCopy(
          'Action needed before we can continue',
          r.reason == DeletionReason.soleAdmin
              ? 'You are the only administrator of your school. Add another '
                    'administrator first, so the school is not left without '
                    'anyone able to manage it, then email hi@avail404.com '
                    'with your reference.'
              : 'Email hi@avail404.com with your reference and we will help.',
        );
      case DeletionStatus.approved:
        return const DeletionCopy(
          'Approved, waiting to be processed',
          'Your request was approved. The deletion has not been completed yet.',
        );
      case DeletionStatus.processing:
      case DeletionStatus.failedRetryable:
        return const DeletionCopy(
          'Being processed',
          'The deletion is in progress and is not complete yet.',
        );
      case DeletionStatus.completed:
        return const DeletionCopy(
          'Completed',
          'Your account and eligible personal data were deleted.',
        );
      case DeletionStatus.rejected:
        return const DeletionCopy(
          'We could not process this request',
          'Email hi@avail404.com with your reference and we will help.',
        );
      case DeletionStatus.cancelled:
        return const DeletionCopy(
          'Cancelled',
          'This request was withdrawn. Nothing was deleted.',
        );
      case DeletionStatus.expired:
        return const DeletionCopy(
          'Expired',
          'Nothing was done. You can submit a new request.',
        );
      case DeletionStatus.unknown:
        return const DeletionCopy(
          'In progress',
          'Your request is being handled. It is not complete yet.',
        );
    }
  }

  /// What deleting removes.
  static const deleted = <String>[
    'Your sign-in account and credentials',
    'Your profile: name, email, phone number and photo',
    'Your registered devices and push-notification tokens',
    'Your access to the school and its data',
  ];

  /// What it does not remove, and why.
  static const kept = <String>[
    'School records (students, attendance, results, homework, timetables) '
        'belong to the school and stay with it. A parent\'s request covers '
        'the parent\'s own account, not a child\'s school records.',
    'Fee, invoice, payment, receipt and audit records may be kept where the '
        'school needs them or the law requires it.',
    'Backups are overwritten on their normal schedule.',
  ];
}
