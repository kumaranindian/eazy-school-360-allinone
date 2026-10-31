import 'package:flutter/material.dart';

import '../../../core/permissions/permission.dart';
import '../../../core/routing/app_routes.dart';
import '../domain/manual_catalog.dart';
import '../domain/manual_models.dart';
import 'manual_guides_more.dart';

/// The bundled user manual. Written against the screens as they exist: every
/// field and button named here is on that screen, and nothing describes a
/// feature the app does not have (no online payment, late fees or
/// instalments). Update a guide's `version` when its steps change meaning.
const manualCatalog = ManualCatalog(_categories, [..._guides, ...moreGuides]);

const _categories = [
  ManualCategory(
    'start',
    'Getting Started',
    'Signing in, finding your way round, and getting help.',
    Icons.flag_outlined,
  ),
  ManualCategory(
    'setup',
    'School Setup Guide',
    'What to configure first, in order.',
    Icons.settings_outlined,
  ),
  ManualCategory(
    'people',
    'Student & Parent Management',
    'Admissions, sheet uploads, records and parent logins.',
    Icons.groups_outlined,
  ),
  ManualCategory(
    'staff',
    'Staff Management',
    'Adding staff, logins and teaching assignments.',
    Icons.badge_outlined,
  ),
  ManualCategory(
    'attendance',
    'Attendance Management',
    'Daily registers, corrections and staff attendance.',
    Icons.fact_check_outlined,
  ),
  ManualCategory(
    'timetable',
    'Timetable Management',
    'Bell timings, timetables, substitutes and views.',
    Icons.calendar_view_week_outlined,
  ),
  ManualCategory(
    'homework',
    'Homework Management',
    'Setting, reviewing and handing in homework.',
    Icons.menu_book_outlined,
  ),
  ManualCategory(
    'exams',
    'Examination Management',
    'Grading schemes, exams, marks and results.',
    Icons.grading_outlined,
  ),
  ManualCategory(
    'fees',
    'Fee Management',
    'Fee structures, assignment, invoices and payments.',
    Icons.payments_outlined,
  ),
  ManualCategory(
    'comms',
    'Communication & Announcements',
    'Announcements, messages and notifications.',
    Icons.campaign_outlined,
  ),
  ManualCategory(
    'leave',
    'Leave',
    'Applying for, reviewing and configuring leave.',
    Icons.beach_access_outlined,
  ),
  ManualCategory(
    'reports',
    'Reports & Analytics',
    'Which report to use and how to read it.',
    Icons.bar_chart_outlined,
  ),
  ManualCategory(
    'parent',
    'Parent Guide',
    'Everything a parent can do in the app.',
    Icons.family_restroom_outlined,
  ),
  ManualCategory(
    'account',
    'Account & Access',
    'Branches and deleting your account.',
    Icons.manage_accounts_outlined,
  ),
  ManualCategory(
    'help',
    'Troubleshooting & FAQ',
    'Quick answers and fixes.',
    Icons.help_center_outlined,
  ),
];

