import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/regional/school_time.dart';

import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../staff/domain/staff_status.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_admission_repository.dart';
import '../../domain/admission_activity.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_repository.dart';
import '../../domain/admission_settings.dart';
import '../../domain/admission_status.dart';

final admissionRepositoryProvider = Provider<AdmissionRepository>((ref) {
  // Reads go through Firestore (rules-gated); writes through callables.
  return FirebaseAdmissionRepository(db: ref.watch(firestoreProvider));
});

final admissionSettingsProvider = StreamProvider.autoDispose
    .family<AdmissionSettings, String>(
      (ref, schoolId) =>
          ref.watch(admissionRepositoryProvider).watchSettings(schoolId),
    );

typedef EnquiryKey = ({String schoolId, String branchId, String enquiryId});

final enquiryProvider = StreamProvider.autoDispose
    .family<AdmissionEnquiry?, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .watchEnquiry(key.schoolId, key.branchId, key.enquiryId),
    );

/// The status history; re-read when the enquiry's revision changes.
final enquiryHistoryProvider = FutureProvider.autoDispose
    .family<List<StatusHistoryEntry>, (EnquiryKey, int)>(
      (ref, args) => ref
          .watch(admissionRepositoryProvider)
          .fetchHistory(args.$1.schoolId, args.$1.branchId, args.$1.enquiryId),
    );

/// Every activity event of one enquiry, newest first. Activity changes do not
/// bump the enquiry's revision, so [lastActivityAt] (millis) is part of the key.
final enquiryActivityHistoryProvider = FutureProvider.autoDispose
    .family<List<ActivityHistoryEntry>, (EnquiryKey, int)>(
      (ref, args) => ref
          .watch(admissionRepositoryProvider)
          .fetchActivityHistory(
            args.$1.schoolId,
            args.$1.branchId,
            args.$1.enquiryId,
          ),
    );

final admissionCountsProvider = FutureProvider.autoDispose
    .family<Map<AdmissionStatus, int>, BranchKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .countByStatus(key.schoolId, key.branchId),
    );

/// Every follow-up of one enquiry. Invalidated by the UI after each change.
final enquiryActivitiesProvider = FutureProvider.autoDispose
    .family<List<AdmissionActivity>, EnquiryKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .fetchActivitiesForEnquiry(key.schoolId, key.branchId, key.enquiryId),
    );

typedef FollowUpKey = ({String schoolId, String branchId, String userId});

/// Counts for the follow-up dashboard; "today" is the SCHOOL's today.
final followUpCountsProvider = FutureProvider.autoDispose
    .family<FollowUpCounts, FollowUpKey>(
      (ref, key) => ref
          .watch(admissionRepositoryProvider)
          .countFollowUps(
            schoolId: key.schoolId,
            branchId: key.branchId,
            todayKey: SchoolTime.todayKey(),
            userId: key.userId,
          ),
    );

/// A person an enquiry can be assigned to: staff of the branch that have a
/// login (the server additionally checks the account is active and in scope).
typedef Assignee = ({String userId, String name});

final assigneesProvider = FutureProvider.autoDispose
    .family<List<Assignee>, BranchKey>((ref, key) async {
      final page = await ref
          .watch(staffRepositoryProvider)
          .fetchStaff(
            schoolId: key.schoolId,
            branchId: key.branchId,
            status: StaffStatus.active,
            pageSize: 100,
          );
      return [
        for (final s in page.items)
          if (s.userId != null)
            (
              userId: s.userId!,
              name: [
                s.firstName,
                s.lastName,
              ].where((p) => p.isNotEmpty).join(' '),
            ),
      ];
    });

/// Runs the admission write callables and exposes loading/error like the
/// other write controllers. Each method returns its result, or null/false on
/// failure (the error stays in [state] for the UI to show).
class AdmissionWriteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AdmissionRepository get _repo => ref.read(admissionRepositoryProvider);

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    T? out;
    state = await AsyncValue.guard(() async => out = await action());
    return state.hasError ? null : out;
  }

  Future<CreatedEnquiry?> create({
    required String schoolId,
    required String branchId,
    required EnquiryInput input,
    String? assignedTo,
  }) => _run(
    () => _repo.createEnquiry(
      schoolId: schoolId,
      branchId: branchId,
      input: input,
      assignedTo: assignedTo,
    ),
  );

  Future<bool> updateEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required EnquiryInput input,
    int? baseRevision,
  }) async =>
      await _run(
        () => _repo.updateEnquiry(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          input: input,
          baseRevision: baseRevision,
        ),
      ) !=
      null;

  Future<bool> assign({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String? assignedTo,
  }) async =>
      await _run(
        () => _repo.assignEnquiry(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          assignedTo: assignedTo,
        ),
      ) !=
      null;

  Future<bool> changeStatus({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String status,
    String? reason,
    int? baseRevision,
  }) async =>
      await _run(
        () => _repo.changeStatus(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          status: status,
          reason: reason,
          baseRevision: baseRevision,
        ),
      ) !=
      null;

  /// A fresh idempotency key: a retry of the same save never duplicates.
  static String newRequestId() {
    final r = Random.secure();
    return List.generate(20, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  Future<bool> scheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async =>
      await _run(
        () => _repo.scheduleActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          input: input,
          requestId: requestId,
        ),
      ) !=
      null;

  Future<bool> scheduleVisit({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async =>
      await _run(
        () => _repo.scheduleVisit(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          input: input,
          requestId: requestId,
        ),
      ) !=
      null;

  Future<bool> rescheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required String scheduledDate,
    String? scheduledTime,
    String? reason,
  }) async =>
      await _run(
        () => _repo.rescheduleActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          scheduledDate: scheduledDate,
          scheduledTime: scheduledTime,
          reason: reason,
          baseRevision: activity.revision,
        ),
      ) !=
      null;

  Future<bool> reassignActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required String? assignedTo,
  }) async =>
      await _run(
        () => _repo.reassignActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          assignedTo: assignedTo,
          baseRevision: activity.revision,
        ),
      ) !=
      null;

  Future<bool> cancelActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required String reason,
  }) async =>
      await _run(
        () => _repo.cancelActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          reason: reason,
          baseRevision: activity.revision,
        ),
      ) !=
      null;

  Future<bool> completeActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required AdmissionActivity activity,
    required ActivityCompletion completion,
    ActivityInput? next,
  }) async =>
      await _run<String?>(() async {
        await _repo.completeActivity(
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: enquiryId,
          activityId: activity.id,
          completion: completion,
          next: next,
          baseRevision: activity.revision,
        );
        return 'ok';
      }) !=
      null;

  Future<bool> saveSettings({
    required String schoolId,
    required AdmissionSettings settings,
  }) async =>
      await _run(
        () => _repo.saveSettings(
          schoolId: schoolId,
          settings: settings,
          baseVersion: settings.version,
        ),
      ) !=
      null;
}

final admissionWriteControllerProvider =
    AsyncNotifierProvider.autoDispose<AdmissionWriteController, void>(
      AdmissionWriteController.new,
    );
