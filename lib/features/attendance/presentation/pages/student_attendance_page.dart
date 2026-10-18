import '../../../../core/regional/school_time.dart';
import '../../../leave/domain/leave_enums.dart';
import '../../../leave/domain/leave_submission.dart';
import '../../../leave/presentation/providers/leave_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/layouts/scope_bar.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/attendance_date.dart';
import '../../domain/attendance_registers.dart';
import '../../domain/attendance_sheet.dart';
import '../../domain/student_attendance.dart';
import '../../domain/student_attendance_repository.dart';
import '../providers/attendance_providers.dart';
import '../widgets/calendar_support.dart';
import '../widgets/register_editor.dart';

/// `/attendance/students` — pick academic year → class → section → date, load
/// the students enrolled then, mark, review the totals and save.
///
/// Teachers only see the sections they are class teacher of; admins see the
/// branch. The selectors are convenience — `firestore.rules` is what refuses a
/// teacher writing to a section that is not theirs.
class StudentAttendancePage extends StatelessWidget {
  const StudentAttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) => Scaffold(
        appBar: AppBar(title: const Text('Student attendance')),
        body: _StudentAttendance(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
        ),
      ),
    );
  }
}

class _StudentAttendance extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;

  const _StudentAttendance({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
  });

  @override
  ConsumerState<_StudentAttendance> createState() => _StudentAttendanceState();
}

class _StudentAttendanceState extends ConsumerState<_StudentAttendance> {
  String? _yearId;
  String? _classId;
  String? _sectionId;
  DateTime _date = AttendanceDate.dateOnly(SchoolTime.wallNow());

  StudentRegister? _register;
  AttendanceSheet? _sheet;
  bool _loading = false;
  String? _loadError;
  int _loadToken = 0;

