import '../../academic_setup/domain/weekday.dart';
import '../../attendance/domain/attendance_date.dart';
import '../../leave/domain/leave_application.dart';
import '../../leave/domain/leave_enums.dart';
import 'period_set.dart';
import 'timetable.dart';
import 'timetable_enums.dart';

class TimetableBundle {
  final Timetable timetable;
  final List<TimetableEntry> entries;

  const TimetableBundle(this.timetable, this.entries);
}

/// What the M4 assignments say a teacher may teach: an ACTIVE subject (or
/// class-teacher) assignment to a section.
class AssignmentFact {
  final String teacherStaffId;
  final String classId;
  final String sectionId;
  final String? subjectId;
  final bool isClassTeacher;

  const AssignmentFact({
    required this.teacherStaffId,
    required this.classId,
    required this.sectionId,
    this.subjectId,
    this.isClassTeacher = false,
  });
}

class TimetableIssue {
  final IssueSeverity severity;
  final IssueKind kind;
  final String message;
  final Weekday? weekday;
  final String? slotId;
  final String? teacherStaffId;
  final String? otherTimetableId;

  const TimetableIssue({
    required this.severity,
    required this.kind,
    required this.message,
    this.weekday,
    this.slotId,
    this.teacherStaffId,
    this.otherTimetableId,
  });

  bool get isError => severity == IssueSeverity.error;
}

