import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'exam_enums.dart';
import 'examination.dart';

/// One student's marks for one subject. [marks] is meaningful only when
/// [status] is `entered` (and is the sum of [theory] and [practical] when the
/// subject has components). Zero marks is `entered` with `marks == 0`.
class MarksEntry {
  final String sheetId;
  final String examId;
  final String subjectId;
  final String studentId;
  final String studentName;
  final String? rollNumber;
  final String classId;
  final String sectionId;
  final String academicYearId;
  final String schoolId;
  final String branchId;
  final MarkStatus status;
  final double? marks;
  final double? theory;
  final double? practical;
  final String remark;
  final int revision;
  final String? updatedBy;
  final DateTime? updatedAt;

  const MarksEntry({
    required this.sheetId,
    required this.examId,
    required this.subjectId,
    required this.studentId,
    required this.studentName,
    this.rollNumber,
    required this.classId,
    required this.sectionId,
    required this.academicYearId,
    required this.schoolId,
    required this.branchId,
    this.status = MarkStatus.pending,
    this.marks,
    this.theory,
    this.practical,
    this.remark = '',
    this.revision = 0,
    this.updatedBy,
    this.updatedAt,
  });

  static String idFor(String sheetId, String studentId) =>
      '${sheetId}__$studentId';

  String get id => idFor(sheetId, studentId);

  /// The marks that count: the entered total, or theory + practical when the
  /// subject has components. Null when nothing usable was entered.
  double? get effectiveMarks =>
      marks ??
      (theory != null && practical != null ? theory! + practical! : null);

  /// Not yet saved by anyone.
  bool get isUnsaved => revision == 0;

  MarksEntry copyWith({
    MarkStatus? status,
    double? marks,
    bool clearMarks = false,
    double? theory,
    double? practical,
    bool clearComponents = false,
    String? remark,
    int? revision,
  }) => MarksEntry(
    sheetId: sheetId,
    examId: examId,
    subjectId: subjectId,
    studentId: studentId,
    studentName: studentName,
    rollNumber: rollNumber,
    classId: classId,
    sectionId: sectionId,
    academicYearId: academicYearId,
    schoolId: schoolId,
    branchId: branchId,
    status: status ?? this.status,
    marks: clearMarks ? null : (marks ?? this.marks),
    theory: clearComponents ? null : (theory ?? this.theory),
    practical: clearComponents ? null : (practical ?? this.practical),
    remark: remark ?? this.remark,
    revision: revision ?? this.revision,
    updatedBy: updatedBy,
    updatedAt: updatedAt,
  );

  /// A user-readable problem with this entry against [subject], or null.
  String? validate(ExaminationSubject subject) {
    switch (status) {
      case MarkStatus.entered:
        if (subject.hasComponents) {
          if (theory == null || practical == null) {
            return 'Enter theory and practical marks.';
          }
          if (theory! < 0 || theory! > subject.theoryMax!) {
            return 'Theory marks must be between 0 and '
                '${_fmt(subject.theoryMax!)}.';
          }
          if (practical! < 0 || practical! > subject.practicalMax!) {
            return 'Practical marks must be between 0 and '
                '${_fmt(subject.practicalMax!)}.';
          }
        } else {
          final m = marks;
          if (m == null) return 'Enter the marks.';
          if (m < 0) return 'Marks cannot be negative.';
          if (m > subject.maxMarks) {
            return 'Marks cannot exceed ${_fmt(subject.maxMarks)}.';
          }
        }
        if (_decimals(marks ?? 0) > 2) return 'Use at most 2 decimal places.';
      case MarkStatus.absent:
      case MarkStatus.exempted:
      case MarkStatus.pending:
        break;
    }
    if (remark.trim().length > 200) {
      return 'Keep the remark under 200 characters.';
    }
    return null;
  }