  bool get _isManager => widget.tenant.can(Permission.manageAttendance);
  OwnStaffKeyAlias get _ownKey => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    userId: widget.tenant.user.userId,
  );

  bool get _complete =>
      _yearId != null && _classId != null && _sectionId != null;

  Future<void> _load() async {
    if (!_complete) return;
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _loadError = null;
      _register = null;
      _sheet = null;
    });
    try {
      final register = await ref
          .read(studentAttendanceRepositoryProvider)
          .loadRegister(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: _yearId!,
            classId: _classId!,
            sectionId: _sectionId!,
            date: _date,
          );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _register = register;
        _sheet = register.toSheet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loadError = userMessageFor(error);
        _loading = false;
      });
    }
  }

  Future<void> _submit(RegisterSubmit submit) {
    final register = _register!;
    return ref
        .read(studentAttendanceRepositoryProvider)
        .saveRegister(
          SaveStudentRegisterRequest(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: _yearId!,
            classId: _classId!,
            sectionId: _sectionId!,
            dateKey: AttendanceDate.key(_date),
            entries: _sheet!.entries,
            finalize: submit.finalize,
            reason: submit.reason,
            expectedDayRevision: register.day?.revision ?? 0,
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
    final yearsAsync = ref.watch(academicYearsProvider(branchKey));
    final teacherAsync = _isManager
        ? null
        : ref.watch(classTeacherAssignmentsProvider(_ownKey));

    if (yearsAsync.isLoading || (teacherAsync?.isLoading ?? false)) {
      return const Center(child: CircularProgressIndicator());
    }
    final loadFailure = yearsAsync.error ?? teacherAsync?.error;
    if (loadFailure != null) {
      return ErrorView(
        message: userMessageFor(loadFailure),
        onRetry: () => ref.invalidate(academicYearsProvider(branchKey)),
      );
    }

    final allYears = yearsAsync.value ?? const <AcademicYear>[];
    final assignments = teacherAsync?.value ?? const [];
    final years = _isManager
        ? allYears
        : allYears
              .where(
                (y) => assignments.any(
                  (a) => a.academicYearId == y.academicYearId,
                ),
              )
              .toList();

    if (years.isEmpty) {
      return EmptyView(
        icon: Icons.fact_check_outlined,
        message: _isManager
            ? 'Create an academic year in Settings before marking attendance.'
            : "You aren't the class teacher of any section yet. Ask an administrator to assign you as class teacher.",
      );
    }

    if (_yearId == null || !years.any((y) => y.academicYearId == _yearId)) {
      _yearId = years
          .firstWhere(
            (y) => y.status == AcademicYearStatus.active,
            orElse: () => years.first,
          )
          .academicYearId;
    }
    final year = years.firstWhere((y) => y.academicYearId == _yearId);
    final yearKey = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: _yearId!,
    );

    final classes = (ref.watch(classesProvider(yearKey)).value ?? const [])
        .where((c) => c.status.wireValue == 'ACTIVE')
        .where((c) {
          return _isManager ||
              assignments.any(
                (a) => a.academicYearId == _yearId && a.classId == c.classId,
              );
        })
        .toList();
    // A teacher with a single class (the usual case) needs no clicking.
    if (!_isManager && _classId == null && classes.length == 1) {
      _classId = classes.single.classId;
    }
    final classKey = _classId == null
        ? null
        : (
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: _yearId!,
            classId: _classId!,
          );
    final sections = classKey == null
        ? const []
        : (ref.watch(sectionsProvider(classKey)).value ?? const [])
              .where((s) => s.status.wireValue == 'ACTIVE')
              .where((s) {
                return _isManager ||
                    assignments.any(
                      (a) =>
                          a.academicYearId == _yearId &&
                          a.classId == _classId &&
                          a.sectionId == s.sectionId,
                    );
              })
              .toList();

    if (!_isManager && _sectionId == null && sections.length == 1) {
      _sectionId = sections.single.sectionId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final calendar = _complete
        ? watchCalendarDay(
            ref,
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: _yearId,
            date: _date,
          )
        : null;
    final dateError = attendanceDateError(_date, year: year);

    Widget dropdown(
      String label,
      String? value,
      List<DropdownMenuItem<String>> items,
      ValueChanged<String?>? onChanged, {
      bool narrow = false,
    }) {
      return SizedBox(
        width: narrow ? double.infinity : 190,
        child: DropdownButtonFormField<String>(
          value: items.any((i) => i.value == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: items,
          onChanged: onChanged,
        ),
      );
    }

    final className = classes
        .where((c) => c.classId == _classId)
        .firstOrNull
        ?.name;
    final sectionName = sections
        .where((s) => s.sectionId == _sectionId)
        .firstOrNull
        ?.name;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ScopeBar(
            complete: _complete,
            summary: _complete
                ? '${className ?? 'Class'} · Section ${sectionName ?? ''} · '
                      '${formatDisplayDate(_date)}'
                : 'Choose a register',
            controlsBuilder: (context, narrow) => Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                dropdown(
                  'Academic year',
                  _yearId,
                  [
                    for (final y in years)
                      DropdownMenuItem(
                        value: y.academicYearId,
                        child: Text(y.name),
                      ),
                  ],
                  (v) {
                    setState(() {
                      _yearId = v;
                      _classId = null;
                      _sectionId = null;
                      _register = null;
                      _sheet = null;
                    });
                  },
                  narrow: narrow,
                ),
                dropdown(
                  'Class',
                  _classId,
                  [
                    for (final c in classes)
                      DropdownMenuItem(value: c.classId, child: Text(c.name)),
                  ],
                  (v) {
                    setState(() {
                      _classId = v;
                      _sectionId = null;
                      _register = null;
                      _sheet = null;
                    });
                  },
                  narrow: narrow,
                ),
                dropdown(
                  'Section',
                  _sectionId,
                  [
                    for (final s in sections)
                      DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
                  ],
                  _classId == null
                      ? null
                      : (v) {
                          setState(() => _sectionId = v);
                          _load();
                        },
                  narrow: narrow,
                ),
                SizedBox(
                  width: narrow ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(formatDisplayDate(_date)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _body(
            context,
            calendar,
            dateError,
            year,
            className,
            sectionName,
          ),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<dynamic>? calendar,
    String? dateError,
    AcademicYear year,
    String? className,
    String? sectionName,
  ) {
    if (!_complete) {
      return const EmptyView(
        icon: Icons.fact_check_outlined,
        message:
            'Choose an academic year, class, section and date to mark attendance.',
      );
    }
    if (_loading || calendar == null || calendar.isLoading) {
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
    if (sheet == null) return const Center(child: CircularProgressIndicator());

    // Approved leave for this section and date — an annotation only. It
    // never marks, changes or finalizes attendance (see the leave module).
    final dateKey = AttendanceDate.key(_date);
    final leaveEntries =
        ref
            .watch(
              leaveCalendarProvider((
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                kind: LeaveKind.student,
                fromKey: dateKey,
                toKey: dateKey,
                classId: _classId,
                sectionId: _sectionId,
                subjectId: null,
              )),
            )
            .value ??
        const [];
    final leaveLabels = {
      for (final e in LeaveAttendanceOverlay.forDate(
        leaveEntries,
        dateKey,
      ).entries)
        e.key: LeaveAttendanceOverlay.label(e.value),
    };

    return RegisterEditor(
      key: ValueKey(
        '${_yearId}_${_classId}_${_sectionId}_${AttendanceDate.key(_date)}_${_register.hashCode}',
      ),
      leaveLabels: leaveLabels,
      sheet: sheet,
      title:
          '${className ?? 'Class'} · Section ${sectionName ?? ''} · ${year.name} · ${formatDisplayDate(_date)} · ${sheet.entries.length} enrolled',
      calendar: calendar.value,
      dateError: dateError,
      canMark: widget.tenant.can(Permission.markStudentAttendance),
      canManage: _isManager,
      onSubmit: _submit,
      onReload: _load,
      historyLoader: (entry) => ref
          .read(studentAttendanceRepositoryProvider)
          .fetchHistory(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            attendanceId: StudentAttendance.idFor(
              AttendanceDate.key(_date),
              entry.subjectId,
            ),
          ),
    );
  }
}

typedef OwnStaffKeyAlias = ({String schoolId, String branchId, String userId});
