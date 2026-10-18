import '../../../../core/utils/date_formatting.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../staff/domain/staff.dart';
import '../../../staff/domain/staff_search_field.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../domain/leave_balance.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../../domain/leave_type.dart';
import '../../domain/leave_units.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_scope.dart';

/// `/leave/balances` — find a staff member, see their balances for the year
/// and the append-only ledger; reviewers with `adjustLeaveBalances` can adjust
/// (with a reason) or carry a balance forward from the previous year.
class LeaveBalancesPage extends StatelessWidget {
  const LeaveBalancesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff leave balances')),
      body: LeaveScope(builder: (context, leave) => _Balances(leave: leave)),
    );
  }
}

class _Balances extends ConsumerStatefulWidget {
  final LeaveContext leave;

  const _Balances({required this.leave});

  @override
  ConsumerState<_Balances> createState() => _BalancesState();
}

class _BalancesState extends ConsumerState<_Balances> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Staff> _results = const [];
  bool _searching = false;
  String? _error;
  Staff? _staff;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  int _generation = 0;

  Future<void> _run() async {
    final q = _search.text.trim();
    // Only the newest search may write its results or clear the spinner.
    final generation = ++_generation;
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(staffRepositoryProvider)
          .searchStaff(
            schoolId: widget.leave.schoolId,
            branchId: widget.leave.branchId,
            field: StaffSearchField.name,
            query: q,
          );
      if (mounted && generation == _generation) {
        setState(() => _results = page.items);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = userMessageFor(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        TextField(
          controller: _search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: 'Find a staff member by name',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_error != null) Text(_error!),
        if (_staff == null)
          for (final s in _results)
            ListTile(
              title: Text(s.displayName),
              subtitle: Text(s.employeeCode),
              onTap: () => setState(() => _staff = s),
            ),
        if (_staff == null &&
            _results.isEmpty &&
            _search.text.trim().length >= 2 &&
            !_searching)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text('No staff match that name.'),
          ),
        if (_staff == null && _search.text.trim().length < 2)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: EmptyView(
              icon: Icons.account_balance_wallet_outlined,
              message: 'Search for a staff member to see their leave balances.',
            ),
          ),
        if (_staff != null)
          _StaffBalances(
            key: ValueKey(_staff!.staffId),
            leave: leave,
            staff: _staff!,
            onClear: () => setState(() => _staff = null),
          ),
      ],
    );
  }
}

class _StaffBalances extends ConsumerStatefulWidget {
  final LeaveContext leave;
  final Staff staff;
  final VoidCallback onClear;

  const _StaffBalances({
    super.key,
    required this.leave,
    required this.staff,
    required this.onClear,
  });

  @override
  ConsumerState<_StaffBalances> createState() => _StaffBalancesState();
}

class _StaffBalancesState extends ConsumerState<_StaffBalances> {
  final _ledger = PagedListController<LeaveLedgerEntry>();

  @override
  void initState() {
    super.initState();
    final leave = widget.leave;
    _ledger.fetch = (cursor) => ref
        .read(leaveBalanceRepositoryProvider)
        .fetchLedger(
          schoolId: leave.schoolId,
          branchId: leave.branchId,
          staffId: widget.staff.staffId,
          cursor: cursor,
        );
    _ledger.reload();
  }

  @override
  void dispose() {
    _ledger.dispose();
    super.dispose();
  }

  LeaveActor get _actor =>
      LeaveActor(userId: widget.leave.userId, name: widget.leave.userName);

