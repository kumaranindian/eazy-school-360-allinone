import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/activation_status.dart';
import '../../../core/constants/firestore_fields.dart';
import '../domain/academic_record_status.dart';
import '../domain/parent_student_link.dart';
import '../domain/student.dart';
import '../domain/student_academic_record.dart';
import '../domain/student_status.dart';

/// One document write of a plan, as a path + data pair so the exact documents
/// can be exported as a fixture and replayed against `firestore.rules`
/// (test/students/branch_transfer_write_contract_test.dart).
class PlannedWrite {
  final bool isCreate; // set (create) vs update
  final String path;
  final Map<String, dynamic> data;
  const PlannedWrite.create(this.path, this.data) : isCreate = true;
  const PlannedWrite.update(this.path, this.data) : isCreate = false;
}

/// A guardian of the student being moved.
class TransferGuardian {
  final String parentId;

  /// The guardian's record in the old branch (a copy is made in the new one if
  /// it has none). Null when [existsInDestination].
  final Map<String, dynamic>? parentData;
  final bool existsInDestination;

  /// The ACTIVE link in the old branch.
  final ParentStudentLink link;

  const TransferGuardian({
    required this.parentId,
    required this.parentData,
    required this.existsInDestination,
    required this.link,
  });
}

class BranchTransferInput {
  final Student source;
  final String toBranchId;
  final String admissionNumber;
  final String academicYearId;
  final String classId;
  final String sectionId;
  final String? rollNumber;
  final String? reason;
  final DateTime effectiveDate;
  final String actorId;
  final String? activeSourceRecordId;
  final String destinationRecordId;
  final String transferId;
  final List<TransferGuardian> guardians;

  const BranchTransferInput({
    required this.source,
    required this.toBranchId,
    required this.admissionNumber,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.rollNumber,
    this.reason,
    required this.effectiveDate,
    required this.actorId,
    this.activeSourceRecordId,
    required this.destinationRecordId,
    required this.transferId,
    this.guardians = const [],
  });
}

/// Moves a student from one branch to another as ONE atomic batch.
///
/// * History stays where it happened: attendance, fees, marks and academic
///   records remain in the old branch, readable there; the old student record
///   becomes `TRANSFERRED` and points to the new one (`transferredTo`).
/// * The new branch gets the student (same id, a fresh admission number,
///   `transferredFrom`) already placed in a section, so there is never a
///   half-admitted student, plus a copy of each guardian and link so families
///   keep their access under the same parent id.
/// * `schools/{s}/studentTransfers/{id}` records who moved whom, when and why.
abstract final class BranchTransferWrites {
  static String _studentPath(String s, String b, String id) =>
      'schools/$s/branches/$b/students/$id';

  /// A problem with the request itself, or null. The repository adds the
  /// checks that need data (admission number free, section belongs to class).
  static String? validate(BranchTransferInput i) {
    final s = i.source;
    if (i.toBranchId.isEmpty) return 'Choose the branch to move to.';
    if (i.toBranchId == s.branchId) {
      return 'The student is already in that branch.';
    }
    if (s.status != StudentStatus.active) {
      return 'Only an active student can be moved to another branch.';
    }
    if (i.admissionNumber.trim().isEmpty) {
      return 'Enter the admission number in the new branch.';
    }
    if (i.academicYearId.isEmpty || i.classId.isEmpty || i.sectionId.isEmpty) {
      return 'Choose the class and section in the new branch.';
    }
    return null;
  }

