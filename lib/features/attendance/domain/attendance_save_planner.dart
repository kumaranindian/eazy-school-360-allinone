import 'attendance_sheet.dart';
import 'attendance_status.dart';
import 'attendance_tally.dart';

/// What a transaction just read for one entry.
class CurrentAttendance {
  final int revision;
  final AttendanceStatus status;
  final String? remarks;
  final String? sectionId;

  const CurrentAttendance({
    required this.revision,
    required this.status,
    this.remarks,
    this.sectionId,
  });
}

class PlannedWrite {
  final AttendanceEntry entry;
  final AttendanceStatus newStatus;
  final String? newRemarks;
  final AttendanceStatus? previousStatus;
  final String? previousRemarks;
  final int newRevision;

  const PlannedWrite({
    required this.entry,
    required this.newStatus,
    required this.newRemarks,
    required this.previousStatus,
    required this.previousRemarks,
    required this.newRevision,
  });

  bool get isNew => newRevision == 1;
}

class SavePlan {
  /// Entries whose stored data changed since the user loaded them (or that
  /// are already recorded elsewhere). When non-empty nothing may be written.
  final List<String> conflicts;
  final List<PlannedWrite> writes;

  /// Counts for the whole register after the writes.
  final AttendanceTally resultingTally;

  const SavePlan({
    required this.conflicts,
    required this.writes,
    required this.resultingTally,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Turns "what the user edited" + "what the transaction just read" into the
/// exact writes — the optimistic-concurrency decision, as a pure function.
///
/// - If a stored revision differs from the one the user loaded, someone else
///   changed it: a conflict, and nothing is written.
/// - A student already stored under another section on this date is a
///   conflict too (one authoritative record per student per day).
/// - Only entries that actually changed are written, which keeps a class
///   save to a handful of writes instead of one per student.
abstract final class AttendanceSavePlanner {
  static SavePlan plan({
    required List<AttendanceEntry> entries,
    required Map<String, CurrentAttendance?> current,
    String? sectionId,
  }) {
    final conflicts = <String>[];
    final writes = <PlannedWrite>[];
    final finalStatuses = <AttendanceStatus?>[];

    for (final entry in entries) {
      final stored = current[entry.subjectId];

      if (stored == null && entry.isSaved) {
        conflicts.add(entry.name);
        finalStatuses.add(entry.status);
        continue;
      }
      if (stored != null) {
        final changedMeanwhile = stored.revision != entry.savedRevision;
        final elsewhere =
            !entry.isSaved &&
            sectionId != null &&
            stored.sectionId != null &&
            stored.sectionId != sectionId;
        if (changedMeanwhile || elsewhere) {
          conflicts.add(entry.name);
          finalStatuses.add(entry.status ?? stored.status);
          continue;
        }
      }

      final status = entry.status;
      finalStatuses.add(status ?? stored?.status);
      if (status == null) continue;

      final remarks = AttendanceEntry.cleanRemarks(entry.remarks);
      final unchanged =
          stored != null &&
          stored.status == status &&
          AttendanceEntry.cleanRemarks(stored.remarks) == remarks;
      if (unchanged) continue;

      writes.add(
        PlannedWrite(
          entry: entry,
          newStatus: status,
          newRemarks: remarks,
          previousStatus: stored?.status,
          previousRemarks: stored?.remarks,
          newRevision: (stored?.revision ?? 0) + 1,
        ),
      );
    }

    return SavePlan(
      conflicts: conflicts,
      writes: writes,
      resultingTally: AttendanceTally.of(finalStatuses),
    );
  }
}
