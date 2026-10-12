import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'file_attachment.dart';
import 'homework_enums.dart';

/// `.../homeworkSubmissions/{homeworkId}__{studentId}` — one per student per
/// homework *by construction* (the id), so a double-tap or a network retry
/// cannot create a second one. The current state lives here; every change
/// also appends a [SubmissionRevision], so nothing is overwritten untraceably.
class HomeworkSubmission {
  final String submissionId;
  final String homeworkId;
  final String studentId;
  final String studentName;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final SubmissionStatus status;
  final String textAnswer;
  final List<FileAttachment> attachments;
  final int revision;
  final bool late;
  final String submittedBy;
  final DateTime? submittedAt;
  final String? feedback;
  final int? marks;
  final String? gradedBy;
  final String? gradedByName;
  final DateTime? gradedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HomeworkSubmission({
    required this.submissionId,
    required this.homeworkId,
    required this.studentId,
    this.studentName = '',
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    required this.status,
    this.textAnswer = '',
    this.attachments = const [],
    this.revision = 1,
    this.late = false,
    required this.submittedBy,
    this.submittedAt,
    this.feedback,
    this.marks,
    this.gradedBy,
    this.gradedByName,
    this.gradedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
  });

  static String idFor(String homeworkId, String studentId) =>
      '${homeworkId}__$studentId';

  bool get isGraded => status == SubmissionStatus.graded;

  factory HomeworkSubmission.fromFirestore(Map<String, dynamic> d, String id) =>
      HomeworkSubmission(
        submissionId: id,
        homeworkId: d['homeworkId'] as String,
        studentId: d['studentId'] as String,
        studentName: d['studentName'] as String? ?? '',
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        classId: d['classId'] as String,
        sectionId: d['sectionId'] as String,
        status: SubmissionStatus.fromWireValue(
          d[FirestoreFields.status] as String,
        ),
        textAnswer: d['textAnswer'] as String? ?? '',
        attachments: [
          for (final a in d['attachments'] as List? ?? [])
            FileAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
        ],
        revision: (d['revision'] as num?)?.toInt() ?? 1,
        late: d['late'] as bool? ?? false,
        submittedBy: d['submittedBy'] as String? ?? '',
        submittedAt: (d['submittedAt'] as Timestamp?)?.toDate(),
        feedback: d['feedback'] as String?,
        marks: (d['marks'] as num?)?.toInt(),
        gradedBy: d['gradedBy'] as String?,
        gradedByName: d['gradedByName'] as String?,
        gradedAt: (d['gradedAt'] as Timestamp?)?.toDate(),
        reviewedBy: d['reviewedBy'] as String?,
        reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      );
}

/// One append-only record of a submission change.
class SubmissionRevision {
  final String submissionId;
  final int revision;
  final SubmissionEvent event;
  final SubmissionStatus status;
  final String textAnswer;
  final List<FileAttachment> attachments;
  final String? feedback;
  final int? marks;
  final String actorId;
  final String actorName;
  final String actorRole;
  final DateTime? at;

  const SubmissionRevision({
    required this.submissionId,
    required this.revision,
    required this.event,
    required this.status,
    this.textAnswer = '',
    this.attachments = const [],
    this.feedback,
    this.marks,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    this.at,
  });

  static String idFor(String submissionId, int revision) =>
      '${submissionId}__$revision';

  factory SubmissionRevision.fromFirestore(Map<String, dynamic> d) =>
      SubmissionRevision(
        submissionId: d['submissionId'] as String,
        revision: (d['revision'] as num).toInt(),
        event: SubmissionEvent.fromWireValue(d['event'] as String),
        status: SubmissionStatus.fromWireValue(d['status'] as String),
        textAnswer: d['textAnswer'] as String? ?? '',
        attachments: [
          for (final a in d['attachments'] as List? ?? [])
            FileAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
        ],
        feedback: d['feedback'] as String?,
        marks: (d['marks'] as num?)?.toInt(),
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        actorRole: d['actorRole'] as String? ?? '',
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}
