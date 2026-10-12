import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../staff/domain/employment_type.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_type.dart';
import '../../domain/leave_units.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_scope.dart';

/// `/leave/types` — leave types and the branch's leave policy. Everyone with
/// leave access can read; only `manageLeaveTypes` holders see the controls.
/// Types are deactivated, never deleted, and applications keep a snapshot.
class LeaveTypesPage extends StatelessWidget {
  const LeaveTypesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave types & policy')),
      body: LeaveScope(
        showYearSelector: false,
        builder: (context, leave) => _Types(leave: leave),
      ),
    );
  }
}

class _Types extends ConsumerStatefulWidget {
  final LeaveContext leave;

  const _Types({required this.leave});

  @override
  ConsumerState<_Types> createState() => _TypesState();
}

class _TypesState extends ConsumerState<_Types> {
  LeaveKind _kind = LeaveKind.student;

  Future<void> _edit([LeaveType? existing]) async {
    final leave = widget.leave;
    await showAdaptiveAppDialog<void>(
      context: context,
      builder: (dialogContext) => LeaveTypeForm(
        schoolId: leave.schoolId,
        branchId: leave.branchId,
        kind: _kind,
        existing: existing,
        actorId: leave.userId,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final canManage = leave.tenant.can(Permission.manageLeaveTypes);
    final types = ref.watch(
      leaveTypesProvider((
        schoolId: leave.schoolId,
        branchId: leave.branchId,
        kind: _kind,
      )),
    );
    final onBehalf = ref
        .watch(leaveAllowOnBehalfProvider(leave.branchKey))
        .value;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<LeaveKind>(
                segments: const [
                  ButtonSegment(
                    value: LeaveKind.student,
                    label: Text('Student leave'),
                  ),
                  ButtonSegment(
                    value: LeaveKind.staff,
                    label: Text('Staff leave'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add leave type'),
                ),
            ],
          ),
        ),
        if (canManage)
          SwitchListTile(
            title: const Text('Office staff may file student leave on behalf'),
            subtitle: const Text(
              'Off by default. When on, an admin can apply for a student, '
              'and another admin must approve it.',
            ),
            value: onBehalf ?? false,
            onChanged: onBehalf == null
                ? null
                : (v) async {
                    try {
                      await ref
                          .read(leaveTypeRepositoryProvider)
                          .setAllowAdminOnBehalf(
                            leave.schoolId,
                            leave.branchId,
                            v,
                            actorId: leave.userId,
                          );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(userMessageFor(e))),
                      );
                    }
                  },
          ),
        Expanded(
          child: types.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(leaveTypesProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return EmptyView(
                  icon: Icons.tune,
                  message: canManage
                      ? 'No ${_kind.displayName.toLowerCase()} leave types yet. Add the first one.'
                      : 'No leave types have been set up yet.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final t = list[i];
                  final facts = <String>[
                    t.payType.displayName,
                    if (t.annualEntitlementUnits != null)
                      '${LeaveUnits.formatDays(t.annualEntitlementUnits!)}/year',
                    if (t.requiresDocument) 'document required',
                    if (!t.allowHalfDay) 'no half days',
                    if (t.countNonWorkingDays) 'counts holidays',
                  ];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      title: Text('${t.name} (${t.code})'),
                      subtitle: Text(facts.join(' · ')),
                      trailing: t.isActive
                          ? (canManage ? const Icon(Icons.edit_outlined) : null)
                          : const Chip(label: Text('Inactive')),
                      onTap: canManage ? () => _edit(t) : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class LeaveTypeForm extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final LeaveKind kind;
  final LeaveType? existing;
  final String actorId;
  final VoidCallback onDone;

  const LeaveTypeForm({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.existing,
    required this.actorId,
    required this.onDone,
  });

  @override
  ConsumerState<LeaveTypeForm> createState() => _LeaveTypeFormState();
}

class _LeaveTypeFormState extends ConsumerState<LeaveTypeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _entitlement;
  late final TextEditingController _carry;
  late final TextEditingController _maxDays;
  late LeavePayType _pay;
  late bool _requiresDoc;
  late bool _requiresReason;
  late bool _halfDay;
  late bool _countNonWorking;
  late AccrualMode _accrual;
  late ExceedPolicy _exceed;
  late bool _active;
  late Set<String> _roles;
  late Set<String> _employment;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;
  bool get _isStaff => widget.kind == LeaveKind.staff;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _code = TextEditingController(text: t?.code ?? '');
    _name = TextEditingController(text: t?.name ?? '');
    _entitlement = TextEditingController(
      text: t?.annualEntitlementUnits == null
          ? ''
          : LeaveUnits.format(t!.annualEntitlementUnits!),
    );
    _carry = TextEditingController(
      text: (t?.carryForwardMaxUnits ?? 0) == 0
          ? ''
          : LeaveUnits.format(t!.carryForwardMaxUnits),
    );
    _maxDays = TextEditingController(
      text: t?.maxDaysPerRequest?.toString() ?? '',
    );
    _pay =
        t?.payType ??
        (_isStaff ? LeavePayType.paid : LeavePayType.notApplicable);
    _requiresDoc = t?.requiresDocument ?? false;
    _requiresReason = t?.requiresReason ?? true;
    _halfDay = t?.allowHalfDay ?? true;
    _countNonWorking = t?.countNonWorkingDays ?? false;
    _accrual = t?.accrual ?? AccrualMode.upfront;
    _exceed = t?.exceedPolicy ?? ExceedPolicy.block;
    _active = t?.isActive ?? true;
    _roles = {...?t?.applicableRoles};
    _employment = {...?t?.applicableEmploymentTypes};
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _entitlement, _carry, _maxDays]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    final entitlementText = _entitlement.text.trim();
    final carryText = _carry.text.trim();
    final type = LeaveType(
      typeId:
          widget.existing?.typeId ?? LeaveType.idFor(widget.kind, _code.text),
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      kind: widget.kind,
      code: widget.existing?.code ?? _code.text.trim(),
      name: _name.text.trim(),
      payType: _pay,
      requiresDocument: _requiresDoc,
      requiresReason: _requiresReason,
      allowHalfDay: _halfDay,
      countNonWorkingDays: _countNonWorking,
      maxDaysPerRequest: int.tryParse(_maxDays.text.trim()),
      applicableRoles: _roles.toList()..sort(),
      applicableEmploymentTypes: _employment.toList()..sort(),
      annualEntitlementUnits: _isStaff && entitlementText.isNotEmpty
          ? LeaveUnits.parse(entitlementText)
          : null,
      accrual: _accrual,
      carryForwardMaxUnits: _isStaff && carryText.isNotEmpty
          ? (LeaveUnits.parse(carryText) ?? 0)
          : 0,
      exceedPolicy: _exceed,
      status: _active ? ActivationStatus.active : ActivationStatus.inactive,
    );
    final problem = type.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(leaveTypeRepositoryProvider)
          .saveType(type, isNew: _isNew, actorId: widget.actorId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isNew ? 'Leave type created.' : 'Leave type updated.'),
        ),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? daysValidator(String? v, {bool required = false}) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return required ? 'Enter the number of days.' : null;
      return LeaveUnits.parse(t) == null || LeaveUnits.parse(t)! <= 0
          ? 'Use whole or half days, e.g. 12 or 7.5.'
          : null;
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isNew
                ? 'New ${widget.kind.displayName.toLowerCase()} leave type'
                : 'Edit leave type',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _code,
            enabled: _isNew,
            decoration: const InputDecoration(labelText: 'Code'),
            validator: (v) =>
                RegExp(r'^[A-Za-z0-9_-]{2,20}$').hasMatch((v ?? '').trim())
                ? null
                : '2-20 letters, digits, "-" or "_".',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v ?? '').trim().length < 2 ? 'Enter a name.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_isStaff) ...[
            DropdownButtonFormField<LeavePayType>(
              value: _pay,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pay'),
              items: const [
                DropdownMenuItem(value: LeavePayType.paid, child: Text('Paid')),
                DropdownMenuItem(
                  value: LeavePayType.unpaid,
                  child: Text('Unpaid'),
                ),
              ],
              onChanged: (v) => setState(() {
                _pay = v ?? LeavePayType.paid;
                if (_pay == LeavePayType.unpaid) _entitlement.clear();
              }),
            ),
            if (_pay == LeavePayType.paid) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _entitlement,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Annual entitlement (days)',
                  helperText: 'Leave empty if no balance is tracked.',
                ),
                validator: daysValidator,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<AccrualMode>(
                value: _accrual,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Accrual'),
                items: [
                  for (final a in AccrualMode.values)
                    DropdownMenuItem(value: a, child: Text(a.displayName)),
                ],
                onChanged: (v) =>
                    setState(() => _accrual = v ?? AccrualMode.upfront),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _carry,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Carry-forward limit (days)',
                  helperText: 'Most that may carry into the next year.',
                ),
                validator: daysValidator,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<ExceedPolicy>(
                value: _exceed,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'When a request exceeds the balance',
                ),
                items: [
                  for (final e in ExceedPolicy.values)
                    DropdownMenuItem(value: e, child: Text(e.displayName)),
                ],
                onChanged: (v) =>
                    setState(() => _exceed = v ?? ExceedPolicy.block),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _maxDays,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Longest single request (days)',
              helperText:
                  'Up to ${LeaveType.globalMaxDays}. Empty = no extra limit.',
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              final n = int.tryParse(t);
              return n == null || n < 1 || n > LeaveType.globalMaxDays
                  ? 'Enter 1-${LeaveType.globalMaxDays}.'
                  : null;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Supporting document required'),
            value: _requiresDoc,
            onChanged: (v) => setState(() => _requiresDoc = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reason required'),
            value: _requiresReason,
            onChanged: (v) => setState(() => _requiresReason = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Half days allowed'),
            value: _halfDay,
            onChanged: (v) => setState(() => _halfDay = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Count holidays and weekends as leave'),
            value: _countNonWorking,
            onChanged: (v) => setState(() => _countNonWorking = v),
          ),
          if (_isStaff) ...[
            Text(
              'Available to roles (none selected = everyone)',
              style: theme.textTheme.labelLarge,
            ),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in const [
                  ('TEACHER', 'Teachers'),
                  ('FINANCE', 'Finance'),
                  ('BRANCH_ADMIN', 'Branch admins'),
                  ('SCHOOL_ADMIN', 'School admins'),
                ])
                  FilterChip(
                    label: Text(r.$2),
                    selected: _roles.contains(r.$1),
                    onSelected: (on) => setState(
                      () => on ? _roles.add(r.$1) : _roles.remove(r.$1),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Available to employment types (none = all)',
              style: theme.textTheme.labelLarge,
            ),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final e in EmploymentType.values)
                  FilterChip(
                    label: Text(e.displayName),
                    selected: _employment.contains(e.wireValue),
                    onSelected: (on) => setState(
                      () => on
                          ? _employment.add(e.wireValue)
                          : _employment.remove(e.wireValue),
                    ),
                  ),
              ],
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: const Text(
              'Inactive types cannot be chosen for new applications. '
              'Existing applications are unaffected.',
            ),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : widget.onDone,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
