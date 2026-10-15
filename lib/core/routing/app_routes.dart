import '../permissions/permission.dart';

/// Centralized route path constants. Add one line here per new top-level
/// route instead of letting path strings scatter through the app — future
/// feature modules should only need to add a constant + a route entry in
/// `app_router.dart`, never touch unrelated routes.
abstract final class AppRoutes {
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String accountInactive = '/account-inactive';
  static const String createSchool = '/create-school';
  static const String dashboard = '/dashboard';
  static const String school = '/school';
  static const String users = '/users';

  /// Settings/academic-configuration section (Milestone 2) — `/settings`
  /// is the overview/checklist; the rest are its children. Deliberately
  /// flat (no `academicYearId` segment) — the page itself holds "which
  /// academic year am I viewing" as local state, via `AcademicYearSelector`.
  static const String settings = '/settings';
  static const String settingsBranches = '/settings/branches';
  static const String settingsAcademicYears = '/settings/academic-years';
  static const String settingsClasses = '/settings/classes';
  static const String settingsSections = '/settings/sections';
  static const String settingsSubjects = '/settings/subjects';
  static const String settingsWorkingDays = '/settings/working-days';
  static const String settingsHolidays = '/settings/holidays';
  static const String settingsAuthentication = '/settings/authentication';

  /// Student + Parent management (Milestone 3). `:studentId`/`:parentId`
  /// are the route *templates* (see note on [requiredPermissions] below),
  /// matching `GoRouterState.fullPath`, not a literal path.
  static const String students = '/students';
  static const String newStudent = '/students/new';
  static const String studentProfile = '/students/:studentId';
  static const String parents = '/parents';
  static const String parentProfile = '/parents/:parentId';

  /// Staff + Teacher management (Milestone 4). `/teachers` is a sibling view
  /// of `/staff` (same nav destination); `/my-profile` is the signed-in
  /// user's own staff/teaching profile.
  static const String staff = '/staff';
  static const String newStaff = '/staff/new';
  static const String staffDepartments = '/staff/departments';
  static const String staffDesignations = '/staff/designations';
  static const String staffProfile = '/staff/:staffId';
  static const String editStaff = '/staff/:staffId/edit';
  static const String teachers = '/teachers';
  static const String myProfile = '/my-profile';

  /// Attendance (Milestone 5).
  static const String attendance = '/attendance';
  static const String studentAttendance = '/attendance/students';
  static const String staffAttendance = '/attendance/staff';
  static const String attendanceReports = '/attendance/reports';

  /// Fees (Milestone 6). `/my-fees` is the parent's read-only view.
  static const String fees = '/fees';
  static const String feeStructures = '/fees/structures';
  static const String feeAssignments = '/fees/assign';
  static const String invoices = '/fees/invoices';
  static const String generateInvoices = '/fees/invoices/generate';
  static const String invoiceDetail = '/fees/invoices/:invoiceId';
  static const String feePayments = '/fees/payments';
  static const String receiptDetail = '/fees/receipts/:receiptId';
  static const String feeReports = '/fees/reports';
  static const String myFees = '/my-fees';
  static const String myFeesInvoice = '/my-fees/invoices/:invoiceId';
  static const String myFeesReceipt = '/my-fees/receipts/:receiptId';

  /// Leave (Milestone 7). `/my-leave` is the self-service area: a staff
  /// member's own leave, or a parent's children's.
  static const String leave = '/leave';
  static const String leaveApplications = '/leave/applications';
  static const String leaveApplicationDetail =
      '/leave/applications/:applicationId';
  static const String leaveApply = '/leave/apply';
  static const String leaveTypes = '/leave/types';
  static const String leaveBalances = '/leave/balances';
  static const String leaveCalendar = '/leave/calendar';
  static const String leaveReports = '/leave/reports';
  static const String myLeave = '/my-leave';
  static const String myLeaveApply = '/my-leave/apply';
  static const String myLeaveApplication =
      '/my-leave/applications/:applicationId';
  static const String myLeaveNotifications = '/my-leave/notifications';

