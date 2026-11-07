# Application audit (Phase 1)

Branch `feature/ui-design-system`. Frontend-only revamp; backend untouched.

## Login roles
platformAdmin, schoolAdmin, branchAdmin, teacher, finance, parent (`lib/core/permissions/user_role.dart`). Role gates: `route_permissions` + `RolePermissions.grants` (unchanged).

## Screens (pages) per feature

### academic_setup (8 page files, 7 dialogs/sheets)

- academic_years_page.dart
- classes_page.dart
- holidays_page.dart
- school_years_page.dart
- sections_page.dart
- settings_overview_page.dart
- subjects_page.dart
- working_days_page.dart
- (dialog) academic_year_form_dialog.dart
- (dialog) class_form_dialog.dart
- (dialog) class_subjects_dialog.dart
- (dialog) holiday_form_dialog.dart
- (dialog) school_year_dialogs.dart
- (dialog) section_form_dialog.dart
- (dialog) subject_form_dialog.dart

### account_deletion (1 page files, 0 dialogs/sheets)

- account_deletion_page.dart

### announcements (3 page files, 0 dialogs/sheets)

- announcement_detail_page.dart
- announcement_form_page.dart
- announcements_page.dart

### attendance (5 page files, 1 dialogs/sheets)

- attendance_hub_page.dart
- attendance_reports_page.dart
- my_attendance_page.dart
- staff_attendance_page.dart
- student_attendance_page.dart
- (dialog) attendance_sheet_rows.dart

### authentication (6 page files, 0 dialogs/sheets)

- account_inactive_page.dart
- change_initial_password_page.dart
- forgot_password_page.dart
- login_page.dart
- register_page.dart
- splash_page.dart

### communication (3 page files, 0 dialogs/sheets)

- conversation_page.dart
- conversations_page.dart
- new_conversation_page.dart

### dashboard (1 page files, 0 dialogs/sheets)

- dashboard_page.dart

### exams (11 page files, 0 dialogs/sheets)

- exam_detail_page.dart
- exam_form_page.dart
- exam_history_page.dart
- exam_list_page.dart
- exam_results_page.dart
- grading_schemes_page.dart
- marks_entry_page.dart
- marks_review_page.dart
- my_results_pages.dart
- performance_page.dart
- student_result_page.dart

### fees (11 page files, 4 dialogs/sheets)

- fee_assignment_page.dart
- fee_reminder_settings_page.dart
- fee_reports_page.dart
- fee_structures_page.dart
- fees_hub_page.dart
- generate_invoices_page.dart
- invoice_detail_page.dart
- invoices_page.dart
- parent_fees_page.dart
- payments_page.dart
- receipt_page.dart
- (dialog) copy_structures_dialog.dart
- (dialog) fee_action_dialogs.dart
- (dialog) fee_structure_form_dialog.dart
- (dialog) student_fees_dialog.dart

### help (2 page files, 0 dialogs/sheets)

- help_home_page.dart
- manual_guide_page.dart

### homework (7 page files, 0 dialogs/sheets)

- homework_detail_page.dart
- homework_form_page.dart
- homework_list_page.dart
- homework_review_page.dart
- my_homework_detail_page.dart
- my_homework_page.dart
- submission_review_page.dart

### leave (10 page files, 0 dialogs/sheets)

- leave_applications_page.dart
- leave_apply_pages.dart
- leave_balances_page.dart
- leave_calendar_page.dart
- leave_detail_pages.dart
- leave_hub_page.dart
- leave_notifications_page.dart
- leave_reports_page.dart
- leave_types_page.dart
- my_leave_page.dart

### notifications (2 page files, 0 dialogs/sheets)

- notification_center_page.dart
- notification_preferences_page.dart

### school_setup (4 page files, 1 dialogs/sheets)

- branches_page.dart
- create_school_page.dart
- regional_settings_page.dart
- school_setup_page.dart
- (dialog) branch_form_dialog.dart

### staff (7 page files, 4 dialogs/sheets)

- my_staff_profile_page.dart
- staff_bulk_import_page.dart
- staff_config_page.dart
- staff_form_page.dart
- staff_list_page.dart
- staff_profile_page.dart
- teachers_list_page.dart
- (dialog) link_user_dialog.dart
- (dialog) staff_config_form_dialog.dart
- (dialog) staff_status_dialog.dart
- (dialog) teacher_assignment_dialog.dart

### students (8 page files, 6 dialogs/sheets)

- parent_profile_page.dart
- parents_list_page.dart
- student_admission_page.dart
- student_bulk_import_page.dart
- student_profile_page.dart
- students_entry_page.dart
- students_list_page.dart
- teacher_students_page.dart
- (dialog) link_parent_dialog.dart
- (dialog) parent_duplicates_dialog.dart
- (dialog) parent_form_dialog.dart
- (dialog) student_branch_transfer_dialog.dart
- (dialog) student_status_dialog.dart
- (dialog) student_transfer_dialog.dart

### timetable (6 page files, 0 dialogs/sheets)

- period_sets_page.dart
- substitution_pages.dart
- timetable_conflicts_page.dart
- timetable_editor_page.dart
- timetable_hub_page.dart
- timetable_views_pages.dart

### users (3 page files, 5 dialogs/sheets)

- auth_settings_page.dart
- login_access_page.dart
- users_page.dart
- (dialog) add_school_admin_dialog.dart
- (dialog) bulk_reset_password_dialog.dart
- (dialog) login_access_dialog.dart
- (dialog) provision_logins_dialog.dart
- (dialog) reset_password_dialog.dart

Total page files: 98

## Routes
`lib/core/routing/app_routes.dart` (108 route constants, each with a required permission) incl. shell tabs (dashboard, school, settings, students, parents, more). Route guards and deep links are not modified.

## Shared UI already centralised (reused, not duplicated)
`lib/core/theme` (AppColors, AppTheme, AdminDashboardPalette, AppSpacing, AppTypography), `lib/shared/{branding,layouts,filters,dialogs,loading,error,widgets,dashboard}`: PageHero, SectionPage, ScopeBar, FilterBar, StatChipsBar, DirectoryToolbar/ListCard, HubTile, app_dialog, AsyncValueWidget, EmptyView, StatusPill.

## Colour audit (before)
- All interactive colour came from `AppColors.primary` (blue 0A6BD9) via ColorScheme; hero panels used a navy→blue gradient; ~14 files used `brandBlue/navy` directly (dashboard tiles, fees hub, timetable, users page).
- Stray hexes: 3x D9EAFF (light blue text on hero), indigo gradient on one home tile, violet/pink category colours (data colour-coding, kept for now), one sky-blue window in the painted welcome illustration.
- No `Colors.blue*` usages.

## Plan
1. Global tokens (this batch): blue -> green/neutral in `app_colors.dart`, `app_theme.dart`, `admin_dashboard_palette.dart`; tokens renamed (brandBlue->accent, navy->ink).
2. Shell/header/navigation. 3. Platform admin. 4. School admin. 5. Branch admin. 6. Teacher. 7. Finance. 8. Parent. 9. Forms/dialogs. 10. Regression + responsive.
Each batch stops for approval.
