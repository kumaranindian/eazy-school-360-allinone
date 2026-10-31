# Feature audit matrix

Legend: ✔ evidence found · ◐ partial / unverified · ✘ missing · – not applicable. **Status** rules: PASS needs UI, backend, database, security and test evidence; PARTIAL has a stated gap; FAIL is a demonstrated defect; NOT IMPLEMENTED means the capability does not exist in the repository; NOT TESTED could not be verified in a read-only audit.

**Totals:** 122 features in 13 modules - PASS 70 · PARTIAL 35 · FAIL 2 · NOT IMPLEMENTED 11 · NOT TESTED 4

## Authentication & Users
_11 features: PASS 5, PARTIAL 6_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Authentication & Users | Email/password login | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | router redirects + session tests; login-access-rules |
| Authentication & Users | Google sign-in | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Rules gate it (loginAllowed, email_verified); real OAuth/SHA-1/authorized domains on prod not verified |
| Authentication & Users | Password reset (forgot password) | ✔ | ✔ | – | ✔ | ◐ | PARTIAL | Calls sendPasswordResetEmail via fakes; email delivery/templates not exercised |
| Authentication & Users | Phone OTP (WhatsApp) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | functions/otp.js + 168 test lines; OFF on dev and prod (META_WA_* env empty); never run live |
| Authentication & Users | Role-based login (admin/teacher/finance/parent) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | rbac-screen-sweep, rbac-first-load, route_permissions tests |
| Authentication & Users | Create logins (individual & bulk) - provisionLogins | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | provision.test.js uses fakes; Admin-SDK path not run against the Auth emulator |
| Authentication & Users | Admin password reset / forced change at first sign-in | ✔ | ✔ | ✔ | ◐ | ◐ | PARTIAL | mustChangePassword enforced by app + callable only, not by rules (documented design) |
| Authentication & Users | User activation / deactivation | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | isActiveCaller() in every rule; login-access-rules |
| Authentication & Users | Role assignment | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | users rule limits managed roles; rules.test.mjs privilege-escalation cases |
| Authentication & Users | Session management & logout | ✔ | ✔ | – | ✔ | ◐ | PARTIAL | logout clears devices; Firebase default persistence; no idle timeout / forced re-auth |
| Authentication & Users | Unauthorized access prevention (routes + rules) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | 479/479 rules tests; route_permissions_test |

## School Management
_9 features: PARTIAL 2, PASS 7_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| School Management | School registration (self sign-up) | ✔ | ✔ | ✔ | ◐ | ✔ | PARTIAL | Rule restricts to a brand-new school; no abuse/spam control (anyone can create schools) |
| School Management | School profile | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | rules.test.mjs, school widget tests |
| School Management | Branches & per-branch roles | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | multi-branch-rules, multi-branch-storage |
| School Management | Academic year management | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | school-year-rules; TZ matrix in CI |
| School Management | Classes / sections / subjects | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | rules.test.mjs + settings widget tests |
| School Management | Class-subject mapping | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | classSubjects rules; limited widget tests [downgraded: a column is only partially evidenced] |
| School Management | Working days & holidays | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | holiday-calendar-rules |
| School Management | Regional settings & currency lock | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | regional-settings-rules, currency_lock tests |
| School Management | Per-school authentication settings | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | login-access-rules, access.test.js |

