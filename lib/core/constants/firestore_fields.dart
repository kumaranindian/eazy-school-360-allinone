/// Shared Firestore field names for tenant isolation and audit tracking.
///
/// Every tenant-owned document is expected to carry these fields — see
/// FIRESTORE_ARCHITECTURE.md for the full multi-tenancy strategy. Centralizing
/// the literal field names here means a future rename only touches one file.
abstract final class FirestoreFields {
  // Tenant isolation
  static const String schoolId = 'schoolId';
  static const String branchId = 'branchId';

  // Audit fields
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String createdBy = 'createdBy';
  static const String updatedBy = 'updatedBy';

  // Shared entity fields
  static const String status = 'status';
  static const String name = 'name';
  static const String role = 'role';

  // Collection names
  static const String usersCollection = 'users';
  static const String schoolsCollection = 'schools';
  static const String branchesCollection = 'branches';
  static const String academicYearsCollection = 'academicYears';
  static const String classesCollection = 'classes';
  static const String sectionsCollection = 'sections';
  static const String subjectsCollection = 'subjects';
  static const String classSubjectsCollection = 'classSubjects';
  static const String holidaysCollection = 'holidays';
  static const String settingsCollection = 'settings';
  static const String studentsCollection = 'students';
  static const String parentsCollection = 'parents';
  static const String academicRecordsCollection = 'academicRecords';
  static const String parentLinksCollection = 'parentLinks';

  // Staff + Teacher management (Milestone 4)
  static const String staffCollection = 'staff';
  static const String staffCodesCollection = 'staffCodes';
  static const String admissionNumbersCollection = 'admissionNumbers';
  static const String staffDocumentsCollection = 'documents';
  static const String departmentsCollection = 'departments';
  static const String designationsCollection = 'designations';
  static const String teacherAssignmentsCollection = 'teacherAssignments';
  static const String assignmentSlotsCollection = 'assignmentSlots';

  // Attendance (Milestone 5)
  static const String studentAttendanceCollection = 'studentAttendance';
  static const String staffAttendanceCollection = 'staffAttendance';
  static const String attendanceSessionsCollection = 'attendanceSessions';
  static const String staffAttendanceDaysCollection = 'staffAttendanceDays';
  static const String attendanceHistoryCollection = 'history';

  // Fees (Milestone 6)
  static const String feeStructuresCollection = 'feeStructures';
  static const String feeAssignmentsCollection = 'studentFeeAssignments';
  static const String invoicesCollection = 'invoices';
  static const String invoiceNumbersCollection = 'invoiceNumbers';
  static const String feeCountersCollection = 'feeCounters';
  static const String feeChargesCollection = 'feeCharges';
  static const String invoiceWaiversCollection = 'invoiceWaivers';
  static const String paymentsCollection = 'payments';
  static const String receiptsCollection = 'receipts';
  static const String receiptNumbersCollection = 'receiptNumbers';
  static const String paymentReversalsCollection = 'paymentReversals';
  static const String financialAuditCollection = 'financialAuditLogs';

  // Singleton settings document ids within `settings`.
  static const String workingDaysSettingsDoc = 'workingDays';
  static const String academicSettingsDoc = 'academic';

  // Leave management (Milestone 7).
  static const String leaveTypesCollection = 'leaveTypes';
  static const String leaveApplicationsCollection = 'leaveApplications';
  static const String leaveHistoryCollection = 'leaveHistory';
  static const String leaveCalendarCollection = 'leaveCalendar';
  static const String leaveDayLocksCollection = 'leaveDayLocks';
  static const String leaveBalancesCollection = 'leaveBalances';
  static const String leaveLedgerCollection = 'leaveLedger';
  static const String leaveSettingsCollection = 'leaveSettings';
  static const String notificationsCollection = 'notifications';

  // Timetable and substitution (Milestone 8).
  static const String periodSetsCollection = 'periodSets';
  static const String timetablesCollection = 'timetables';
  static const String timetableEntriesCollection = 'timetableEntries';
  static const String timetableCountersCollection = 'timetableCounters';
  static const String timetableLocksCollection = 'timetableLocks';
  static const String timetableHistoryCollection = 'timetableHistory';
  static const String substitutionsCollection = 'substitutions';
  static const String substitutionDaysCollection = 'substitutionDays';
  static const String substitutionHistoryCollection = 'substitutionHistory';

  // Homework, submissions and announcements (Milestone 9).
  static const String homeworkCollection = 'homework';
  static const String homeworkHistoryCollection = 'homeworkHistory';
  static const String homeworkSubmissionsCollection = 'homeworkSubmissions';
  static const String homeworkRevisionsCollection = 'homeworkRevisions';
  static const String announcementsCollection = 'announcements';
  static const String announcementHistoryCollection = 'announcementHistory';
  // Examinations, marks and results (Milestone 10).
  static const String gradingSchemesCollection = 'gradingSchemes';
  static const String examinationsCollection = 'examinations';
  static const String examSubjectsCollection = 'examinationSubjects';
  static const String examHistoryCollection = 'examHistory';
  static const String marksSheetsCollection = 'marksSheets';
  static const String marksEntriesCollection = 'marksEntries';
  static const String marksRevisionsCollection = 'marksRevisions';
  static const String marksSheetHistoryCollection = 'marksSheetHistory';
  static const String examRemarksCollection = 'examRemarks';
  static const String resultSummariesCollection = 'resultSummaries';
  // Notifications and communication (Milestone 11).
  static const String conversationsCollection = 'conversations';
  static const String conversationMessagesCollection = 'messages';
  static const String conversationEventsCollection = 'conversationEvents';
  static const String broadcastNoticesCollection = 'broadcastNotices';
}
