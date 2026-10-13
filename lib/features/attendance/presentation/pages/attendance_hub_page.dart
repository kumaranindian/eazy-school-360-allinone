import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/attendance_date.dart';
import '../../domain/attendance_day.dart';
import '../../domain/attendance_tally.dart';
import '../providers/attendance_providers.dart';
import '../widgets/attendance_summary_bar.dart';

/// `/attendance` — what is happening today (or any date) and where to go.
///
/// Every figure is read from the register documents the marking flow
/// maintains (`attendanceSessions`, `staffAttendanceDays`), never invented:
/// one small document per section instead of every student. "Enrolled" is the
/// number on the registers that have been started — sections nobody has
/// opened yet have no count to read, so they appear only under "pending".
class AttendanceHubPage extends StatelessWidget {
  const AttendanceHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) =>
          _Hub(tenant: tenant, schoolId: schoolId, branchId: branchId),
    );
  }
}

class _SectionStatus {
  final SchoolClass schoolClass;
  final Section section;
  final AttendanceDay? day;

  const _SectionStatus(this.schoolClass, this.section, this.day);
}

class _HubData {
  final List<_SectionStatus> sections;
  final AttendanceDay? staffDay;

  const _HubData(this.sections, this.staffDay);
}

class _Hub extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;

  const _Hub({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
  });

  @override
  ConsumerState<_Hub> createState() => _HubState();
}

class _HubState extends ConsumerState<_Hub> {
  DateTime _date = AttendanceDate.dateOnly(DateTime.now());
  String? _yearId;
  String? _classId;
  String? _sectionId;
  _HubData? _data;
  String? _error;
  bool _loading = false;
  int _token = 0;

  bool get _isManager => widget.tenant.can(Permission.manageAttendance);
  bool get _isTeacherOnly =>
      !_isManager && widget.tenant.can(Permission.markStudentAttendance);

  Future<void> _load(List<(SchoolClass, Section)> scope) async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dateKey = AttendanceDate.key(_date);
      final studentRepo = ref.read(studentAttendanceRepositoryProvider);
      final days = <String, AttendanceDay>{};

      if (_yearId != null && scope.isNotEmpty) {
        if (_isManager) {
          for (final d in await studentRepo.fetchSessions(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: _yearId!,
            dateKey: dateKey,
            classId: _classId,
            sectionId: _sectionId,
          )) {
            days[d.sectionId!] = d;
          }
        } else {
          // A teacher's rules only allow queries pinned to their own section.
          for (final (c, s) in scope) {
            for (final d in await studentRepo.fetchSessions(
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              academicYearId: _yearId!,
              dateKey: dateKey,
              classId: c.classId,
              sectionId: s.sectionId,
            )) {
              days[d.sectionId!] = d;
            }
          }
        }
      }

      AttendanceDay? staffDay;
      if (widget.tenant.can(Permission.viewStaffAttendance)) {
        staffDay = await ref
            .read(staffAttendanceRepositoryProvider)
            .fetchDay(
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              dateKey: dateKey,
            );
      }

