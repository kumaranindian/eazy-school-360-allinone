import '../../../../core/regional/school_time.dart';
import '../../../leave/domain/leave_enums.dart';
import '../../../leave/domain/leave_submission.dart';
import '../../../leave/presentation/providers/leave_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/attendance_date.dart';
import '../../domain/attendance_registers.dart';
import '../../domain/attendance_sheet.dart';
import '../../domain/staff_attendance.dart';
import '../../domain/staff_attendance_repository.dart';
import '../providers/attendance_providers.dart';
import '../widgets/calendar_support.dart';
import '../widgets/register_editor.dart';

/// `/attendance/staff` — the branch's staff on a date. Managers mark and
/// correct; finance can look (read-only). Only staff who were employed on the
/// chosen date appear (see `StaffEligibility`), and nobody is pre-marked.
class StaffAttendancePage extends StatelessWidget {
  const StaffAttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) => Scaffold(
        appBar: AppBar(title: const Text('Staff attendance')),
        body: _StaffAttendance(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
        ),
      ),
    );
  }
}

class _StaffAttendance extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;

  const _StaffAttendance({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
  });

  @override
  ConsumerState<_StaffAttendance> createState() => _StaffAttendanceState();
}

class _StaffAttendanceState extends ConsumerState<_StaffAttendance> {
  DateTime _date = AttendanceDate.dateOnly(SchoolTime.wallNow());
  StaffRegister? _register;
  AttendanceSheet? _sheet;
  bool _loading = true;
  String? _loadError;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final register = await ref
          .read(staffAttendanceRepositoryProvider)
          .loadRegister(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            date: _date,
          );
      if (!mounted || token != _token) return;
      setState(() {
        _register = register;
        _sheet = register.toSheet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _token) return;
      setState(() {
        _loadError = userMessageFor(error);
        _loading = false;
      });
    }
  }

  Future<void> _submit(RegisterSubmit submit) {
    return ref
        .read(staffAttendanceRepositoryProvider)
        .saveRegister(
          SaveStaffRegisterRequest(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            dateKey: AttendanceDate.key(_date),
            entries: _sheet!.entries,
            finalize: submit.finalize,
            reason: submit.reason,
            expectedDayRevision: _register?.day?.revision ?? 0,
            dayKind: submit.dayKind,
            overrideReason: submit.overrideReason,
            actorId: widget.tenant.user.userId,
          ),
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: SchoolTime.wallNow(),
    );
    if (picked != null) {
      setState(() => _date = AttendanceDate.dateOnly(picked));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final years =
        ref.watch(academicYearsProvider(branchKey)).value ??
        const <AcademicYear>[];
    // The academic year whose calendar applies is the one containing the date.
    final year = years
        .where(
          (y) =>
              !AttendanceDate.dateOnly(
                _date,
              ).isBefore(AttendanceDate.dateOnly(y.startDate)) &&
              !AttendanceDate.dateOnly(
                _date,
              ).isAfter(AttendanceDate.dateOnly(y.endDate)),
        )
        .firstOrNull;
    final calendar = watchCalendarDay(
      ref,
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: year?.academicYearId,
      date: _date,
    );
    final canManage = widget.tenant.can(Permission.manageAttendance);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(formatDisplayDate(_date)),
              ),
              if (!canManage)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.md),
                  child: Text('View only'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Builder(
            builder: (context) {
              if (_loading || calendar.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (calendar.hasError) {
                return ErrorView(
                  message: userMessageFor(calendar.error!),
                  onRetry: _load,
                );
              }
              if (_loadError != null) {
                return ErrorView(message: _loadError!, onRetry: _load);
              }
              final sheet = _sheet;
              if (sheet == null) {
                return const EmptyView(message: 'No staff attendance to show.');
              }
              // Approved staff leave for this date: readable by reviewers only
              // (rules), so other roles simply see no annotation.
              final dateKey = AttendanceDate.key(_date);
              final leaveEntries =
                  ref
                      .watch(
                        leaveCalendarProvider((
                          schoolId: widget.schoolId,
                          branchId: widget.branchId,
                          kind: LeaveKind.staff,
                          fromKey: dateKey,
                          toKey: dateKey,
                          classId: null,
                          sectionId: null,
                          subjectId: null,
                        )),
                      )
                      .value ??
                  const [];
              return RegisterEditor(
                key: ValueKey(
                  '${AttendanceDate.key(_date)}_${_register.hashCode}',
                ),
                leaveLabels: {
                  for (final e in LeaveAttendanceOverlay.forDate(
                    leaveEntries,
                    dateKey,
                  ).entries)
                    e.key: LeaveAttendanceOverlay.label(e.value),
                },
                sheet: sheet,
                detailLabel: 'Code',
                title:
                    'Staff · ${formatDisplayDate(_date)} · ${sheet.entries.length} on the register',
                calendar: calendar.value,
                dateError: attendanceDateError(_date),
                canMark: canManage,
                canManage: canManage,
                onSubmit: _submit,
                onReload: _load,
                historyLoader: canManage
                    ? (entry) => ref
                          .read(staffAttendanceRepositoryProvider)
                          .fetchHistory(
                            schoolId: widget.schoolId,
                            branchId: widget.branchId,
                            attendanceId: StaffAttendance.idFor(
                              AttendanceDate.key(_date),
                              entry.subjectId,
                            ),
                          )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