/// Every check a timetable must pass before it can be published, as one pure
/// function — the editor shows its result, the publish action refuses on its
/// errors, and the tests drive it directly.
///
/// **Where this is and isn't enforced.** The publish transaction re-reads the
/// published set under the branch publication lock and refuses a stale
/// validation, so two admins cannot publish conflicting timetables
/// concurrently. `firestore.rules` independently enforce the state machine,
/// the lock bump, and that every entry's teacher really holds the section's
/// ACTIVE assignment for that subject. Rules cannot *query* the other
/// published timetables, so "no teacher double-booking" itself is verified by
/// this function (under the lock), not by rules — see the milestone doc.
abstract final class TimetableValidator {
  static List<TimetableIssue> validate({
    required TimetableBundle candidate,
    required Map<String, PeriodSet> periodSets,
    required Set<String> workingWeekdays,
    required List<TimetableBundle> otherPublished,
    required List<AssignmentFact> sectionAssignments,
    required Set<String> activeTeacherIds,
    List<LeaveCalendarEntry> staffLeave = const [],
  }) {
    final t = candidate.timetable;
    final entries = candidate.entries;
    final issues = <TimetableIssue>[];

    String when(TimetableEntry e) =>
        '${e.weekday.displayName} period ${e.periodNumber} (${e.timeLabel})';

    if (entries.isEmpty) {
      issues.add(
        const TimetableIssue(
          severity: IssueSeverity.error,
          kind: IssueKind.empty,
          message: 'No teaching period has a subject and teacher yet.',
        ),
      );
    }

    for (final wd in t.dayPeriodSets.keys) {
      if (!workingWeekdays.contains(wd)) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.error,
            kind: IssueKind.nonWorkingDay,
            message:
                '${Weekday.fromWireValue(wd).displayName} is not a working '
                'day of this branch.',
            weekday: Weekday.fromWireValue(wd),
          ),
        );
      }
      if (!periodSets.containsKey(t.dayPeriodSets[wd])) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.error,
            kind: IssueKind.missingPeriodSet,
            message:
                '${Weekday.fromWireValue(wd).displayName} uses a period '
                'schedule that no longer exists.',
            weekday: Weekday.fromWireValue(wd),
          ),
        );
      }
    }

    final byTeacherSubject = {
      for (final a in sectionAssignments)
        if (!a.isClassTeacher &&
            a.subjectId != null &&
            a.classId == t.classId &&
            a.sectionId == t.sectionId)
          a.subjectId!: a.teacherStaffId,
    };

    for (final e in entries) {
      final setId = t.dayPeriodSets[e.weekday.wireValue];
      if (setId == null) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.error,
            kind: IssueKind.nonWorkingDay,
            message: '${when(e)} is on a day this timetable does not cover.',
            weekday: e.weekday,
            slotId: e.slotId,
          ),
        );
        continue;
      }
      final set = periodSets[setId];
      final slot = set?.slot(e.slotId);
      if (set != null && (slot == null || !slot.isTeaching)) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.error,
            kind: IssueKind.invalidSlot,
            message:
                '${e.weekday.displayName}: the slot "${e.slotId}" is not a '
                'teaching period of "${set.name}".',
            weekday: e.weekday,
            slotId: e.slotId,
          ),
        );
      } else if (slot != null &&
          (slot.startMin != e.startMin || slot.endMin != e.endMin)) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.error,
            kind: IssueKind.stalePeriods,
            message:
                '${when(e)} no longer matches the schedule "${set!.name}" '
                '(${slot.timeLabel}). Re-save the period.',
            weekday: e.weekday,
            slotId: e.slotId,
          ),
        );
      }
      if (byTeacherSubject[e.subjectId] != e.teacherStaffId ||
          !activeTeacherIds.contains(e.teacherStaffId)) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.error,
            kind: IssueKind.notAssigned,
            message:
                '${when(e)}: ${e.teacherName} is not the active teacher '
                'assigned to ${e.subjectName} for ${t.title}.',
            weekday: e.weekday,
            slotId: e.slotId,
            teacherStaffId: e.teacherStaffId,
          ),
        );
      }
    }

    // ---- teacher / room conflicts: inside the timetable, then against others
    bool timesOverlap(TimetableEntry a, TimetableEntry b) =>
        a.weekday == b.weekday &&
        MinuteOfDay.overlaps(a.startMin, a.endMin, b.startMin, b.endMin);

    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i];
        final b = entries[j];
        if (!timesOverlap(a, b)) continue;
        if (a.teacherStaffId == b.teacherStaffId) {
          issues.add(
            TimetableIssue(
              severity: IssueSeverity.error,
              kind: IssueKind.teacherConflict,
              message:
                  '${a.teacherName} is in two overlapping periods on '
                  '${a.weekday.displayName}: period ${a.periodNumber} and '
                  'period ${b.periodNumber}.',
              weekday: a.weekday,
              teacherStaffId: a.teacherStaffId,
            ),
          );
        }
      }
    }

    final sameKey = t.sectionKeyValue;
    for (final other in otherPublished) {
      final o = other.timetable;
      if (o.timetableId == t.timetableId) continue;
      if (!o.overlapsRange(t.effectiveFromKey, t.effectiveToKey)) continue;
      if (o.sectionKeyValue == sameKey) {
        issues.add(
          TimetableIssue(
            severity: IssueSeverity.warning,
            kind: IssueKind.sectionOverlap,
            message:
                'Published version v${o.version} of ${o.title} runs '
                '${_fmt(o.effectiveFromKey)}–'
                '${o.effectiveToKey == null ? 'open' : _fmt(o.effectiveToKey!)}. '
                'Publishing this will '
                '${o.effectiveFromKey.compareTo(t.effectiveFromKey) >= 0 ? 'replace' : 'end'} it.',
            otherTimetableId: o.timetableId,
          ),
        );
        continue; // same section's other versions never conflict: they are replaced
      }
      for (final a in entries) {
        for (final b in other.entries) {
          if (!timesOverlap(a, b)) continue;
          if (a.teacherStaffId == b.teacherStaffId) {
            issues.add(
              TimetableIssue(
                severity: IssueSeverity.error,
                kind: IssueKind.teacherConflict,
                message:
                    '${a.teacherName} is already teaching ${o.title} '
                    '${b.subjectName} on ${a.weekday.displayName} period '
                    '${b.periodNumber} (${b.timeLabel}), which overlaps '
                    'period ${a.periodNumber} (${a.timeLabel}) of ${t.title}.',
                weekday: a.weekday,
                slotId: a.slotId,
                teacherStaffId: a.teacherStaffId,
                otherTimetableId: o.timetableId,
              ),
            );
          }
          if (a.roomKey.isNotEmpty && a.roomKey == b.roomKey) {
            issues.add(
              TimetableIssue(
                severity: IssueSeverity.error,
                kind: IssueKind.roomConflict,
                message:
                    'Room "${a.room}" is also used by ${o.title} on '
                    '${a.weekday.displayName} period ${b.periodNumber} '
                    '(${b.timeLabel}).',
                weekday: a.weekday,
                slotId: a.slotId,
                otherTimetableId: o.timetableId,
              ),
            );
          }
        }
      }
    }

    // ---- approved leave: informational, a substitution will be needed -------
    if (staffLeave.isNotEmpty) {
      final entriesByTeacher = <String, List<TimetableEntry>>{};
      for (final e in entries) {
        (entriesByTeacher[e.teacherStaffId] ??= []).add(e);
      }
      for (final leave in staffLeave) {
        if (!leave.active || leave.kind != LeaveKind.staff) continue;
        final mine = entriesByTeacher[leave.subjectId];
        if (mine == null) continue;
        final hit = <String>[];
        for (final d in leave.countedDateKeys) {
          if (!t.coversDate(d)) continue;
          final wd = Weekday.fromDateTimeWeekday(
            AttendanceDate.parse(d).weekday,
          );
          if (mine.any((e) => e.weekday == wd)) hit.add(d);
        }
        if (hit.isNotEmpty) {
          issues.add(
            TimetableIssue(
              severity: IssueSeverity.warning,
              kind: IssueKind.teacherOnLeave,
              message:
                  '${mine.first.teacherName} has approved leave on '
                  '${hit.map(_fmt).join(', ')} during this timetable — '
                  'those periods will need a substitute.',
              teacherStaffId: leave.subjectId,
            ),
          );
        }
      }
    }
    return issues;
  }

  static String _fmt(String key) {
    final p = key.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
  }
}

