import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../academic_setup/domain/holiday.dart';
import '../../academic_setup/domain/weekday.dart';
import '../../academic_setup/domain/working_days.dart';
import '../../attendance/domain/attendance_calendar.dart';
import '../../attendance/domain/attendance_date.dart';
import '../../leave/domain/leave_application.dart';
import '../../leave/domain/leave_enums.dart';
import 'period_set.dart';
import 'timetable.dart';
import 'timetable_enums.dart';
import 'timetable_validation.dart';

/// A date-specific cover for one timetable slot. The timetable itself is
/// never rewritten: the substitution is an override layered over it for one
/// date. `.../substitutions/{dateKey}__{timetableId}__{slotId}` — the id
/// *is* (date, timetable, slot), so a second substitution for the same slot
/// and date is impossible at the database level, and a retry is idempotent.
class Substitution {
  final String substitutionId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String dateKey;
  final String timetableId;
  final int timetableVersion;
  final String entryId;
  final String slotId;
  final Weekday weekday;
  final int periodNumber;
  final int startMin;
  final int endMin;
  final String classId;
  final String sectionId;
  final String? classLabel;
  final String subjectId;
  final String subjectName;
  final String originalTeacherId;
  final String originalTeacherName;
  final String substituteTeacherId;
  final String substituteTeacherName;
  final SubstitutionReasonKind reasonKind;
  final String reason;

  /// Set when the cover is for approved leave; used to re-validate when the
  /// leave changes. Never copied: the leave record is only referenced.
  final String? leaveApplicationId;
  final SubstitutionStatus status;
  final int revision;
  final String? cancelReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const Substitution({
    required this.substitutionId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.dateKey,
    required this.timetableId,
    required this.timetableVersion,
    required this.entryId,
    required this.slotId,
    required this.weekday,
    required this.periodNumber,
    required this.startMin,
    required this.endMin,
    required this.classId,
    required this.sectionId,
    this.classLabel,
    required this.subjectId,
    required this.subjectName,
    required this.originalTeacherId,
    required this.originalTeacherName,
    required this.substituteTeacherId,
    required this.substituteTeacherName,
    required this.reasonKind,
    required this.reason,
    this.leaveApplicationId,
    this.status = SubstitutionStatus.active,
    this.revision = 1,
    this.cancelReason,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  static String idFor(String dateKey, String timetableId, String slotId) =>
      '${dateKey}__${timetableId}__$slotId';

  bool get isActive => status == SubstitutionStatus.active;
  String get timeLabel => MinuteOfDay.range(startMin, endMin);

  factory Substitution.fromFirestore(Map<String, dynamic> d, String id) =>
      Substitution(
        substitutionId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        dateKey: d['dateKey'] as String,
        timetableId: d['timetableId'] as String,
        timetableVersion: (d['timetableVersion'] as num?)?.toInt() ?? 0,
        entryId: d['entryId'] as String,
        slotId: d['slotId'] as String,
        weekday: Weekday.fromWireValue(d['weekday'] as String),
        periodNumber: (d['periodNumber'] as num).toInt(),
        startMin: (d['startMin'] as num).toInt(),
        endMin: (d['endMin'] as num).toInt(),
        classId: d['classId'] as String,
        sectionId: d['sectionId'] as String,
        classLabel: d['classLabel'] as String?,
        subjectId: d['subjectId'] as String,
        subjectName: d['subjectName'] as String? ?? '',
        originalTeacherId: d['originalTeacherId'] as String,
        originalTeacherName: d['originalTeacherName'] as String? ?? '',
        substituteTeacherId: d['substituteTeacherId'] as String,
        substituteTeacherName: d['substituteTeacherName'] as String? ?? '',
        reasonKind: SubstitutionReasonKind.fromWireValue(
          d['reasonKind'] as String? ?? 'OTHER',
        ),
        reason: d['reason'] as String? ?? '',
        leaveApplicationId: d['leaveApplicationId'] as String?,
        status: SubstitutionStatus.fromWireValue(
          d[FirestoreFields.status] as String,
        ),
        revision: (d['revision'] as num?)?.toInt() ?? 1,
        cancelReason: d['cancelReason'] as String?,
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
        createdBy: d[FirestoreFields.createdBy] as String?,
        updatedBy: d[FirestoreFields.updatedBy] as String?,
      );

  Map<String, dynamic> body() => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'dateKey': dateKey,
    'date': AttendanceDate.timestampFor(dateKey),
    'timetableId': timetableId,
    'timetableVersion': timetableVersion,
    'entryId': entryId,
    'slotId': slotId,
    'weekday': weekday.wireValue,
    'periodNumber': periodNumber,
    'startMin': startMin,
    'endMin': endMin,
    'classId': classId,
    'sectionId': sectionId,
    'classLabel': classLabel,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'originalTeacherId': originalTeacherId,
    'originalTeacherName': originalTeacherName,
    'substituteTeacherId': substituteTeacherId,
    'substituteTeacherName': substituteTeacherName,
    'reasonKind': reasonKind.wireValue,
    'reason': reason.trim(),
    'leaveApplicationId': leaveApplicationId,
  };
}

class SubstitutionHistoryEntry {
  final String substitutionId;
  final int revision;
  final SubstitutionEvent event;
  final String substituteTeacherName;
  final String actorId;
  final String actorName;
  final String? note;
  final DateTime? at;

