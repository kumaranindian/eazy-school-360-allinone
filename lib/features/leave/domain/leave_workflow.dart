import 'leave_application.dart';
import 'leave_enums.dart';
import 'leave_type.dart';
import 'leave_units.dart';

/// The business rules of the leave workflow as pure functions returning a
/// user-readable reason or null. Repositories call them for good messages;
/// `firestore.rules` independently re-enforces the transitions, the
/// self-approval ban, the tenant/parent/staff ownership and the balance
/// arithmetic — the UI is never the only enforcement.
abstract final class LeaveWorkflow {
  /// Permitted status changes and who may make them.
  ///
  /// - PENDING → APPROVED | REJECTED | RETURNED   (reviewer)
  /// - PENDING | RETURNED → WITHDRAWN              (the applicant)
  /// - RETURNED → PENDING                          (the applicant, resubmit)
  /// - APPROVED → CANCELLED                        (a reviewer only)
  static const Map<LeaveStatus, Set<LeaveStatus>> reviewerTransitions = {
    LeaveStatus.pending: {
      LeaveStatus.approved,
      LeaveStatus.rejected,
      LeaveStatus.returned,
    },
    LeaveStatus.approved: {LeaveStatus.cancelled},
  };

  static const Map<LeaveStatus, Set<LeaveStatus>> applicantTransitions = {
    LeaveStatus.pending: {LeaveStatus.withdrawn},
    LeaveStatus.returned: {LeaveStatus.pending, LeaveStatus.withdrawn},
  };

  static bool reviewerMayMove(LeaveStatus from, LeaveStatus to) =>
      reviewerTransitions[from]?.contains(to) ?? false;

  static bool applicantMayMove(LeaveStatus from, LeaveStatus to) =>
      applicantTransitions[from]?.contains(to) ?? false;

  static const int minRemarkLength = 3;

  /// Checks a reviewer's decision.
  static String? checkDecision({
    required LeaveApplication application,
    required LeaveStatus target,
    required String reviewerUserId,
    String? subjectUserId,
    String? remarks,
  }) {
    if (!reviewerMayMove(application.status, target)) {
      return application.status == LeaveStatus.approved
          ? 'An approved leave can only be cancelled.'
          : 'This application is ${application.status.displayName.toLowerCase()} '
                'and can no longer be decided.';
    }
    if (reviewerUserId == application.applicantUserId ||
        (subjectUserId != null && reviewerUserId == subjectUserId)) {
      return 'You cannot decide your own leave application. '
          'Another reviewer must do it.';
    }
    final needsRemarks =
        target == LeaveStatus.rejected ||
        target == LeaveStatus.returned ||
        target == LeaveStatus.cancelled;
    if (needsRemarks && (remarks ?? '').trim().length < minRemarkLength) {
      return 'Give a reason for this decision.';
    }
    return null;
  }

  static String? checkApplicantAction({
    required LeaveApplication application,
    required LeaveStatus target,
    required String userId,
  }) {
    if (application.applicantUserId != userId) {
      return 'Only the person who applied can do this.';
    }
    if (!applicantMayMove(application.status, target)) {
      return 'This application can no longer be changed by the applicant.';
    }
    return null;
  }

  /// Validates a new (or resubmitted) application's fields. [span] is the
  /// output of the day calculator for the same dates and type.
  static String? checkApply({
    required LeaveType type,
    required int spanUnits,
    required String? reason,
    required int attachmentCount,
    required String? applicantRole,
    String? employmentType,
  }) {
    if (!type.isActive) return 'This leave type is not available.';
    if (applicantRole != null &&
        type.kind == LeaveKind.staff &&
        !type.appliesToRole(applicantRole)) {
      return 'This leave type is not available for your role.';
    }
    if (type.kind == LeaveKind.staff &&
        !type.appliesToEmployment(employmentType)) {
      return 'This leave type does not apply to your employment type.';
    }
    if (spanUnits <= 0) return 'There are no leave days in this range.';
    if (type.requiresReason && (reason ?? '').trim().length < 3) {
      return 'Please give a reason.';
    }
    if ((reason ?? '').trim().length > 500) {
      return 'Keep the reason under 500 characters.';
    }
    if (type.requiresDocument && attachmentCount == 0) {
      return 'A supporting document is required for ${type.name}.';
    }
    if (attachmentCount > maxAttachments) {
      return 'Attach at most $maxAttachments files.';
    }
    return null;
  }

  static const int maxAttachments = 3;
  static const int maxAttachmentBytes = 5 * 1024 * 1024;
  static const Set<String> attachmentTypes = {
    'application/pdf',
    'image/jpeg',
    'image/png',
  };

  /// Overlap against [existing] applications of the same subject. A half day
  /// only conflicts with a full day or the same session. Withdrawn, rejected,
  /// returned and cancelled applications do not hold days.
  static LeaveApplication? findOverlap({
    required Iterable<LeaveApplication> existing,
    required List<String> countedDateKeys,
    required HalfDay halfDay,
    String? ignoreApplicationId,
  }) {
    final mine = countedDateKeys.toSet();
    for (final other in existing) {
      if (other.applicationId == ignoreApplicationId) continue;
      if (!other.status.holdsDays) continue;
      if (!other.countedDateKeys.any(mine.contains)) continue;
      if (halfDay == HalfDay.none ||
          other.halfDay == HalfDay.none ||
          other.halfDay == halfDay) {
        return other;
      }
    }
    return null;
  }

  static String overlapMessage(LeaveApplication other) =>
      'This overlaps an existing ${other.status.displayName.toLowerCase()} '
      'application (${other.startDateKey} to ${other.endDateKey}, '
      '${LeaveUnits.formatDays(other.units)}).';
}
