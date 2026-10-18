import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/domain/staff.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../students/domain/student.dart';
import '../../../students/presentation/providers/student_providers.dart';
import '../../domain/attendance_date.dart';
import '../../domain/attendance_reports.dart';
import '../../domain/attendance_status.dart';
import '../../domain/attendance_tally.dart';
import '../providers/attendance_providers.dart';
import '../widgets/attendance_summary_bar.dart';

enum _ReportKind { students, staff }

/// `/attendance/reports` — per-person totals and attendance percentage for a
/// date range, student-wise or staff-wise, with a day-by-day drill-down and
/// CSV export.
///
/// A student report is always for **one academic year's section** (or one
/// student), and the range must lie inside that year, so a percentage never
/// mixes years. Teachers can only report on sections they are class teacher
/// of; finance only sees staff.
class AttendanceReportsPage extends StatelessWidget {
  const AttendanceReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) => Scaffold(
        appBar: AppBar(title: const Text('Attendance reports')),
        body: _Reports(tenant: tenant, schoolId: schoolId, branchId: branchId),
      ),
    );
  }
}

class _Reports extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;

  const _Reports({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
  });

  @override
  ConsumerState<_Reports> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<_Reports> {
  late _ReportKind _kind = widget.tenant.can(Permission.markStudentAttendance)
      ? _ReportKind.students
      : _ReportKind.staff;
  late DateTime _from = DateTime(
    SchoolTime.wallNow().year,
    SchoolTime.wallNow().month,
    1,
  );
  late DateTime _to = AttendanceDate.dateOnly(SchoolTime.wallNow());
  String? _yearId;
  String? _classId;
  String? _sectionId;
  Student? _student;
  Staff? _staffMember;

  List<AttendanceSummaryRow>? _rows;
  Map<
    String,
    List<({String dateKey, AttendanceStatus status, String? remarks})>
  >
  _days = {};
  bool _truncated = false;
  bool _loading = false;
  String? _error;

  bool get _isManager => widget.tenant.can(Permission.manageAttendance);

  String? _validate(AcademicYear? year) {
    if (_from.isAfter(_to)) return 'The start date is after the end date.';
    if (_to.difference(_from).inDays > 366) {
      return 'Choose a range of at most one year.';
    }
    if (_kind == _ReportKind.students && year != null) {
      final start = AttendanceDate.dateOnly(year.startDate);
      final end = AttendanceDate.dateOnly(year.endDate);
      if (_from.isBefore(start) || _to.isAfter(end)) {
        return 'Keep the range inside ${year.name} (${formatDisplayDate(start)} – ${formatDisplayDate(end)}) so years are not mixed.';
      }
    }
    return null;
  }

  Future<void> _generate(AcademicYear? year) async {
    final problem = _validate(year);
    if (problem != null) {
      context.showSnackBar(problem, isError: true);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _rows = null;
    });
    final fromKey = AttendanceDate.key(_from);
    final toKey = AttendanceDate.key(_to);
    try {
      if (_kind == _ReportKind.students) {
        final repo = ref.read(studentAttendanceRepositoryProvider);
        final range = _student != null
            ? await repo.fetchStudentRange(
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                studentId: _student!.studentId,
                fromKey: fromKey,
                toKey: toKey,
              )
            : await repo.fetchSectionRange(
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                academicYearId: _yearId!,
                classId: _classId!,
                sectionId: _sectionId!,
                fromKey: fromKey,
                toKey: toKey,
              );
        final tallies = AttendanceReports.tallyBySubject(
          range.items.map((r) => (subjectId: r.studentId, status: r.status)),
        );
        final students = await repo.loadStudents(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          studentIds: tallies.keys.toSet(),
        );
        final days =
            <
              String,
              List<({String dateKey, AttendanceStatus status, String? remarks})>
            >{};
        for (final r in range.items) {
          days.putIfAbsent(r.studentId, () => []).add((
            dateKey: r.dateKey,
            status: r.status,
            remarks: r.remarks,
          ));
        }
        final rows = [
          for (final e in tallies.entries)
            AttendanceSummaryRow(
              subjectId: e.key,
              name: students[e.key]?.displayName ?? 'Unknown student',
              detail: students[e.key]?.rollNumberLabel,
              tally: e.value,
            ),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _days = days;
          _truncated = range.truncated;
          _loading = false;
        });
      } else {
        final range = await ref
            .read(staffAttendanceRepositoryProvider)
            .fetchRange(
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              fromKey: fromKey,
              toKey: toKey,
              staffId: _staffMember?.staffId,
            );
        final tallies = AttendanceReports.tallyBySubject(
          range.items.map((r) => (subjectId: r.staffId, status: r.status)),
        );
        final staff = await ref
            .read(staffRepositoryProvider)
            .getStaffByIds(
              widget.schoolId,
              widget.branchId,
              tallies.keys.toList(),
            );
        final byId = {for (final s in staff) s.staffId: s};
        final days =
            <
              String,
              List<({String dateKey, AttendanceStatus status, String? remarks})>
            >{};
        for (final r in range.items) {
          days.putIfAbsent(r.staffId, () => []).add((
            dateKey: r.dateKey,
            status: r.status,
            remarks: r.remarks,
          ));
        }
        final rows = [
          for (final e in tallies.entries)
            AttendanceSummaryRow(
              subjectId: e.key,
              name: byId[e.key]?.displayName ?? 'Unknown staff',
              detail: byId[e.key]?.employeeCode,
              tally: e.value,
            ),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _days = days;
          _truncated = range.truncated;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userMessageFor(error);
        _loading = false;
      });
    }
  }

  Future<void> _pickStudent() async {
    final picked = await showDialog<Student>(
      context: context,
      builder: (context) => _StudentSearchDialog(
        schoolId: widget.schoolId,
        branchId: widget.branchId,
      ),
    );
    if (picked != null) setState(() => _student = picked);
  }

  Future<void> _pickStaff() async {
    final page = await ref
        .read(staffRepositoryProvider)
        .fetchStaff(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          pageSize: 200,
        );
    if (!mounted) return;
    final picked = await showDialog<Staff>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose staff member'),
        children: [
          for (final s in page.items)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(s),
              child: Text('${s.displayName} · ${s.employeeCode}'),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _staffMember = picked);
  }

  Future<void> _copyCsv() async {
    await Clipboard.setData(
      ClipboardData(text: AttendanceReports.summaryCsv(_rows!)),
    );
    if (mounted) {
      context.showSnackBar(
        'Report copied as CSV. Paste it into a spreadsheet.',
      );
    }
  }

  void _showDays(AttendanceSummaryRow row) {
    final days = (_days[row.subjectId] ?? const [])
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row.name),
        content: SizedBox(
          width: 420,
          child: days.isEmpty
              ? const Text('No attendance in this period.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in days)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${formatDisplayDate(AttendanceDate.parse(d.dateKey))}  ·  ${d.status.displayName}',
                        ),
                        subtitle: (d.remarks ?? '').isEmpty
                            ? null
                            : Text(d.remarks!),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: days.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: AttendanceReports.dailyCsv(row.name, days),
                      ),
                    );
                    if (context.mounted) {
                      context.showSnackBar('Daily records copied as CSV.');
                    }
                  },
            child: const Text('Copy CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final canStudents = tenant.can(Permission.markStudentAttendance);
    final canStaff = tenant.can(Permission.viewStaffAttendance);
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final ownKey = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      userId: tenant.user.userId,
    );
    final assignments = (!_isManager && canStudents)
        ? ref.watch(classTeacherAssignmentsProvider(ownKey)).value ?? const []
        : const [];

    final allYears =
        ref.watch(academicYearsProvider(branchKey)).value ??
        const <AcademicYear>[];
    final years = _isManager
        ? allYears
        : allYears
              .where(
                (y) => assignments.any(
                  (a) => a.academicYearId == y.academicYearId,
                ),
              )
              .toList();
    if (_yearId == null && years.isNotEmpty) {
      _yearId = years
          .firstWhere(
            (y) => y.status == AcademicYearStatus.active,
            orElse: () => years.first,
          )
          .academicYearId;
    }
    final year = years.where((y) => y.academicYearId == _yearId).firstOrNull;
    final yearKey = _yearId == null
        ? null
        : (
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: _yearId!,
          );
    final classes = yearKey == null
        ? const []
        : (ref.watch(classesProvider(yearKey)).value ?? const [])
              .where(
                (c) =>
                    _isManager ||
                    assignments.any(
                      (a) =>
                          a.academicYearId == _yearId && a.classId == c.classId,
                    ),
              )
              .toList();
    final sections = (yearKey == null || _classId == null)
        ? const []
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
                  const [])
              .where(
                (s) =>
                    _isManager ||
                    assignments.any(
                      (a) =>
                          a.academicYearId == _yearId &&
                          a.classId == _classId &&
                          a.sectionId == s.sectionId,
                    ),
              )
              .toList();

    if (!canStudents && !canStaff) {
      return const EmptyView(
        icon: Icons.lock_outline,
        message: "You don't have access to attendance reports.",
      );
    }

    final canGenerate =
        _kind == _ReportKind.staff ||
        _student != null ||
        (_yearId != null && _classId != null && _sectionId != null);

    Widget dateButton(
      String label,
      DateTime value,
      ValueChanged<DateTime> onPicked,
    ) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text('$label ${formatDisplayDate(value)}'),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2000),
            lastDate: SchoolTime.wallNow(),
          );
          if (picked != null) {
            setState(() => onPicked(AttendanceDate.dateOnly(picked)));
          }
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (canStudents && canStaff)
          SegmentedButton<_ReportKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _ReportKind.students,
                icon: Icon(Icons.groups_outlined),
                label: Text('Students'),
              ),
              ButtonSegment(
                value: _ReportKind.staff,
                icon: Icon(Icons.badge_outlined),
                label: Text('Staff'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _rows = null;
            }),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            dateButton('From', _from, (d) => _from = d),
            dateButton('To', _to, (d) => _to = d),
            TextButton(
              onPressed: () => setState(() {
                final now = SchoolTime.wallNow();
                _from = DateTime(now.year, now.month, 1);
                _to = AttendanceDate.dateOnly(now);
              }),
              child: const Text('This month'),
            ),
            TextButton(
              onPressed: () => setState(() {
                final now = SchoolTime.wallNow();
                _from = DateTime(now.year, now.month - 1, 1);
                _to = DateTime(now.year, now.month, 0);
              }),
              child: const Text('Last month'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_kind == _ReportKind.students)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _dropdown(
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
                  });
                },
              ),
              _dropdown(
                'Class',
                _classId,
                [
                  for (final c in classes)
                    DropdownMenuItem(
                      value: c.classId as String,
                      child: Text(c.name as String),
                    ),
                ],
                (v) {
                  setState(() {
                    _classId = v;
                    _sectionId = null;
                  });
                },
              ),
              _dropdown(
                'Section',
                _sectionId,
                [
                  for (final s in sections)
                    DropdownMenuItem(
                      value: s.sectionId as String,
                      child: Text(s.name as String),
                    ),
                ],
                _classId == null ? null : (v) => setState(() => _sectionId = v),
              ),
              if (_isManager)
                _student == null
                    ? OutlinedButton.icon(
                        onPressed: _pickStudent,
                        icon: const Icon(Icons.person_search_outlined),
                        label: const Text('One student…'),
                      )
                    : InputChip(
                        label: Text(_student!.displayName),
                        onDeleted: () => setState(() => _student = null),
                      ),
            ],
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (_isManager || canStaff)
                _staffMember == null
                    ? OutlinedButton.icon(
                        onPressed: _pickStaff,
                        icon: const Icon(Icons.person_search_outlined),
                        label: const Text('One staff member…'),
                      )
                    : InputChip(
                        label: Text(_staffMember!.displayName),
                        onDeleted: () => setState(() => _staffMember = null),
                      ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: (!canGenerate || _loading)
                ? null
                : () => _generate(year),
            icon: _loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assessment_outlined),
            label: const Text('Generate report'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_error != null)
          SizedBox(
            height: 200,
            child: ErrorView(message: _error!, onRetry: () => _generate(year)),
          )
        else if (_rows != null)
          ..._results(context),
      ],
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String?>? onChanged,
  ) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        value: items.any((i) => i.value == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final rows = _rows!;
    final total = AttendanceReports.total(rows);
    return [
      if (_truncated)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Results were limited to ${4000} records. Narrow the date range for a complete report.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (rows.isEmpty)
        const SizedBox(
          height: 200,
          child: EmptyView(
            icon: Icons.event_busy_outlined,
            message: 'No attendance was recorded in this period.',
          ),
        )
      else ...[
        Row(
          children: [
            Expanded(
              child: AttendanceSummaryBar(
                tally: AttendanceTally(
                  present: total.present,
                  absent: total.absent,
                  late: total.late,
                  halfDay: total.halfDay,
                ),
                totalLabel: 'Records',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _copyCsv,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy CSV'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Attendance % = (present + late + ½ × half day) ÷ days marked. Days with no record (holidays, unmarked) are not counted.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 520,
          child: ResponsiveDataList<AttendanceSummaryRow>(
            items: rows,
            columnHeaders: const [
              'Name',
              'Detail',
              'Present',
              'Absent',
              'Late',
              'Half day',
              'Marked',
              'Attendance %',
              '',
            ],
            emptyState: const EmptyView(message: 'Nothing to show.'),
            cellsBuilder: (r) => [
              DataCell(Text(r.name)),
              DataCell(Text(r.detail ?? '—')),
              DataCell(Text('${r.tally.present}')),
              DataCell(Text('${r.tally.absent}')),
              DataCell(Text('${r.tally.late}')),
              DataCell(Text('${r.tally.halfDay}')),
              DataCell(Text('${r.tally.marked}')),
              DataCell(Text(AttendanceReports.percentLabel(r.tally))),
              DataCell(
                TextButton(
                  onPressed: () => _showDays(r),
                  child: const Text('Days'),
                ),
              ),
            ],
            cardBuilder: (r) => Card(
              child: ListTile(
                title: Text(r.name),
                subtitle: Text(
                  'P ${r.tally.present} · A ${r.tally.absent} · L ${r.tally.late} · H ${r.tally.halfDay}  —  ${AttendanceReports.percentLabel(r.tally)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDays(r),
              ),
            ),
          ),
        ),
      ],
    ];
  }
}

class _StudentSearchDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;

  const _StudentSearchDialog({required this.schoolId, required this.branchId});

  @override
  ConsumerState<_StudentSearchDialog> createState() =>
      _StudentSearchDialogState();
}

class _StudentSearchDialogState extends ConsumerState<_StudentSearchDialog> {
  final _query = TextEditingController();
  List<Student> _results = const [];
  String? _error;
  bool _searching = false;

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(studentRepositoryProvider)
          .searchStudentsByName(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            query: q,
          );
      if (mounted) setState(() => _results = page.items);
    } catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find a student'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name starts with…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(_error!),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in _results)
                    ListTile(
                      dense: true,
                      title: Text(s.displayName),
                      subtitle: Text(s.admissionNumber),
                      onTap: () => Navigator.of(context).pop(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