const _guides = [
  ManualGuide(
    id: 'getting-started',
    categoryId: 'start',
    title: 'Getting started with EazySchool 360',
    summary:
        'Sign in, understand the menu for your role, and find help on any screen.',
    minutes: 3,
    keywords: ['login', 'sign in', 'menu', 'navigation', 'password', 'help'],
    contextRoutes: [AppRoutes.dashboard],
    steps: [
      ManualStep(
        'Sign in',
        'Use the email and password you were given. If the school gave you a temporary password, the app asks you to choose a new one before you continue.',
        check:
            'You land on the Dashboard. If you are sent to a "change password" screen, set a new password first.',
        mistake:
            'Typing the temporary password with different capital letters. Copy it exactly, or ask the school for a password reset link.',
      ),
      ManualStep(
        'Find your menu',
        'The menu on the left (or the menu button on a phone) lists only what your role may use. A teacher sees Attendance, Homework and Exams; a parent sees My Fees, My Results and so on. If something is missing, your role does not include it.',
        route: AppRoutes.dashboard,
        actionLabel: 'Open Dashboard',
      ),
      ManualStep(
        'Check where you are working',
        'The header shows the school name. If your school has several branches and you are an administrator, the branch you are acting in is shown on pages that add data, so records land in the right place.',
      ),
      ManualStep(
        'Use the Help icon',
        'On most screens a question-mark icon in the top bar opens the guide for that screen. This Help section lists every guide you are allowed to use and remembers which steps you finished.',
        route: AppRoutes.help,
        actionLabel: 'Open Help',
      ),
      ManualStep(
        'Notifications and messages',
        'The bell shows school notices. Messages are conversations between parents and teachers.',
        route: AppRoutes.notifications,
        actionLabel: 'Open Notifications',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'I cannot sign in.',
        'Check the email address for typing errors. Ask your school administrator to send a password reset link. Your account may also be switched off; the app then shows "account inactive".',
      ),
      ManualTroubleshooting(
        'A menu item I expect is missing.',
        'Menus follow your role. Ask your school administrator whether your role should include it.',
      ),
    ],
  ),
  ManualGuide(
    id: 'school-setup',
    categoryId: 'setup',
    title: 'Set up your school (first-time checklist)',
    summary:
        'Profile, academic year, classes, sections, subjects, working days and holidays, in the order the app needs them.',
    anyOf: {Permission.manageAcademicSetup, Permission.manageSchool},
    minutes: 20,
    prerequisites: [
      'You are signed in as a school or branch administrator.',
      'You know your class names, section names and the academic year dates.',
    ],
    keywords: [
      'setup',
      'academic year',
      'class',
      'section',
      'subject',
      'branch',
      'holiday',
      'working days',
      'school profile',
      'regional',
      'currency',
    ],
    contextRoutes: [AppRoutes.settings, AppRoutes.school],
    related: ['admit-student', 'fee-structure'],
    steps: [
      ManualStep(
        'Check the school profile',
        'Open School and confirm the school name, contact email and phone, and address. Parents see the school name and logo, so correct them now.',
        route: AppRoutes.school,
        actionLabel: 'Open School',
        check: 'School name and contact email are filled in.',
      ),
      ManualStep(
        'Set the country, currency and time zone',
        'Open Settings → Regional settings. Country, currency, time zone and date format are one setting for the whole school. Choose carefully: the currency locks once any fee or payment exists.',
        route: AppRoutes.settingsRegional,
        actionLabel: 'Open Regional settings',
        mistake: 'Leaving the default currency and finding it locked later.',
      ),
      ManualStep(
        'Add branches (if you have more than one)',
        'Open Settings → Branches and add each branch with a name and code. A single-branch school can skip this.',
        route: AppRoutes.settingsBranches,
        actionLabel: 'Open Branches',
      ),
      ManualStep(
        'Create the academic year',
        'Open Settings → Academic years and add the year with its start and end dates. Mark the current year active. Classes, fees, attendance and exams all hang off an academic year.',
        route: AppRoutes.settingsAcademicYears,
        actionLabel: 'Open Academic years',
        check: 'One academic year is active.',
      ),
      ManualStep(
        'Create classes',
        'Open Settings → Classes and add every class (for example Grade 1, Grade 2).',
        route: AppRoutes.settingsClasses,
        actionLabel: 'Open Classes',
      ),
      ManualStep(
        'Create sections',
        'Open Settings → Sections and add the sections of each class (A, B, …). A student is always placed in a class and a section.',
        route: AppRoutes.settingsSections,
        actionLabel: 'Open Sections',
        check: 'Every class has at least one section.',
      ),
      ManualStep(
        'Create subjects and link them to classes',
        'Open Settings → Subjects, add the subjects, and link each subject to the classes that study it. Timetables, homework and exams use these links.',
        route: AppRoutes.settingsSubjects,
        actionLabel: 'Open Subjects',
      ),
      ManualStep(
        'Set working days and holidays',
        'Open Settings → Working days to mark the weekly days off, then Holidays for dates the school is closed. Attendance and leave use these.',
        route: AppRoutes.settingsWorkingDays,
        actionLabel: 'Open Working days',
      ),
      ManualStep(
        'Review the login rules',
        'Open Settings → Authentication to choose which sign-in methods the school allows before you create logins for staff and parents.',
        route: AppRoutes.settingsAuthentication,
        actionLabel: 'Open Authentication',
      ),
      ManualStep(
        'Verify the setup',
        'Walk back through Academic years, Classes, Sections and Subjects and confirm nothing is missing. You are ready to add students and staff.',
        check:
            'Year, classes, sections and subjects all exist. Next: Admit a student.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'The admission form shows no classes or sections.',
        'Create the academic year first, then classes, then sections for that year. The form lists only what exists for the year you choose.',
      ),
      ManualTroubleshooting(
        'The currency cannot be changed.',
        'It locks once money exists (a fee, invoice or payment). Contact your platform administrator if it was set wrongly.',
      ),
    ],
  ),
  ManualGuide(
    id: 'admit-student',
    categoryId: 'people',
    title: 'Admit a student (with parent details)',
    summary:
        'The four-step admission form: student, parent or guardian, class placement, review.',
    anyOf: {Permission.manageStudentData},
    minutes: 8,
    prerequisites: [
      'Academic year, class and section exist (see the school setup guide).',
      'You have the student\'s name, date of birth and the parent\'s mobile number.',
    ],
    keywords: [
      'admission',
      'admit',
      'add student',
      'new student',
      'parent',
      'guardian',
      'admission number',
      'register',
      'enrol',
    ],
    contextRoutes: [AppRoutes.newStudent],
    related: ['parent-login', 'bulk-import-students'],
    steps: [
      ManualStep(
        'Open the admission form',
        'Open Students and choose to add a student. The form is titled "Admit student" and has four steps.',
        route: AppRoutes.newStudent,
        actionLabel: 'Open Admit student',
      ),
      ManualStep(
        'Step 1 – Basic information',
        'Enter First name, Last name (Middle name is optional), Date of birth, Gender and the Admission date. The admission number is created for you (for example ADM-0001) and cannot be edited, so numbers never repeat. Blood group, email, phone, address and city are optional.',
        check: 'Name and date of birth are filled in; Next is enabled.',
        mistake:
            'Looking for a place to type the admission number: it is generated.',
      ),
      ManualStep(
        'Step 2 – Parent / guardian',
        'Choose one: Add later (no parent yet), Existing (search the parent and select them — use this for a second child of the same family) or New (enter First name, Last name, Phone and optionally Email). Then set the relationship and whether they are the primary and emergency contact.',
        check:
            'For New, the phone is valid. When you press Next the app checks the branch for the same email or phone.',
        mistake:
            'Choosing New for a parent who already has another child here. That would create a second record: choose Existing.',
      ),
      ManualStep(
        'Handle a possible duplicate',
        'If a parent with the same email already exists, the app does not create another: you can use the existing parent. If only the phone matches, you are asked whether to use the existing parent or create a separate record.',
        check: 'You deliberately chose between "use existing" and "create".',
      ),
      ManualStep(
        'Optionally request a parent login',
        'Tick "Give this parent a login after admission" if the parent should sign in to see fees, homework and results. This only opens the login screen after saving; see the parent login guide. Leave it off to do it later.',
      ),
      ManualStep(
        'Step 3 – Academic placement',
        'Choose the Academic year, then Class, then Section. A Roll number is optional.',
        check: 'All three of year, class and section are chosen.',
      ),
      ManualStep(
        'Step 4 – Review and admit',
        'Check the name, admission number, parent and placement, then press "Admit student". The student is saved first, then the parent is created and linked.',
        check:
            'A message confirms the student was admitted and the parent linked. You are taken to the student\'s profile.',
        mistake:
            'Pressing the button twice. Wait for the spinner; the form disables itself while saving.',
      ),
      ManualStep(
        'If the parent could not be saved',
        'The student is still admitted. The message says the parent was not linked and why. Open the student profile and link or add the parent from there.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'It is taking a long time.',
        'Check your internet connection. The form saves the student, then the parent, then the link. If a step fails you get a message instead of a spinner that never ends.',
      ),
      ManualTroubleshooting(
        'I cannot pick a section.',
        'The section list shows sections of the chosen class and year. Create the sections in Settings first.',
      ),
      ManualTroubleshooting(
        'The parent was not created.',
        'Parents are created only when you choose New (or Existing) on step 2. "Add later" saves the student with no parent.',
      ),
    ],
  ),
  ManualGuide(
    id: 'bulk-import-students',
    categoryId: 'people',
    title: 'Upload many students from a sheet',
    summary:
        'Download the template, fill it in, preview the checks, then import. Parents are created and linked too.',
    anyOf: {Permission.manageStudentData},
    minutes: 15,
    prerequisites: [
      'Classes and sections already exist with the same names you will type in the sheet.',
      'You chose the right academic year and branch.',
    ],
    keywords: [
      'bulk',
      'import',
      'upload',
      'sheet',
      'csv',
      'excel',
      'template',
      'many students',
    ],
    contextRoutes: [AppRoutes.students],
    related: ['admit-student', 'parent-login'],
    steps: [
      ManualStep(
        'Open the student import',
        'From Students, open the import option (in the page menu).',
        route: AppRoutes.students,
        actionLabel: 'Open Students',
      ),
      ManualStep(
        'Download the sample sheet',
        'Use the sample so the column names are exactly right. Admission numbers are not in the sheet: the app assigns them in the same ADM-0001 series as single admissions.',
        mistake: 'Renaming or reordering required columns.',
      ),
      ManualStep(
        'Fill in one row per student',
        'Class and section must match your setup. Dates can be written 2015-06-30 or 30/06/2015. Add the parent columns (first name, last name, phone, relationship, optional email) on the same row; children with the same parent phone share one parent record.',
        check: 'Parent name and phone are filled together or both left empty.',
      ),
      ManualStep(
        'Upload and read the preview',
        'Every row is checked before anything is saved. Rows with problems are listed with the line number, the reason and how to fix it. Fix them in the sheet or inline.',
        check: 'The number of valid rows is what you expect.',
        mistake:
            'Importing before fixing flagged rows: only valid rows are imported.',
      ),
      ManualStep(
        'Import',
        'Confirm the import. Each student is saved separately, so one bad row never blocks the others. Keep the window open until it finishes.',
        mistake:
            'Uploading a file again after it succeeded. Because numbers are assigned automatically, the same students would be added twice.',
      ),
      ManualStep(
        'Fix failed rows and give logins',
        'Download the failed rows, correct them and upload only those. Importing never creates parent logins: use "Give login access" in Parents afterwards.',
        route: AppRoutes.parents,
        actionLabel: 'Open Parents',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'A parent email already belongs to a parent in the branch.',
        'The row is flagged instead of creating a second record. Clear the parent columns for that row and link the existing parent from the student profile.',
      ),
    ],
  ),
  ManualGuide(
    id: 'parent-login',
    categoryId: 'people',
    title: 'Give a parent a login',
    summary:
        'A parent record is not a login. Create the sign-in, choose how the first password is set, and verify the parent sees the right child.',
    anyOf: {Permission.manageUsers},
    minutes: 10,
    prerequisites: [
      'The parent exists and is linked to at least one student.',
      'The parent has an email address (it becomes the sign-in).',
    ],
    keywords: [
      'parent login',
      'provision',
      'give login',
      'login access',
      'password',
      'activation email',
      'portal',
      'sign in',
      'reset password',
    ],
    contextRoutes: [AppRoutes.parents],
    related: ['admit-student'],
    steps: [
      ManualStep(
        'Understand record versus login',
        'A parent record holds name, phone and email and links to children. It cannot sign in. A login is a separate sign-in account created from the record. Admission and sheet uploads create records only.',
      ),
      ManualStep(
        'Open Parents',
        'Open the Parents list and find the parent. Use the key icon on a row, or select several parents and choose "Give login access".',
        route: AppRoutes.parents,
        actionLabel: 'Open Parents',
      ),
      ManualStep(
        'Check the email and portal access',
        'The dialog lists each parent with their sign-in email; enter one for anyone without. Keep "Allow portal access to their children" on so the parent can see their children.',
        check: 'Every parent you want has a valid email.',
      ),
      ManualStep(
        'Choose how the first password is set',
        'Pick one: Name + mobile number (easy to guess, least secure), Random temporary password (shown once for you to download), Activation email (the parent sets their own password from a secure link — recommended), Password set/reset link, or One password set by you for the whole batch.',
        mistake:
            'Sending passwords by chat or writing them where others can see them. Prefer the activation email.',
      ),
      ManualStep(
        'Create the logins',
        'Press "Create login". Keep the window open; large lists are processed in small groups. Passwords are never stored by the app.',
        check:
            'Each row shows a result. Use Retry for any that failed and Download passwords (CSV) only if you chose a temporary password.',
      ),
      ManualStep(
        'Hand over the details securely',
        'Give each parent their sign-in email and the way to set the password. A temporary password forces a change at first sign-in.',
      ),
      ManualStep(
        'Verify as the parent',
        'Ask the parent to sign in. They should see only their own children in My Fees, My Attendance, My Homework and My Results. If a second child is missing, link the child to the same parent (do not create a second parent).',
        check: 'The right child, class and section appear.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'The email is already in use.',
        'That address already has a login. Link the child to the existing parent record instead of creating another parent, or use a different email.',
      ),
      ManualTroubleshooting(
        'Login creation failed for some parents.',
        'Use Retry for the failed rows. If it keeps failing, the email may be invalid or the school may have restricted sign-in methods in Settings → Authentication.',
      ),
      ManualTroubleshooting(
        'The parent signed in but sees no child.',
        'Check the student is linked to this parent and that portal access is on for that link. Use "Refresh parent access" if your administrator has told you to.',
      ),
    ],
  ),
  ManualGuide(
    id: 'fee-structure',
    categoryId: 'fees',
    title: 'Create a fee structure',
    summary:
        'Define each fee (name, category, amount, how often it is billed, who it applies to) for an academic year.',
    anyOf: {Permission.viewFees},
    minutes: 10,
    prerequisites: [
      'The academic year, classes and sections exist.',
      'Only administrators can add or edit fees; finance staff can view them.',
    ],
    keywords: [
      'fee structure',
      'fees',
      'tuition',
      'transport',
      'category',
      'amount',
      'frequency',
      'quarterly',
      'monthly',
      'due date',
      'copy fees',
    ],
    contextRoutes: [AppRoutes.feeStructures],
    related: ['fee-assign', 'invoices'],
    steps: [
      ManualStep(
        'Open Fee structures',
        'Open Fees → Fee structures and pick the academic year at the top.',
        route: AppRoutes.feeStructures,
        actionLabel: 'Open Fee structures',
      ),
      ManualStep(
        'Start from last year (optional)',
        'Use "Copy from another year" to bring a previous year\'s fees across, then adjust the amounts.',
      ),
      ManualStep(
        'Add a fee',
        'Choose "Add fee". Enter a Code, a Fee name and the Category (Tuition, Transport, etc.; add a new category with Category name).',
        mistake: 'Reusing one code for two different fees.',
      ),
      ManualStep(
        'Set the amount and how it is billed',
        'Enter the Amount in the school currency and choose Billed: One time, Monthly, Quarterly, Half-yearly, Annual or Custom period. For "term-wise" fees use Quarterly, Half-yearly or Custom period.',
        check: 'The amount and billing choice match your fee circular.',
      ),
      ManualStep(
        'Choose who it applies to',
        'Pick the Class (and Section if it is specific). Leave Section empty for the whole class.',
      ),
      ManualStep(
        'Set the due date rule',
        '"Days until due after issue" decides each invoice\'s due date from the day it is issued. The Description appears on invoices; Payment instructions are optional.',
        mistake:
            'Expecting late-fee or instalment settings: the app has neither. Late payment is handled by staff.',
      ),
      ManualStep(
        'Optional, active, save',
        'Mark a fee "Optional fee" if not every student pays it. Keep it Active; inactive fees are not billed. Save.',
        check:
            'The fee shows on the list for the right class. Check the list before assigning fees to students.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'I cannot add or edit a fee.',
        'Only administrators can. A finance login can view structures, assign fees and issue invoices.',
      ),
      ManualTroubleshooting(
        'A fee is missing from invoices.',
        'It may be marked inactive. Turn on "Show inactive fees" to find it.',
      ),
    ],
  ),
  ManualGuide(
    id: 'fee-assign',
    categoryId: 'fees',
    title: 'Assign fees to students',
    summary:
        'Choose a class and section, select students, preview, then assign. Existing assignments are never duplicated.',
    anyOf: {Permission.assignFees},
    minutes: 6,
    prerequisites: [
      'The fee structure for the academic year is saved and active.',
      'Students are admitted and placed in a class and section.',
    ],
    keywords: [
      'assign fees',
      'fee assignment',
      'student fees',
      'bulk',
      'class',
      'section',
      'mid year',
      'new admission',
    ],
    contextRoutes: [AppRoutes.feeAssignments],
    related: ['fee-structure', 'invoices'],
    steps: [
      ManualStep(
        'Open Assign fees',
        'Open Fees → Assign fees and choose the academic year.',
        route: AppRoutes.feeAssignments,
        actionLabel: 'Open Assign fees',
      ),
      ManualStep(
        'Pick the class and section',
        'Choose the Class and a Section (or All sections), then "Load students".',
      ),
      ManualStep(
        'Select students',
        'Tick individual students, or use Select all / Select none. For one student who joined mid-year, tick only that student.',
        mistake: 'Leaving everyone ticked when only new students need fees.',
      ),
      ManualStep(
        'Preview',
        'Press "Preview assignment". The preview lists what will be created and what will be skipped, with the reason (for example already assigned, or the fee is inactive).',
        check: 'The numbers match what you expect before you continue.',
      ),
      ManualStep(
        'Assign',
        'Confirm "Assign N". A progress counter shows the work. Re-running it is safe: students who already have the fee are skipped, not charged twice.',
        check:
            'The result says how many were created and how many already existed.',
      ),
      ManualStep(
        'Verify a student\'s fees',
        'Open a student\'s fees (from the student or the invoices list) and confirm the components and the total.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'Some students were skipped.',
        'The preview lists the reason for each. Common reasons are an existing assignment or an inactive fee.',
      ),
    ],
  ),
  ManualGuide(
    id: 'invoices',
    categoryId: 'fees',
    title: 'Generate invoices',
    summary:
        'Choose the scope and billing period, preview, generate, then check the invoices. Includes waivers and voiding.',
    anyOf: {Permission.issueInvoices},
    minutes: 8,
    prerequisites: [
      'Fees are assigned to the students (see Assign fees).',
      'You know the billing period (month, quarter, half-year, year or custom).',
    ],
    keywords: [
      'invoice',
      'generate invoice',
      'bill',
      'billing period',
      'preview',
      'void',
      'waive',
      'concession',
      'discount',
      'pdf',
      'print',
    ],
    contextRoutes: [AppRoutes.invoices],
    related: ['fee-assign', 'payments'],
    steps: [
      ManualStep(
        'Open Generate invoices',
        'Open Fees → Invoices and choose "Generate invoices".',
        route: AppRoutes.generateInvoices,
        actionLabel: 'Open Generate invoices',
      ),
      ManualStep(
        'Choose the scope',
        'Pick the academic year, Class and Section (or All sections). Only students with an assigned fee for that period are billed.',
      ),
      ManualStep(
        'Choose the billing period and issue date',
        'Pick the period (for example Quarter 1) and check the Issue date. A fee is billed only in a period that matches its "Billed" setting (a quarterly fee in a quarter). The due date of each invoice comes from the fee\'s "days until due".',
        mistake: 'Choosing the wrong quarter and issuing early.',
      ),
      ManualStep(
        'Preview',
        'Press "Preview". Read the count, the sample of invoices and any warnings or skipped students.',
        check: 'The number of invoices and total look right.',
      ),
      ManualStep(
        'Generate',
        'Confirm "Generate N invoices". Wait for the progress to finish; do not close the page.',
        mistake:
            'Closing the page mid-way. Re-open and preview again: students already invoiced for the period are skipped ("Already invoiced"), never billed twice.',
      ),
      ManualStep(
        'Check the invoices',
        'Open "View invoices" and filter by Class, Section or Status. Open one: confirm the invoice number, student, period, fee breakdown, Subtotal, Concessions, Payable and Balance due. Use PDF or Print to hand out copies.',
        route: AppRoutes.invoices,
        actionLabel: 'Open Invoices',
        check: 'Parents see issued invoices under My Fees.',
      ),
      ManualStep(
        'Concessions and corrections',
        'On an invoice, "Waive" reduces the balance (a waiver cannot exceed the balance due and needs a reason, which is recorded in the audit log). Administrators can void a wrong invoice with a reason. Each invoice covers one period; earlier unpaid invoices stay separate.',
      ),
      ManualStep(
        'Invoice versus receipt',
        'An invoice is the bill (what is owed). A receipt is proof of one payment. Paying an invoice produces a receipt and lowers the balance.',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'Preview shows 0 invoices.',
        'No student in that scope has an active fee assignment for the period. Assign fees first.',
      ),
      ManualTroubleshooting(
        'An invoice has the wrong amount.',
        'Void it (administrator) with a reason, correct the fee or assignment, and generate again.',
      ),
    ],
  ),
  ManualGuide(
    id: 'payments',
    categoryId: 'fees',
    title: 'Collect a payment and issue a receipt',
    summary:
        'Record cash, UPI, bank transfer or cheque against an invoice, then check the balance and receipt.',
    anyOf: {Permission.collectPayments},
    minutes: 5,
    prerequisites: [
      'The invoice has been generated and has a balance due.',
      'The money has actually been received. Recording a payment does not collect money.',
    ],
    keywords: [
      'payment',
      'collect',
      'receipt',
      'cash',
      'upi',
      'cheque',
      'bank transfer',
      'partial payment',
      'reverse payment',
      'refund',
    ],
    contextRoutes: [AppRoutes.feePayments],
    related: ['invoices'],
    steps: [
      ManualStep(
        'Find the invoice',
        'Open Fees → Invoices, search or filter for the student, and open the invoice with a balance.',
        route: AppRoutes.invoices,
        actionLabel: 'Open Invoices',
      ),
      ManualStep(
        'Choose "Collect payment"',
        'On the invoice, press "Collect payment".',
      ),
      ManualStep(
        'Enter the amount',
        'Enter the Amount received. Part payments are allowed; an amount larger than the balance due is refused (overpayment is not accepted).',
        mistake: 'Typing the invoice total when only part was paid.',
      ),
      ManualStep(
        'Choose the payment method',
        'Pick Cash, UPI, Bank transfer, Cheque or Other. UPI, bank transfer and cheque need a reference or cheque number. Check the Payment date.',
      ),
      ManualStep(
        'Save and check',
        'Save the payment. The invoice balance drops and a receipt is created. Open Receipt to print or save a PDF.',
        check: 'Balance due equals the old balance minus what you entered.',
      ),
      ManualStep(
        'Review payments later',
        'Fees → Payments & receipts lists payments with filters for From, To, Method and Status.',
        route: AppRoutes.feePayments,
        actionLabel: 'Open Payments',
      ),
    ],
    troubleshooting: [
      ManualTroubleshooting(
        'I recorded the wrong amount.',
        'An administrator can reverse a payment with a reason (it is kept in the audit log) and you then record the correct one.',
      ),
      ManualTroubleshooting(
        'Parents want to pay online.',
        'Online payment is not available yet. Fees are paid at the school and recorded by staff; parents see invoices and receipts in My Fees.',
      ),
    ],
  ),
  ManualGuide(
    id: 'leave-apply',
    categoryId: 'leave',
    title: 'Apply for leave',
    summary:
        'Staff apply for their own leave; parents apply for a child. Follow the status.',
    anyOf: {Permission.viewOwnLeave},
    minutes: 3,
    keywords: ['leave', 'apply leave', 'absence', 'holiday request', 'sick'],
    contextRoutes: [AppRoutes.myLeave],
    related: ['leave-review'],
    steps: [
      ManualStep(
        'Open My Leave',
        'Open My Leave to see your balances and past requests.',
        route: AppRoutes.myLeave,
        actionLabel: 'Open My Leave',
      ),
      ManualStep(
        'Start a request',
        'Choose to apply for leave, pick the leave type and the dates, add a reason and submit.',
        route: AppRoutes.myLeaveApply,
        actionLabel: 'Apply for leave',
        mistake:
            'Choosing dates that fall on a holiday or weekly day off; they are not working days.',
      ),
      ManualStep(
        'Follow the status',
        'Your request shows as pending until it is reviewed. You are notified of the decision.',
        route: AppRoutes.myLeaveNotifications,
        actionLabel: 'Open leave notifications',
      ),
    ],
  ),
  ManualGuide(
    id: 'leave-review',
    categoryId: 'leave',
    title: 'Review leave requests',
    summary: 'Approve or decline staff leave and keep balances right.',
    anyOf: {Permission.reviewLeave},
    minutes: 4,
    keywords: [
      'leave',
      'approve leave',
      'reject leave',
      'balance',
      'leave types',
    ],
    contextRoutes: [AppRoutes.leave],
    related: ['leave-apply'],
    steps: [
      ManualStep(
        'Open the applications',
        'Open Leave → Applications to see requests waiting for a decision.',
        route: AppRoutes.leaveApplications,
        actionLabel: 'Open Applications',
      ),
      ManualStep(
        'Open a request and decide',
        'Check the person, dates, type and reason, then approve or decline it with a note.',
        check: 'The decision shows on the request and the person is notified.',
      ),
      ManualStep(
        'Keep types and balances right',
        'Leave types and yearly balances are managed under Leave → Types and Balances.',
        route: AppRoutes.leaveTypes,
        actionLabel: 'Open Leave types',
      ),
    ],
  ),
  ManualGuide(
    id: 'switch-branch',
    categoryId: 'account',
    title: 'Work in a different branch',
    summary:
        'School administrators can act in any branch; pick the branch before adding data.',
    anyOf: {Permission.manageBranches},
    minutes: 2,
    keywords: ['branch', 'switch branch', 'multi branch', 'acting branch'],
    steps: [
      ManualStep(
        'Choose the acting branch',
        'Use the branch selector in the header to choose the branch you are working in.',
      ),
      ManualStep(
        'Check the banner',
        'Admission and upload pages show a banner naming the branch where data will land. Read it before saving.',
        mistake: 'Admitting students while still acting in the wrong branch.',
      ),
    ],
  ),
  ManualGuide(
    id: 'delete-account',
    categoryId: 'account',
    title: 'Request deletion of your account',
    summary:
        'How account deletion works, what it removes, and what it never touches.',
    minutes: 3,
    keywords: ['delete account', 'remove account', 'privacy', 'data'],
    contextRoutes: [AppRoutes.deleteAccount],
    steps: [
      ManualStep(
        'Open Delete account',
        'Go to Dashboard → Account → Delete account.',
        route: AppRoutes.deleteAccount,
        actionLabel: 'Open Delete account',
      ),
      ManualStep(
        'Submit the request',
        'Every request is reviewed by the platform administrator before anything happens.',
      ),
      ManualStep(
        'Wait for the result',
        'The app never says your account is deleted until the server reports it as completed. Student and financial records are not deleted by this process.',
      ),
    ],
  ),
];
