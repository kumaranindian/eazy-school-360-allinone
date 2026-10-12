import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../../staff/domain/staff.dart';
import '../domain/attendance_date.dart';
import '../domain/attendance_day.dart';
import '../domain/attendance_history_entry.dart';
import '../domain/attendance_registers.dart';
import '../domain/attendance_save_planner.dart';
import '../domain/attendance_status.dart';
import '../domain/staff_attendance.dart';
import '../domain/staff_attendance_repository.dart';
import '../domain/staff_eligibility.dart';
import 'attendance_register_transaction.dart';

/// `/schools/{s}/branches/{b}/staffAttendance/{dateKey}_{staffId}` (+
/// `/history/{revision}`) and `staffAttendanceDays/{dateKey}`.
///
/// Who appears on a date's register is decided by [StaffEligibility] from the
/// staff record (joining date, status and status-change date); nobody is
/// marked automatically. The branch's staff are read in pages of 200 (cap
/// 1,000) — a register needs the whole branch, but never unbounded.
class FirebaseStaffAttendanceRepository implements StaffAttendanceRepository {
  final FirebaseFirestore _firestore;

  static const int pageSize = 200;
  static const int maxStaff = 1000;
  static const int maxRangeRows = 4000;

  FirebaseStaffAttendanceRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _branch(String s, String b) =>
      _firestore
          .collection(FirestoreFields.schoolsCollection)
          .doc(s)
          .collection(FirestoreFields.branchesCollection)
          .doc(b);

  CollectionReference<Map<String, dynamic>> _records(String s, String b) =>
      _branch(s, b).collection(FirestoreFields.staffAttendanceCollection);

  CollectionReference<Map<String, dynamic>> _days(String s, String b) =>
      _branch(s, b).collection(FirestoreFields.staffAttendanceDaysCollection);

  @override
  Future<StaffRegister> loadRegister({
    required String schoolId,
    required String branchId,
    required DateTime date,
  }) async {
    try {
      final dateKey = AttendanceDate.key(date);

      final roster = <Staff>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      var read = 0;
      while (read < maxStaff) {
        Query<Map<String, dynamic>> q = _branch(schoolId, branchId)
            .collection(FirestoreFields.staffCollection)
            .orderBy('displayNameLower')
            .limit(pageSize);
        if (cursor != null) q = q.startAfterDocument(cursor);
        final page = await q.get();
        for (final d in page.docs) {
          final staff = Staff.fromFirestore(schoolId, branchId, d.id, d.data());
          if (StaffEligibility.isEligible(
            status: staff.status,
            joiningDate: staff.joiningDate,
            statusChangeDate: staff.statusChangeDate,
            date: date,
          )) {
            roster.add(staff);
          }
        }
        read += page.docs.length;
        if (page.docs.length < pageSize) break;
        cursor = page.docs.last;
      }

      final existing = await _records(
        schoolId,
        branchId,
      ).where('dateKey', isEqualTo: dateKey).get();
      final records = {
        for (final d in existing.docs)
          (d.data()['staffId'] as String): StaffAttendance.fromFirestore(
            schoolId,
            branchId,
            d.id,
            d.data(),
          ),
      };
      final daySnapshot = await _days(
        schoolId,
        branchId,
      ).doc(AttendanceDay.staffDayId(dateKey)).get();
      final day = daySnapshot.exists
          ? AttendanceDay.fromFirestore(
              schoolId,
              branchId,
              daySnapshot.id,
              daySnapshot.data()!,
            )
          : null;

      return StaffRegister(roster: roster, records: records, day: day);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> saveRegister(SaveStaffRegisterRequest r) async {
    try {
      StaffAttendance record(PlannedWrite w, String? reason) => StaffAttendance(
        attendanceId: StaffAttendance.idFor(r.dateKey, w.entry.subjectId),
        schoolId: r.schoolId,
        branchId: r.branchId,
        dateKey: r.dateKey,
        staffId: w.entry.subjectId,
        status: w.newStatus,
        remarks: w.newRemarks,
        revision: w.newRevision,
        lastChangeReason: reason,
      );

      await AttendanceRegisterTransaction.run(
        firestore: _firestore,
        dayRef: _days(
          r.schoolId,
          r.branchId,
        ).doc(AttendanceDay.staffDayId(r.dateKey)),
        recordsCollection: _records(r.schoolId, r.branchId),
        entries: r.entries,
        recordIdFor: (e) => StaffAttendance.idFor(r.dateKey, e.subjectId),
        currentFrom: (d) => CurrentAttendance(
          revision: (d['revision'] as num?)?.toInt() ?? 1,
          status: AttendanceStatus.fromWireValue(
            d[FirestoreFields.status] as String,
          ),
          remarks: d['remarks'] as String?,
        ),
        createData: (w, reason) =>
            record(w, reason).toFirestoreCreate(createdBy: r.actorId),
        updateData: (w, reason) =>
            record(w, reason).toFirestoreUpdate(updatedBy: r.actorId),
        historyData: (w, reason, actor) => {
          FirestoreFields.schoolId: r.schoolId,
          FirestoreFields.branchId: r.branchId,
          'dateKey': r.dateKey,
          'staffId': w.entry.subjectId,
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
          dayId: AttendanceDay.staffDayId(r.dateKey),
          schoolId: r.schoolId,
          branchId: r.branchId,
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
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AttendanceDay?> fetchDay({
    required String schoolId,
    required String branchId,
    required String dateKey,
  }) async {
    try {
      final snapshot = await _days(
        schoolId,
        branchId,
      ).doc(AttendanceDay.staffDayId(dateKey)).get();
      return snapshot.exists
          ? AttendanceDay.fromFirestore(
              schoolId,
              branchId,
              snapshot.id,
              snapshot.data()!,
            )
          : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AttendanceRange<StaffAttendance>> fetchRange({
    required String schoolId,
    required String branchId,
    required String fromKey,
    required String toKey,
    String? staffId,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _records(schoolId, branchId);
      if (staffId != null) q = q.where('staffId', isEqualTo: staffId);
      q = q
          .where('dateKey', isGreaterThanOrEqualTo: fromKey)
          .where('dateKey', isLessThanOrEqualTo: toKey)
          .orderBy('dateKey')
          .limit(maxRangeRows);
      final snapshot = await q.get();
      return AttendanceRange(
        snapshot.docs
            .map(
              (d) => StaffAttendance.fromFirestore(
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
}