  const SubstitutionHistoryEntry({
    required this.substitutionId,
    required this.revision,
    required this.event,
    required this.substituteTeacherName,
    required this.actorId,
    required this.actorName,
    this.note,
    this.at,
  });

  factory SubstitutionHistoryEntry.fromFirestore(Map<String, dynamic> d) =>
      SubstitutionHistoryEntry(
        substitutionId: d['substitutionId'] as String,
        revision: (d['revision'] as num).toInt(),
        event: SubstitutionEvent.fromWireValue(d['event'] as String),
        substituteTeacherName: d['substituteTeacherName'] as String? ?? '',
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        note: d['note'] as String?,
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}

// ---------------------------------------------------------------------------
// Planning
// ---------------------------------------------------------------------------

/// A scheduled period that falls on a real school day in the range.
class AffectedPeriod {
  final String dateKey;
  final Timetable timetable;
  final TimetableEntry entry;

  /// The substitution already covering it (active or cancelled), if any.
  final Substitution? existing;

  const AffectedPeriod({
    required this.dateKey,
    required this.timetable,
    required this.entry,
    this.existing,
  });

  String get substitutionId =>
      Substitution.idFor(dateKey, timetable.timetableId, entry.slotId);
  bool get isCovered => existing != null && existing!.isActive;
}

class StaffLite {
  final String staffId;
  final String name;
  final String? userId;

  const StaffLite({required this.staffId, required this.name, this.userId});
}

class SubstituteCandidate {
  final StaffLite staff;
  final bool eligible;
  final bool teachesSubject;
  final bool teachesClass;
  final List<String> reasons;

  const SubstituteCandidate({
    required this.staff,
    required this.eligible,
    required this.teachesSubject,
    required this.teachesClass,
    this.reasons = const [],
  });

  /// Suggestions only: lists the best-fitting eligible people first. The
  /// admin always confirms; nothing is assigned automatically.
  int get rank => !eligible ? 3 : (teachesSubject ? 0 : (teachesClass ? 1 : 2));
}

abstract final class SubstitutionPlanner {
  /// Periods [teacherId] is scheduled to teach between [fromKey] and [toKey]
  /// on real school days, under the version applicable on each date.
  static List<AffectedPeriod> affected({
    required String teacherId,
    required String fromKey,
    required String toKey,
    required List<TimetableBundle> published,
    required WorkingDays workingDays,
    required Iterable<Holiday> calendarEntries,
    required Iterable<Substitution> substitutions,
  }) {
    final result = <AffectedPeriod>[];
    final subs = {for (final s in substitutions) s.substitutionId: s};
    final bundles = {for (final b in published) b.timetable.timetableId: b};
    for (final dateKey in AttendanceDate.keysBetween(fromKey, toKey)) {
      final date = AttendanceDate.parse(dateKey);
      final info = AttendanceCalendar.evaluate(
        date: date,
        workingDays: workingDays,
        calendarEntries: calendarEntries,
      );
      if (!info.isSchoolDay) continue;
      final wd = Weekday.fromDateTimeWeekday(date.weekday);
      final applicable = TimetableResolver.allOn(
        published.map((b) => b.timetable),
        dateKey,
      );
      for (final t in applicable) {
        final b = bundles[t.timetableId]!;
        for (final e in b.entries) {
          if (e.weekday != wd || e.teacherStaffId != teacherId) continue;
          final id = Substitution.idFor(dateKey, t.timetableId, e.slotId);
          result.add(
            AffectedPeriod(
              dateKey: dateKey,
              timetable: t,
              entry: e,
              existing: subs[id],
            ),
          );
        }
      }
    }
    result.sort((a, b) {
      final c = a.dateKey.compareTo(b.dateKey);
      return c != 0 ? c : a.entry.startMin.compareTo(b.entry.startMin);
    });
    return result;
  }

