import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../academic_setup/domain/weekday.dart';
import 'timetable_enums.dart';

/// One class-section's weekly schedule, versioned.
///
/// `.../branches/{b}/timetables/{yearId}__{classId}__{sectionId}__v{n}` —
/// the version `n` comes from a per-section counter, so ids are unique and
/// increasing. Its cells are [TimetableEntry] documents. A PUBLISHED version
/// is immutable (entries, periods, effective start): a change is a new
/// version, never an edit.
class Timetable {
  final String timetableId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String? className;
  final String? sectionName;
  final String name;
  final int version;
  final TimetableStatus status;

  /// Weekday wire value -> period-set id, for each working day this
  /// timetable covers.
  final Map<String, String> dayPeriodSets;
  final String effectiveFromKey;

  /// Null = open-ended.
  final String? effectiveToKey;
  final int entryCount;

  /// Distinct teacher staff ids on this timetable (for "who is affected").
  final List<String> teacherIds;
  final String? copiedFrom;
  final int revision;
  final String? publishedBy;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const Timetable({
    required this.timetableId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.className,
    this.sectionName,
    required this.name,
    required this.version,
    this.status = TimetableStatus.draft,
    required this.dayPeriodSets,
    required this.effectiveFromKey,
    this.effectiveToKey,
    this.entryCount = 0,
    this.teacherIds = const [],
    this.copiedFrom,
    this.revision = 1,
    this.publishedBy,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  static String sectionKey(
    String academicYearId,
    String classId,
    String sectionId,
  ) => '${academicYearId}__${classId}__$sectionId';

  static String idFor(String sectionKey, int version) =>
      '${sectionKey}__v$version';

  String get sectionKeyValue => sectionKey(academicYearId, classId, sectionId);

  String get title => '${className ?? classId} ${sectionName ?? sectionId}';

  bool get isDraft => status == TimetableStatus.draft;
  bool get isPublished => status == TimetableStatus.published;

  Set<String> get periodSetIds => dayPeriodSets.values.toSet();

  /// Whether [dateKey] falls in the effective range (civil date keys compare
  /// lexicographically).
  bool coversDate(String dateKey) =>
      dateKey.compareTo(effectiveFromKey) >= 0 &&
      (effectiveToKey == null || dateKey.compareTo(effectiveToKey!) <= 0);

  /// Whether two timetables' effective ranges share any date.
  bool overlapsRange(String fromKey, String? toKey) {
    final thisEndsBefore =
        effectiveToKey != null && effectiveToKey!.compareTo(fromKey) < 0;
    final otherEndsBefore =
        toKey != null && toKey.compareTo(effectiveFromKey) < 0;
    return !thisEndsBefore && !otherEndsBefore;
  }

  /// A user-readable reason the metadata is invalid, or null.
  String? validateMeta({String? yearStartKey, String? yearEndKey}) {
    final n = name.trim();
    if (n.length < 2 || n.length > 60) {
      return 'The timetable name must be 2-60 characters.';
    }
    final key = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!key.hasMatch(effectiveFromKey)) {
      return 'Choose the effective start date.';
    }
    if (effectiveToKey != null) {
      if (!key.hasMatch(effectiveToKey!)) return 'The end date is not valid.';
      if (effectiveToKey!.compareTo(effectiveFromKey) < 0) {
        return 'The end date cannot be before the start date.';
      }
    }
    if (yearStartKey != null && effectiveFromKey.compareTo(yearStartKey) < 0) {
      return 'The timetable cannot start before the academic year.';
    }
    if (yearEndKey != null) {
      if (effectiveFromKey.compareTo(yearEndKey) > 0 ||
          (effectiveToKey != null &&
              effectiveToKey!.compareTo(yearEndKey) > 0)) {
        return 'The timetable cannot run past the academic year.';
      }
    }
    if (dayPeriodSets.isEmpty) {
      return 'Choose a period schedule for at least one working day.';
    }
    return null;
  }

  Timetable copyWith({
    String? name,
    Map<String, String>? dayPeriodSets,
    String? effectiveFromKey,
    String? effectiveToKey,
    bool clearEffectiveTo = false,
    int? entryCount,
    List<String>? teacherIds,
    TimetableStatus? status,
    int? revision,
  }) => Timetable(
    timetableId: timetableId,
    schoolId: schoolId,
    branchId: branchId,
    academicYearId: academicYearId,
    classId: classId,
    sectionId: sectionId,
    className: className,
    sectionName: sectionName,
    name: name ?? this.name,
    version: version,
    status: status ?? this.status,
    dayPeriodSets: dayPeriodSets ?? this.dayPeriodSets,
    effectiveFromKey: effectiveFromKey ?? this.effectiveFromKey,
    effectiveToKey: clearEffectiveTo
        ? null
        : (effectiveToKey ?? this.effectiveToKey),
    entryCount: entryCount ?? this.entryCount,
    teacherIds: teacherIds ?? this.teacherIds,
    copiedFrom: copiedFrom,
    revision: revision ?? this.revision,
    publishedBy: publishedBy,
    publishedAt: publishedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
  );

  factory Timetable.fromFirestore(
    Map<String, dynamic> d,
    String id,
  ) => Timetable(
    timetableId: id,
    schoolId: d[FirestoreFields.schoolId] as String,
    branchId: d[FirestoreFields.branchId] as String,
    academicYearId: d['academicYearId'] as String,
    classId: d['classId'] as String,
    sectionId: d['sectionId'] as String,
    className: d['className'] as String?,
    sectionName: d['sectionName'] as String?,
    name: d['name'] as String,
    version: (d['version'] as num).toInt(),
    status: TimetableStatus.fromWireValue(d[FirestoreFields.status] as String),
    dayPeriodSets: Map<String, String>.from(d['dayPeriodSets'] as Map? ?? {}),
    effectiveFromKey: d['effectiveFromKey'] as String,
    effectiveToKey: d['effectiveToKey'] as String?,
    entryCount: (d['entryCount'] as num?)?.toInt() ?? 0,
    teacherIds: List<String>.from(d['teacherIds'] as List? ?? []),
    copiedFrom: d['copiedFrom'] as String?,
    revision: (d['revision'] as num?)?.toInt() ?? 1,
    publishedBy: d['publishedBy'] as String?,
    publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
    createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
    updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
    createdBy: d[FirestoreFields.createdBy] as String?,
  );

  /// The user-editable body (also used when a draft is edited).
  Map<String, dynamic> body() => {
    'name': name.trim(),
    'dayPeriodSets': dayPeriodSets,
    'effectiveFromKey': effectiveFromKey,
    'effectiveToKey': effectiveToKey,
    'entryCount': entryCount,
    'teacherIds': teacherIds,
  };

  Map<String, dynamic> toFirestoreCreate({required String actorId}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'classId': classId,
    'sectionId': sectionId,
    'className': className,
    'sectionName': sectionName,
    'version': version,
    FirestoreFields.status: TimetableStatus.draft.wireValue,
    ...body(),
    'copiedFrom': copiedFrom,
    'revision': 1,
    'lastEvent': TimetableEvent.created.wireValue,
    'publishedBy': null,
    'publishedAt': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: actorId,
    FirestoreFields.updatedBy: actorId,
  };
}

/// One cell: a teaching slot of one weekday of one timetable version.
///
/// `.../timetableEntries/{timetableId}__{WEEKDAY}__{slotId}`. The slot's
/// times, the subject name and the teacher's display name are **copied** into
/// the entry deliberately: conflict detection across other classes must not
/// need every period set, and teachers/parents (who cannot read staff
/// documents) still need to see "Maths · Mrs Iyer". Only the display name of
/// the teacher is copied, nothing private.
class TimetableEntry {
  final String entryId;
  final String timetableId;
  final String schoolId;
  final String branchId;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final Weekday weekday;
  final String slotId;
  final int periodNumber;
  final int startMin;
  final int endMin;
  final String subjectId;
  final String subjectName;
  final String teacherStaffId;
  final String teacherName;

