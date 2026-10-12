import 'attendance_status.dart';
import 'attendance_tally.dart';

/// One row of an attendance sheet — a student or a staff member.
class AttendanceEntry {
  /// `studentId` or `staffId`.
  final String subjectId;
  final String name;

  /// Roll number / employee code, shown beside the name.
  final String? detail;

  /// Students only: the academic record they are being marked under.
  final String? academicRecordId;

  /// What is stored right now (null / revision 0 = never saved).
  final AttendanceStatus? savedStatus;
  final String? savedRemarks;
  final int savedRevision;

  /// Students only: the section an existing record was saved under, so a
  /// student already marked in a *different* section on this date is caught.
  final String? savedSectionId;

  AttendanceStatus? status;
  String? remarks;

  AttendanceEntry({
    required this.subjectId,
    required this.name,
    this.detail,
    this.academicRecordId,
    this.savedStatus,
    this.savedRemarks,
    this.savedRevision = 0,
    this.savedSectionId,
  }) : status = savedStatus,
       remarks = savedRemarks;

  bool get isSaved => savedRevision > 0;

  bool get isChanged =>
      status != savedStatus || _clean(remarks) != _clean(savedRemarks);

  static String? _clean(String? v) => cleanRemarks(v);

  /// Trimmed, with empty meaning null — so "" and null compare equal.
  static String? cleanRemarks(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}

/// The editable state of one register (a class section on a date, or the
/// staff of a branch on a date) and every rule about editing it, kept free
/// of UI and Firestore so it can be tested directly.
///
/// Nothing is ever assumed: an entry with no status stays "not marked" — it
/// is not silently turned into present or absent.
class AttendanceSheet {
  final List<AttendanceEntry> entries;

  /// Null when this register has never been saved.
  final AttendanceDayStatus? savedDayStatus;

  AttendanceSheet({required this.entries, this.savedDayStatus});

  bool get isFinalized => savedDayStatus == AttendanceDayStatus.finalized;

  AttendanceTally get tally => AttendanceTally.of(entries.map((e) => e.status));

  bool get hasUnmarked => entries.any((e) => e.status == null);

  bool get isDirty => entries.any((e) => e.isChanged);

  Iterable<AttendanceEntry> get changedEntries =>
      entries.where((e) => e.isChanged);

  AttendanceEntry? entryFor(String subjectId) =>
      entries.where((e) => e.subjectId == subjectId).firstOrNull;

  void setStatus(String subjectId, AttendanceStatus? status) =>
      entryFor(subjectId)?.status = status;

  void setRemarks(String subjectId, String? remarks) =>
      entryFor(subjectId)?.remarks = remarks;

  /// Marks everyone who has no status yet as present. It does **not**
  /// overwrite a status already chosen (or already saved) — a teacher who
  /// marked three absentees first must not lose them.
  void markAllPresent() {
    for (final e in entries) {
      e.status ??= AttendanceStatus.present;
    }
  }

  /// Puts one entry back to what is stored (or "not marked" if never saved).
  void reset(String subjectId) {
    final e = entryFor(subjectId);
    if (e == null) return;
    e.status = e.savedStatus;
    e.remarks = e.savedRemarks;
  }

  /// Why saving is not allowed right now, or null. [allowPartial] is the
  /// user's explicit confirmation to save with some entries unmarked.
  /// [reason] is the written reason a correction to a finalized register
  /// needs.
  String? validateSave({
    bool allowPartial = false,
    String? reason,
    bool canEditFinalized = false,
  }) {
    if (entries.isEmpty) return 'There is nobody to mark attendance for.';
    if (!isDirty) return 'There are no changes to save.';
    if (isFinalized) {
      if (!canEditFinalized) {
        return 'This attendance is finalized. Ask a manager to correct it.';
      }
      if (reason == null || reason.trim().isEmpty) {
        return 'Enter a reason for correcting finalized attendance.';
      }
    }
    if (hasUnmarked && !allowPartial) {
      return '${tally.notMarked} not marked. Mark everyone, or confirm saving partial attendance.';
    }
    return null;
  }

  /// Finalizing locks the register, so everyone must be marked.
  String? validateFinalize() {
    if (entries.isEmpty) return 'There is nobody to mark attendance for.';
    if (hasUnmarked) {
      return 'Mark every entry before finalizing (${tally.notMarked} not marked).';
    }
    return null;
  }
}
