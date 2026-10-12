import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../attendance/domain/attendance_date.dart';
import 'leave_enums.dart';

class LeaveAttachment {
  final String path;
  final String name;
  final String contentType;
  final int sizeBytes;

  const LeaveAttachment({
    required this.path,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
  });

  factory LeaveAttachment.fromMap(Map<String, dynamic> m) => LeaveAttachment(
    path: m['path'] as String,
    name: m['name'] as String,
    contentType: m['contentType'] as String,
    sizeBytes: (m['sizeBytes'] as num).toInt(),
  );

  Map<String, dynamic> toMap() => {
    'path': path,
    'name': name,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
  };
}

/// Who filed the application, relative to the subject.
enum ApplicantRelation {
  parent('PARENT'),
  self('SELF'),
  admin('ADMIN');

  final String wireValue;
  const ApplicantRelation(this.wireValue);

  static ApplicantRelation fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// `.../branches/{b}/leaveApplications/{applicationId}` — the private record
/// (reason, attachments, decision). Who may read it is decided by
/// `firestore.rules`: the applicant, a parent linked to the student, and
/// reviewers. Everyone else sees only the minimal [LeaveCalendarEntry].
///
/// The id is generated once per submission screen and reused on retry, so a
/// double-tap or a network retry cannot create two applications.
class LeaveApplication {
  final String applicationId;
  final String schoolId;
  final String branchId;
  final LeaveKind kind;
  final String subjectId;
  final String subjectName;
  final String? subjectCode;
  final String? academicYearId;
  final String? classId;
  final String? className;
  final String? sectionId;
  final String? sectionName;
  final String applicantUserId;
  final String applicantName;
  final ApplicantRelation relation;
  final String typeId;
  final String typeName;
  final LeavePayType payType;
  final String startDateKey;
  final String endDateKey;
  final HalfDay halfDay;
  final int units;
  final List<String> countedDateKeys;
  final String? reason;
  final List<LeaveAttachment> attachments;
  final LeaveStatus status;
  final int revision;
  final String? balanceId;

  /// First day of the leave year (academic year) this application counts
  /// against; the balance is created from it on first use.
  final String? leaveYearStartKey;
  final String? decidedBy;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionRemarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LeaveApplication({
    required this.applicationId,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.subjectId,
    required this.subjectName,
    this.subjectCode,
    this.academicYearId,
    this.classId,
    this.className,
    this.sectionId,
    this.sectionName,
    required this.applicantUserId,
    required this.applicantName,
    required this.relation,
    required this.typeId,
    required this.typeName,
    required this.payType,
    required this.startDateKey,
    required this.endDateKey,
    this.halfDay = HalfDay.none,
    required this.units,
    required this.countedDateKeys,
    this.reason,
    this.attachments = const [],
    this.status = LeaveStatus.pending,
    this.revision = 1,
    this.balanceId,
    this.leaveYearStartKey,
    this.decidedBy,
    this.decidedByName,
    this.decidedAt,
    this.decisionRemarks,
    this.createdAt,
    this.updatedAt,
  });

  static String newId() =>
      'lv_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(DateTime.now().hashCode & 0xffff).toRadixString(36)}';

  bool get isSingleDay => startDateKey == endDateKey;

  /// The calendar-entry id is the application id, so approval can never
  /// produce two entries for one application.
  String get calendarId => applicationId;

  factory LeaveApplication.fromFirestore(Map<String, dynamic> d, String id) {
    return LeaveApplication(
      applicationId: id,
      schoolId: d[FirestoreFields.schoolId] as String,
      branchId: d[FirestoreFields.branchId] as String,
      kind: LeaveKind.fromWireValue(d['subjectKind'] as String),
      subjectId: d['subjectId'] as String,
      subjectName: d['subjectName'] as String? ?? '',
      subjectCode: d['subjectCode'] as String?,
      academicYearId: d['academicYearId'] as String?,
      classId: d['classId'] as String?,
      className: d['className'] as String?,
      sectionId: d['sectionId'] as String?,
      sectionName: d['sectionName'] as String?,
      applicantUserId: d['applicantUserId'] as String,
      applicantName: d['applicantName'] as String? ?? '',
      relation: ApplicantRelation.fromWireValue(d['relation'] as String),
      typeId: d['typeId'] as String,
      typeName: d['typeName'] as String? ?? '',
      payType: LeavePayType.fromWireValue(d['payType'] as String),
      startDateKey: d['startDateKey'] as String,
      endDateKey: d['endDateKey'] as String,
      halfDay: HalfDay.fromWireValue(d['halfDay'] as String? ?? 'NONE'),
      units: (d['units'] as num).toInt(),
      countedDateKeys: List<String>.from(d['countedDateKeys'] as List? ?? []),
      reason: d['reason'] as String?,
      attachments: [
        for (final a in d['attachments'] as List? ?? [])
          LeaveAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
      ],
      status: LeaveStatus.fromWireValue(d[FirestoreFields.status] as String),
      revision: (d['revision'] as num?)?.toInt() ?? 1,
      balanceId: d['balanceId'] as String?,
      leaveYearStartKey: d['leaveYearStartKey'] as String?,
      decidedBy: d['decidedBy'] as String?,
      decidedByName: d['decidedByName'] as String?,
      decidedAt: (d['decidedAt'] as Timestamp?)?.toDate(),
      decisionRemarks: d['decisionRemarks'] as String?,
      createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
    );
  }

