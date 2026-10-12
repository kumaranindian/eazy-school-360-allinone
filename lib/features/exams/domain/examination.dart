import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'exam_enums.dart';

/// An examination for one class (all its sections, or one). The id is
/// deterministic — `{year}__{class}__{section|ALL}__{name-slug}` — so the same
/// examination cannot be created twice in the same scope.
class Examination {
  final String examId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;

  /// Null = every section of the class.
  final String? sectionId;
  final String? classLabel;
  final String name;
  final String description;
  final ExamType type;
  final String schemeId;
  final String startDateKey;
  final String endDateKey;
  final String instructions;
  final ExamStatus status;
  final int revision;

  /// Subjects configured (kept in step with the subject documents).
  final int subjectCount;

  /// Marks sheets expected: subjects × sections. Set when marks entry opens.
  final int sheetCount;
  final int approvedSheets;

  /// Result version in force (0 until the first finalisation).
  final int resultVersion;
  final int resultCount;
  final int resultsWritten;
  final Map<String, dynamic>? schemeSnapshot;
  final String? finalizedBy;
  final String? publishedBy;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const Examination({
    required this.examId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    this.sectionId,
    this.classLabel,
    required this.name,
    this.description = '',
    this.type = ExamType.unitTest,
    required this.schemeId,
    required this.startDateKey,
    required this.endDateKey,
    this.instructions = '',
    this.status = ExamStatus.draft,
    this.revision = 1,
    this.subjectCount = 0,
    this.sheetCount = 0,
    this.approvedSheets = 0,
    this.resultVersion = 0,
    this.resultCount = 0,
    this.resultsWritten = 0,
    this.schemeSnapshot,
    this.finalizedBy,
    this.publishedBy,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  static String slug(String name) {
    final s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  static String idFor({
    required String academicYearId,
    required String classId,
    String? sectionId,
    required String name,
  }) => '${academicYearId}__${classId}__${sectionId ?? 'ALL'}__${slug(name)}';

  bool get coversAllSections => sectionId == null;

  /// "Half-yearly 2026 · Class 5 – A".
  String get title =>
      '$name · ${classLabel ?? classId}${sectionId == null ? '' : ''}';

  /// A user-readable problem with the configuration, or null.
  String? validate() {
    final n = name.trim();
    if (n.length < 3 || n.length > 80) {
      return 'The examination name must be 3-80 characters.';
    }
    if (slug(n).isEmpty) return 'The name needs letters or digits.';
    if (description.trim().length > 500) {
      return 'Keep the description under 500 characters.';
    }
    if (instructions.trim().length > 2000) {
      return 'Keep the instructions under 2000 characters.';
    }
    final key = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!key.hasMatch(startDateKey) || !key.hasMatch(endDateKey)) {
      return 'Choose the start and end dates.';
    }
    if (endDateKey.compareTo(startDateKey) < 0) {
      return 'The end date cannot be before the start date.';
    }
    if (schemeId.isEmpty) return 'Choose a grading scheme.';
    return null;
  }

  factory Examination.fromFirestore(Map<String, dynamic> d, String id) =>
      Examination(
        examId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        classId: d['classId'] as String,
        sectionId: d['sectionId'] as String?,
        classLabel: d['classLabel'] as String?,
        name: d['name'] as String? ?? '',
        description: d['description'] as String? ?? '',
        type: ExamType.fromWireValue(d['type'] as String? ?? ''),
        schemeId: d['schemeId'] as String? ?? '',
        startDateKey: d['startDateKey'] as String,
        endDateKey: d['endDateKey'] as String,
        instructions: d['instructions'] as String? ?? '',
        status: ExamStatus.fromWireValue(d[FirestoreFields.status] as String),
        revision: (d['revision'] as num?)?.toInt() ?? 1,
        subjectCount: (d['subjectCount'] as num?)?.toInt() ?? 0,
        sheetCount: (d['sheetCount'] as num?)?.toInt() ?? 0,
        approvedSheets: (d['approvedSheets'] as num?)?.toInt() ?? 0,
        resultVersion: (d['resultVersion'] as num?)?.toInt() ?? 0,
        resultCount: (d['resultCount'] as num?)?.toInt() ?? 0,
        resultsWritten: (d['resultsWritten'] as num?)?.toInt() ?? 0,
        schemeSnapshot: d['schemeSnapshot'] == null
            ? null
            : Map<String, dynamic>.from(d['schemeSnapshot'] as Map),
        finalizedBy: d['finalizedBy'] as String?,
        publishedBy: d['publishedBy'] as String?,
        publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
        createdBy: d[FirestoreFields.createdBy] as String?,
      );

  /// The editable body (create and configuration edits).
  Map<String, dynamic> body() => {
    'name': name.trim(),
    'description': description.trim(),
    'type': type.wireValue,
    'schemeId': schemeId,
    'startDateKey': startDateKey,
    'endDateKey': endDateKey,
    'instructions': instructions.trim(),
  };

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'classId': classId,
    'sectionId': sectionId,
    'classLabel': classLabel,
    'nameSlug': slug(name),
    ...body(),
    FirestoreFields.status: ExamStatus.draft.wireValue,
    'revision': 1,
    'lastEvent': ExamEvent.created.wireValue,
    'subjectCount': 0,
    'sheetCount': 0,
    'approvedSheets': 0,
    'resultVersion': 0,
    'resultCount': 0,
    'resultsWritten': 0,
    'schemeSnapshot': null,
    'finalizedBy': null,
    'publishedBy': null,
    'publishedAt': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };

  Examination copyWith({
    String? name,
    String? description,
    ExamType? type,
    String? schemeId,
    String? startDateKey,
    String? endDateKey,
    String? instructions,
    ExamStatus? status,
    int? revision,
    int? subjectCount,
  }) => Examination(
    examId: examId,
    schoolId: schoolId,
    branchId: branchId,
    academicYearId: academicYearId,
    classId: classId,
    sectionId: sectionId,
    classLabel: classLabel,
    name: name ?? this.name,
    description: description ?? this.description,
    type: type ?? this.type,
    schemeId: schemeId ?? this.schemeId,
    startDateKey: startDateKey ?? this.startDateKey,
    endDateKey: endDateKey ?? this.endDateKey,
    instructions: instructions ?? this.instructions,
    status: status ?? this.status,
    revision: revision ?? this.revision,
    subjectCount: subjectCount ?? this.subjectCount,
    sheetCount: sheetCount,
    approvedSheets: approvedSheets,
    resultVersion: resultVersion,
    resultCount: resultCount,
    resultsWritten: resultsWritten,
    schemeSnapshot: schemeSnapshot,
    finalizedBy: finalizedBy,
    publishedBy: publishedBy,
    publishedAt: publishedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
  );
}

/// One subject of an examination: its maximum, passing marks, weightage,
/// date and (optionally) a theory/practical split.
class ExaminationSubject {
  final String examId;
  final String subjectId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String subjectName;
  final double maxMarks;