## Student Management
_13 features: PASS 8, PARTIAL 3, NOT IMPLEMENTED 1, FAIL 1_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Student Management | Add student (admission wizard) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | individual_registration_test, admission-number-rules |
| Student Management | Edit student / profile | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | rules tests + widget tests |
| Student Management | Admission number generation (ADM-0001) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Format unit-tested; live Firestore query + retry not run on an emulator; window of 50 numbers |
| Student Management | Parent association / linking | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent-scope tests |
| Student Management | Class & section placement | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | academicRecords rules + tests |
| Student Management | Year-end student promotion | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | Only a code comment in student_transfer_dialog.dart mentions it |
| Student Management | In-branch student transfer | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | branch_transfer_write_contract replayed to rules |
| Student Management | Cross-branch student transfer | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | multi-branch-rules, transfer contract |
| Student Management | Student deactivation / status change | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | rules + student status tests |
| Student Management | Student search & filtering | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | students_list_test, server count() aggregates |
| Student Management | Bulk student upload | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Fakes only; per-row atomic; 500-row cap; see finding PB-05 |
| Student Management | Bulk upload re-upload protection | ✔ | ✘ | ✘ | – | ✔ | FAIL | After auto-numbering the sheet carries no admission number, so uploading the same file twice creates duplicate students |
| Student Management | Duplicate student prevention | ◐ | ◐ | ✔ | ✔ | ◐ | PARTIAL | Only admission-number uniqueness (reservation docs); no name+DOB check |

## Parent Management
_5 features: PASS 4, PARTIAL 1_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Parent Management | Parent record create / edit | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent rules, parent form tests |
| Parent Management | Duplicate parent detection (email/phone) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Fake-tested; whereIn queries not run on emulator |
| Parent Management | Multiple children under one parent | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent-scope, parentAccess tests |
| Parent Management | Parent profile | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent profile widget + rules |
| Parent Management | Parent portal boundaries (own child only) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent-scope, parent-attendance-rules, parent-leave-results, tenant sweeps |

## Fee Management
_20 features: PASS 13, NOT IMPLEMENTED 3, PARTIAL 4_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Fee Management | Fee structures & categories | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | fees-rules, fee planner tests |
| Fee Management | Class-wise & student-specific assignment | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | AssignmentPlanner tests, deterministic ids |
| Fee Management | Academic-year mapping | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | structures keyed by year |
| Fee Management | Monthly / quarterly / half-yearly / annual / custom billing | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | FeeFrequency, BillingPeriod tests |
| Fee Management | Discounts / concessions (waivers) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | invoiceWaivers rules; waiver <= balance enforced |
| Fee Management | Late fees | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | No late-fee model anywhere in lib/ |
| Fee Management | Instalment plans | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | No instalment model in lib/ |
| Fee Management | Invoice generation (idempotent) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | InvoicePlanner skips already-invoiced; fees-rules |
| Fee Management | Invoice & receipt numbering | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | counters in transactions, numbers reserved; one counter per branch (throughput limit) |
| Fee Management | Payment collection (idempotent id) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | payments rule: amount<=balance, balanceAfter, receipt in same commit |
| Fee Management | Partial payments | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | rule + payment_rules tests; overpayment refused |
| Fee Management | Payment methods (cash/UPI/bank/cheque/other) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | reference required for UPI/bank/cheque; no card |
| Fee Management | Receipt generation (view/print/PDF) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | fee_pdf.dart; PDF layout not visually verified here [downgraded: a column is only partially evidenced] |
| Fee Management | Payment history & due tracking | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | payments page, invoice filters |
| Fee Management | Outstanding balances | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | fee reports, invoice_reconciler |
| Fee Management | Payment reconciliation | ◐ | ◐ | ✔ | ✔ | ◐ | PARTIAL | Pure InvoiceReconciler only; no scheduled check or UI |
| Fee Management | Reversals / voids / refunds | ✔ | ✔ | ✔ | ✔ | ✔ | PARTIAL | Reversal and void exist (admin, audited); no cash-refund workflow |
| Fee Management | Online payment gateway | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | "Pay online - coming soon" placeholder |
| Fee Management | Fee due reminders | – | ✔ | ✔ | ✔ | ◐ | PARTIAL | feeDueReminders scheduled function; Android push only |
| Fee Management | Parent fee view (My Fees) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent rules P4 tests; widget tests |