  /// Timetable & substitution (Milestone 8). `/my-timetable` is a teacher's
  /// own timetable, or a parent's view of the linked child's class.
  static const String timetable = '/timetable';
  static const String timetablePeriods = '/timetable/periods';
  static const String timetableEditor = '/timetable/editor/:timetableId';
  static const String timetableView = '/timetable/view';
  static const String timetableTeachers = '/timetable/teachers';
  static const String timetableConflicts = '/timetable/conflicts';
  static const String timetableSubstitutions = '/timetable/substitutions';
  static const String timetableNewSubstitution = '/timetable/substitutions/new';
  static const String timetableHistory = '/timetable/history';
  static const String myTimetable = '/my-timetable';

  /// Homework, submissions and announcements (Milestone 9). `/my-homework` is
  /// a parent's view of the linked children's homework.
  static const String homework = '/homework';
  static const String homeworkNew = '/homework/new';
  static const String homeworkEdit = '/homework/edit/:homeworkId';
  static const String homeworkDetail = '/homework/detail/:homeworkId';
  static const String homeworkReview = '/homework/review/:homeworkId';
  static const String homeworkSubmission =
      '/homework/review/:homeworkId/:studentId';
  static const String myHomework = '/my-homework';
  static const String myHomeworkDetail = '/my-homework/:homeworkId/:studentId';
  static const String announcements = '/announcements';
  static const String announcementNew = '/announcements/new';
  static const String announcementEdit = '/announcements/edit/:announcementId';
  static const String announcementDetail =
      '/announcements/detail/:announcementId';

  /// Examinations, marks and results (Milestone 10). `/my-results` is a
  /// parent's view of the linked children's published results.
  static const String exams = '/exams';
  static const String examNew = '/exams/new';
  static const String examEdit = '/exams/edit/:examId';
  static const String examSchemes = '/exams/schemes';
  static const String examPerformance = '/exams/performance';
  static const String examDetail = '/exams/detail/:examId';
  static const String examMarks = '/exams/marks/:examId/:subjectId/:sectionId';
  static const String examReview = '/exams/review/:examId';
  static const String examResults = '/exams/results/:examId';
  static const String examStudentResult = '/exams/results/:examId/:studentId';
  static const String examHistory = '/exams/history/:examId';
  static const String myResults = '/my-results';
  static const String myResult = '/my-results/:examId/:studentId';

  /// Notification centre and parent–teacher messages (Milestone 11).
  static const String notifications = '/notifications';
  static const String notificationPreferences = '/notifications/preferences';
  static const String messages = '/messages';
  static const String messageNew = '/messages/new';
  static const String messageThread = '/messages/:conversationId';