  /// Everyone considered for covering [period], with why not when ineligible.
  ///
  /// A person is eligible when they are an active teacher, are not the
  /// original teacher, are *qualified* (teach this subject somewhere, or
  /// teach in this class), have no regular period overlapping that slot on
  /// that date (a period already covered by someone else counts as free),
  /// no overlapping substitution of their own, and no approved leave that
  /// day. Half-day leave blocks the whole day for covering purposes.
  static List<SubstituteCandidate> candidates({
    required AffectedPeriod period,
    required List<StaffLite> activeTeachers,
    required List<AssignmentFact> yearAssignments,
    required List<TimetableBundle> published,
    required Iterable<Substitution> substitutionsOnDate,
    required List<LeaveCalendarEntry> staffLeave,
    String? ignoreSubstitutionId,
  }) {
    final e = period.entry;
    final date = AttendanceDate.parse(period.dateKey);
    final wd = Weekday.fromDateTimeWeekday(date.weekday);
    final applicable = {
      for (final t in TimetableResolver.allOn(
        published.map((b) => b.timetable),
        period.dateKey,
      ))
        t.timetableId,
    };
    final activeSubs = [
      for (final s in substitutionsOnDate)
        if (s.isActive && s.substitutionId != ignoreSubstitutionId) s,
    ];
    // Periods that are covered by someone else are free for their teacher.
    final coveredIds = {for (final s in activeSubs) s.substitutionId};
    final onLeave = <String>{
      for (final l in staffLeave)
        if (l.active &&
            l.kind == LeaveKind.staff &&
            l.countedDateKeys.contains(period.dateKey))
          l.subjectId,
    };

    final result = <SubstituteCandidate>[];
    for (final staff in activeTeachers) {
      final reasons = <String>[];
      if (staff.staffId == e.teacherStaffId) {
        reasons.add('This is the teacher being replaced.');
      }
      final teachesSubject = yearAssignments.any(
        (a) =>
            a.teacherStaffId == staff.staffId &&
            !a.isClassTeacher &&
            a.subjectId == e.subjectId,
      );
      final teachesClass = yearAssignments.any(
        (a) => a.teacherStaffId == staff.staffId && a.classId == e.classId,
      );
      if (!teachesSubject && !teachesClass) {
        reasons.add(
          'Does not teach ${e.subjectName} or any subject in this class.',
        );
      }
      if (onLeave.contains(staff.staffId)) {
        reasons.add('Has approved leave on this date.');
      }
      for (final b in published) {
        if (!applicable.contains(b.timetable.timetableId)) continue;
        for (final o in b.entries) {
          if (o.teacherStaffId != staff.staffId || o.weekday != wd) continue;
          if (!MinuteOfDay.overlaps(
            o.startMin,
            o.endMin,
            e.startMin,
            e.endMin,
          )) {
            continue;
          }
          final id = Substitution.idFor(
            period.dateKey,
            b.timetable.timetableId,
            o.slotId,
          );
          if (coveredIds.contains(id)) continue; // someone else covers it
          reasons.add(
            'Teaches ${b.timetable.title} ${o.subjectName} in period '
            '${o.periodNumber} (${o.timeLabel}).',
          );
        }
      }
      for (final s in activeSubs) {
        if (s.substituteTeacherId != staff.staffId) continue;
        if (s.substitutionId == period.substitutionId) continue;
        if (MinuteOfDay.overlaps(s.startMin, s.endMin, e.startMin, e.endMin)) {
          reasons.add(
            'Already covering ${s.classLabel ?? s.classId} period '
            '${s.periodNumber} (${s.timeLabel}).',
          );
        }
      }
      result.add(
        SubstituteCandidate(
          staff: staff,
          eligible: reasons.isEmpty,
          teachesSubject: teachesSubject,
          teachesClass: teachesClass,
          reasons: reasons,
        ),
      );
    }
    result.sort((a, b) {
      final c = a.rank.compareTo(b.rank);
      return c != 0 ? c : a.staff.name.compareTo(b.staff.name);
    });
    return result;
  }
}

/// Re-validation of an existing substitution against the world as it is now.
/// Leave approval and substitution stay separate operations: this only
/// *reports* — it never edits either record.
enum SubstitutionWarning {
  leaveNoLongerApproved(
    'The leave this cover was arranged for is no longer approved.',
  ),
  substituteOnLeave('The substitute now has approved leave on this date.'),
  timetableChanged(
    'The timetable this cover belongs to is no longer in force.',
  ),
  teacherChanged('The period now has a different regular teacher.');

  final String message;
  const SubstitutionWarning(this.message);
}

abstract final class SubstitutionHealth {
  static List<SubstitutionWarning> check({
    required Substitution substitution,
    required List<LeaveCalendarEntry> staffLeave,
    required Iterable<Timetable> published,
    Iterable<TimetableBundle> bundles = const [],
  }) {
    if (!substitution.isActive) return const [];
    final s = substitution;
    final warnings = <SubstitutionWarning>[];
    if (s.leaveApplicationId != null) {
      final stillOn = staffLeave.any(
        (l) =>
            l.active &&
            l.applicationId == s.leaveApplicationId &&
            l.countedDateKeys.contains(s.dateKey),
      );
      if (!stillOn) warnings.add(SubstitutionWarning.leaveNoLongerApproved);
    }
    final subOnLeave = staffLeave.any(
      (l) =>
          l.active &&
          l.kind == LeaveKind.staff &&
          l.subjectId == s.substituteTeacherId &&
          l.countedDateKeys.contains(s.dateKey),
    );
    if (subOnLeave) warnings.add(SubstitutionWarning.substituteOnLeave);
    final stillInForce = published.any(
      (t) => t.timetableId == s.timetableId && t.coversDate(s.dateKey),
    );
    if (!stillInForce) warnings.add(SubstitutionWarning.timetableChanged);
    for (final b in bundles) {
      if (b.timetable.timetableId != s.timetableId) continue;
      final cell = b.entries.where((e) => e.entryId == s.entryId).firstOrNull;
      if (cell != null && cell.teacherStaffId != s.originalTeacherId) {
        warnings.add(SubstitutionWarning.teacherChanged);
      }
    }
    return warnings;
  }
}