## Attendance
_10 features: PASS 6, NOT IMPLEMENTED 1, PARTIAL 3_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Attendance | Student attendance (daily, class-wise) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | attendance-rules, register transaction tests |
| Attendance | Staff attendance | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | staff attendance rules + tests |
| Attendance | Statuses present/absent/late/half-day | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | AttendanceStatus enum |
| Attendance | Leave as an attendance status | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | Leave is a separate module; not an attendance status |
| Attendance | Correction with reason + history | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | history subcollection, revision conflict handling |
| Attendance | Duplicate attendance prevention | ✔ | ✔ | ✔ | ◐ | ✔ | PARTIAL | Deterministic ids/transaction; rules trust client section/date (ACAD-9 accepted) |
| Attendance | Attendance reports | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Copy-CSV only; widget tests [downgraded: a column is only partially evidenced] |
| Attendance | Parent attendance view | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent-attendance-rules |
| Attendance | Parent attendance notifications | – | ✔ | ✔ | ✔ | ◐ | PARTIAL | notifyRegisterFinalized deployed; no device end-to-end test |
| Attendance | Teacher scoping to assigned sections | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | teacherAccess index (server-written) + rules tests |

## Timetable
_7 features: PASS 6, PARTIAL 1_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Timetable | Bell schedules / periods | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | timetable rules + contract |
| Timetable | Class timetable create / edit / copy | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | timetable_write_contract replayed |
| Timetable | Publish / withdraw / versioning | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | publish lock, history |
| Timetable | Conflict detection & report | ✔ | ✔ | – | – | ✔ | PASS | timetable_validation tests |
| Timetable | Substitutions | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | substitution rules/contract |
| Timetable | Class / teacher / own / parent views | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | timetable view widget tests, parent tests |
| Timetable | Teacher availability calendar | ◐ | ◐ | – | – | ◐ | PARTIAL | Conflict checks only; no availability/preference model |

## Homework
_7 features: PASS 6, PARTIAL 1_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Homework | Create / edit / publish homework | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | homework_write_contract; homework-rules |
| Homework | Class & subject targeting | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | teacher scope rules |
| Homework | Attachments | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | homework-storage-rules |
| Homework | Due dates / late handling | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | server time decides lateness |
| Homework | Student submission & review/grading | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | submissions rules + review tests |
| Homework | Parent visibility | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent homework tests |
| Homework | Homework notifications | – | ✔ | ✔ | ✔ | ◐ | PARTIAL | audience-addressed push; Android only; not device-tested |

## Examinations & Results
_9 features: PASS 7, PARTIAL 2_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Examinations & Results | Grading schemes | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | exam-rules, grading tests |
| Examinations & Results | Exam creation & scheduling | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | exam_write_contract |
| Examinations & Results | Exam timetable view | ◐ | ◐ | ✔ | ✔ | ◐ | PARTIAL | Per-subject dates only; no dedicated exam-timetable screen |
| Examinations & Results | Marks entry & validation (max/absent/exempt) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | marks rules, ResultCalculator tests |
| Examinations & Results | Marks review / approve / return | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | sheetUpdateOk rules |
| Examinations & Results | Result calculation, grades, ranks | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | result_calculator tests |
| Examinations & Results | Report card (PDF) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | report_card_pdf.dart; one test file; layout not visually verified |
| Examinations & Results | Result publishing & parent view | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | parent-leave-results tests |
| Examinations & Results | Result correction & audit history | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | reopen, resultVersion, history |

## Communication & Notifications
_8 features: PASS 4, PARTIAL 1, NOT IMPLEMENTED 3_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Communication & Notifications | Announcements (audience, attachments) | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | announcement rules + storage tests |
| Communication & Notifications | Notification centre & history | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | notification tests |
| Communication & Notifications | Parent-teacher messaging | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | communication-rules/contract |
| Communication & Notifications | Push notifications (Android) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | 132+ node tests; no device test; ENFORCE_APP_CHECK off |
| Communication & Notifications | Delivery failure handling & redrive | – | ✔ | ✔ | ✔ | ✔ | PASS | pushRedrive, delivery_log tests |
| Communication & Notifications | Web push | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | Documented as unsupported |
| Communication & Notifications | WhatsApp notifications | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | WhatsApp is used for OTP only |
| Communication & Notifications | Email / SMS notifications | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | "Not available" in settings |

