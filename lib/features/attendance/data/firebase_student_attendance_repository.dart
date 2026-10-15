import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/student.dart';
import '../../students/domain/student_academic_record.dart';
import '../domain/attendance_date.dart';
import '../domain/attendance_day.dart';
import '../domain/attendance_history_entry.dart';
import '../domain/attendance_registers.dart';
import '../domain/attendance_save_planner.dart';
import '../domain/attendance_status.dart';
import '../domain/enrollment_eligibility.dart';
import '../domain/student_attendance.dart';
import '../domain/student_attendance_repository.dart';
import 'attendance_register_transaction.dart';

/// `/schools/{s}/branches/{b}/studentAttendance/{dateKey}_{studentId}` (+
/// `/history/{revision}`) and `attendanceSessions/{dateKey__year__class__section}`.
///
/// Enrollment is read from each student's `academicRecords` history through
/// one collection-group query (equality on school, branch, year, class,
/// section — see `firestore.indexes.json`), then filtered by date in
/// [EnrollmentEligibility]. Security rules cannot check enrollment per
/// student (one read each, far over the per-request limit), so this
/// repository is where "the student belongs to this section on this date" is
/// enforced; see the milestone doc for what that does and doesn't cover.
class FirebaseStudentAttendanceRepository
    implements StudentAttendanceRepository {
  final FirebaseFirestore _firestore;

  /// Safety cap for range reads (a 31-day month of ~100 students ≈ 3,100).
  static const int maxRangeRows = 4000;

  FirebaseStudentAttendanceRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _branch(
    String schoolId,
    String branchId,
  ) => _firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> _records(String s, String b) =>
      _branch(s, b).collection(FirestoreFields.studentAttendanceCollection);

  CollectionReference<Map<String, dynamic>> _sessions(String s, String b) =>
      _branch(s, b).collection(FirestoreFields.attendanceSessionsCollection);

  @override
  Future<StudentRegister> loadRegister({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    required DateTime date,
  }) async {
    try {
      final dateKey = AttendanceDate.key(date);

      final enrollment = await _firestore
          .collectionGroup('academicRecords')
          .where(FirestoreFields.schoolId, isEqualTo: schoolId)
          .where(FirestoreFields.branchId, isEqualTo: branchId)
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .get();

      final recordByStudent = <String, StudentAcademicRecord>{};
      for (final doc in enrollment.docs) {
        final studentId =
            (doc.data()['studentId'] as String?) ??
            doc.reference.parent.parent!.id;
        final record = StudentAcademicRecord.fromFirestore(
          schoolId,
          branchId,
          studentId,
          doc.id,
          doc.data(),
        );
        if (EnrollmentEligibility.recordCovers(record, date)) {
          recordByStudent[studentId] = record;
        }
      }

      final existing = await _records(schoolId, branchId)
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where('dateKey', isEqualTo: dateKey)
          .get();
      final records = {
        for (final d in existing.docs)
          (d.data()['studentId'] as String): StudentAttendance.fromFirestore(
            schoolId,
            branchId,
            d.id,
            d.data(),
          ),
      };

      final students = await _studentsByIds(schoolId, branchId, {
        ...recordByStudent.keys,
        ...records.keys,
      });

      final roster = <EnrolledStudent>[];
      final recordOnly = <Student>[];
      for (final student in students) {
        final record = recordByStudent[student.studentId];
        final stillEnrolled = EnrollmentEligibility.studentStillEnrolled(
          status: student.status,
          statusChangeDate: student.statusChangeDate,
          date: date,
        );
        if (record != null && stillEnrolled) {
          roster.add(
            EnrolledStudent(
              student: student,
              academicRecordId: record.recordId,
            ),
          );
        } else if (records.containsKey(student.studentId)) {
          recordOnly.add(student);
        }
      }
      roster.sort((a, b) => _byRollThenName(a.student, b.student));
      recordOnly.sort(_byRollThenName);

      final daySnapshot = await _sessions(schoolId, branchId)
          .doc(
            AttendanceDay.studentSessionId(
              dateKey: dateKey,
              academicYearId: academicYearId,
              classId: classId,
              sectionId: sectionId,
            ),
          )
          .get();
      final day = daySnapshot.exists
          ? AttendanceDay.fromFirestore(
              schoolId,
              branchId,
              daySnapshot.id,
              daySnapshot.data()!,
            )
          : null;

      return StudentRegister(
        roster: roster,
        records: records,
        day: day,
        recordOnly: recordOnly,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  int _byRollThenName(Student a, Student b) {
    final ra = int.tryParse(a.currentRollNumber ?? '');
    final rb = int.tryParse(b.currentRollNumber ?? '');
    if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
    if (ra != null && rb == null) return -1;
    if (ra == null && rb != null) return 1;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  /// The students named by the section's enrolment/attendance records, read
  /// one document at a time. (A `whereIn documentId` list cannot be proven
  /// readable for a teacher — rules are not filters — whereas each `get` is
  /// judged on that student's own placement.) A student the caller may no
  /// longer read (moved to a section they do not teach) is skipped, so one
  /// unreadable student never fails the whole register.
  Future<List<Student>> _studentsByIds(
    String schoolId,
    String branchId,
    Set<String> ids,
  ) async {
    final students = _branch(
      schoolId,
      branchId,
    ).collection(FirestoreFields.studentsCollection);
    final fetched = await Future.wait(
      ids.map((id) async {
        try {
          final snap = await students.doc(id).get();
          return snap.exists
              ? Student.fromFirestore(schoolId, branchId, snap.id, snap.data()!)
              : null;
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied') return null;
          rethrow;
        }
      }),
    );
    return [
      for (final s in fetched)
        if (s != null) s,
    ];
  }

  @override
  Future<void> saveRegister(SaveStudentRegisterRequest r) async {
    try {
      final records = _records(r.schoolId, r.branchId);
      await AttendanceRegisterTransaction.run(
        firestore: _firestore,
        dayRef: _sessions(r.schoolId, r.branchId).doc(
          AttendanceDay.studentSessionId(
            dateKey: r.dateKey,
            academicYearId: r.academicYearId,
            classId: r.classId,
            sectionId: r.sectionId,
          ),
        ),
        recordsCollection: records,
        entries: r.entries,
        recordIdFor: (e) => StudentAttendance.idFor(r.dateKey, e.subjectId),
        currentFrom: (d) => CurrentAttendance(
          revision: (d['revision'] as num?)?.toInt() ?? 1,
          status: AttendanceStatus.fromWireValue(
            d[FirestoreFields.status] as String,
          ),
          remarks: d['remarks'] as String?,
          sectionId: d['sectionId'] as String?,
        ),
        createData: (w, reason) =>
            _record(r, w, reason).toFirestoreCreate(createdBy: r.actorId),
        updateData: (w, reason) =>
            _record(r, w, reason).toFirestoreUpdate(updatedBy: r.actorId),
        historyData: (w, reason, actor) => {
          FirestoreFields.schoolId: r.schoolId,
          FirestoreFields.branchId: r.branchId,
          'academicYearId': r.academicYearId,
          'classId': r.classId,
          'sectionId': r.sectionId,
          'dateKey': r.dateKey,
          'studentId': w.entry.subjectId,
          'revision': w.newRevision,
          'previousStatus': w.previousStatus?.wireValue,
          'previousRemarks': w.previousRemarks,
          'newStatus': w.newStatus.wireValue,
          'newRemarks': w.newRemarks,
          'reason': reason,
          'changedBy': actor,
          'changedAt': FieldValue.serverTimestamp(),
        },
        buildDay: (revision, status, tally) => AttendanceDay(
          dayId: AttendanceDay.studentSessionId(
            dateKey: r.dateKey,
            academicYearId: r.academicYearId,
            classId: r.classId,
            sectionId: r.sectionId,
          ),
          schoolId: r.schoolId,
          branchId: r.branchId,
          academicYearId: r.academicYearId,
          classId: r.classId,
          sectionId: r.sectionId,
          dateKey: r.dateKey,
          status: status,
          tally: tally,
          dayKind: r.dayKind,
          overrideReason: r.overrideReason,
          revision: revision,
        ),
        createDay: (day, actor) => day.toFirestoreCreate(createdBy: actor),
        expectedDayRevision: r.expectedDayRevision,
        finalize: r.finalize,
        reason: r.reason,
        actorId: r.actorId,
        sectionId: r.sectionId,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  StudentAttendance _record(
    SaveStudentRegisterRequest r,
    PlannedWrite w,
    String? reason,
  ) {
    return StudentAttendance(
      attendanceId: StudentAttendance.idFor(r.dateKey, w.entry.subjectId),
      schoolId: r.schoolId,
      branchId: r.branchId,
      academicYearId: r.academicYearId,
      dateKey: r.dateKey,
      studentId: w.entry.subjectId,
      academicRecordId: w.entry.academicRecordId ?? '',
      classId: r.classId,
      sectionId: r.sectionId,
      status: w.newStatus,
      remarks: w.newRemarks,
      revision: w.newRevision,
      lastChangeReason: reason,
    );
  }

  @override
  Future<List<AttendanceDay>> fetchSessions({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String dateKey,
    String? classId,
    String? sectionId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _sessions(schoolId, branchId)
          .where('dateKey', isEqualTo: dateKey)
          .where('academicYearId', isEqualTo: academicYearId);
      if (classId != null) q = q.where('classId', isEqualTo: classId);
      if (sectionId != null) q = q.where('sectionId', isEqualTo: sectionId);
      final snapshot = await q.limit(500).get();
      return snapshot.docs
          .map(
            (d) =>
                AttendanceDay.fromFirestore(schoolId, branchId, d.id, d.data()),
          )
          .toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AttendanceRange<StudentAttendance>> fetchSectionRange({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final snapshot = await _records(schoolId, branchId)
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .orderBy('dateKey')
          .limit(maxRangeRows)
          .get();
      return AttendanceRange(
        snapshot.docs
            .map(
              (d) => StudentAttendance.fromFirestore(
                schoolId,
                branchId,
                d.id,
                d.data(),
              ),
            )
            .toList(),
        truncated: snapshot.docs.length >= maxRangeRows,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AttendanceRange<StudentAttendance>> fetchStudentRange({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final snapshot = await _records(schoolId, branchId)
          .where('studentId', isEqualTo: studentId)
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .orderBy('dateKey')
          .limit(maxRangeRows)
          .get();
      return AttendanceRange(
        snapshot.docs
            .map(
              (d) => StudentAttendance.fromFirestore(
                schoolId,
                branchId,
                d.id,
                d.data(),
              ),
            )
            .toList(),
        truncated: snapshot.docs.length >= maxRangeRows,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<AttendanceHistoryEntry>> fetchHistory({
    required String schoolId,
    required String branchId,
    required String attendanceId,
  }) async {
    try {
      final snapshot = await _records(schoolId, branchId)
          .doc(attendanceId)
          .collection(FirestoreFields.attendanceHistoryCollection)
          .orderBy('revision')
          .get();
      return snapshot.docs
          .map((d) => AttendanceHistoryEntry.fromFirestore(d.data()))
          .toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Map<String, Student>> loadStudents({
    required String schoolId,
    required String branchId,
    required Set<String> studentIds,
  }) async {
    try {
      return {
        for (final s in await _studentsByIds(schoolId, branchId, studentIds))
          s.studentId: s,
      };
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