      if (!mounted || token != _token) return;
      setState(() {
        _data = _HubData([
          for (final (c, s) in scope) _SectionStatus(c, s, days[s.sectionId]),
        ], staffDay);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = userMessageFor(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final yearsAsync = ref.watch(academicYearsProvider(branchKey));
    final ownKey = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      userId: widget.tenant.user.userId,
    );
    final teacherAssignments = _isTeacherOnly
        ? ref.watch(classTeacherAssignmentsProvider(ownKey))
        : null;

    final years = yearsAsync.value ?? const <AcademicYear>[];
    if (_yearId == null && years.isNotEmpty) {
      _yearId = years
          .firstWhere(
            (y) => y.status == AcademicYearStatus.active,
            orElse: () => years.first,
          )
          .academicYearId;
    }

    // Sections in scope for the chosen year (+ optional class/section filters).
    final scope = <(SchoolClass, Section)>[];
    if (_yearId != null) {
      final yearKey = (
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        academicYearId: _yearId!,
      );
      final classes =
          (ref.watch(classesProvider(yearKey)).value ?? const <SchoolClass>[])
              .where((c) => c.status.wireValue == 'ACTIVE');
      for (final c in classes) {
        if (_classId != null && c.classId != _classId) continue;
        final sections =
            ref
                .watch(
                  sectionsProvider((
                    schoolId: widget.schoolId,
                    branchId: widget.branchId,
                    academicYearId: _yearId!,
                    classId: c.classId,
                  )),
                )
                .value ??
            const <Section>[];
        for (final s in sections.where((s) => s.status.wireValue == 'ACTIVE')) {
          if (_sectionId != null && s.sectionId != _sectionId) continue;
          final mine =
              teacherAssignments?.value?.any(
                (a) =>
                    a.academicYearId == _yearId &&
                    a.classId == c.classId &&
                    a.sectionId == s.sectionId,
              ) ??
              true;
          if (_isTeacherOnly && !mine) continue;
          scope.add((c, s));
        }
      }
    }

    final signature =
        '$_yearId|$_classId|$_sectionId|${AttendanceDate.key(_date)}|${scope.map((e) => e.$2.sectionId).join(',')}';
    if (_lastSignature != signature) {
      _lastSignature = signature;
      if (!yearsAsync.isLoading && !(teacherAssignments?.isLoading ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(scope);
        });
      }
    }

    final classesForFilter = _yearId == null
        ? const <SchoolClass>[]
        : (ref
                  .watch(
                    classesProvider((
                      schoolId: widget.schoolId,
                      branchId: widget.branchId,
                      academicYearId: _yearId!,
                    )),
                  )
                  .value ??
              const <SchoolClass>[]);
    final sectionsForFilter = (_yearId == null || _classId == null)
        ? const <Section>[]
        : (ref
                  .watch(
                    sectionsProvider((
                      schoolId: widget.schoolId,
                      branchId: widget.branchId,
                      academicYearId: _yearId!,
                      classId: _classId!,
                    )),
                  )
                  .value ??
              const <Section>[]);

    final canMark = widget.tenant.can(Permission.markStudentAttendance);
    final canViewStaff = widget.tenant.can(Permission.viewStaffAttendance);

    final body = ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (canMark) ...[
          Row(
            children: [
              Expanded(child: _dateStepper(context)),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : () => _load(scope),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilterBar(
            fieldsBuilder: () => _filters(
              years: years,
              classes: classesForFilter,
              sections: sectionsForFilter,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_loading && _data == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          SizedBox(
            height: 240,
            child: ErrorView(message: _error!, onRetry: () => _load(scope)),
          )
        else if (_data != null)
          ..._content(context, _data!),
        const SizedBox(height: AppSpacing.lg),
        HubGroup(
          title: 'Go to',
          tiles: [
            if (canMark)
              HubTile(
                icon: Icons.groups_outlined,
                title: 'Student attendance',
                description: 'Mark and review class registers',
                onTap: () => context.push('/attendance/students'),
              ),
            if (canViewStaff)
              HubTile(
                icon: Icons.badge_outlined,
                title: _isManager
                    ? 'Staff attendance'
                    : 'View staff attendance',
                description: 'Daily staff register',
                onTap: () => context.push('/attendance/staff'),
              ),
            HubTile(
              icon: Icons.assessment_outlined,
              title: 'Reports',
              description: 'Attendance summaries and exports',
              onTap: () => context.push('/attendance/reports'),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canMark
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/attendance/students'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Mark attendance'),
            )
          : null,
      body: body,
    );
  }

  /// ‹ date › : step a day at a time, or tap the date to pick one. Attendance
  /// cannot be marked in the future, so "next" stops at today.
  Widget _dateStepper(BuildContext context) {
    final today = AttendanceDate.dateOnly(DateTime.now());
    final isToday = !_date.isBefore(today);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(
            () => _date = AttendanceDate.dateOnly(
              _date.subtract(const Duration(days: 1)),
            ),
          ),
        ),
        Flexible(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _date = AttendanceDate.dateOnly(picked));
              }
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              formatDisplayDate(_date),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: isToday
              ? null
              : () => setState(
                  () => _date = AttendanceDate.dateOnly(
                    _date.add(const Duration(days: 1)),
                  ),
                ),
        ),
        if (!isToday)
          TextButton(
            onPressed: () => setState(() => _date = today),
            child: const Text('Today'),
          ),
      ],
    );
  }