## Leave
_4 features: PASS 3, PARTIAL 1_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Leave | Leave types & policy | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | leave-rules/contract |
| Leave | Apply / approve / reject / withdraw | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | transactional decisions |
| Leave | Balances, ledger, carry-forward | ✔ | ✔ | ✔ | ✔ | ✔ | PASS | leaveLedger rules |
| Leave | Leave calendar & reports | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | widget tests [downgraded: a column is only partially evidenced] |

## Reports & Dashboards
_8 features: PARTIAL 6, NOT IMPLEMENTED 2_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Reports & Dashboards | Admin / teacher / parent dashboards | ✔ | ✔ | – | ✔ | ◐ | PARTIAL | Shortcut hubs filtered by permission; no KPIs or role analytics |
| Reports & Dashboards | Finance dashboard | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | Finance gets the same hub; only Fee reports exist |
| Reports & Dashboards | Fee collection report | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Collections by period, Copy CSV [downgraded: a column is only partially evidenced] |
| Reports & Dashboards | Outstanding fee report | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | Outstanding by class and section [downgraded: a column is only partially evidenced] |
| Reports & Dashboards | Attendance report | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | students/staff, period [downgraded: a column is only partially evidenced] |
| Reports & Dashboards | Examination report (performance) | ✔ | ✔ | ✔ | ✔ | ◐ | PARTIAL | pass rate, distribution [downgraded: a column is only partially evidenced] |
| Reports & Dashboards | Student report | ✘ | ✘ | ✘ | – | ✘ | NOT IMPLEMENTED | Student list only |
| Reports & Dashboards | Export / download | ◐ | ◐ | – | – | ◐ | PARTIAL | CSV is copied to clipboard; staff CSV export; invoices/receipts/report cards as PDF |

## Platform, Operations & Compliance
_11 features: PARTIAL 4, FAIL 1, NOT TESTED 4, NOT IMPLEMENTED 1, PASS 1_

| Module | Feature | UI | Backend | Database | Security | Tests | Status | Evidence / note |
|---|---|---|---|---|---|---|---|---|
| Platform, Operations & Compliance | Account deletion (request/review/processor) | ✔ | ✔ | ✔ | ✔ | ✔ | PARTIAL | Processor OFF and never run on real data; web form needs Auth settings |
| Platform, Operations & Compliance | Help & User Manual | ✔ | – | ✔ | ✔ | ✔ | PARTIAL | 18+ tests pass, but see PB-02 (header regression) |
| Platform, Operations & Compliance | Branding header on phone width | ✔ | – | – | – | ✔ | FAIL | branding_shell_test: 6 failures - title 72 px off-centre with the Help icon |
| Platform, Operations & Compliance | App Check | ✔ | ✔ | – | ◐ | ◐ | PARTIAL | Opt-in; ENFORCE_APP_CHECK absent on deployed dev and prod functions |
| Platform, Operations & Compliance | Crash reporting & monitoring | ◐ | – | – | – | ◐ | NOT TESTED | Crashlytics wiring present; console state and alert policies unverified |
| Platform, Operations & Compliance | Backup / PITR / restore | – | – | – | – | ✘ | NOT TESTED | Docs only; no evidence of enabled PITR or a restore drill |
| Platform, Operations & Compliance | Privacy policy link | ✘ | – | – | – | ✘ | NOT IMPLEMENTED | No privacy-policy page or URL in app, web or manifest |
| Platform, Operations & Compliance | Android release build & signing | – | ✔ | – | ✔ | ✔ | PASS | build fails without key.properties; android_signing/manifest tests |
| Platform, Operations & Compliance | Web hosting security headers | – | ✔ | – | ◐ | ✔ | PARTIAL | HSTS, X-Frame etc. set; CSP is Report-Only |
| Platform, Operations & Compliance | Production data integrity (duplicates, orphans, balances) | – | – | ✔ | – | ✘ | NOT TESTED | Read-only audit: no production data was inspected |
| Platform, Operations & Compliance | Load / scale behaviour | – | – | – | – | ✘ | NOT TESTED | No load test exists or was run |
