import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_leave_application_repository.dart';
import '../../data/firebase_leave_attachment_store.dart';
import '../../data/firebase_leave_balance_repository.dart';
import '../../data/firebase_leave_support_repositories.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_balance.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../../domain/leave_type.dart';

final leaveTypeRepositoryProvider = Provider<LeaveTypeRepository>(
  (ref) => FirebaseLeaveTypeRepository(ref.watch(firestoreProvider)),
);
final leaveApplicationRepositoryProvider = Provider<LeaveApplicationRepository>(
  (ref) => FirebaseLeaveApplicationRepository(ref.watch(firestoreProvider)),
);
final leaveBalanceRepositoryProvider = Provider<LeaveBalanceRepository>(
  (ref) => FirebaseLeaveBalanceRepository(ref.watch(firestoreProvider)),
);
final leaveCalendarRepositoryProvider = Provider<LeaveCalendarRepository>(
  (ref) => FirebaseLeaveCalendarRepository(ref.watch(firestoreProvider)),
);
final leaveNotificationRepositoryProvider =
    Provider<LeaveNotificationRepository>(
      (ref) =>
          FirebaseLeaveNotificationRepository(ref.watch(firestoreProvider)),
    );
final leaveReportRepositoryProvider = Provider<LeaveReportRepository>(
  (ref) => FirebaseLeaveReportRepository(ref.watch(firestoreProvider)),
);
final leaveAttachmentStoreProvider = Provider<LeaveAttachmentStore>(
  (ref) => FirebaseLeaveAttachmentStore(ref.watch(firebaseStorageProvider)),
);

typedef LeaveTypesKey = ({String schoolId, String branchId, LeaveKind kind});
typedef LeaveSubjectKey = ({
  String schoolId,
  String branchId,
  LeaveKind kind,
  String subjectId,
});
typedef LeaveAppKey = ({
  String schoolId,
  String branchId,
  String applicationId,
});
typedef LeaveBalancesKey = ({
  String schoolId,
  String branchId,
  String staffId,
  String academicYearId,
});
typedef LeaveCalendarKey = ({
  String schoolId,
  String branchId,
  LeaveKind kind,
  String fromKey,
  String toKey,
  String? classId,
  String? sectionId,
  String? subjectId,
});
typedef LeaveUserKey = ({String schoolId, String branchId, String userId});
typedef LeavePendingKey = ({String schoolId, String branchId, LeaveKind kind});

final leaveTypesProvider = StreamProvider.autoDispose
    .family<List<LeaveType>, LeaveTypesKey>((ref, key) {
      return ref
          .watch(leaveTypeRepositoryProvider)
          .watchTypes(key.schoolId, key.branchId, kind: key.kind);
    });

/// Types a person can currently choose: active ones only.
final activeLeaveTypesProvider = Provider.autoDispose
    .family<AsyncValue<List<LeaveType>>, LeaveTypesKey>((ref, key) {
      return ref
          .watch(leaveTypesProvider(key))
          .whenData(
            (types) => [
              for (final t in types)
                if (t.status == ActivationStatus.active) t,
            ],
          );
    });

final subjectLeaveProvider = FutureProvider.autoDispose
    .family<List<LeaveApplication>, LeaveSubjectKey>((ref, key) {
      return ref
          .watch(leaveApplicationRepositoryProvider)
          .fetchForSubject(
            schoolId: key.schoolId,
            branchId: key.branchId,
            kind: key.kind,
            subjectId: key.subjectId,
          );
    });

final leaveApplicationProvider = StreamProvider.autoDispose
    .family<LeaveApplication?, LeaveAppKey>((ref, key) {
      return ref
          .watch(leaveApplicationRepositoryProvider)
          .watch(key.schoolId, key.branchId, key.applicationId);
    });

typedef LeaveHistoryKey = ({
  String schoolId,
  String branchId,
  String applicationId,
  LeaveKind kind,
  String subjectId,
});

final leaveHistoryProvider = StreamProvider.autoDispose
    .family<List<LeaveHistoryEntry>, LeaveHistoryKey>((ref, key) {
      return ref
          .watch(leaveApplicationRepositoryProvider)
          .watchHistory(
            key.schoolId,
            key.branchId,
            key.applicationId,
            kind: key.kind,
            subjectId: key.subjectId,
          );
    });

final staffLeaveBalancesProvider = StreamProvider.autoDispose
    .family<List<LeaveBalance>, LeaveBalancesKey>((ref, key) {
      return ref
          .watch(leaveBalanceRepositoryProvider)
          .watchStaffBalances(
            schoolId: key.schoolId,
            branchId: key.branchId,
            staffId: key.staffId,
            academicYearId: key.academicYearId,
          );
    });

final leaveCalendarProvider = FutureProvider.autoDispose
    .family<List<LeaveCalendarEntry>, LeaveCalendarKey>((ref, key) {
      return ref
          .watch(leaveCalendarRepositoryProvider)
          .fetch(
            schoolId: key.schoolId,
            branchId: key.branchId,
            kind: key.kind,
            fromKey: key.fromKey,
            toKey: key.toKey,
            classId: key.classId,
            sectionId: key.sectionId,
            subjectId: key.subjectId,
          );
    });

final leaveUserNotificationsProvider = StreamProvider.autoDispose
    .family<List<LeaveNotification>, LeaveUserKey>((ref, key) {
      return ref
          .watch(leaveNotificationRepositoryProvider)
          .watchForUser(key.schoolId, key.branchId, key.userId);
    });

final leaveReviewerNotificationsProvider = StreamProvider.autoDispose
    .family<List<LeaveNotification>, BranchKey>((ref, key) {
      return ref
          .watch(leaveNotificationRepositoryProvider)
          .watchForReviewers(key.schoolId, key.branchId);
    });

final leavePendingCountProvider = FutureProvider.autoDispose
    .family<int, LeavePendingKey>((ref, key) {
      return ref
          .watch(leaveApplicationRepositoryProvider)
          .countPending(
            schoolId: key.schoolId,
            branchId: key.branchId,
            kind: key.kind,
          );
    });

final leaveAllowOnBehalfProvider = StreamProvider.autoDispose
    .family<bool, BranchKey>((ref, key) {
      return ref
          .watch(leaveTypeRepositoryProvider)
          .watchAllowAdminOnBehalf(key.schoolId, key.branchId);
    });
