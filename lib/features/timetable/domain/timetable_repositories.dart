import 'period_set.dart';
import 'substitution.dart';
import 'timetable.dart';
import 'timetable_enums.dart';
import 'timetable_validation.dart';

class TimetableActor {
  final String userId;
  final String name;

  const TimetableActor({required this.userId, required this.name});
}

/// Who should be told that something changed (resolved by the caller).
class Recipient {
  final String userId;
  final String staffId;
  final String name;

  const Recipient({
    required this.userId,
    required this.staffId,
    required this.name,
  });
}

abstract class PeriodSetRepository {
  Stream<List<PeriodSet>> watchPeriodSets(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  Future<void> savePeriodSet(
    PeriodSet set, {
    required bool isNew,
    required String actorId,
  });
}

abstract class TimetableRepository {
  /// Every version in the year, any status (admin screens).
  Stream<List<Timetable>> watchTimetables(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  Stream<Timetable?> watchTimetable(
    String schoolId,
    String branchId,
    String timetableId,
  );

  Future<List<TimetableEntry>> fetchEntries(
    String schoolId,
    String branchId,
    String timetableId,
  );

  /// PUBLISHED timetables of the year with their live entries.
  Future<List<TimetableBundle>> fetchPublished(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  /// The published timetables of one section (any effective range) with
  /// their live entries — the class/section and parent views.
  Future<List<TimetableBundle>> fetchPublishedForSection({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
  });

  /// A teacher's live entries (with the published timetables they belong
  /// to) — the personal timetable.
  Future<List<TimetableBundle>> fetchPublishedForTeacher({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String teacherStaffId,
  });

  /// The publication-lock sequence; a publish validated against a snapshot
  /// taken at a different sequence is refused.
  Future<int> publishSequence(String schoolId, String branchId);

  /// Creates the next version of a section's timetable as a DRAFT. The
  /// version number is assigned inside the transaction.
  Future<Timetable> createDraft({
    required Timetable template,
    required List<TimetableEntry> entries,
    required TimetableActor actor,
  });

  /// Applies a draft edit: metadata plus only the entries that changed.
  Future<void> saveDraft({
    required Timetable timetable,
    required List<TimetableEntry> upserts,
    required List<TimetableEntry> removals,
    required List<String> teacherIds,
    required int entryCount,
    required TimetableActor actor,
  });

  /// Publishes [timetable] atomically. [expectedSequence] is the lock
  /// sequence the validation was run against. [recipients] are notified.
  Future<void> publish({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    required SupersessionPlan supersession,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  });

  /// Withdraws a published timetable (or discards a draft).
  Future<void> archive({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    required String reason,
    required TimetableActor actor,
  });

  Stream<List<TimetableHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String academicYearId,
  );
}

abstract class SubstitutionRepository {
  Future<List<Substitution>> fetchRange({
    required String schoolId,
    required String branchId,
    required String fromKey,
    required String toKey,
  });

  Future<List<Substitution>> fetchForTeacher({
    required String schoolId,
    required String branchId,
    required String teacherStaffId,
    required String fromKey,
    required String toKey,
  });

  Future<List<Substitution>> fetchForSection({
    required String schoolId,
    required String branchId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  });

  /// The substitution day sequence; assignments validated against another
  /// sequence are refused.
  Future<int> daySequence(String schoolId, String branchId, String dateKey);

  /// Creates, or reinstates a cancelled, cover for one slot and date.
  Future<void> assign({
    required Substitution substitution,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  });

  Future<void> change({
    required Substitution current,
    required String substituteTeacherId,
    required String substituteTeacherName,
    required String reason,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  });

  Future<void> cancel({
    required Substitution current,
    required String reason,
    required int expectedSequence,
    required List<Recipient> recipients,
    required TimetableActor actor,
  });

  Stream<List<SubstitutionHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String substitutionId,
  );
}

extension TimetableStatusX on TimetableStatus {
  bool get isLive => this == TimetableStatus.published;
}
