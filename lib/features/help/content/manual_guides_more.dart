import '../../../core/permissions/permission.dart';
import '../../../core/routing/app_routes.dart';
import '../domain/manual_models.dart';

// Route prefixes (no parameters) for screens whose full route needs an id.
const _examMarks = '${AppRoutes.exams}/marks';
const _examReview = '${AppRoutes.exams}/review';
const _examResults = '${AppRoutes.exams}/results';
const _homeworkReview = '${AppRoutes.homework}/review';

/// Guides for the rest of the application (timetable, staff, attendance,
/// homework, exams, communication, leave policy, reports, the parent portal,
/// FAQ). Same rule as the first set: only what the screens really offer.
const moreGuides = <ManualGuide>[
  // ───────────────────────── Staff ─────────────────────────
  ManualGuide(
    id: 'staff-add',
    categoryId: 'staff',
    title: 'Add staff and give them a login',
    summary:
        'Register a staff member, set departments and designations, and create their sign-in.',
    anyOf: {Permission.manageStaff},
    minutes: 10,
    prerequisites: [
      'Departments and designations you want to use (you can add them first).',
      'An email address for each person who will sign in.',
    ],
    keywords: [
      'staff',
      'employee',
      'teacher',
      'add staff',
      'department',
      'designation',
      'employee code',
      'login',
      'import staff',
      'deactivate',
      'status',
    ],
    contextRoutes: [AppRoutes.staff],
    related: ['teacher-assign', 'parent-login'],
    steps: [
      ManualStep(
        'Set up departments and designations',
        'Open Staff → Departments and Designations and add the ones your school uses. They appear as pick-lists on the staff form.',
        route: AppRoutes.staffDepartments,
        actionLabel: 'Open Departments',
      ),
      ManualStep(
        'Add a staff member',
        'Open Staff and choose "Add staff". Enter First name, Last name, Phone and an Employee code (for example EMP-0001; it must be unique in the branch). Choose Department, Designation, Employment type and the Joining date. Date of birth, address and other details are optional.',
        route: AppRoutes.newStaff,
        actionLabel: 'Open Add staff',
        mistake: 'Reusing an employee code that is already taken.',
      ),
      ManualStep(
        'Mark teaching staff',
        'Switch on "Has teaching responsibility" for anyone who teaches. Only these people can be assigned to classes and subjects.',
      ),
      ManualStep(
        'Or import many at once',
        'In the Staff page menu choose Import (CSV): download the sample, fill it, "Check file", review the result, then Import. Download the rows that failed, fix them and upload the corrected file. Importing never creates logins.',
      ),
      ManualStep(
        'Give them a login',
        'Open the person (or select several in the list) and choose "Give login access". Pick how the first password is set, exactly as for parents. Teachers always get the Teacher role; for other staff you choose Branch admin or Finance.',
        check: 'The staff profile shows an application account.',
      ),
      ManualStep(
        'Change status or details later',
        'On the staff profile use Edit to change details, and "Change status" to deactivate someone who has left. Use "Refresh teacher access" in the list if a teacher cannot see their classes after an assignment change.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'A teacher signs in but sees no classes.',
        'Check they have teaching responsibility and are assigned to a class and subject (Teachers → Assign). Then use "Refresh teacher access".',
      ),
    ],
  ),
  ManualGuide(
    id: 'teacher-assign',
    categoryId: 'staff',
    title: 'Assign teachers to classes and subjects',
    summary:
        'Who teaches what and where. Timetables, attendance, homework and marks all depend on this.',
    anyOf: {Permission.manageStaff, Permission.viewStaff},
    minutes: 6,
    prerequisites: [
      'The staff member exists and has teaching responsibility.',
      'The academic year, classes, sections and subjects exist.',
    ],
    keywords: [
      'assign teacher',
      'class teacher',
      'subject teacher',
      'teaching',
      'allocation',
      'teachers',
    ],
    contextRoutes: [AppRoutes.teachers],
    related: ['staff-add', 'timetable-build'],
    steps: [
      ManualStep(
        'Open the teaching staff list',
        'Open Teachers to see who teaches what, filtered by Academic year, Class, Section, Subject and Status.',
        route: AppRoutes.teachers,
        actionLabel: 'Open Teachers',
      ),
      ManualStep(
        'Open the teacher\'s Teaching tab',
        'Open the teacher\'s profile and go to the Teaching tab.',
        route: AppRoutes.staff,
        actionLabel: 'Open Staff',
      ),
      ManualStep(
        'Assign',
        'Choose Academic year, Class, Section and Subject, and tick "Class teacher" if they are the class teacher for that section. Press Assign.',
        check:
            'The assignment shows on the Teaching tab and in the Teachers list.',
        mistake:
            'Skipping this step and then wondering why the teacher cannot be chosen in the timetable or mark attendance.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'The teacher is not offered when I build the timetable.',
        'The timetable only offers a teacher assigned to that section and subject. Add the assignment first.',
      ),
    ],
  ),

  // ───────────────────────── Timetable ─────────────────────────
  ManualGuide(
    id: 'bell-schedule',
    categoryId: 'timetable',
    title: 'Set up periods and bell timings',
    summary:
        'A bell schedule lists the day\'s periods, breaks and lunch with start and end times.',
    anyOf: {Permission.manageTimetable},
    minutes: 8,
    prerequisites: [
      'The academic year exists.',
      'Working days are set (Settings → Working days).',
      'You know the school\'s period timings.',
    ],
    keywords: [
      'bell',
      'period',
      'periods',
      'bell schedule',
      'break',
      'lunch',
      'timings',
      'school timing',
      'period set',
    ],
    contextRoutes: [AppRoutes.timetablePeriods],
    related: ['timetable-build', 'school-setup'],
    steps: [
      ManualStep(
        'Open Bell schedules',
        'Open Timetable → Bell schedules and pick the academic year. Each schedule is a named list of periods; different classes can use different schedules.',
        route: AppRoutes.timetablePeriods,
        actionLabel: 'Open Bell schedules',
      ),
      ManualStep(
        'Create a new bell schedule',
        'Choose "New bell schedule" and give it a Name (for example "Regular day").',
        mistake:
            'Naming two schedules the same, which makes them hard to choose later.',
      ),
      ManualStep(
        'Add periods, breaks and lunch in order',
        'Add rows in time order. Each row is a Period, a Break or Lunch, with a Label and Start and End times. Teaching periods are numbered automatically.',
        check:
            'Times do not overlap and run in order through the day. Use Remove to delete a wrong row.',
      ),
      ManualStep(
        'Save',
        'Press Save. The schedule can now be chosen when you create a timetable.',
        check: 'It appears in the list for this academic year.',
      ),
      ManualStep(
        'Next',
        'Build the timetable that uses this schedule.',
        route: AppRoutes.timetable,
        actionLabel: 'Open Timetable',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        '"Create a bell schedule first" when creating a timetable.',
        'A timetable needs a bell schedule. Create one here for the same academic year.',
      ),
    ],
  ),
  ManualGuide(
    id: 'timetable-build',
    categoryId: 'timetable',
    title: 'Build and publish a class timetable',
    summary:
        'Create a draft for a section, fill the periods, validate, then publish so teachers and parents can see it.',
    anyOf: {Permission.manageTimetable},
    minutes: 20,
    prerequisites: [
      'A bell schedule exists for the academic year.',
      'Teachers are assigned to the section\'s subjects.',
      'Working days and holidays are set.',
    ],
    keywords: [
      'timetable',
      'schedule',
      'draft',
      'publish',
      'validate',
      'conflict',
      'period',
      'room',
      'copy timetable',
      'new version',
      'class timetable',
    ],
    contextRoutes: [AppRoutes.timetable],
    related: ['bell-schedule', 'teacher-assign', 'timetable-views'],
    steps: [
      ManualStep(
        'Open Timetable',
        'Open Timetable and pick the academic year.',
        route: AppRoutes.timetable,
        actionLabel: 'Open Timetable',
      ),
      ManualStep(
        'Create a draft',
        'Choose "New timetable". Enter a Name, choose the Class and Section and the bell schedule, then press "Create draft". Nothing is visible to parents or teachers yet.',
      ),
      ManualStep(
        'Fill each period',
        'Open the draft. For each day and period tap the cell, choose "Subject and teacher" (the list shows only teachers assigned to that section), add a Room if you want, and press "Set period". Use Copy and Clear to repeat or remove entries.',
        mistake: 'Putting one teacher in two sections in the same period.',
      ),
      ManualStep(
        'Save the draft',
        'Press "Save draft" often. You can leave and come back; a draft keeps your work.',
      ),
      ManualStep(
        'Validate',
        'Press "Validate". The report lists problems such as a teacher in two places at once, a room used twice, a period on a non-working day, or a subject nobody teaches. Fix every error; warnings are advisory.',
        check: 'Validation shows no errors.',
      ),
      ManualStep(
        'Publish',
        'Press "Publish" and confirm. Teachers see their periods in My Timetable and parents see their child\'s timetable. If another version of the section is in force, it is replaced.',
        check: 'The status changes to Published.',
        mistake:
            'Publishing before validating. Conflicts then appear on teachers\' timetables.',
      ),
      ManualStep(
        'Change a published timetable',
        'Use "New version from this" to make an editable draft copy, change it and publish. "Withdraw" takes a published timetable out of use; "Discard draft" deletes a draft you do not need.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'A teacher is missing from the list for a period.',
        'They are not assigned to that section and subject. Add the assignment under Teachers.',
      ),
      ManualTroubleshooting(
        'I cannot publish.',
        'Errors from Validate block publishing. Open the conflict report to see them.',
      ),
    ],
  ),
  ManualGuide(
    id: 'timetable-views',
    categoryId: 'timetable',
    title: 'View timetables and check conflicts',
    summary:
        'Class and teacher timetables, the conflict report and the change history.',
    anyOf: {Permission.viewTimetable},
    minutes: 4,
    keywords: [
      'timetable view',
      'teacher timetable',
      'class timetable',
      'conflict report',
      'history',
      'free teacher',
    ],
    contextRoutes: [
      AppRoutes.timetableView,
      AppRoutes.timetableTeachers,
      AppRoutes.timetableConflicts,
      AppRoutes.timetableHistory,
    ],
    related: ['timetable-build', 'substitution'],
    steps: [
      ManualStep(
        'Class timetable',
        'Open Class timetable, choose Class and Section, and move between weeks. It shows the published timetable in force for that week.',
        route: AppRoutes.timetableView,
        actionLabel: 'Open Class timetable',
      ),
      ManualStep(
        'Teacher timetable',
        'Open Teacher timetable and choose a Teacher to see all their periods. Covers arranged for them show as "Covered by …".',
        route: AppRoutes.timetableTeachers,
        actionLabel: 'Open Teacher timetable',
      ),
      ManualStep(
        'Conflict report',
        'Open the Conflict report to list problems across draft and published timetables, with an Open button to jump to the timetable that needs fixing.',
        route: AppRoutes.timetableConflicts,
        actionLabel: 'Open Conflict report',
      ),
      ManualStep(
        'History',
        'Open Timetable history to see who created, edited, published or withdrew a timetable.',
        route: AppRoutes.timetableHistory,
        actionLabel: 'Open History',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        '"No published timetable is in force for this week."',
        'Nothing is published for that section and week. Publish a timetable that covers those dates.',
      ),
    ],
  ),
  ManualGuide(
    id: 'substitution',
    categoryId: 'timetable',
    title: 'Arrange a substitute teacher',
    summary:
        'Cover the periods of a teacher who is absent, on leave or on duty.',
    anyOf: {Permission.manageSubstitutions},
    minutes: 6,
    prerequisites: ['A published timetable exists for the affected sections.'],
    keywords: [
      'substitute',
      'substitution',
      'cover',
      'absent teacher',
      'replacement',
    ],
    contextRoutes: [AppRoutes.timetableSubstitutions],
    related: ['timetable-views'],
    steps: [
      ManualStep(
        'Open Substitutions',
        'Open Timetable → Substitutions and choose "Arrange cover".',
        route: AppRoutes.timetableNewSubstitution,
        actionLabel: 'Open Arrange cover',
      ),
      ManualStep(
        'Choose the teacher and reason',
        'Select the Teacher being covered, the date range and a Reason (Approved leave, Absence, School duty or Other), with an optional Note.',
      ),
      ManualStep(
        'Find affected periods',
        'Press "Find affected periods". The app lists every period the teacher would have taught in that range.',
        check: 'The list matches the days the teacher is away.',
      ),
      ManualStep(
        'Choose a substitute for each period',
        'Pick a Substitute for each period. Only teachers who are free at that time and can teach are offered.',
      ),
      ManualStep(
        'Review and confirm',
        'Press "Review and confirm", check the list and confirm. The covering teacher sees it in their timetable.',
      ),
      ManualStep(
        'Change or cancel later',
        'Open the substitution to "Change substitute" or "Cancel cover". The History button shows what changed.',
      ),
    ],
  ),
  ManualGuide(
    id: 'my-timetable',
    categoryId: 'timetable',
    title: 'See my timetable',
    summary: 'Teachers see their periods; parents see their child\'s week.',
    anyOf: {Permission.viewOwnTimetable},
    minutes: 2,
    keywords: ['my timetable', 'timetable', 'schedule', 'periods', 'week'],
    contextRoutes: [AppRoutes.myTimetable],
    steps: [
      ManualStep(
        'Open My Timetable',
        'Open My Timetable. Move between weeks with the week selector.',
        route: AppRoutes.myTimetable,
        actionLabel: 'Open My Timetable',
      ),
      ManualStep(
        'Parents: choose the child',
        'If you have more than one child, pick the child first. The timetable is the one published for their class and section.',
      ),
      ManualStep(
        'Read changes',
        'A period marked "Covered by …" has a substitute teacher that day.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'It says no timetable is published.',
        'The school has not published one for this class yet. Ask the school office.',
      ),
    ],
  ),

  // ───────────────────────── Attendance ─────────────────────────
  ManualGuide(
    id: 'attendance-mark',
    categoryId: 'attendance',
    title: 'Mark student attendance',
    summary:
        'Take the daily register for a section, correct it later and finalize it.',
    anyOf: {Permission.markStudentAttendance},
    minutes: 5,
    prerequisites: [
      'You are assigned to the section (teachers) or are an administrator.',
      'The day is a working day, not a holiday.',
    ],
    keywords: [
      'attendance',
      'mark attendance',
      'present',
      'absent',
      'late',
      'half day',
      'register',
      'finalize',
      'correction',
    ],
    contextRoutes: [AppRoutes.attendance],
    related: ['reports-guide'],
    steps: [
      ManualStep(
        'Open Attendance',
        'Open Attendance. Choose the Academic year, Class and Section, and the date (use the arrows or Today).',
        route: AppRoutes.attendance,
        actionLabel: 'Open Attendance',
      ),
      ManualStep(
        'Open the register',
        'Press "Mark attendance" for the section. The student list opens.',
        route: AppRoutes.studentAttendance,
        actionLabel: 'Open Student attendance',
      ),
      ManualStep(
        'Mark each student',
        'Choose Present, Absent, Late or Half day for each student. "Mark all present" is the quick start; then change the exceptions. Add Remarks for anyone who needs a note.',
        mistake:
            'Leaving the default for absent students after "Mark all present".',
      ),
      ManualStep(
        'Save and finalize',
        'Save the register, then press "Finalize" when it is complete. A finalized register can still be corrected, but each change asks for a Reason for correction and is kept in History.',
        check: 'The hub shows the register as finalized.',
      ),
      ManualStep(
        'Correct a mistake',
        'Reopen the same date, change the status and give the reason. If someone else changed it meanwhile you are told "Changed by someone else": Reload and try again.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'I cannot mark a date.',
        'It may be a holiday or weekly off (Settings → Holidays / Working days), or you are not assigned to that section.',
      ),
    ],
  ),
  ManualGuide(
    id: 'attendance-staff',
    categoryId: 'attendance',
    title: 'Staff attendance',
    summary: 'Record and review daily staff attendance.',
    anyOf: {Permission.viewStaffAttendance},
    minutes: 4,
    keywords: ['staff attendance', 'teacher attendance', 'employee attendance'],
    contextRoutes: [AppRoutes.staffAttendance],
    steps: [
      ManualStep(
        'Open Staff attendance',
        'From Attendance choose Staff attendance and pick the date.',
        route: AppRoutes.staffAttendance,
        actionLabel: 'Open Staff attendance',
      ),
      ManualStep(
        'Mark or review',
        'Administrators mark each person\'s status for the day and add remarks. Roles with "View only" can look but not change.',
        check:
            'The hub no longer says "Staff attendance has not been marked for this date."',
      ),
      ManualStep(
        'Leave interacts with attendance',
        'Approved staff leave is recorded in Leave, so check there before marking someone absent.',
        route: AppRoutes.leave,
        actionLabel: 'Open Leave',
      ),
    ],
  ),
  ManualGuide(
    id: 'parent-attendance',
    categoryId: 'parent',
    title: 'Parents: see my child\'s attendance',
    summary: 'A month calendar of attendance for each child.',
    anyOf: {Permission.viewOwnAttendance},
    minutes: 2,
    keywords: ['my attendance', 'child attendance', 'absent', 'present'],
    contextRoutes: [AppRoutes.myAttendance],
    steps: [
      ManualStep(
        'Open My Attendance',
        'Open My Attendance and choose your child if you have more than one.',
        route: AppRoutes.myAttendance,
        actionLabel: 'Open My Attendance',
      ),
      ManualStep(
        'Change the month',
        'Use the previous and next month arrows. Each day shows Present, Absent, Late or Half day.',
      ),
      ManualStep(
        'Tell the school about an absence',
        'Apply for leave for your child from My Leave so the absence is recorded as approved.',
        route: AppRoutes.myLeave,
        actionLabel: 'Open My Leave',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'No attendance shown for this month.',
        'The teacher has not recorded it yet, or the days were holidays.',
      ),
    ],
  ),

  // ───────────────────────── Homework ─────────────────────────
  ManualGuide(
    id: 'homework-publish',
    categoryId: 'homework',
    title: 'Create and publish homework',
    summary:
        'Write the homework, choose who sees it and the deadline, review, then publish.',
    anyOf: {Permission.manageHomework},
    minutes: 6,
    prerequisites: [
      'You are assigned to the class, section and subject (teachers).',
    ],
    keywords: [
      'homework',
      'assignment',
      'publish homework',
      'deadline',
      'attachment',
      'create homework',
      'submission',
    ],
    contextRoutes: [AppRoutes.homework],
    related: ['homework-review', 'parent-homework'],
    steps: [
      ManualStep(
        'Open Homework',
        'Open Homework and choose "New homework".',
        route: AppRoutes.homeworkNew,
        actionLabel: 'Open New homework',
      ),
      ManualStep('Details', 'Enter a Title and the Instructions.'),
      ManualStep(
        'Sections and subjects',
        'Choose the sections and subjects it is for. Teachers see only the ones they teach.',
      ),
      ManualStep(
        'Deadline',
        'Set the deadline date (and a time if you want one; "Clear time" removes it).',
      ),
      ManualStep(
        'Marks and submission',
        'Decide whether students hand in work online ("Students submit work"), accept late submissions, allow resubmission before the deadline, and allow file attachments. Enter Maximum marks only if it is graded.',
      ),
      ManualStep(
        'Attach files',
        'Use "Add files" for worksheets. The type, size and number of files are limited; the form shows the allowed files.',
      ),
      ManualStep(
        'Save a draft or review',
        '"Save draft" keeps it private ("Families cannot see this yet"). "Preview & publish" shows exactly what families will see.',
      ),
      ManualStep(
        'Publish',
        'On the review screen publish it. Parents see it in My Homework and are notified.',
        check: 'The status is Published.',
        mistake: 'Publishing without checking the deadline date.',
      ),
      ManualStep(
        'After publishing',
        'You can edit a published homework until it is closed. "Close" stops submissions; "Archive" hides it. Closed or archived homework cannot be edited.',
      ),
    ],
  ),
  ManualGuide(
    id: 'homework-review',
    categoryId: 'homework',
    title: 'Review submissions and give feedback',
    summary: 'See who handed in, grade or return work, and chase the rest.',
    anyOf: {Permission.reviewSubmissions},
    minutes: 5,
    keywords: [
      'review homework',
      'submission',
      'grade',
      'feedback',
      'return for revision',
      'late',
      'marks',
    ],
    contextRoutes: [_homeworkReview],
    related: ['homework-publish'],
    steps: [
      ManualStep(
        'Open the homework',
        'Open Homework and pick the item; the summary shows "to review" counts.',
        route: AppRoutes.homework,
        actionLabel: 'Open Homework',
      ),
      ManualStep(
        'Review submissions',
        'Press Review. Filter by To review, Handed in, Graded or Returned. "Late" marks work handed in after the deadline.',
      ),
      ManualStep(
        'Open a submission',
        'Read the Answer and any files, then enter Feedback and (if graded) Marks within the maximum.',
        check: 'Marks are within 0 and the maximum.',
      ),
      ManualStep(
        'Grade or return',
        'Save the grade, or use "Return for revision" so the student can fix it. The student and parent are notified.',
      ),
      ManualStep(
        'Find who has not handed in',
        'The summary says when every active student has handed in; otherwise use the list to follow up.',
      ),
    ],
  ),
  ManualGuide(
    id: 'parent-homework',
    categoryId: 'parent',
    title: 'Parents: homework and handing in work',
    summary: 'See homework per child, download files and hand in answers.',
    anyOf: {Permission.viewOwnHomework},
    minutes: 4,
    keywords: [
      'my homework',
      'submit homework',
      'hand in',
      'attachment',
      'deadline',
    ],
    contextRoutes: [AppRoutes.myHomework],
    steps: [
      ManualStep(
        'Open My Homework',
        'Open My Homework and choose your child. Filter by Subject or status: To do, Submitted, Overdue, Graded, Needs revision.',
        route: AppRoutes.myHomework,
        actionLabel: 'Open My Homework',
      ),
      ManualStep(
        'Read the homework',
        'Open an item to read the instructions, the deadline and download attached files.',
      ),
      ManualStep(
        'Hand in',
        'If the teacher allows online submission, type "Your answer", use "Attach a file" and hand it in. You see "Handed in. Your teacher can see it now."',
        mistake:
            'Waiting until after the deadline when late work is not accepted.',
      ),
      ManualStep(
        'Check feedback',
        'Graded work shows the marks and feedback. "Needs revision" means the teacher returned it: fix and hand in again.',
      ),
    ],
  ),

  // ───────────────────────── Examinations ─────────────────────────
  ManualGuide(
    id: 'grading-scheme',
    categoryId: 'exams',
    title: 'Create a grading scheme',
    summary:
        'Define grades, the pass rule, rounding and ranking before creating exams.',
    anyOf: {Permission.manageExams},
    minutes: 8,
    keywords: [
      'grading',
      'grade',
      'gpa',
      'pass percentage',
      'rank',
      'rounding',
      'scheme',
    ],
    contextRoutes: [AppRoutes.examSchemes],
    related: ['exam-create'],
    steps: [
      ManualStep(
        'Open Grading schemes',
        'Open Exams → Grading schemes and choose "New grading scheme".',
        route: AppRoutes.examSchemes,
        actionLabel: 'Open Grading schemes',
      ),
      ManualStep('Name it', 'Give it a Name and Description.'),
      ManualStep(
        'Add the grades',
        'Use "Add grade": for each grade enter the Grade (A, B…), the lowest percentage ("From %") and the Grade point.',
        check: 'Grades cover every percentage from 0 up with no gaps.',
      ),
      ManualStep(
        'Pass rule and calculation',
        'Set the Subject pass percentage and optionally an Overall pass percentage. Choose Rounding, Decimal places for percentages, and how "An absent subject" is treated (excluded, or counted as zero). Switch on "Rank students" if you want ranks.',
      ),
      ManualStep(
        'Save scheme',
        'Press "Save scheme". It becomes available for new examinations; results already finalised keep their own copy, so editing it later does not change old results.',
      ),
    ],
  ),
  ManualGuide(
    id: 'exam-create',
    categoryId: 'exams',
    title: 'Create and schedule an examination',
    summary:
        'Set up the exam, add its subjects with maximum and passing marks, schedule it and open marks entry.',
    anyOf: {Permission.manageExams},
    minutes: 12,
    prerequisites: [
      'A grading scheme exists.',
      'Teachers are assigned to the subjects.',
    ],
    keywords: [
      'exam',
      'examination',
      'create exam',
      'schedule exam',
      'maximum marks',
      'passing marks',
      'theory',
      'practical',
      'weightage',
      'open marks entry',
    ],
    contextRoutes: [AppRoutes.exams],
    related: ['grading-scheme', 'marks-entry', 'exam-results'],
    steps: [
      ManualStep(
        'Start a new examination',
        'Open Exams and choose "New examination".',
        route: AppRoutes.examNew,
        actionLabel: 'Open New examination',
      ),
      ManualStep(
        'Examination details',
        'Enter the Name, Type (Unit test, Quarterly, Half-yearly, Annual, Practical, Other), Description, and the Grading scheme.',
      ),
      ManualStep(
        'Who it is for and dates',
        'Choose the Class and Section (or All sections) and the exam dates. Add Instructions and remarks if needed.',
      ),
      ManualStep(
        'Add the subjects',
        'On the examination page press "Add subject". For each: Subject, Date, Maximum marks (or Theory maximum and Practical maximum), Passing marks (blank uses the scheme\'s percentage) and Weightage.',
        check:
            'Every subject that will be examined is listed with its maximum.',
        mistake: 'Setting a passing mark higher than the maximum.',
      ),
      ManualStep(
        'Schedule',
        'Press "Schedule". The exam is now planned and teachers can see their subjects.',
      ),
      ManualStep(
        'Open marks entry',
        'When the exam is over, press "Open marks entry" so teachers can enter marks. Use "Edit details" or "Withdraw" if something was wrong.',
        check: 'The status shows Marks entry.',
      ),
    ],
  ),
  ManualGuide(
    id: 'marks-entry',
    categoryId: 'exams',
    title: 'Enter marks (teachers)',
    summary:
        'Enter marks for your subject and section, then submit for review.',
    anyOf: {Permission.enterMarks},
    minutes: 8,
    prerequisites: [
      'Marks entry has been opened for the examination.',
      'You are assigned to the subject and section.',
    ],
    keywords: [
      'marks',
      'enter marks',
      'marks entry',
      'absent',
      'exempted',
      'submit for review',
    ],
    contextRoutes: [_examMarks, AppRoutes.exams],
    related: ['exam-review'],
    steps: [
      ManualStep(
        'Open your examination',
        'Open Exams and pick the examination, then your subject and section to open "Enter marks".',
        route: AppRoutes.exams,
        actionLabel: 'Open Exams',
      ),
      ManualStep(
        'Enter the marks',
        'Type each student\'s marks. Find a student with "Search name or roll number". The app refuses marks above the maximum.',
        check: 'No row is left empty.',
      ),
      ManualStep(
        'Absent or exempted students',
        'Set their status to Absent or Exempted instead of typing 0. Add a Remark if useful.',
        mistake: 'Entering 0 for an absent student, which counts as a fail.',
      ),
      ManualStep(
        'Save',
        'Save as you go ("Marks saved."). You can come back to finish.',
      ),
      ManualStep(
        'Submit for review',
        'When complete press "Submit for review". After that the sheet is locked unless the administrator returns it ("Returned for correction").',
      ),
    ],
  ),
  ManualGuide(
    id: 'exam-review',
    categoryId: 'exams',
    title: 'Review and approve marks',
    summary: 'Approve each submitted marks sheet or return it for correction.',
    anyOf: {Permission.approveResults},
    minutes: 6,
    keywords: ['approve marks', 'review marks', 'return marks', 'marks sheet'],
    contextRoutes: [_examReview],
    related: ['exam-results'],
    steps: [
      ManualStep(
        'Open the examination review',
        'Open the examination and choose Review marks.',
        route: AppRoutes.exams,
        actionLabel: 'Open Exams',
      ),
      ManualStep(
        'Check each sheet',
        'Open a submitted sheet and look at the marks, absentees and remarks.',
      ),
      ManualStep(
        'Approve or return',
        'Choose Approve ("Approve these marks?") or Return with a reason so the teacher corrects it.',
        mistake:
            'Approving a sheet with missing marks; results will show it as incomplete.',
      ),
    ],
  ),
  ManualGuide(
    id: 'exam-results',
    categoryId: 'exams',
    title: 'Finalise and publish results',
    summary:
        'Add remarks, finalise the results, then publish them to parents. Includes correction.',
    anyOf: {Permission.approveResults},
    minutes: 8,
    prerequisites: [
      'All marks sheets are approved.',
      'Student attendance for the period is complete (the app warns if not).',
    ],
    keywords: [
      'results',
      'publish results',
      'finalise',
      'report card',
      'rank',
      'reopen',
      'correction',
      'remarks',
    ],
    contextRoutes: [_examResults],
    related: ['exam-review', 'parent-results'],
    steps: [
      ManualStep(
        'Open Results',
        'Open the examination and choose Results. You see Students, Passed, Failed, Absent in a subject, Incomplete and Average.',
      ),
      ManualStep(
        'Add remarks',
        'Add the Class teacher and Principal remarks for each student where needed.',
      ),
      ManualStep(
        'Check for problems',
        'Fix anything listed as incomplete. An "Attendance is incomplete" warning tells you the attendance on report cards is not final.',
      ),
      ManualStep(
        'Finalise',
        'Press "Finalise results" and confirm. This calculates grades and ranks from the approved marks.',
      ),
      ManualStep(
        'Publish',
        'Press "Publish results" and confirm. Parents can now see them in My Results.',
        check: 'The status is Published and shows "Results published."',
      ),
      ManualStep(
        'Correct after publishing',
        'Use "Reopen for correction", fix the marks and finalise and publish again. The result version increases and the history records the change.',
      ),
    ],
  ),
  ManualGuide(
    id: 'parent-results',
    categoryId: 'parent',
    title: 'Parents: see exam results',
    summary: 'Published results and progress between examinations.',
    anyOf: {Permission.viewOwnResults},
    minutes: 3,
    keywords: ['my results', 'marks', 'result', 'report card', 'exam'],
    contextRoutes: [AppRoutes.myResults],
    steps: [
      ManualStep(
        'Open My Results',
        'Open My Results and choose your child.',
        route: AppRoutes.myResults,
        actionLabel: 'Open My Results',
      ),
      ManualStep(
        'Open an examination',
        'Pick an examination to see subject-wise marks, grade, remarks and rank (if the school ranks).',
      ),
      ManualStep(
        'Compare examinations',
        'The progress section shows how your child moved between examinations.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        '"Result not available yet."',
        'The school has not published it. It appears here as soon as it does.',
      ),
    ],
  ),

  // ───────────────────────── Communication ─────────────────────────
  ManualGuide(
    id: 'announcements',
    categoryId: 'comms',
    title: 'Create and publish an announcement',
    summary: 'Write a notice, choose the audience, attach files and publish.',
    anyOf: {Permission.manageAnnouncements},
    minutes: 5,
    keywords: [
      'announcement',
      'notice',
      'circular',
      'publish',
      'audience',
      'attachment',
      'notify',
    ],
    contextRoutes: [AppRoutes.announcements],
    related: ['notifications-guide'],
    steps: [
      ManualStep(
        'Open Announcements',
        'Open Announcements and choose "New announcement".',
        route: AppRoutes.announcementNew,
        actionLabel: 'Open New announcement',
      ),
      ManualStep('Write it', 'Enter a Title and the Message.'),
      ManualStep(
        'Choose the audience',
        '"Send to" picks who sees it, for example the whole school or particular classes and sections. Teachers can send to their own section.',
        check: 'The "Goes to" summary names the right people.',
        mistake: 'Sending a class notice to the whole school.',
      ),
      ManualStep(
        'Attachments and expiry',
        'Attach files if needed (type, size and count are limited). You can set an expiry date so old notices disappear.',
      ),
      ManualStep(
        'Review and publish',
        '"Save draft" keeps it private. "Preview & publish" shows how it will look; tick "Publish immediately" or publish from the detail page.',
      ),
      ManualStep(
        'After publishing',
        'Parents and staff are notified. Edit later with "Save update" (optionally "Notify the audience about this update") or Archive it.',
      ),
    ],
  ),
  ManualGuide(
    id: 'messages-guide',
    categoryId: 'comms',
    title: 'Parent–teacher messages',
    summary:
        'Parents message teachers about their child; teachers choose whether they accept messages.',
    anyOf: {Permission.useMessages},
    minutes: 5,
    keywords: [
      'message',
      'chat',
      'conversation',
      'teacher',
      'parent',
      'report',
      'contact',
    ],
    contextRoutes: [AppRoutes.messages],
    steps: [
      ManualStep(
        'Open Messages',
        'Open Messages to see your conversations.',
        route: AppRoutes.messages,
        actionLabel: 'Open Messages',
      ),
      ManualStep(
        'Teachers: allow messages',
        'Switch on "Let parents of my sections message me". Parents can only message teachers who teach their child.',
      ),
      ManualStep(
        'Parents: start a conversation',
        'Choose "New conversation", pick the Teacher (the child is shown as "About …"), add a Subject and your Message, and Send.',
        route: AppRoutes.messageNew,
        actionLabel: 'Open New conversation',
      ),
      ManualStep(
        'Reply and attach',
        'Open a conversation to reply (Ctrl+Enter sends). Use the paperclip to attach a file. Archive or reopen a conversation from the actions menu.',
      ),
      ManualStep(
        'Report a problem',
        'Use "Report this conversation" and say what is wrong. School administrators see only reported conversations.',
      ),
    ],
  ),
  ManualGuide(
    id: 'notifications-guide',
    categoryId: 'comms',
    title: 'Notifications and settings',
    summary: 'Read, filter and control the notifications you receive.',
    minutes: 3,
    keywords: ['notification', 'bell', 'push', 'unread', 'preferences', 'mute'],
    contextRoutes: [AppRoutes.notifications],
    steps: [
      ManualStep(
        'Open Notifications',
        'Click the bell or open Notifications. Filter by All or Unread and by Category.',
        route: AppRoutes.notifications,
        actionLabel: 'Open Notifications',
      ),
      ManualStep(
        'Mark as read',
        'Open an item to go to the related screen, or "Mark all as read".',
      ),
      ManualStep(
        'Choose what you get',
        'Open Notification settings to switch categories on or off. Administrative notices cannot be switched off. Push notifications work on the Android app, not in the browser.',
        route: AppRoutes.notificationPreferences,
        actionLabel: 'Open settings',
      ),
    ],
  ),

  // ───────────────────────── Student records ─────────────────────────
  ManualGuide(
    id: 'student-records',
    categoryId: 'people',
    title: 'Update a student\'s record, status or branch',
    summary:
        'Find a student, edit details, change status, link parents and move a student to another branch.',
    anyOf: {Permission.viewStudentData},
    minutes: 6,
    keywords: [
      'student profile',
      'edit student',
      'student status',
      'transfer',
      'move branch',
      'link parent',
      'add parent',
      'primary contact',
      'emergency contact',
    ],
    contextRoutes: [AppRoutes.students],
    related: ['admit-student', 'parent-login'],
    steps: [
      ManualStep(
        'Find the student',
        'Open Students and search or filter the list. Open the student to see the profile: admission number, student code, class and section, contacts and academic history.',
        route: AppRoutes.students,
        actionLabel: 'Open Students',
      ),
      ManualStep(
        'Edit details',
        'Administrators can edit the profile. The admission number is part of the record and is not re-generated.',
      ),
      ManualStep(
        'Link another parent or guardian',
        'On the profile use "Add parent": create a new one or link an existing parent. Mark who is the Primary contact and Emergency contact, and use "Allow parent portal access" so that parent can see this child once they have a login.',
      ),
      ManualStep(
        'Change status',
        'Use the status control (for example to mark a student as having left). Give a reason.',
      ),
      ManualStep(
        'Move to another branch',
        'Use "Move to another branch" to transfer a student. Choose the branch, the new admission number and the placement.',
        mistake:
            'Moving a student before their fees in the old branch are settled.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'I cannot edit a student.',
        'Only roles with student-management permission can. Teachers can view the students they teach.',
      ),
    ],
  ),

  // ───────────────────────── Setup extras ─────────────────────────
  ManualGuide(
    id: 'holidays',
    categoryId: 'setup',
    title: 'Holidays and weekly offs',
    summary:
        'Mark days the school is closed so attendance, leave and timetables skip them.',
    anyOf: {Permission.manageAcademicSetup},
    minutes: 4,
    keywords: [
      'holiday',
      'weekly off',
      'saturday',
      'working days',
      'calendar',
      'closed',
    ],
    contextRoutes: [AppRoutes.settingsHolidays, AppRoutes.settingsWorkingDays],
    related: ['school-setup'],
    steps: [
      ManualStep(
        'Set weekly offs',
        'Open Settings → Working days. Choose the weekly days off, including patterns such as "1st, 3rd, 5th" or "2nd, 4th" Saturdays. Save.',
        route: AppRoutes.settingsWorkingDays,
        actionLabel: 'Open Working days',
      ),
      ManualStep(
        'Add holidays',
        'Open Settings → Holidays and choose "Add holiday". Switch between Calendar and List to review them.',
        route: AppRoutes.settingsHolidays,
        actionLabel: 'Open Holidays',
        mistake: 'Adding holidays to the wrong academic year.',
      ),
      ManualStep(
        'Check the effect',
        'Attendance cannot be marked on these days, leave does not count them (unless a leave type says so), and timetables skip them.',
      ),
    ],
  ),
  ManualGuide(
    id: 'leave-policy',
    categoryId: 'leave',
    title: 'Set up leave types and balances',
    summary: 'Define the leave policy, adjust balances and carry them forward.',
    anyOf: {Permission.manageLeaveTypes},
    minutes: 8,
    keywords: [
      'leave type',
      'leave policy',
      'entitlement',
      'carry forward',
      'balance',
      'adjust balance',
      'paid leave',
      'half day',
    ],
    contextRoutes: [AppRoutes.leaveTypes, AppRoutes.leaveBalances],
    related: ['leave-review', 'leave-apply'],
    steps: [
      ManualStep(
        'Add leave types',
        'Open Leave → Leave types & policy and choose "Add leave type". Enter Name and Code, whether it is for Staff leave or Student leave, Pay (Paid/Unpaid), the Annual entitlement (days), the longest single request, and the Carry-forward limit.',
        route: AppRoutes.leaveTypes,
        actionLabel: 'Open Leave types',
      ),
      ManualStep(
        'Set the rules',
        'Choose Half days allowed, Reason required, Supporting document required, whether holidays and weekends count as leave, and what happens "When a request exceeds the balance". For student leave you can let office staff file on behalf.',
      ),
      ManualStep(
        'Adjust a balance',
        'Open Leave → Balances, find the staff member, press Adjust, enter the days (use − to remove) and the reason. It is kept in the ledger.',
        route: AppRoutes.leaveBalances,
        actionLabel: 'Open Balances',
      ),
      ManualStep(
        'Carry forward at year end',
        'Use "Carry forward" to move unused days into the new year up to each type\'s limit.',
      ),
    ],
  ),

  // ───────────────────────── Reports ─────────────────────────
  ManualGuide(
    id: 'reports-guide',
    categoryId: 'reports',
    title: 'Which report do I use?',
    summary:
        'Fee, attendance, leave and academic reports: where they are and how to read them.',
    anyOf: {
      Permission.viewFeeReports,
      Permission.viewAttendance,
      Permission.viewLeaveReports,
      Permission.viewExams,
    },
    minutes: 6,
    keywords: [
      'report',
      'reports',
      'fee report',
      'collection',
      'outstanding',
      'attendance report',
      'leave report',
      'performance',
      'export',
      'csv',
      'pass rate',
    ],
    contextRoutes: [
      AppRoutes.feeReports,
      AppRoutes.attendanceReports,
      AppRoutes.leaveReports,
      AppRoutes.examPerformance,
    ],
    steps: [
      ManualStep(
        'Fee reports',
        'Fees → Fee reports. Choose the report and period and press Run to see collections and outstanding amounts. "Find a student" shows one student\'s position. "Copy CSV" copies the table so you can paste it into a spreadsheet.',
        route: AppRoutes.feeReports,
        actionLabel: 'Open Fee reports',
      ),
      ManualStep(
        'Invoices and receipts',
        'There is no separate invoice or receipt report. Use Invoices (filter by Class, Section, Status, Due from/to) and Payments & receipts (filter by From, To, Method, Status). Invoices and receipts can be printed or saved as PDF.',
        route: AppRoutes.feePayments,
        actionLabel: 'Open Payments & receipts',
      ),
      ManualStep(
        'Attendance reports',
        'Attendance → Reports. Choose Students or Staff, a period (This month, Last month or custom), then "Generate report". Look at one person with "One student…" or "One staff member…". "Copy CSV" copies the table.',
        route: AppRoutes.attendanceReports,
        actionLabel: 'Open Attendance reports',
      ),
      ManualStep(
        'Leave reports',
        'Leave → Reports shows applications, days granted and, for staff, the balance used and available per leave type, and class-wise student leave.',
        route: AppRoutes.leaveReports,
        actionLabel: 'Open Leave reports',
      ),
      ManualStep(
        'Academic performance',
        'Exams → Academic performance. Choose an Examination to see pass rate, average, grade distribution and the students who may need support.',
        route: AppRoutes.examPerformance,
        actionLabel: 'Open Academic performance',
      ),
      ManualStep(
        'Lists and exports',
        'The Students, Parents and Staff lists have filters and counts; Staff can be exported with Export (CSV). There is no separate student or staff report page.',
      ),
    ],
  ),

  // ───────────────────────── Parent portal ─────────────────────────
  ManualGuide(
    id: 'parent-start',
    categoryId: 'parent',
    title: 'Parents: getting started',
    summary: 'Sign in, choose your child, and find fees, work and notices.',
    anyOf: {Permission.viewOwnChildFees, Permission.viewOwnHomework},
    minutes: 4,
    keywords: [
      'parent',
      'parent login',
      'sign in',
      'child',
      'password',
      'announcement',
      'first login',
    ],
    contextRoutes: [AppRoutes.announcements],
    steps: [
      ManualStep(
        'Sign in',
        'Use the email the school registered for you. If you were given an activation or reset link, open it to choose your own password. A temporary password must be changed at first sign-in.',
        mistake: 'Using a different email from the one the school registered.',
      ),
      ManualStep(
        'Choose your child',
        'If you have more than one child at the school, pick the child on each page. You only ever see your own children.',
      ),
      ManualStep(
        'Where things are',
        'My Fees (invoices and receipts), My Attendance, My Timetable, My Homework, My Results, Announcements, Messages and Leave are in the menu.',
        route: AppRoutes.dashboard,
        actionLabel: 'Open Dashboard',
      ),
      ManualStep(
        'Read announcements',
        'Announcements shows school and class notices. Notifications tells you when something new arrives.',
        route: AppRoutes.announcements,
        actionLabel: 'Open Announcements',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'I can sign in but see no child.',
        'The school needs to link your child to your account and turn on portal access. Contact the school office.',
      ),
    ],
  ),
  ManualGuide(
    id: 'parent-fees',
    categoryId: 'parent',
    title: 'Parents: fees, invoices and receipts',
    summary:
        'See what is due and download receipts. Fees are paid at the school.',
    anyOf: {Permission.viewOwnChildFees},
    minutes: 3,
    keywords: [
      'my fees',
      'invoice',
      'receipt',
      'balance due',
      'pay fees',
      'overdue',
    ],
    contextRoutes: [AppRoutes.myFees],
    steps: [
      ManualStep(
        'Open My Fees',
        'Open My Fees and choose your child. The summary shows Total billed, Paid, Balance due, Overdue and Upcoming.',
        route: AppRoutes.myFees,
        actionLabel: 'Open My Fees',
      ),
      ManualStep(
        'Open an invoice',
        'Select an invoice to see the fee breakdown, due date and payments recorded against it.',
      ),
      ManualStep(
        'Pay at the school',
        'Online payment is not available yet. Pay at the school office; staff record it and the receipt appears here.',
      ),
      ManualStep(
        'Get the receipt',
        'Open the payment\'s receipt to view, print or save it.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'My payment is not showing.',
        'Staff record payments when you pay. If it is missing after a day, contact the school office with your payment details.',
      ),
    ],
  ),

  // ───────────────────────── Teacher ─────────────────────────
  ManualGuide(
    id: 'teacher-day',
    categoryId: 'start',
    title: 'Teachers: your day in the app',
    summary:
        'The quickest route through attendance, homework, marks, messages and leave.',
    anyOf: {Permission.markStudentAttendance, Permission.enterMarks},
    minutes: 4,
    keywords: ['teacher', 'daily', 'classes', 'my students', 'workflow'],
    related: [
      'attendance-mark',
      'homework-publish',
      'marks-entry',
      'my-timetable',
      'messages-guide',
      'leave-apply',
    ],
    steps: [
      ManualStep(
        'Check your timetable',
        'My Timetable shows today\'s periods, including covers.',
        route: AppRoutes.myTimetable,
        actionLabel: 'Open My Timetable',
      ),
      ManualStep(
        'Mark attendance',
        'Take the register for your section first thing.',
        route: AppRoutes.attendance,
        actionLabel: 'Open Attendance',
      ),
      ManualStep(
        'Set homework',
        'Create and publish homework for the classes you taught.',
        route: AppRoutes.homework,
        actionLabel: 'Open Homework',
      ),
      ManualStep(
        'Enter marks when asked',
        'Enter and submit marks once the administrator opens marks entry.',
        route: AppRoutes.exams,
        actionLabel: 'Open Exams',
      ),
      ManualStep(
        'Answer parents',
        'Check Messages for parent questions and Notifications for school notices.',
        route: AppRoutes.messages,
        actionLabel: 'Open Messages',
      ),
    ],
  ),

  // ───────────────────────── FAQ & troubleshooting ─────────────────────────
  ManualGuide(
    id: 'faq',
    categoryId: 'help',
    title: 'Frequently asked questions',
    summary: 'Short answers to the questions people ask most.',
    keywords: ['faq', 'questions', 'help'],
    steps: [],
    troubleshooting: [
      ManualTroubleshooting(
        'Why is a menu item missing?',
        'Menus follow your role. A teacher does not see fees; a parent sees only "My …" pages. Ask your school administrator if your role should include it.',
      ),
      ManualTroubleshooting(
        'What is the difference between a parent record and a parent login?',
        'A record holds contact details and links to children. A login is a separate sign-in account. Admission and sheet uploads create records; "Give login access" creates logins.',
      ),
      ManualTroubleshooting(
        'What is the difference between an invoice and a receipt?',
        'An invoice is the bill (what is owed). A receipt is proof of one payment.',
      ),
      ManualTroubleshooting(
        'Can parents pay fees online?',
        'Not yet. Fees are paid at the school and recorded by staff.',
      ),
      ManualTroubleshooting(
        'How are admission numbers created?',
        'Automatically, in one series for the branch: ADM-0001, ADM-0002 and so on, for both single admissions and sheet uploads.',
      ),
      ManualTroubleshooting(
        'Does marking a guide step as done do anything in the school\'s data?',
        'No. It only saves your place in the guide.',
      ),
      ManualTroubleshooting(
        'Does the app send push notifications to the browser?',
        'No. Push notifications work on the Android app. In the browser use the bell.',
      ),
    ],
  ),
  ManualGuide(
    id: 'troubleshooting',
    categoryId: 'help',
    title: 'Troubleshooting common problems',
    summary: 'What to check when something does not work.',
    keywords: ['problem', 'error', 'not working', 'cannot', 'fix', 'stuck'],
    steps: [],
    troubleshooting: [
      ManualTroubleshooting(
        'A save is taking a long time.',
        'Check your connection. If a step fails the app shows a message. Wait for the spinner to finish before pressing again; do not close the page during imports or invoice generation.',
      ),
      ManualTroubleshooting(
        'I can open a page but it is empty.',
        'There may be nothing set up for the chosen academic year, class or section yet. Check the filters at the top, and Settings for missing classes or sections.',
      ),
      ManualTroubleshooting(
        'A teacher cannot see their class or mark attendance.',
        'They need a class/subject assignment (Teachers → Assign). Then use "Refresh teacher access" on the Staff list.',
      ),
      ManualTroubleshooting(
        'A parent cannot see their child.',
        'Check the child is linked to that parent with portal access on, and that the parent has a login. See "Give a parent a login".',
      ),
      ManualTroubleshooting(
        'A sheet import rejected rows.',
        'The preview lists the line, the cell and how to fix it. Fix those rows and upload only them; do not upload rows that were already imported.',
      ),
      ManualTroubleshooting(
        'A login could not be created.',
        'The email may already have a login, or may be invalid. Use Retry in the dialog, or link the child to the existing parent record.',
      ),
      ManualTroubleshooting(
        'I entered the wrong payment or invoice.',
        'An administrator can reverse a payment or void an invoice with a reason; then record or generate it again correctly.',
      ),
      ManualTroubleshooting(
        'The timetable will not publish.',
        'Run Validate and fix every error, such as a teacher in two places or a missing assignment.',
      ),
    ],
    related: ['parent-login', 'timetable-build', 'invoices'],
  ),
];