/// Which published version applies on a date.
abstract final class TimetableResolver {
  /// The version of one section applicable on [dateKey], or null.
  static Timetable? forSectionOn(
    Iterable<Timetable> published,
    String sectionKey,
    String dateKey,
  ) {
    Timetable? best;
    for (final t in published) {
      if (!t.isPublished || t.sectionKeyValue != sectionKey) continue;
      if (!t.coversDate(dateKey)) continue;
      if (best == null || t.version > best.version) best = t;
    }
    return best;
  }

  /// One applicable version per section on [dateKey].
  static List<Timetable> allOn(Iterable<Timetable> published, String dateKey) {
    final bySection = <String, Timetable>{};
    for (final t in published) {
      if (!t.isPublished || !t.coversDate(dateKey)) continue;
      final cur = bySection[t.sectionKeyValue];
      if (cur == null || t.version > cur.version) {
        bySection[t.sectionKeyValue] = t;
      }
    }
    return bySection.values.toList();
  }
}

/// What publishing [candidate] does to the same section's published versions.
class SupersessionPlan {
  /// Versions fully replaced: archived.
  final List<Timetable> archive;

  /// Versions that started earlier: their end date is cut to the day before.
  final List<({Timetable timetable, String newEndKey})> truncate;

  const SupersessionPlan({required this.archive, required this.truncate});

  bool get isEmpty => archive.isEmpty && truncate.isEmpty;
}

abstract final class TimetablePublication {
  static SupersessionPlan planSupersession(
    Timetable candidate,
    Iterable<Timetable> published,
  ) {
    final archive = <Timetable>[];
    final truncate = <({Timetable timetable, String newEndKey})>[];
    for (final p in published) {
      if (!p.isPublished || p.timetableId == candidate.timetableId) continue;
      if (p.sectionKeyValue != candidate.sectionKeyValue) continue;
      if (!p.overlapsRange(
        candidate.effectiveFromKey,
        candidate.effectiveToKey,
      )) {
        continue;
      }
      if (p.effectiveFromKey.compareTo(candidate.effectiveFromKey) >= 0) {
        archive.add(p);
      } else {
        final end = AttendanceDate.parse(candidate.effectiveFromKey);
        final dayBefore = AttendanceDate.key(
          DateTime.utc(end.year, end.month, end.day - 1),
        );
        truncate.add((timetable: p, newEndKey: dayBefore));
      }
    }
    return SupersessionPlan(archive: archive, truncate: truncate);
  }

  /// Why [t] cannot be published right now, or null.
  static String? checkPublish(Timetable t, List<TimetableIssue> issues) {
    if (!t.isDraft) {
      return 'Only a draft can be published; this one is '
          '${t.status.displayName.toLowerCase()}.';
    }
    final errors = issues.where((i) => i.isError).toList();
    if (errors.isNotEmpty) {
      return '${errors.length} problem${errors.length == 1 ? '' : 's'} must '
          'be fixed before publishing.';
    }
    return null;
  }
}
