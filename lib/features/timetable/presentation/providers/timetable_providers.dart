import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../academic_setup/domain/subject.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../leave/domain/leave_application.dart';
import '../../../leave/domain/leave_enums.dart';
import '../../../leave/presentation/providers/leave_providers.dart';
import '../../../staff/domain/staff_status.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_timetable_repositories.dart';
import '../../domain/period_set.dart';
import '../../domain/substitution.dart';
import '../../domain/timetable.dart';
import '../../domain/timetable_repositories.dart';
import '../../domain/timetable_validation.dart';

final periodSetRepositoryProvider = Provider<PeriodSetRepository>(
  (ref) => FirebasePeriodSetRepository(ref.watch(firestoreProvider)),
);
final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => FirebaseTimetableRepository(ref.watch(firestoreProvider)),
);
final substitutionRepositoryProvider = Provider<SubstitutionRepository>(
  (ref) => FirebaseSubstitutionRepository(ref.watch(firestoreProvider)),
);

typedef TimetableYearKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
});
typedef TimetableIdKey = ({
  String schoolId,
  String branchId,
  String timetableId,
});
typedef TimetableSectionKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String classId,
  String sectionId,
});
typedef TimetableTeacherKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String teacherStaffId,
});
typedef SubstitutionRangeKey = ({
  String schoolId,
  String branchId,
  String fromKey,
  String toKey,
});

final periodSetsProvider = StreamProvider.autoDispose
    .family<List<PeriodSet>, TimetableYearKey>((ref, key) {
      return ref
          .watch(periodSetRepositoryProvider)
          .watchPeriodSets(key.schoolId, key.branchId, key.academicYearId);
    });

final timetablesProvider = StreamProvider.autoDispose
    .family<List<Timetable>, TimetableYearKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .watchTimetables(key.schoolId, key.branchId, key.academicYearId);
    });

final timetableProvider = StreamProvider.autoDispose
    .family<Timetable?, TimetableIdKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .watchTimetable(key.schoolId, key.branchId, key.timetableId);
    });

final timetableEntriesProvider = FutureProvider.autoDispose
    .family<List<TimetableEntry>, TimetableIdKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .fetchEntries(key.schoolId, key.branchId, key.timetableId);
    });

final publishedBundlesProvider = FutureProvider.autoDispose
    .family<List<TimetableBundle>, TimetableYearKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .fetchPublished(key.schoolId, key.branchId, key.academicYearId);
    });

final sectionBundlesProvider = FutureProvider.autoDispose
    .family<List<TimetableBundle>, TimetableSectionKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .fetchPublishedForSection(
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            classId: key.classId,
            sectionId: key.sectionId,
          );
    });

final teacherBundlesProvider = FutureProvider.autoDispose
    .family<List<TimetableBundle>, TimetableTeacherKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .fetchPublishedForTeacher(
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            teacherStaffId: key.teacherStaffId,
          );
    });

final substitutionsRangeProvider = FutureProvider.autoDispose
    .family<List<Substitution>, SubstitutionRangeKey>((ref, key) {
      return ref
          .watch(substitutionRepositoryProvider)
          .fetchRange(
            schoolId: key.schoolId,
            branchId: key.branchId,
            fromKey: key.fromKey,
            toKey: key.toKey,
          );
    });

final timetableHistoryProvider = StreamProvider.autoDispose
    .family<List<TimetableHistoryEntry>, TimetableYearKey>((ref, key) {
      return ref
          .watch(timetableRepositoryProvider)
          .watchHistory(key.schoolId, key.branchId, key.academicYearId);
    });

/// Every ACTIVE assignment of the year (all pages) as plain facts.
final yearAssignmentsProvider = FutureProvider.autoDispose
    .family<List<AssignmentFact>, TimetableYearKey>((ref, key) async {
      final repo = ref.watch(teacherAssignmentRepositoryProvider);
      final facts = <AssignmentFact>[];
      Object? cursor;
      do {
        final page = await repo.fetchActiveAssignments(
          schoolId: key.schoolId,
          branchId: key.branchId,
          academicYearId: key.academicYearId,
          pageSize: 100,
          cursor: cursor,
        );
        for (final a in page.items) {
          facts.add(
            AssignmentFact(
              teacherStaffId: a.teacherStaffId,
              classId: a.classId,
              sectionId: a.sectionId,
              subjectId: a.subjectId,
              isClassTeacher: a.isClassTeacher,
            ),
          );
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      return facts;
    });

/// The branch's ACTIVE teachers (all pages).
final activeTeachersProvider = FutureProvider.autoDispose
    .family<List<StaffLite>, BranchKey>((ref, key) async {
      final repo = ref.watch(staffRepositoryProvider);
      final result = <StaffLite>[];
      Object? cursor;
      do {
        final page = await repo.fetchStaff(
          schoolId: key.schoolId,
          branchId: key.branchId,
          status: StaffStatus.active,
          isTeacher: true,
          pageSize: 100,
          cursor: cursor,
        );
        for (final s in page.items) {
          result.add(
            StaffLite(
              staffId: s.staffId,
              name: s.displayName,
              userId: s.userId,
            ),
          );
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      return result;
    });

/// Approved staff leave overlapping a range (cancelled entries included, so a
/// cancellation is visible to re-validation).
typedef StaffLeaveRangeKey = ({
  String schoolId,
  String branchId,
  String fromKey,
  String toKey,
});

final staffLeaveRangeProvider = FutureProvider.autoDispose
    .family<List<LeaveCalendarEntry>, StaffLeaveRangeKey>((ref, key) {
      return ref
          .watch(leaveCalendarRepositoryProvider)
          .fetch(
            schoolId: key.schoolId,
            branchId: key.branchId,
            kind: LeaveKind.staff,
            fromKey: key.fromKey,
            toKey: key.toKey,
          );
    });

final yearSubjectsProvider = Provider.autoDispose
    .family<AsyncValue<Map<String, Subject>>, TimetableYearKey>((ref, key) {
      return ref
          .watch(
            subjectsProvider((
              schoolId: key.schoolId,
              branchId: key.branchId,
              academicYearId: key.academicYearId,
            )),
          )
          .whenData((list) => {for (final s in list) s.subjectId: s});
    });

/// Reads an auto-dispose provider's value from imperative code (a button
/// handler) and keeps it alive until it has loaded.
///
/// `ref.read(provider.future)` on an auto-dispose provider that nothing is
/// watching can be disposed while still loading ("disposed during loading
/// state"), which surfaces as a failed action. Listening for the duration of
/// the read prevents that.
Future<T> readAlive<T>(
  WidgetRef ref,
  ProviderListenable<AsyncValue<T>> provider,
) {
  final completer = Completer<T>();
  ProviderSubscription<AsyncValue<T>>? sub;
  void handle(AsyncValue<T> value) {
    if (completer.isCompleted) return;
    if (value.hasError) {
      completer.completeError(value.error!, value.stackTrace);
    } else if (value.hasValue && !value.isLoading) {
      completer.complete(value.requireValue);
    }
  }

  sub = ref.listenManual<AsyncValue<T>>(
    provider,
    (_, next) => handle(next),
    fireImmediately: true,
  );
  return completer.future.whenComplete(() => sub?.close());
}

typedef SubstitutionHistoryKey = ({
  String schoolId,
  String branchId,
  String substitutionId,
});

final substitutionHistoryProvider = StreamProvider.autoDispose
    .family<List<SubstitutionHistoryEntry>, SubstitutionHistoryKey>((ref, key) {
      return ref
          .watch(substitutionRepositoryProvider)
          .watchHistory(key.schoolId, key.branchId, key.substitutionId);
    });