  /// Free-text room label (there is no room master in this system). Null
  /// when unset; conflict detection compares it case-insensitively.
  final String? room;

  /// True while the parent timetable is PUBLISHED (what readers query).
  final bool live;

  const TimetableEntry({
    required this.entryId,
    required this.timetableId,
    required this.schoolId,
    required this.branchId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    required this.weekday,
    required this.slotId,
    required this.periodNumber,
    required this.startMin,
    required this.endMin,
    required this.subjectId,
    required this.subjectName,
    required this.teacherStaffId,
    required this.teacherName,
    this.room,
    this.live = false,
  });

  static String idFor(String timetableId, Weekday weekday, String slotId) =>
      '${timetableId}__${weekday.wireValue}__$slotId';

  String get roomKey => (room ?? '').trim().toLowerCase();
  String get timeLabel => '${_f(startMin)}–${_f(endMin)}';

  static String _f(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  TimetableEntry copyWith({
    String? timetableId,
    String? classId,
    String? sectionId,
    Weekday? weekday,
    String? slotId,
    int? periodNumber,
    int? startMin,
    int? endMin,
    String? subjectId,
    String? subjectName,
    String? teacherStaffId,
    String? teacherName,
    String? room,
    bool clearRoom = false,
    bool? live,
  }) {
    final tt = timetableId ?? this.timetableId;
    final wd = weekday ?? this.weekday;
    final sl = slotId ?? this.slotId;
    return TimetableEntry(
      entryId: idFor(tt, wd, sl),
      timetableId: tt,
      schoolId: schoolId,
      branchId: branchId,
      academicYearId: academicYearId,
      classId: classId ?? this.classId,
      sectionId: sectionId ?? this.sectionId,
      weekday: wd,
      slotId: sl,
      periodNumber: periodNumber ?? this.periodNumber,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      teacherStaffId: teacherStaffId ?? this.teacherStaffId,
      teacherName: teacherName ?? this.teacherName,
      room: clearRoom ? null : (room ?? this.room),
      live: live ?? this.live,
    );
  }

  factory TimetableEntry.fromFirestore(Map<String, dynamic> d, String id) =>
      TimetableEntry(
        entryId: id,
        timetableId: d['timetableId'] as String,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String,
        classId: d['classId'] as String,
        sectionId: d['sectionId'] as String,
        weekday: Weekday.fromWireValue(d['weekday'] as String),
        slotId: d['slotId'] as String,
        periodNumber: (d['periodNumber'] as num).toInt(),
        startMin: (d['startMin'] as num).toInt(),
        endMin: (d['endMin'] as num).toInt(),
        subjectId: d['subjectId'] as String,
        subjectName: d['subjectName'] as String? ?? '',
        teacherStaffId: d['teacherStaffId'] as String,
        teacherName: d['teacherName'] as String? ?? '',
        room: d['room'] as String?,
        live: d['live'] == true,
      );

  Map<String, dynamic> toFirestore() => {
    'timetableId': timetableId,
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'classId': classId,
    'sectionId': sectionId,
    'weekday': weekday.wireValue,
    'slotId': slotId,
    'periodNumber': periodNumber,
    'startMin': startMin,
    'endMin': endMin,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'teacherStaffId': teacherStaffId,
    'teacherName': teacherName,
    'room': (room ?? '').trim().isEmpty ? null : room!.trim(),
    'live': live,
  };
}

/// `timetableHistory/{timetableId}__{seq}` — who published / archived /
/// superseded what, append-only.
class TimetableHistoryEntry {
  final String timetableId;
  final int version;
  final String title;
  final TimetableEvent event;
  final String actorId;
  final String actorName;
  final String? note;
  final DateTime? at;

  const TimetableHistoryEntry({
    required this.timetableId,
    required this.version,
    required this.title,
    required this.event,
    required this.actorId,
    required this.actorName,
    this.note,
    this.at,
  });

  factory TimetableHistoryEntry.fromFirestore(Map<String, dynamic> d) =>
      TimetableHistoryEntry(
        timetableId: d['timetableId'] as String,
        version: (d['version'] as num).toInt(),
        title: d['title'] as String? ?? '',
        event: TimetableEvent.fromWireValue(d['event'] as String),
        actorId: d['actorId'] as String,
        actorName: d['actorName'] as String? ?? '',
        note: d['note'] as String?,
        at: (d['at'] as Timestamp?)?.toDate(),
      );
}