  /// Null = use the scheme's pass percentage of [maxMarks].
  final double? passMarks;
  final double weightage;
  final String? dateKey;
  final int? startMin;
  final int? endMin;

  /// Both null (no components) or both set, summing to [maxMarks].
  final double? theoryMax;
  final double? practicalMax;
  final int revision;

  const ExaminationSubject({
    required this.examId,
    required this.subjectId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.subjectName,
    required this.maxMarks,
    this.passMarks,
    this.weightage = 1,
    this.dateKey,
    this.startMin,
    this.endMin,
    this.theoryMax,
    this.practicalMax,
    this.revision = 1,
  });

  static String idFor(String examId, String subjectId) =>
      '${examId}__$subjectId';

  String get id => idFor(examId, subjectId);
  bool get hasComponents => theoryMax != null && practicalMax != null;

  /// Passing marks in force for this subject under [schemePassPercent].
  double effectivePassMarks(double schemePassPercent) =>
      passMarks ?? maxMarks * schemePassPercent / 100;

  String? validate({String? examStartKey, String? examEndKey}) {
    if (!(maxMarks > 0) || maxMarks > 1000) {
      return 'Maximum marks must be positive and at most 1000.';
    }
    if (passMarks != null && (passMarks! < 0 || passMarks! > maxMarks)) {
      return 'Passing marks must be between 0 and the maximum marks.';
    }
    if (!(weightage > 0) || weightage > 100) {
      return 'Weightage must be greater than 0 and at most 100.';
    }
    if ((theoryMax == null) != (practicalMax == null)) {
      return 'Set both theory and practical maximums, or neither.';
    }
    if (hasComponents) {
      if (theoryMax! < 0 || practicalMax! < 0) {
        return 'Component maximums cannot be negative.';
      }
      if ((theoryMax! + practicalMax! - maxMarks).abs() > 0.0001) {
        return 'Theory and practical maximums must add up to the maximum '
            'marks.';
      }
    }
    if (dateKey != null) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateKey!)) {
        return 'The subject date is not valid.';
      }
      if (examStartKey != null && dateKey!.compareTo(examStartKey) < 0) {
        return 'The subject date is before the examination starts.';
      }
      if (examEndKey != null && dateKey!.compareTo(examEndKey) > 0) {
        return 'The subject date is after the examination ends.';
      }
    }
    if ((startMin == null) != (endMin == null)) {
      return 'Set both start and end time, or neither.';
    }
    if (startMin != null) {
      if (startMin! < 0 || endMin! > 1440 || endMin! <= startMin!) {
        return 'The end time must be after the start time.';
      }
    }
    return null;
  }

  factory ExaminationSubject.fromFirestore(Map<String, dynamic> d) =>
      ExaminationSubject(
        examId: d['examId'] as String,
        subjectId: d['subjectId'] as String,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        classId: d['classId'] as String,
        subjectName: d['subjectName'] as String? ?? '',
        maxMarks: (d['maxMarks'] as num).toDouble(),
        passMarks: (d['passMarks'] as num?)?.toDouble(),
        weightage: (d['weightage'] as num?)?.toDouble() ?? 1,
        dateKey: d['dateKey'] as String?,
        startMin: (d['startMin'] as num?)?.toInt(),
        endMin: (d['endMin'] as num?)?.toInt(),
        theoryMax: (d['theoryMax'] as num?)?.toDouble(),
        practicalMax: (d['practicalMax'] as num?)?.toDouble(),
        revision: (d['revision'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> body() => {
    'subjectName': subjectName,
    'maxMarks': maxMarks,
    'passMarks': passMarks,
    'weightage': weightage,
    'dateKey': dateKey,
    'startMin': startMin,
    'endMin': endMin,
    'theoryMax': theoryMax,
    'practicalMax': practicalMax,
  };

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'examId': examId,
    'subjectId': subjectId,
    'academicYearId': academicYearId,
    'classId': classId,
    ...body(),
    'revision': 1,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };
}