  static int _decimals(double v) {
    final s = v.toString();
    final i = s.indexOf('.');
    if (i < 0) return 0;
    final frac = s.substring(i + 1).replaceAll(RegExp(r'0+$'), '');
    return frac.length;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  factory MarksEntry.fromFirestore(Map<String, dynamic> d, String id) {
    return MarksEntry(
      sheetId: d['sheetId'] as String,
      examId: d['examId'] as String,
      subjectId: d['subjectId'] as String,
      studentId: d['studentId'] as String,
      studentName: d['studentName'] as String? ?? '',
      rollNumber: d['rollNumber'] as String?,
      classId: d['classId'] as String,
      sectionId: d['sectionId'] as String,
      academicYearId: d['academicYearId'] as String,
      schoolId: d[FirestoreFields.schoolId] as String,
      branchId: d[FirestoreFields.branchId] as String,
      status: MarkStatus.fromWireValue(d[FirestoreFields.status] as String),
      marks: (d['marks'] as num?)?.toDouble(),
      theory: (d['theory'] as num?)?.toDouble(),
      practical: (d['practical'] as num?)?.toDouble(),
      remark: d['remark'] as String? ?? '',
      revision: (d['revision'] as num?)?.toInt() ?? 1,
      updatedBy: d[FirestoreFields.updatedBy] as String?,
      updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
    );
  }

  /// Fields written to Firestore (create and update). `marks` is derived from
  /// the components when the subject has them.
  Map<String, dynamic> body({required bool components}) {
    final total = status == MarkStatus.entered
        ? (components ? (theory! + practical!) : marks)
        : null;
    return {
      FirestoreFields.status: status.wireValue,
      'marks': total,
      'theory': status == MarkStatus.entered && components ? theory : null,
      'practical': status == MarkStatus.entered && components
          ? practical
          : null,
      'remark': remark.trim(),
    };
  }
}

/// One subject's marks in one section, with its review state.
class MarksSheet {
  final String examId;
  final String subjectId;
  final String sectionId;
  final String classId;
  final String academicYearId;
  final String schoolId;
  final String branchId;
  final SheetStatus status;
  final int revision;
  final int rosterCount;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? reviewNote;
  final DateTime? updatedAt;

  const MarksSheet({
    required this.examId,
    required this.subjectId,
    required this.sectionId,
    required this.classId,
    required this.academicYearId,
    required this.schoolId,
    required this.branchId,
    this.status = SheetStatus.draft,
    this.revision = 1,
    this.rosterCount = 0,
    this.submittedBy,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.reviewNote,
    this.updatedAt,
  });

  static String idFor(String examId, String subjectId, String sectionId) =>
      '${examId}__${subjectId}__$sectionId';

  String get id => idFor(examId, subjectId, sectionId);

  factory MarksSheet.fromFirestore(Map<String, dynamic> d) => MarksSheet(
    examId: d['examId'] as String,
    subjectId: d['subjectId'] as String,
    sectionId: d['sectionId'] as String,
    classId: d['classId'] as String,
    academicYearId: d['academicYearId'] as String,
    schoolId: d[FirestoreFields.schoolId] as String,
    branchId: d[FirestoreFields.branchId] as String,
    status: SheetStatus.fromWireValue(d[FirestoreFields.status] as String),
    revision: (d['revision'] as num?)?.toInt() ?? 1,
    rosterCount: (d['rosterCount'] as num?)?.toInt() ?? 0,
    submittedBy: d['submittedBy'] as String?,
    submittedAt: (d['submittedAt'] as Timestamp?)?.toDate(),
    approvedBy: d['approvedBy'] as String?,
    approvedAt: (d['approvedAt'] as Timestamp?)?.toDate(),
    reviewNote: d['reviewNote'] as String?,
    updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
  );
}

/// One append-only record of a sheet or exam change, for the audit view.
class ExamAuditEntry {
  final String refId;
  final String scope; // EXAM | SHEET
  final int revision;
  final String event;
  final String? toStatus;
  final String actorId;
  final String actorName;
  final String? note;
  final DateTime? at;

  const ExamAuditEntry({
    required this.refId,
    required this.scope,
    required this.revision,
    required this.event,
    this.toStatus,
    required this.actorId,
    required this.actorName,
    this.note,
    this.at,
  });

  factory ExamAuditEntry.fromFirestore(Map<String, dynamic> d, String scope) =>
      ExamAuditEntry(
        refId: (scope == 'EXAM' ? d['examId'] : d['sheetId']) as String,
        scope: scope,
        revision: (d['revision'] as num).toInt(),
        event: d['event'] as String,
        toStatus: d['toStatus'] as String?,
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        note: d['note'] as String?,
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}
