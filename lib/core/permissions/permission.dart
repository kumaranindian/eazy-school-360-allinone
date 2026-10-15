/// Fine-grained, feature-agnostic capabilities. UI and repositories check
/// `tenantContext.can(Permission.x)` — never `role == UserRole.schoolAdmin`
/// directly — so a future role or a future feature only has to extend
/// [RolePermissions], not hunt down scattered role checks.
///
/// Kept intentionally small: only permissions exercised by what exists so
/// far. Business features (students, fees, attendance, ...) add their own
/// permissions when they're built, following the same pattern.
enum Permission {
  managePlatform,
  manageSchool,
  manageBranches,
  manageUsers,
  viewUsers,
  manageOwnProfile,

  /// Create/edit/activate academic years, classes, sections, subjects,
  /// class-subject links, working days, and the holiday calendar.
  manageAcademicSetup,

  /// Read-only access to the same academic configuration — granted more
  /// broadly than [manageAcademicSetup] (e.g. teachers checking the
  /// holiday calendar or class list) without allowing changes.
  viewAcademicSetup,

  /// Create/edit students, parents, parent-student relationships, academic
  /// enrollment records, transfers, and withdrawals (Milestone 3).
  manageStudentData,

  /// Read-only access to student/parent master data — granted to teacher
  /// and finance roles for their own branch. Deliberately NOT granted to
  /// [UserRole.parent] — a parent's access to a student is relationship-
  /// based (see `firestore.rules` → `canAccessAsParent`), never this
  /// general permission, so a parent can never browse the full roster.
  viewStudentData,

  /// The branch-wide parent/guardian directory (list + profile pages) —
  /// administrators and finance. Deliberately NOT a teacher permission: a
  /// teacher reaches a parent only through their own student's profile
  /// (`firestore.rules` → `teacherOfParent`), never by browsing the branch.
  viewParents,

  /// Create/edit staff, departments, designations, lifecycle status,
  /// teacher assignments, staff photos and documents (Milestone 4).
  manageStaff,

  /// Read-only access to the staff directory — granted to finance for
  /// their own branch (payroll groundwork). Deliberately NOT granted to
  /// [UserRole.teacher]: a teacher sees only their own record
  /// ([viewOwnStaffProfile]), not colleagues' personal data.
  viewStaff,

  /// Open `/my-profile`: one's own linked staff record and teaching
  /// assignments. Granted to the roles that do NOT get [viewStaff]-style
  /// directory access (teacher) or that want it alongside it (finance);
  /// administrators browse the directory instead. `firestore.rules` is what
  /// actually limits the reads to the caller's own record.
  viewOwnStaffProfile,

  /// Open the attendance area (`/attendance`). The more specific
  /// permissions below decide what is offered inside it.
  viewAttendance,

  /// Mark student attendance. A holder is not thereby allowed every class:
  /// teachers are limited, by `firestore.rules` and the UI, to the sections
  /// they are class teacher of (Milestone 4 assignments); admins to their
  /// branch scope.
  markStudentAttendance,

  /// Mark staff attendance; correct finalized attendance (with a reason);
  /// override the working-day calendar; see school-wide attendance reports.
  manageAttendance,

  /// Read staff attendance (finance: payroll groundwork). Does not allow
  /// writing it — that is [manageAttendance].
  viewStaffAttendance,

  /// Open the fees area and read fee structures, assignments, invoices,
  /// payments and receipts of the branch (Milestone 6).
  viewFees,

  /// Create, edit, activate and deactivate fee structures.
  manageFeeStructures,

  /// Assign fee heads to students.
  assignFees,

  /// Generate and issue invoices.
  issueInvoices,

  /// Record payments and issue receipts.
  collectPayments,

  /// Grant concessions at assignment time and approve post-issue waivers.
  grantConcessions,

  /// Void an unpaid invoice.
  voidInvoices,

  /// Reverse or refund a recorded payment.
  reversePayments,

  /// Fee dashboard and reports.
  viewFeeReports,

  /// A parent's read-only view of the fees, invoices, payments and receipts of
  /// their LINKED children. Holding this opens the screen; which children
  /// appear is decided by `firestore.rules` (an ACTIVE, portal-enabled link).
  viewOwnChildFees,

  /// Leave dashboard, applications, balances and calendar for the branch.
  viewLeave,

  /// Create and edit leave types and the branch leave policy.
  manageLeaveTypes,

  /// Approve, reject, return and cancel leave applications.
  reviewLeave,

  /// Adjust and carry forward staff leave balances.
  adjustLeaveBalances,

  /// Self-service: a staff member's own leave, or a parent's children's.
  viewOwnLeave,

  /// The leave calendar (approved leave only, no reasons).
  viewLeaveCalendar,

  /// Leave reports and summaries.
  viewLeaveReports,

  /// Timetable overview, class/section and teacher timetables, history.
  viewTimetable,

  /// Create, edit, copy and archive timetable drafts and bell schedules.
  manageTimetable,

  /// Publish a timetable version (replacing or ending the one in force).
  publishTimetable,

  /// Assign, change and cancel teacher substitutions.
  manageSubstitutions,

  /// A teacher's own timetable and covers, or a parent's view of the linked
  /// child's class timetable.
  viewOwnTimetable,

  /// Homework lists and details: a teacher's own, or the branch's for admins.
  viewHomework,

  /// Create, edit, publish, extend, close and archive homework (for the
  /// sections and subjects the person is assigned, or any as an admin).
  manageHomework,

  /// Review submissions: grade, return for revision, mark reviewed.
  reviewSubmissions,

  /// A parent's view of the linked children's homework, and submitting it.
  viewOwnHomework,

  /// Read announcements addressed to the person.
  viewAnnouncements,

  /// Create, publish, update and archive announcements (teachers: only to a
  /// section they are class teacher of — enforced by the rules).
  manageAnnouncements,

  /// Examinations, grading schemes, marks sheets and results of the branch
  /// (read), plus academic performance summaries.
  viewExams,

  /// Create and configure examinations and grading schemes; open marks
  /// entry; cancel, withdraw and reopen.
  manageExams,

  /// Enter and submit marks (a teacher: only for sections and subjects they
  /// are assigned — enforced by the rules).
  enterMarks,

  /// Review and approve marks, finalise and publish results.
  approveResults,

  /// A parent's view of the linked children's published results.
  viewOwnResults,

  /// The notification centre and preferences (every signed-in role).
  viewNotifications,

  /// Parent–teacher conversations: parents and teachers converse; an
  /// administrator sees only conversations a member has reported.
  useMessages,
}
