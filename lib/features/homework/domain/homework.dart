import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../attendance/domain/attendance_date.dart';
import 'file_attachment.dart';
import 'homework_enums.dart';

/// One piece of homework for **one class-section** and one subject.
///
/// `.../branches/{b}/homework/{batchId}__{sectionId}` — assigning to several
/// sections creates one document per section sharing a [batchId]; the
/// deterministic id makes a retried publish land on the same documents.
/// Each section's copy is its own record, so security, grading and history
/// are per-section and a transfer or one section's deadline change never
/// touches another's.
class Homework {
  final String homeworkId;
  final String batchId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String? classLabel;
  final String subjectId;
  final String subjectName;
  final String teacherStaffId;
  final String teacherName;
  final String title;
  final String description;
  final String assignedDateKey;
  final String dueDateKey;

  /// Minutes since local midnight, or null = end of the due day.
  final int? dueTimeMin;

  /// The absolute deadline instant, computed once when the due date/time is
  /// set (in the publisher's local timezone, assumed to be the school's).
  /// Security rules compare the **server** time against this, never a
  /// client-claimed time.
  final DateTime dueAt;
  final List<FileAttachment> attachments;
  final int? maxMarks;
  final bool requiresSubmission;
  final bool allowFiles;
  final bool allowLate;
  final bool allowResubmission;
  final HomeworkStatus status;
  final int revision;
  final String? publishedBy;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const Homework({
    required this.homeworkId,
    required this.batchId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.classLabel,
    required this.subjectId,
    required this.subjectName,
    required this.teacherStaffId,
    required this.teacherName,
    required this.title,
    this.description = '',
    required this.assignedDateKey,
    required this.dueDateKey,
    this.dueTimeMin,
    required this.dueAt,
    this.attachments = const [],
    this.maxMarks,
    this.requiresSubmission = true,
    this.allowFiles = true,
    this.allowLate = false,
    this.allowResubmission = true,
    this.status = HomeworkStatus.draft,
    this.revision = 1,
    this.publishedBy,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  static String idFor(String batchId, String sectionId) =>
      '${batchId}__$sectionId';

  bool get isGraded => maxMarks != null;
  bool get isDraft => status == HomeworkStatus.draft;

  /// The deadline instant for a civil date and optional time.
  static DateTime dueInstant(String dueDateKey, int? dueTimeMin) {
    final d = AttendanceDate.parse(dueDateKey);
    final minutes = dueTimeMin ?? (23 * 60 + 59);
    return DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
  }

  bool isPastDue(DateTime now) => now.isAfter(dueAt);

  factory Homework.fromFirestore(Map<String, dynamic> d, String id) => Homework(
    homeworkId: id,
    batchId: d['batchId'] as String? ?? id,
    schoolId: d[FirestoreFields.schoolId] as String,
    branchId: d[FirestoreFields.branchId] as String,
    academicYearId: d['academicYearId'] as String,
    classId: d['classId'] as String,
    sectionId: d['sectionId'] as String,
    classLabel: d['classLabel'] as String?,
    subjectId: d['subjectId'] as String,
    subjectName: d['subjectName'] as String? ?? '',
    teacherStaffId: d['teacherStaffId'] as String,
    teacherName: d['teacherName'] as String? ?? '',
    title: d['title'] as String,
    description: d['description'] as String? ?? '',
    assignedDateKey: d['assignedDateKey'] as String,
    dueDateKey: d['dueDateKey'] as String,
    dueTimeMin: (d['dueTimeMin'] as num?)?.toInt(),
    dueAt: (d['dueAt'] as Timestamp).toDate(),
    attachments: [
      for (final a in d['attachments'] as List? ?? [])
        FileAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
    ],
    maxMarks: (d['maxMarks'] as num?)?.toInt(),
    requiresSubmission: d['requiresSubmission'] as bool? ?? true,
    allowFiles: d['allowFiles'] as bool? ?? true,
    allowLate: d['allowLate'] as bool? ?? false,
    allowResubmission: d['allowResubmission'] as bool? ?? true,
    status: HomeworkStatus.fromWireValue(d[FirestoreFields.status] as String),
    revision: (d['revision'] as num?)?.toInt() ?? 1,
    publishedBy: d['publishedBy'] as String?,
    publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
    createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
    updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
    createdBy: d[FirestoreFields.createdBy] as String?,
  );

  /// The editable body (shared by create and draft/published edits).
  Map<String, dynamic> body() => {
    'title': title.trim(),
    'description': description.trim(),
    'dueDateKey': dueDateKey,
    'dueTimeMin': dueTimeMin,
    'dueAt': Timestamp.fromDate(dueAt),
    'attachments': [for (final a in attachments) a.toMap()],
    'requiresSubmission': requiresSubmission,
    'allowFiles': allowFiles,
    'allowLate': allowLate,
    'allowResubmission': allowResubmission,
  };

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'batchId': batchId,
    'classId': classId,
    'sectionId': sectionId,
    'classLabel': classLabel,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'teacherStaffId': teacherStaffId,
    'teacherName': teacherName,
    'assignedDateKey': assignedDateKey,
    'maxMarks': maxMarks,
    ...body(),
    FirestoreFields.status: HomeworkStatus.draft.wireValue,
    'revision': 1,
    'lastEvent': HomeworkEvent.created.wireValue,
    'publishedBy': null,
    'publishedAt': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };

  Homework copyWith({
    String? title,
    String? description,
    String? dueDateKey,
    int? dueTimeMin,
    bool clearDueTime = false,
    DateTime? dueAt,
    List<FileAttachment>? attachments,
    bool? allowLate,
    bool? allowResubmission,
    bool? allowFiles,
    bool? requiresSubmission,
    HomeworkStatus? status,
    int? revision,
  }) => Homework(
    homeworkId: homeworkId,
    batchId: batchId,
    schoolId: schoolId,
    branchId: branchId,
    academicYearId: academicYearId,
    classId: classId,
    sectionId: sectionId,
    classLabel: classLabel,
    subjectId: subjectId,
    subjectName: subjectName,
    teacherStaffId: teacherStaffId,
    teacherName: teacherName,
    title: title ?? this.title,
    description: description ?? this.description,
    assignedDateKey: assignedDateKey,
    dueDateKey: dueDateKey ?? this.dueDateKey,
    dueTimeMin: clearDueTime ? null : (dueTimeMin ?? this.dueTimeMin),
    dueAt: dueAt ?? this.dueAt,
    attachments: attachments ?? this.attachments,
    maxMarks: maxMarks,
    requiresSubmission: requiresSubmission ?? this.requiresSubmission,
    allowFiles: allowFiles ?? this.allowFiles,
    allowLate: allowLate ?? this.allowLate,
    allowResubmission: allowResubmission ?? this.allowResubmission,
    status: status ?? this.status,
    revision: revision ?? this.revision,
    publishedBy: publishedBy,
    publishedAt: publishedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
  );
}

/// `homeworkHistory/{homeworkId}__{revision}` — append-only.
class HomeworkHistoryEntry {
  final String homeworkId;
  final int revision;
  final HomeworkEvent event;
  final HomeworkStatus toStatus;
  final String actorId;
  final String actorName;
  final String? note;
  final DateTime? at;

  const HomeworkHistoryEntry({
    required this.homeworkId,
    required this.revision,
    required this.event,
    required this.toStatus,
    required this.actorId,
    required this.actorName,
    this.note,
    this.at,
  });

  factory HomeworkHistoryEntry.fromFirestore(Map<String, dynamic> d) =>
      HomeworkHistoryEntry(
        homeworkId: d['homeworkId'] as String,
        revision: (d['revision'] as num).toInt(),
        event: HomeworkEvent.fromWireValue(d['event'] as String),
        toStatus: HomeworkStatus.fromWireValue(d['toStatus'] as String),
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        note: d['note'] as String?,
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}