  Future<void> _adjust(LeaveType type, LeaveBalance? balance) async {
    final leave = widget.leave;
    final base =
        balance ??
        LeaveBalance.fromPolicy(
          schoolId: leave.schoolId,
          branchId: leave.branchId,
          staffId: widget.staff.staffId,
          type: type,
          academicYearId: leave.year.academicYearId,
          leaveYearStartKey: leave.yearStartKey,
        );
    final done = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (dialogContext) => _AdjustForm(
        type: type,
        balance: base,
        exists: balance != null,
        actor: _actor,
        staffUserId: widget.staff.userId,
      ),
    );
    if (done == true) _ledger.reload();
  }

  Future<void> _carry(LeaveType type) async {
    final leave = widget.leave;
    final years =
        ref.read(academicYearsProvider(leave.branchKey)).value ?? const [];
    final sorted = [...years]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final index = sorted.indexWhere(
      (y) => y.academicYearId == leave.year.academicYearId,
    );
    if (index <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There is no earlier leave year to carry from.'),
        ),
      );
      return;
    }
    final previous = sorted[index - 1];
    try {
      final repo = ref.read(leaveBalanceRepositoryProvider);
      final from = await repo.getBalance(
        leave.schoolId,
        leave.branchId,
        LeaveBalance.idFor(
          widget.staff.staffId,
          type.typeId,
          previous.academicYearId,
        ),
      );
      if (from == null) {
        throw StateError('No balance exists for the previous year.');
      }
      final closing = LeaveBalanceMath.figures(
        balance: from,
        todayKey: AttendanceDate.key(previous.endDate.toUtc()),
      ).available;
      final carry = LeaveBalanceMath.carryForwardInto(
        closingAvailableUnits: closing,
        maxCarryUnits: type.carryForwardMaxUnits,
      );
      if (carry <= 0) {
        throw StateError(
          'Nothing can be carried forward '
          '(closing ${LeaveUnits.formatDays(closing)}, limit '
          '${LeaveUnits.formatDays(type.carryForwardMaxUnits)}).',
        );
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Carry forward?'),
          content: Text(
            '${LeaveUnits.formatDays(carry)} of ${type.name} will be carried '
            'into ${leave.year.name} for ${widget.staff.displayName}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Carry forward'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await repo.carryForward(
        toBalance: LeaveBalance.fromPolicy(
          schoolId: leave.schoolId,
          branchId: leave.branchId,
          staffId: widget.staff.staffId,
          type: type,
          academicYearId: leave.year.academicYearId,
          leaveYearStartKey: leave.yearStartKey,
          carryForwardUnits: carry,
        ),
        carryUnits: carry,
        actor: _actor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Balance carried forward.')));
      _ledger.reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is StateError ? e.message : userMessageFor(e)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leave = widget.leave;
    final canAdjust = leave.tenant.can(Permission.adjustLeaveBalances);
    final types =
        ref
            .watch(
              leaveTypesProvider((
                schoolId: leave.schoolId,
                branchId: leave.branchId,
                kind: LeaveKind.staff,
              )),
            )
            .value ??
        const <LeaveType>[];
    final tracked = [
      for (final t in types)
        if (t.tracksBalance) t,
    ];
    final balances =
        ref
            .watch(
              staffLeaveBalancesProvider((
                schoolId: leave.schoolId,
                branchId: leave.branchId,
                staffId: widget.staff.staffId,
                academicYearId: leave.year.academicYearId,
              )),
            )
            .value ??
        const <LeaveBalance>[];
    final today = AttendanceDate.key(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.staff.displayName,
                style: theme.textTheme.titleLarge,
              ),
            ),
            TextButton(onPressed: widget.onClear, child: const Text('Change')),
          ],
        ),
        Text('Leave year ${leave.year.name}', style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        if (tracked.isEmpty)
          const Text(
            'No staff leave type tracks a balance yet. Set an annual '
            'entitlement on a leave type first.',
          ),
        for (final t in tracked)
          Builder(
            builder: (context) {
              final b = balances.where((x) => x.typeId == t.typeId).firstOrNull;
              final f = b == null
                  ? null
                  : LeaveBalanceMath.figures(balance: b, todayKey: today);
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      if (f == null)
                        Text(
                          'Not initialised — '
                          '${LeaveUnits.formatDays(t.annualEntitlementUnits!)} '
                          'per year by policy.',
                          style: theme.textTheme.bodySmall,
                        )
                      else
                        Text(
                          'Available ${LeaveUnits.formatDays(f.available)} · '
                          'Accrued ${LeaveUnits.format(f.accrued)} of '
                          '${LeaveUnits.format(f.entitlement)} · '
                          'Carry-forward ${LeaveUnits.format(f.carryForward)} · '
                          'Adjustments ${LeaveUnits.format(f.adjustments)} · '
                          'Used ${LeaveUnits.format(f.consumed)}',
                        ),
                      if (canAdjust)
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            TextButton(
                              onPressed: () => _adjust(t, b),
                              child: const Text('Adjust'),
                            ),
                            if (b == null && t.carryForwardMaxUnits > 0)
                              TextButton(
                                onPressed: () => _carry(t),
                                child: const Text('Carry forward'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: AppSpacing.md),
        Text('Ledger', style: theme.textTheme.titleSmall),
        ListenableBuilder(
          listenable: _ledger,
          builder: (context, _) {
            if (_ledger.errorMessage != null && _ledger.items.isEmpty) {
              return Text(_ledger.errorMessage!);
            }
            if (!_ledger.hasLoaded) return const LinearProgressIndicator();
            if (_ledger.items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('No ledger entries yet.'),
              );
            }
            return Column(
              children: [
                for (final e in _ledger.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e.type == LedgerEntryType.consume
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                    ),
                    title: Text(
                      '${e.type.displayName}: '
                      '${e.type == LedgerEntryType.consume ? '−' : (e.units > 0 ? '+' : '')}'
                      '${LeaveUnits.formatDays(e.units)}',
                    ),
                    subtitle: Text(
                      [
                        if ((e.reason ?? '').isNotEmpty) e.reason!,
                        e.actorName,
                      ].join(' · '),
                    ),
                    trailing: e.at == null
                        ? null
                        : Text(
                            formatInstant(e.at),
                            style: theme.textTheme.bodySmall,
                          ),
                  ),
                if (_ledger.hasMore)
                  TextButton(
                    onPressed: _ledger.loadMore,
                    child: const Text('Load more'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AdjustForm extends ConsumerStatefulWidget {
  final LeaveType type;
  final LeaveBalance balance;
  final bool exists;
  final LeaveActor actor;
  final String? staffUserId;

  const _AdjustForm({
    required this.type,
    required this.balance,
    required this.exists,
    required this.actor,
    required this.staffUserId,
  });

  @override
  ConsumerState<_AdjustForm> createState() => _AdjustFormState();
}

class _AdjustFormState extends ConsumerState<_AdjustForm> {
  final _formKey = GlobalKey<FormState>();
  final _days = TextEditingController();
  final _reason = TextEditingController();
  // One id per dialog: a retried save cannot adjust twice.
  final String _requestId =
      'adj_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _days.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    final units = LeaveUnits.parse(_days.text)!;
    final f = LeaveBalanceMath.figures(
      balance: widget.balance,
      todayKey: AttendanceDate.key(DateTime.now()),
    );
    if (f.available + units < 0) {
      setState(() => _error = 'That would make the balance negative.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(leaveBalanceRepositoryProvider)
          .adjust(
            balance: widget.balance,
            balanceExists: widget.exists,
            units: units,
            reason: _reason.text,
            actor: widget.actor,
            requestId: _requestId,
            staffUserId: widget.staffUserId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Balance adjusted.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Adjust ${widget.type.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _days,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Days to add (use − to remove)',
              helperText: 'Whole or half days, e.g. 2 or -1.5',
            ),
            validator: (v) {
              final u = LeaveUnits.parse(v ?? '');
              if (u == null || u == 0) {
                return 'Enter a number of days other than zero.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _reason,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (kept in the ledger)',
            ),
            validator: (v) =>
                (v ?? '').trim().length < 3 ? 'Give a reason.' : null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Apply adjustment'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