  List<FilterField> _filters({
    required List<AcademicYear> years,
    required List<SchoolClass> classes,
    required List<Section> sections,
  }) => [
    FilterField.dropdown<String>(
      label: 'Academic year',
      value: years.any((y) => y.academicYearId == _yearId) ? _yearId : null,
      countsAsFilter: false,
      options: [for (final y in years) (y.academicYearId, y.name)],
      onChanged: (v) => setState(() {
        _yearId = v;
        _classId = null;
        _sectionId = null;
      }),
    ),
    if (_isManager) ...[
      FilterField.dropdown<String>(
        label: 'Class',
        value: classes.any((c) => c.classId == _classId) ? _classId : null,
        options: [
          (null, 'All classes'),
          for (final c in classes) (c.classId, c.name),
        ],
        onChanged: (v) => setState(() {
          _classId = v;
          _sectionId = null;
        }),
      ),
      FilterField.dropdown<String>(
        label: 'Section',
        value: sections.any((s) => s.sectionId == _sectionId)
            ? _sectionId
            : null,
        options: [
          (null, 'All sections'),
          for (final s in sections) (s.sectionId, s.name),
        ],
        onChanged: _classId == null
            ? null
            : (v) => setState(() => _sectionId = v),
      ),
    ],
  ];

  String? _lastSignature;

  List<Widget> _content(BuildContext context, _HubData data) {
    final canSeeStudents = widget.tenant.can(Permission.markStudentAttendance);
    final marked = data.sections.where((s) => s.day != null).toList();
    final total = marked.fold(
      const AttendanceTally(),
      (sum, s) => sum + s.day!.tally,
    );
    final finalized = marked.where((s) => s.day!.isFinalized).length;
    final pending = data.sections
        .where((s) => s.day == null || !s.day!.isFinalized)
        .toList();

    return [
      if (canSeeStudents) ...[
        Text(
          'Students · ${formatDisplayDate(_date)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (data.sections.isEmpty)
          const EmptyView(
            icon: Icons.class_outlined,
            message:
                'No active classes or sections to show for this selection.',
          )
        else ...[
          AttendanceSummaryBar(
            tally: total,
            totalLabel: 'Enrolled (marked registers)',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Registers started: ${marked.length} of ${data.sections.length} · finalized: $finalized',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _isTeacherOnly
                ? 'Your classes'
                : 'Attendance pending (${pending.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (pending.isEmpty && !_isTeacherOnly)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('Every register is finalized.'),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in (_isTeacherOnly ? data.sections : pending))
                  ActionChip(
                    avatar: Icon(
                      s.day == null
                          ? Icons.radio_button_unchecked
                          : (s.day!.isFinalized ? Icons.lock : Icons.edit_note),
                      size: 18,
                    ),
                    label: Text(
                      '${s.schoolClass.name} ${s.section.name} · ${s.day == null ? 'Not started' : s.day!.status.displayName}',
                    ),
                    onPressed: () => context.push('/attendance/students'),
                  ),
              ],
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
      if (widget.tenant.can(Permission.viewStaffAttendance)) ...[
        Text(
          'Staff · ${formatDisplayDate(_date)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (data.staffDay == null)
          const Text('Staff attendance has not been marked for this date.')
        else ...[
          AttendanceSummaryBar(
            tally: data.staffDay!.tally,
            totalLabel: 'On register',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(data.staffDay!.status.displayName),
        ],
      ],
    ];
  }
}
