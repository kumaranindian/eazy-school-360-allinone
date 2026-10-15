import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context.dart';
import '../../../announcements/data/firebase_announcement_repository.dart';
import '../../../announcements/domain/announcement.dart';
import '../../../leave/domain/leave_repositories.dart';
import '../../../leave/presentation/providers/leave_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_homework_file_store.dart';
import '../../data/firebase_homework_repository.dart';
import '../../data/firebase_submission_repository.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_repositories.dart';
import '../../domain/homework_submission.dart';

final homeworkRepositoryProvider = Provider<HomeworkRepository>(
  (ref) => FirebaseHomeworkRepository(ref.watch(firestoreProvider)),
);
final submissionRepositoryProvider = Provider<SubmissionRepository>(
  (ref) => FirebaseSubmissionRepository(ref.watch(firestoreProvider)),
);
final announcementRepositoryProvider = Provider<AnnouncementRepository>(
  (ref) => FirebaseAnnouncementRepository(ref.watch(firestoreProvider)),
);
final homeworkFileStoreProvider = Provider<HomeworkFileStore>(
  (ref) => FirebaseHomeworkFileStore(ref.watch(firebaseStorageProvider)),
);

/// Who is acting, for the audit trail and history records.
HomeworkActor actorFor(TenantContext tenant) => HomeworkActor(
  userId: tenant.user.userId,
  name: tenant.user.name,
  role: tenant.role.wireValue,
);

typedef HomeworkKey = ({String schoolId, String branchId, String homeworkId});
typedef SubmissionKey = ({
  String schoolId,
  String branchId,
  String submissionId,
});
typedef SectionHomeworkKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String classId,
  String sectionId,
});
typedef ChildSubmissionsKey = ({
  String schoolId,
  String branchId,
  String studentId,
  String academicYearId,
});
typedef AnnouncementKey = ({
  String schoolId,
  String branchId,
  String announcementId,
});
typedef AnnouncementsKey = ({
  String schoolId,
  String branchId,
  String role,
  String userId,
  String? parentId,
  bool includeDrafts,
});
typedef NoticesKey = ({
  String schoolId,
  String branchId,
  String role,
  String? parentId,
});
typedef CountsKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String? teacherStaffId,
});

final homeworkProvider = StreamProvider.autoDispose
    .family<Homework?, HomeworkKey>((ref, key) {
      return ref
          .watch(homeworkRepositoryProvider)
          .watch(key.schoolId, key.branchId, key.homeworkId);
    });

final homeworkHistoryProvider = StreamProvider.autoDispose
    .family<List<HomeworkHistoryEntry>, HomeworkKey>((ref, key) {
      return ref
          .watch(homeworkRepositoryProvider)
          .watchHistory(key.schoolId, key.branchId, key.homeworkId);
    });

final submissionProvider = StreamProvider.autoDispose
    .family<HomeworkSubmission?, SubmissionKey>((ref, key) {
      return ref
          .watch(submissionRepositoryProvider)
          .watch(key.schoolId, key.branchId, key.submissionId);
    });

final submissionRevisionsProvider = StreamProvider.autoDispose
    .family<List<SubmissionRevision>, SubmissionKey>((ref, key) {
      return ref
          .watch(submissionRepositoryProvider)
          .watchRevisions(key.schoolId, key.branchId, key.submissionId);
    });

final submissionCountsProvider = FutureProvider.autoDispose
    .family<SubmissionCounts, HomeworkKey>((ref, key) {
      return ref
          .watch(submissionRepositoryProvider)
          .counts(
            schoolId: key.schoolId,
            branchId: key.branchId,
            homeworkId: key.homeworkId,
          );
    });

/// What a family sees for one section: PUBLISHED and CLOSED homework.
final sectionHomeworkProvider = FutureProvider.autoDispose
    .family<List<Homework>, SectionHomeworkKey>((ref, key) {
      return ref
          .watch(homeworkRepositoryProvider)
          .fetchForSection(
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            classId: key.classId,
            sectionId: key.sectionId,
          );
    });

final childSubmissionsProvider = FutureProvider.autoDispose
    .family<List<HomeworkSubmission>, ChildSubmissionsKey>((ref, key) {
      return ref
          .watch(submissionRepositoryProvider)
          .fetchForStudent(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
            academicYearId: key.academicYearId,
          );
    });

final announcementProvider = StreamProvider.autoDispose
    .family<Announcement?, AnnouncementKey>((ref, key) {
      return ref
          .watch(announcementRepositoryProvider)
          .watch(key.schoolId, key.branchId, key.announcementId);
    });

final announcementsProvider = FutureProvider.autoDispose
    .family<List<Announcement>, AnnouncementsKey>((ref, key) {
      return ref
          .watch(announcementRepositoryProvider)
          .fetch(
            schoolId: key.schoolId,
            branchId: key.branchId,
            viewerRole: key.role,
            viewerUserId: key.userId,
            viewerParentId: key.parentId,
            includeDrafts: key.includeDrafts,
          );
    });

/// Live: a notice an admin publishes reaches the bell and the centre
/// immediately. Bounded to the newest 30 per branch.
final noticesProvider = StreamProvider.autoDispose
    .family<List<BroadcastNotice>, NoticesKey>((ref, key) {
      return ref
          .watch(announcementRepositoryProvider)
          .watchNotices(
            schoolId: key.schoolId,
            branchId: key.branchId,
            viewerRole: key.role,
            viewerParentId: key.parentId,
          );
    });

typedef UserNoticesKey = ({String schoolId, String branchId, String userId});

/// Targeted notices for the signed-in user (existing `notifications`
/// infrastructure), narrowed to homework events.
final homeworkUpdatesProvider = StreamProvider.autoDispose
    .family<List<LeaveNotification>, UserNoticesKey>((ref, key) {
      return ref
          .watch(leaveNotificationRepositoryProvider)
          .watchForUser(key.schoolId, key.branchId, key.userId)
          .map(
            (all) => [
              for (final n in all)
                if (n.type.startsWith('HOMEWORK_')) n,
            ],
          );
    });

final homeworkStatusCountProvider = FutureProvider.autoDispose
    .family<Map<String, int>, CountsKey>((ref, key) async {
      final repo = ref.watch(homeworkRepositoryProvider);
      final result = <String, int>{};
      for (final s in HomeworkStatus.values) {
        result[s.wireValue] = await repo.countByStatus(
          schoolId: key.schoolId,
          branchId: key.branchId,
          academicYearId: key.academicYearId,
          status: s,
          teacherStaffId: key.teacherStaffId,
        );
      }
      return result;
    });

final awaitingReviewProvider = FutureProvider.autoDispose
    .family<int, HomeworkKey>((ref, key) {
      return ref
          .watch(submissionRepositoryProvider)
          .countAwaitingReview(
            schoolId: key.schoolId,
            branchId: key.branchId,
            homeworkId: key.homeworkId,
          );
    });