  /// Fields of the user-editable body (shared by create and resubmit).
  Map<String, dynamic> body() => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'subjectKind': kind.wireValue,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'subjectCode': subjectCode,
    'academicYearId': academicYearId,
    'classId': classId,
    'className': className,
    'sectionId': sectionId,
    'sectionName': sectionName,
    'applicantUserId': applicantUserId,
    'applicantName': applicantName,
    'relation': relation.wireValue,
    'typeId': typeId,
    'typeName': typeName,
    'payType': payType.wireValue,
    'startDateKey': startDateKey,
    'endDateKey': endDateKey,
    'startDate': AttendanceDate.timestampFor(startDateKey),
    'endDate': AttendanceDate.timestampFor(endDateKey),
    'halfDay': halfDay.wireValue,
    'units': units,
    'countedDateKeys': countedDateKeys,
    'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    'attachments': [for (final a in attachments) a.toMap()],
    'balanceId': balanceId,
    'leaveYearStartKey': leaveYearStartKey,
  };

  Map<String, dynamic> toFirestoreCreate() => {
    ...body(),
    FirestoreFields.status: LeaveStatus.pending.wireValue,
    'revision': 1,
    'lastEvent': LeaveEvent.submit.wireValue,
    // Written explicitly so the decision fields always exist (null until a
    // reviewer decides); the rules require `decidedBy == null` on creation.
    'decidedBy': null,
    'decidedByName': null,
    'decidedAt': null,
    'decisionRemarks': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: applicantUserId,
    FirestoreFields.updatedBy: applicantUserId,
  };
}

/// `.../leaveCalendar/{applicationId}` — the minimal, non-sensitive public
/// face of an APPROVED leave: who, which dates, which session. No reason, no
/// attachment, no leave-type name for students (medical leave must not be
/// inferable from the calendar). Teachers and attendance screens read this.
class LeaveCalendarEntry {
  final String applicationId;
  final String schoolId;
  final String branchId;
  final LeaveKind kind;
  final String subjectId;
  final String subjectName;
  final String? academicYearId;
  final String? classId;
  final String? sectionId;
  final String startDateKey;
  final String endDateKey;
  final HalfDay halfDay;
  final List<String> countedDateKeys;
  final bool active;

  const LeaveCalendarEntry({
    required this.applicationId,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.subjectId,
    required this.subjectName,
    this.academicYearId,
    this.classId,
    this.sectionId,
    required this.startDateKey,
    required this.endDateKey,
    this.halfDay = HalfDay.none,
    required this.countedDateKeys,
    this.active = true,
  });

  bool coversDate(String key) => active && countedDateKeys.contains(key);

  factory LeaveCalendarEntry.fromFirestore(Map<String, dynamic> d, String id) =>
      LeaveCalendarEntry(
        applicationId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        kind: LeaveKind.fromWireValue(d['subjectKind'] as String),
        subjectId: d['subjectId'] as String,
        subjectName: d['subjectName'] as String? ?? '',
        academicYearId: d['academicYearId'] as String?,
        classId: d['classId'] as String?,
        sectionId: d['sectionId'] as String?,
        startDateKey: d['startDateKey'] as String,
        endDateKey: d['endDateKey'] as String,
        halfDay: HalfDay.fromWireValue(d['halfDay'] as String? ?? 'NONE'),
        countedDateKeys: List<String>.from(d['countedDateKeys'] as List? ?? []),
        active: (d[FirestoreFields.status] as String?) != 'CANCELLED',
      );

  static Map<String, dynamic> forApplication(LeaveApplication a) => {
    FirestoreFields.schoolId: a.schoolId,
    FirestoreFields.branchId: a.branchId,
    'subjectKind': a.kind.wireValue,
    'subjectId': a.subjectId,
    'subjectName': a.subjectName,
    'academicYearId': a.academicYearId,
    'classId': a.classId,
    'sectionId': a.sectionId,
    'startDateKey': a.startDateKey,
    'endDateKey': a.endDateKey,
    'halfDay': a.halfDay.wireValue,
    'countedDateKeys': a.countedDateKeys,
    FirestoreFields.status: 'ACTIVE',
  };
}

/// An append-only history record: `leaveHistory/{applicationId}__{revision}`.
class LeaveHistoryEntry {
  final String applicationId;
  final int revision;
  final LeaveStatus? from;
  final LeaveStatus to;
  final LeaveEvent event;
  final String actorId;
  final String actorName;
  final String? remarks;
  final DateTime? at;

  const LeaveHistoryEntry({
    required this.applicationId,
    required this.revision,
    required this.from,
    required this.to,
    required this.event,
    required this.actorId,
    required this.actorName,
    this.remarks,
    this.at,
  });

  static String idFor(String applicationId, int revision) =>
      '${applicationId}__$revision';

  factory LeaveHistoryEntry.fromFirestore(Map<String, dynamic> d) =>
      LeaveHistoryEntry(
        applicationId: d['applicationId'] as String,
        revision: (d['revision'] as num).toInt(),
        from: d['fromStatus'] == null
            ? null
            : LeaveStatus.fromWireValue(d['fromStatus'] as String),
        to: LeaveStatus.fromWireValue(d['toStatus'] as String),
        event: LeaveEvent.fromWireValue(d['event'] as String),
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        remarks: d['remarks'] as String?,
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}
