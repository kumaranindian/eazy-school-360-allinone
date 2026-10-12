import '../../academic_setup/domain/weekday.dart';
import 'period_set.dart';
import 'timetable.dart';

/// Who teaches which subject in a section (from its ACTIVE assignments).
class SectionTeacher {
  final String teacherStaffId;
  final String teacherName;

  const SectionTeacher(this.teacherStaffId, this.teacherName);
}

class CopyResult {
  final List<TimetableEntry> entries;

  /// Cells that could not be carried over and why (shown to the user).
  final List<String> skipped;

  const CopyResult(this.entries, this.skipped);
}

/// Pure helpers behind "copy a day" and "copy to another section". A copy is
/// always re-validated by the normal validator before it can be published —
/// these only map cells sensibly.
abstract final class TimetableCopier {
  /// Copies [day]'s cells onto [targets]. A slot is matched by id when the
  /// target day's schedule has it as a teaching slot, otherwise by period
  /// number; cells with no counterpart are skipped. Existing cells on a target
  /// day are replaced.
  static CopyResult copyDay({
    required Timetable timetable,
    required List<TimetableEntry> entries,
    required Weekday day,
    required List<Weekday> targets,
    required Map<String, PeriodSet> periodSets,
  }) {
    final result = <TimetableEntry>[];
    final skipped = <String>[];
    final source = [
      for (final e in entries)
        if (e.weekday == day) e,
    ];
    for (final target in targets) {
      if (target == day) continue;
      final setId = timetable.dayPeriodSets[target.wireValue];
      final set = setId == null ? null : periodSets[setId];
      if (set == null) {
        skipped.add('${target.displayName}: no period schedule is set.');
        continue;
      }
      for (final e in source) {
        PeriodSlot? slot = set.slot(e.slotId);
        if (slot == null || !slot.isTeaching) {
          slot = set.teachingSlots
              .where((s) => s.number == e.periodNumber)
              .firstOrNull;
        }
        if (slot == null) {
          skipped.add(
            '${target.displayName}: no period ${e.periodNumber} to copy '
            '${e.subjectName} into.',
          );
          continue;
        }
        result.add(
          e.copyWith(
            weekday: target,
            slotId: slot.slotId,
            periodNumber: slot.number!,
            startMin: slot.startMin,
            endMin: slot.endMin,
            live: false,
          ),
        );
      }
    }
    return CopyResult(result, skipped);
  }

  /// Re-targets [entries] at another section: each subject keeps its cell, the
  /// teacher becomes whoever is assigned to that subject in the target
  /// section. Subjects the target does not teach are skipped, never guessed.
  static CopyResult toSection({
    required List<TimetableEntry> entries,
    required Timetable target,
    required Map<String, SectionTeacher> teacherBySubject,
  }) {
    final result = <TimetableEntry>[];
    final skipped = <String>[];
    for (final e in entries) {
      final teacher = teacherBySubject[e.subjectId];
      if (teacher == null) {
        skipped.add(
          '${e.weekday.displayName} period ${e.periodNumber}: '
          '${target.title} has no assigned teacher for ${e.subjectName}.',
        );
        continue;
      }
      result.add(
        e.copyWith(
          timetableId: target.timetableId,
          classId: target.classId,
          sectionId: target.sectionId,
          teacherStaffId: teacher.teacherStaffId,
          teacherName: teacher.teacherName,
          clearRoom: true,
          live: false,
        ),
      );
    }
    return CopyResult(result, skipped);
  }
}