  /// The single place a route declares the permission needed to open it.
  /// The router redirects away when it's missing, and `AppShell` hides the
  /// matching nav destination — neither keeps its own list. Routes absent
  /// from this map only require a resolved tenant.
  ///
  /// School Profile and Branches keep their existing Milestone 1
  /// permissions (`manageSchool`/`manageBranches` — school/platform admin
  /// only); the academic-configuration and student/parent pages use the
  /// broader `viewAcademicSetup`/`viewStudentData` (also granted to branch
  /// admins, teachers, and finance) since those roles need read access
  /// even though only the `manage*` holders see the edit controls within
  /// each page. `newStudent` requires `manageStudentData` specifically —
  /// a view-only role should never reach the admission wizard at all.
  ///
  /// Keyed by [GoRouterState.fullPath] (the route's configured template,
  /// e.g. `/students/:studentId`), not `matchedLocation` (the resolved
  /// path with real values) — the router's redirect compares against
  /// `fullPath` for exactly this reason: a static route's `fullPath` and
  /// `matchedLocation` are identical, so this is a safe, non-breaking
  /// lookup key for every pre-Milestone-3 route too.
  static const Map<String, Permission> requiredPermissions = {
    school: Permission.manageSchool,
    users: Permission.viewUsers,
    settings: Permission.viewAcademicSetup,
    settingsBranches: Permission.manageBranches,
    settingsAcademicYears: Permission.viewAcademicSetup,
    settingsClasses: Permission.viewAcademicSetup,
    settingsSections: Permission.viewAcademicSetup,
    settingsSubjects: Permission.viewAcademicSetup,
    settingsWorkingDays: Permission.viewAcademicSetup,
    settingsHolidays: Permission.viewAcademicSetup,
    settingsAuthentication: Permission.manageSchool,
    students: Permission.viewStudentData,
    newStudent: Permission.manageStudentData,
    studentProfile: Permission.viewStudentData,
    parents: Permission.viewParents,
    parentProfile: Permission.viewParents,
    staff: Permission.viewStaff,
    newStaff: Permission.manageStaff,
    staffDepartments: Permission.viewStaff,
    staffDesignations: Permission.viewStaff,
    staffProfile: Permission.viewStaff,
    editStaff: Permission.manageStaff,
    teachers: Permission.viewStaff,
    myProfile: Permission.viewOwnStaffProfile,
    attendance: Permission.viewAttendance,
    studentAttendance: Permission.markStudentAttendance,
    staffAttendance: Permission.viewStaffAttendance,
    attendanceReports: Permission.viewAttendance,
    fees: Permission.viewFees,
    feeStructures: Permission.viewFees,
    feeAssignments: Permission.assignFees,
    invoices: Permission.viewFees,
    generateInvoices: Permission.issueInvoices,
    invoiceDetail: Permission.viewFees,
    feePayments: Permission.viewFees,
    receiptDetail: Permission.viewFees,
    feeReports: Permission.viewFeeReports,
    myFees: Permission.viewOwnChildFees,
    myFeesInvoice: Permission.viewOwnChildFees,
    myFeesReceipt: Permission.viewOwnChildFees,
    leave: Permission.viewLeave,
    leaveApplications: Permission.viewLeave,
    leaveApplicationDetail: Permission.viewLeave,
    leaveApply: Permission.reviewLeave,
    leaveTypes: Permission.viewLeave,
    leaveBalances: Permission.viewLeave,
    leaveCalendar: Permission.viewLeaveCalendar,
    leaveReports: Permission.viewLeaveReports,
    myLeave: Permission.viewOwnLeave,
    myLeaveApply: Permission.viewOwnLeave,
    myLeaveApplication: Permission.viewOwnLeave,
    myLeaveNotifications: Permission.viewOwnLeave,
    timetable: Permission.viewTimetable,
    timetablePeriods: Permission.viewTimetable,
    timetableEditor: Permission.manageTimetable,
    timetableView: Permission.viewTimetable,
    timetableTeachers: Permission.viewTimetable,
    timetableConflicts: Permission.viewTimetable,
    timetableSubstitutions: Permission.viewTimetable,
    timetableNewSubstitution: Permission.manageSubstitutions,
    timetableHistory: Permission.viewTimetable,
    myTimetable: Permission.viewOwnTimetable,
    homework: Permission.viewHomework,
    homeworkNew: Permission.manageHomework,
    homeworkEdit: Permission.manageHomework,
    homeworkDetail: Permission.viewHomework,
    homeworkReview: Permission.reviewSubmissions,
    homeworkSubmission: Permission.reviewSubmissions,
    myHomework: Permission.viewOwnHomework,
    myHomeworkDetail: Permission.viewOwnHomework,
    announcements: Permission.viewAnnouncements,
    announcementNew: Permission.manageAnnouncements,
    announcementEdit: Permission.manageAnnouncements,
    announcementDetail: Permission.viewAnnouncements,
    exams: Permission.viewExams,
    examNew: Permission.manageExams,
    examEdit: Permission.manageExams,
    examSchemes: Permission.manageExams,
    examPerformance: Permission.viewExams,
    examDetail: Permission.viewExams,
    examMarks: Permission.enterMarks,
    examReview: Permission.approveResults,
    examResults: Permission.approveResults,
    examStudentResult: Permission.approveResults,
    examHistory: Permission.approveResults,
    myResults: Permission.viewOwnResults,
    myResult: Permission.viewOwnResults,
    notifications: Permission.viewNotifications,
    notificationPreferences: Permission.viewNotifications,
    messages: Permission.useMessages,
    messageNew: Permission.useMessages,
    messageThread: Permission.useMessages,
  };
}
