import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../staff/domain/staff.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../domain/leave_balance.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../../domain/leave_type.dart';
import '../../domain/leave_units.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_scope.dart';
import '../widgets/leave_widgets.dart';

/// Everything on this screen comes from aggregate `count()` / `sum()` queries
/// (or, for the balance table, a bounded query of one type's balances) — no
/// application is downloaded to be tallied.
///
/// Definitions, the same everywhere: a leave "day" is a school day counted by
/// the leave calculator (holidays and non-working days excluded unless the
/// type counts them), a half day is 0.5, only APPROVED leave contributes to
/// day totals, and a period includes applications whose first day falls in it.
class LeaveReportsPage extends StatelessWidget {
  const LeaveReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave reports')),
      body: LeaveScope(builder: (context, leave) => _Reports(leave: leave)),
    );
  }
}

class _Reports extends ConsumerStatefulWidget {
  final LeaveContext leave;

  const _Reports({required this.leave});

  @override
  ConsumerState<_Reports> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<_Reports> {
  LeaveKind _kind = LeaveKind.student;
  late String _from = widget.leave.yearStartKey;
  late String _to = widget.leave.yearEndKey;

  Future<void> _pick(bool from) async {
    final y = widget.leave.year;
    final current = AttendanceDate.parse(from ? _from : _to);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: y.startDate.toUtc(),
      lastDate: y.endDate.toUtc(),
    );
    if (picked == null) return;
    setState(() {
      final k = AttendanceDate.key(picked);
      if (from) {
        _from = k;
        if (_to.compareTo(_from) < 0) _to = k;
      } else {
        _to = k;
        if (_from.compareTo(_to) > 0) _from = k;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final theme = Theme.of(context);
    final types =
        ref
            .watch(
              leaveTypesProvider((
                schoolId: leave.schoolId,
                branchId: leave.branchId,
                kind: _kind,
              )),
            )
            .value ??
        const <LeaveType>[];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<LeaveKind>(
              segments: const [
                ButtonSegment(
                  value: LeaveKind.student,
                  label: Text('Students'),
                ),
                ButtonSegment(value: LeaveKind.staff, label: Text('Staff')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(true),
              icon: const Icon(Icons.event),
              label: Text('From ${leaveDate(_from)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(false),
              icon: const Icon(Icons.event_available),
              label: Text('To ${leaveDate(_to)}'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _StatusCounts(
          key: ValueKey('s$_kind$_from$_to'),
          leave: leave,
          kind: _kind,
          from: _from,
          to: _to,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _kind == LeaveKind.student
              ? 'Approved leave by type'
              : 'Staff leave usage by type',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (types.isEmpty)
          const Text('No leave types configured.')
        else
          _TypeUsage(
            key: ValueKey('t$_kind$_from$_to${types.length}'),
            leave: leave,
            kind: _kind,
            types: types,
            from: _from,
            to: _to,
          ),
        const SizedBox(height: AppSpacing.md),
        if (_kind == LeaveKind.student)
          _SectionSummary(
            key: ValueKey('c$_from$_to'),
            leave: leave,
            from: _from,
            to: _to,
          )
        else
          _BalanceSummary(
            key: ValueKey('b${leave.year.academicYearId}${types.length}'),
            leave: leave,
            types: [
              for (final t in types)
                if (t.tracksBalance) t,
            ],
          ),
      ],
    );
  }
}

class _StatusCounts extends ConsumerWidget {
  final LeaveContext leave;
  final LeaveKind kind;
  final String from;
  final String to;

  const _StatusCounts({
    super.key,
    required this.leave,
    required this.kind,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<LeaveStatusCounts>(
      future: ref
          .read(leaveReportRepositoryProvider)
          .statusCounts(
            schoolId: leave.schoolId,
            branchId: leave.branchId,
            kind: kind,
            fromKey: from,
            toKey: to,
          ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (snap.hasError) {
          return ErrorView(message: userMessageFor(snap.error!));
        }
        final c = snap.data!;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final s in LeaveStatus.values)
              SizedBox(
                width: 150,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.of(s)}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          s.displayName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TypeUsage extends ConsumerWidget {
  final LeaveContext leave;
  final LeaveKind kind;
  final List<LeaveType> types;
  final String from;
  final String to;

  const _TypeUsage({
    super.key,
    required this.leave,
    required this.kind,
    required this.types,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(leaveReportRepositoryProvider);
    return FutureBuilder<List<LeaveTypeUsage>>(
      future: Future.wait([
        for (final t in types)
          repo.typeUsage(
            schoolId: leave.schoolId,
            branchId: leave.branchId,
            kind: kind,
            typeId: t.typeId,
            fromKey: from,
            toKey: to,
          ),
      ]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (snap.hasError) {
          return ErrorView(message: userMessageFor(snap.error!));
        }
        final usage = snap.data!;
        return DataTable(
          columns: const [
            DataColumn(label: Text('Leave type')),
            DataColumn(label: Text('Applications'), numeric: true),
            DataColumn(label: Text('Days'), numeric: true),
          ],
          rows: [
            for (var i = 0; i < types.length; i++)
              DataRow(
                cells: [
                  DataCell(Text(types[i].name)),
                  DataCell(Text('${usage[i].applications}')),
                  DataCell(Text(LeaveUnits.format(usage[i].units))),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _SectionSummary extends ConsumerStatefulWidget {
  final LeaveContext leave;
  final String from;
  final String to;

  const _SectionSummary({
    super.key,
    required this.leave,
    required this.from,
    required this.to,
  });

  @override
  ConsumerState<_SectionSummary> createState() => _SectionSummaryState();
}

class _SectionSummaryState extends ConsumerState<_SectionSummary> {
  String? _classId;

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final theme = Theme.of(context);
    final classes =
        ref.watch(classesProvider(leave.yearKey)).value ??
        const <SchoolClass>[];
    final sections = _classId == null
        ? const <Section>[]
        : ref
                  .watch(
                    sectionsProvider((
                      schoolId: leave.schoolId,
                      branchId: leave.branchId,
                      academicYearId: leave.year.academicYearId,
                      classId: _classId!,
                    )),
                  )
                  .value ??
              const <Section>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Approved student leave by section (days)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: DropdownButtonFormField<String?>(
            value: _classId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Class'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Choose a class'),
              ),
              for (final c in classes)
                DropdownMenuItem(value: c.classId, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _classId = v),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_classId != null && sections.isEmpty)
          const Text('This class has no sections.'),
        if (sections.isNotEmpty)
          FutureBuilder<List<LeaveSectionSummary>>(
            key: ValueKey('$_classId${widget.from}${widget.to}'),
            future: Future.wait([
              for (final s in sections)
                ref
                    .read(leaveReportRepositoryProvider)
                    .sectionSummary(
                      schoolId: leave.schoolId,
                      branchId: leave.branchId,
                      classId: _classId!,
                      sectionId: s.sectionId,
                      fromKey: widget.from,
                      toKey: widget.to,
                    ),
            ]),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snap.hasError) {
                return Text(userMessageFor(snap.error!));
              }
              final rows = snap.data!;
              return DataTable(
                columns: const [
                  DataColumn(label: Text('Section')),
                  DataColumn(label: Text('Applications'), numeric: true),
                  DataColumn(label: Text('Days'), numeric: true),
                ],
                rows: [
                  for (var i = 0; i < sections.length; i++)
                    DataRow(
                      cells: [
                        DataCell(Text(sections[i].name)),
                        DataCell(Text('${rows[i].applications}')),
                        DataCell(Text(LeaveUnits.format(rows[i].units))),
                      ],
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _BalanceSummary extends ConsumerStatefulWidget {
  final LeaveContext leave;
  final List<LeaveType> types;

  const _BalanceSummary({super.key, required this.leave, required this.types});

  @override
  ConsumerState<_BalanceSummary> createState() => _BalanceSummaryState();
}

class _BalanceSummaryState extends ConsumerState<_BalanceSummary> {
  String? _typeId;

  Future<List<(Staff?, LeaveBalance)>> _load(
    LeaveContext leave,
    String typeId,
  ) async {
    final balances = await ref
        .read(leaveBalanceRepositoryProvider)
        .fetchTypeBalances(
          schoolId: leave.schoolId,
          branchId: leave.branchId,
          academicYearId: leave.year.academicYearId,
          typeId: typeId,
        );
    final ids = [for (final b in balances) b.staffId];
    final staff = <String, Staff>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      for (final s
          in await ref
              .read(staffRepositoryProvider)
              .getStaffByIds(leave.schoolId, leave.branchId, chunk)) {
        staff[s.staffId] = s;
      }
    }
    return [for (final b in balances) (staff[b.staffId], b)];
  }

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final theme = Theme.of(context);
    final today = AttendanceDate.key(SchoolTime.wallNow());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Staff entitlement and balance summary',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.types.isEmpty)
          const Text('No staff leave type tracks a balance.')
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: DropdownButtonFormField<String?>(
              value: _typeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Leave type'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Choose a type'),
                ),
                for (final t in widget.types)
                  DropdownMenuItem(value: t.typeId, child: Text(t.name)),
              ],
              onChanged: (v) => setState(() => _typeId = v),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_typeId != null)
            FutureBuilder<List<(Staff?, LeaveBalance)>>(
              key: ValueKey(_typeId),
              future: _load(leave, _typeId!),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snap.hasError) return Text(userMessageFor(snap.error!));
                final rows = snap.data!;
                if (rows.isEmpty) {
                  return const Text(
                    'No balances have been initialised for this type this year.',
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Staff')),
                      DataColumn(label: Text('Granted'), numeric: true),
                      DataColumn(label: Text('Used'), numeric: true),
                      DataColumn(label: Text('Available'), numeric: true),
                    ],
                    rows: [
                      for (final (staff, b) in rows)
                        () {
                          final f = LeaveBalanceMath.figures(
                            balance: b,
                            todayKey: today,
                          );
                          return DataRow(
                            cells: [
                              DataCell(Text(staff?.displayName ?? b.staffId)),
                              DataCell(
                                Text(
                                  LeaveUnits.format(
                                    f.accrued + f.carryForward + f.adjustments,
                                  ),
                                ),
                              ),
                              DataCell(Text(LeaveUnits.format(f.consumed))),
                              DataCell(Text(LeaveUnits.format(f.available))),
                            ],
                          );
                        }(),
                    ],
                  ),
                );
              },
            ),
        ],
      ],
    );
  }
}
