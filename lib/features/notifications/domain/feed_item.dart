import '../../../core/permissions/permission.dart';
import '../../../core/permissions/role_permissions.dart';
import '../../../core/permissions/user_role.dart';
import '../../../core/routing/app_routes.dart';
import 'notification_category.dart';

/// Where an item in the notification centre came from, which decides how its
/// read state is kept.
enum FeedSource {
  /// A `notifications` document addressed to this user: read state is its own
  /// `readAt`.
  targeted,

  /// A `broadcastNotices` document addressed to an audience the user belongs
  /// to, or a reviewers' notice: read state is the user's own list of read
  /// ids (a shared document cannot carry per-user state).
  shared,
}

/// One row of the notification centre. Display information only: a title, a
/// short line and references. It carries no student work, marks, message text
/// or leave reason, and **is never an authorisation to open its target**:
/// navigation goes through the normal routes and rules.
class FeedItem {
  final String id;
  final FeedSource source;
  final String branchId;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool read;
  final String? refType;
  final String? refId;
  final String? applicationId;
  final String? homeworkId;
  final String? submissionId;
  final String? conversationId;

  const FeedItem({
    required this.id,
    required this.source,
    required this.branchId,
    required this.type,
    required this.title,
    this.body = '',
    this.createdAt,
    this.expiresAt,
    this.read = false,
    this.refType,
    this.refId,
    this.applicationId,
    this.homeworkId,
    this.submissionId,
    this.conversationId,
  });

  NotificationCategory get category => NotificationCategory.forType(type);

  bool isExpired(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  FeedItem copyWith({bool? read}) => FeedItem(
    id: id,
    source: source,
    branchId: branchId,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    expiresAt: expiresAt,
    read: read ?? this.read,
    refType: refType,
    refId: refId,
    applicationId: applicationId,
    homeworkId: homeworkId,
    submissionId: submissionId,
    conversationId: conversationId,
  );
}

/// Turns a notification into the route that shows its subject, for a given
/// role. Returning a route is **not** a grant of access: the router still
/// requires the route's permission, and the page's own reads are checked by
/// the security rules — a deleted or inaccessible record shows a safe
/// "not available" screen.
abstract final class NotificationNavigator {
  static String? routeFor(FeedItem n, UserRole role) {
    bool can(Permission p) => RolePermissions.roleHas(role, p);
    final isFamily = role == UserRole.parent;
    switch (n.type) {
      case 'MESSAGE_RECEIVED':
        final c = n.conversationId;
        if (c == null) return AppRoutes.messages;
        return '/messages/$c?branchId=${n.branchId}';
      case 'LEAVE_SUBMITTED':
      case 'LEAVE_APPROVED':
      case 'LEAVE_REJECTED':
      case 'LEAVE_RETURNED':
      case 'LEAVE_WITHDRAWN':
      case 'LEAVE_CANCELLED':
      case 'LEAVE_BALANCE_ADJUSTED':
        final a = n.applicationId;
        if (a == null) {
          return can(Permission.viewLeave)
              ? AppRoutes.leaveApplications
              : AppRoutes.myLeave;
        }
        // A reviewer opens the review screen; an applicant their own.
        return can(Permission.viewLeave) && n.source == FeedSource.shared
            ? AppRoutes.leaveApplicationDetail.replaceFirst(':applicationId', a)
            : AppRoutes.myLeaveApplication.replaceFirst(':applicationId', a);
      case 'TIMETABLE_PUBLISHED':
      case 'SUBSTITUTION_ASSIGNED':
      case 'SUBSTITUTION_CHANGED':
      case 'SUBSTITUTION_CANCELLED':
        return AppRoutes.myTimetable;
      case 'HOMEWORK_RETURNED':
      case 'HOMEWORK_GRADED':
        final sid = n.submissionId;
        final hid = n.homeworkId;
        if (sid != null && hid != null && sid.startsWith('${hid}__')) {
          final student = sid.substring(hid.length + 2);
          return AppRoutes.myHomeworkDetail
              .replaceFirst(':homeworkId', hid)
              .replaceFirst(':studentId', student);
        }
        return AppRoutes.myHomework;
      case 'HOMEWORK_PUBLISHED':
      case 'HOMEWORK_DUE_CHANGED':
        if (isFamily || !can(Permission.viewHomework)) {
          return AppRoutes.myHomework;
        }
        return n.refId == null
            ? AppRoutes.homework
            : AppRoutes.homeworkDetail.replaceFirst(':homeworkId', n.refId!);
      case 'ANNOUNCEMENT_PUBLISHED':
      case 'ANNOUNCEMENT_UPDATED':
        if (n.refId == null) return AppRoutes.announcements;
        return '${AppRoutes.announcementDetail.replaceFirst(':announcementId', n.refId!)}'
            '?branchId=${n.branchId}';
      case 'RESULT_PUBLISHED':
        if (isFamily || !can(Permission.viewExams)) return AppRoutes.myResults;
        return n.refId == null
            ? AppRoutes.exams
            : AppRoutes.examDetail.replaceFirst(':examId', n.refId!);
      case 'PAYMENT_RECORDED':
        return AppRoutes.myFees;
      case 'FEE_DUE_REMINDER':
        final inv = n.refId;
        return inv == null
            ? AppRoutes.myFees
            : AppRoutes.myFeesInvoice.replaceFirst(':invoiceId', inv);
      case 'ATTENDANCE_ABSENT':
        return AppRoutes.myAttendance;
      default:
        return null;
    }
  }
}