  static List<PlannedWrite> plan(BranchTransferInput i) {
    final problem = validate(i);
    if (problem != null) throw ArgumentError(problem);
    final s = i.source;
    final schoolId = s.schoolId;
    final from = s.branchId;
    final to = i.toBranchId;
    final fromPath = _studentPath(schoolId, from, s.studentId);
    final toPath = _studentPath(schoolId, to, s.studentId);
    final admission = i.admissionNumber.trim();

    final destination = Student(
      studentId: s.studentId,
      schoolId: schoolId,
      branchId: to,
      admissionNumber: admission,
      studentCode: s.studentCode,
      firstName: s.firstName,
      middleName: s.middleName,
      lastName: s.lastName,
      dateOfBirth: s.dateOfBirth,
      gender: s.gender,
      bloodGroup: s.bloodGroup,
      photoUrl: null, // the photo file lives in the old branch's folder
      email: s.email,
      phone: s.phone,
      addressLine1: s.addressLine1,
      addressLine2: s.addressLine2,
      city: s.city,
      state: s.state,
      country: s.country,
      postalCode: s.postalCode,
      admissionDate: i.effectiveDate,
      status: StudentStatus.active,
    );

    final record = StudentAcademicRecord(
      recordId: i.destinationRecordId,
      studentId: s.studentId,
      schoolId: schoolId,
      branchId: to,
      academicYearId: i.academicYearId,
      classId: i.classId,
      sectionId: i.sectionId,
      rollNumber: i.rollNumber,
      startDate: i.effectiveDate,
      status: AcademicRecordStatus.active,
    );

    final writes = <PlannedWrite>[
      PlannedWrite.create(toPath, {
        ...destination.toFirestoreCreate(createdBy: i.actorId),
        'currentAcademicYearId': i.academicYearId,
        'currentClassId': i.classId,
        'currentSectionId': i.sectionId,
        'currentRollNumber': i.rollNumber,
        'transferredFrom': {
          'branchId': from,
          'studentId': s.studentId,
          'admissionNumber': s.admissionNumber,
        },
      }),
      PlannedWrite.create(
        '$toPath/academicRecords/${i.destinationRecordId}',
        record.toFirestoreCreate(createdBy: i.actorId),
      ),
    ];

    for (final g in i.guardians) {
      if (!g.existsInDestination && g.parentData != null) {
        writes.add(
          PlannedWrite.create(
            'schools/$schoolId/branches/$to/parents/${g.parentId}',
            {
              ...g.parentData!,
              FirestoreFields.schoolId: schoolId,
              FirestoreFields.branchId: to,
              FirestoreFields.createdAt: FieldValue.serverTimestamp(),
              FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
              FirestoreFields.createdBy: i.actorId,
              FirestoreFields.updatedBy: i.actorId,
            },
          ),
        );
      }
      final link = ParentStudentLink(
        relationshipId: g.parentId,
        schoolId: schoolId,
        branchId: to,
        studentId: s.studentId,
        parentId: g.parentId,
        relationshipType: g.link.relationshipType,
        isPrimary: g.link.isPrimary,
        isEmergencyContact: g.link.isEmergencyContact,
        canAccessPortal: g.link.canAccessPortal,
        status: ActivationStatus.active,
      );
      writes.add(
        PlannedWrite.create(
          '$toPath/parentLinks/${g.parentId}',
          link.toFirestoreCreate(createdBy: i.actorId),
        ),
      );
    }

    // The old record: no longer enrolled, and pointing to the new one.
    writes.add(
      PlannedWrite.update(fromPath, {
        ...Student.firestoreStatusChange(
          status: StudentStatus.transferred,
          effectiveDate: i.effectiveDate,
          reason: 'TRANSFERRED_TO_BRANCH',
          notes: i.reason,
          updatedBy: i.actorId,
        ),
        'transferredTo': {
          'branchId': to,
          'studentId': s.studentId,
          'admissionNumber': admission,
        },
      }),
    );
    if (i.activeSourceRecordId != null) {
      writes.add(
        PlannedWrite.update(
          '$fromPath/academicRecords/${i.activeSourceRecordId}',
          {
            FirestoreFields.status: AcademicRecordStatus.transferred.wireValue,
            'endDate': Timestamp.fromDate(i.effectiveDate),
            FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
            FirestoreFields.updatedBy: i.actorId,
          },
        ),
      );
    }

    writes.add(
      PlannedWrite.create(
        'schools/$schoolId/studentTransfers/${i.transferId}',
        {
          FirestoreFields.schoolId: schoolId,
          'studentId': s.studentId,
          'studentName': s.displayName,
          'fromBranchId': from,
          'toBranchId': to,
          'fromAdmissionNumber': s.admissionNumber,
          'toAdmissionNumber': admission,
          'reason': i.reason,
          'effectiveDate': Timestamp.fromDate(i.effectiveDate),
          FirestoreFields.createdAt: FieldValue.serverTimestamp(),
          FirestoreFields.createdBy: i.actorId,
        },
      ),
    );
    return writes;
  }
}
