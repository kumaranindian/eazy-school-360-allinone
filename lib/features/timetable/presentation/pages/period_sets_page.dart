import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../domain/period_set.dart';
import '../../domain/timetable_enums.dart';
import '../providers/timetable_providers.dart';
import '../widgets/timetable_scope.dart';

/// `/timetable/periods` — bell schedules: period numbers, start/end times,
/// breaks, lunch, assembly. A timetable maps each working day to one of
/// these, so different days can follow different schedules.
class PeriodSetsPage extends StatelessWidget {
  const PeriodSetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bell schedules')),
      body: TimetableScope(builder: (context, tt) => _List(tt: tt)),
    );
  }
}

class _List extends ConsumerWidget {
  final TimetableContext tt;

  const _List({required this.tt});

  Future<void> _edit(BuildContext context, [PeriodSet? existing]) {
    return showAdaptiveAppDialog<void>(
      context: context,
      builder: (dialogContext) => PeriodSetForm(
        tt: tt,
        existing: existing,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = tt.tenant.can(Permission.manageTimetable);
    final sets = ref.watch(periodSetsProvider(tt.yearKey));
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('New bell schedule'),
              ),
            ),
          ),
        Expanded(
          child: sets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(periodSetsProvider(tt.yearKey)),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyView(
                  icon: Icons.access_time,
                  message: 'No bell schedules yet for this academic year.',
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  for (final s in list)
                    Card(
                      child: ListTile(
                        title: Text(s.name),
                        subtitle: Text(
                          [
                            for (final slot in s.slots)
                              '${slot.isTeaching ? 'P${slot.number}' : slot.label} ${slot.timeLabel}',
                          ].join(' · '),
                        ),
                        trailing: canManage
                            ? const Icon(Icons.edit_outlined)
                            : null,
                        onTap: canManage ? () => _edit(context, s) : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SlotDraft {
  String slotId;
  SlotKind kind;
  final TextEditingController label;
  final TextEditingController start;
  final TextEditingController end;

  _SlotDraft({
    required this.slotId,
    required this.kind,
    required String label,
    required String start,
    required String end,
  }) : label = TextEditingController(text: label),
       start = TextEditingController(text: start),
       end = TextEditingController(text: end);

  void dispose() {
    label.dispose();
    start.dispose();
    end.dispose();
  }
}

class PeriodSetForm extends ConsumerStatefulWidget {
  final TimetableContext tt;
  final PeriodSet? existing;
  final VoidCallback onDone;

  const PeriodSetForm({
    super.key,
    required this.tt,
    required this.existing,
    required this.onDone,
  });

  @override
  ConsumerState<PeriodSetForm> createState() => _PeriodSetFormState();
}

class _PeriodSetFormState extends ConsumerState<PeriodSetForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final List<_SlotDraft> _slots = [];
  int _nextId = 1;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      for (final s in e.slots) {
        _slots.add(
          _SlotDraft(
            slotId: s.slotId,
            kind: s.kind,
            label: s.label,
            start: MinuteOfDay.format(s.startMin),
            end: MinuteOfDay.format(s.endMin),
          ),
        );
      }
      _nextId = e.slots.length + 1;
      // never reuse an id an existing timetable may reference
      final used = e.slots.map((s) => s.slotId).toSet();
      while (used.contains('s$_nextId')) {
        _nextId++;
      }
    } else {
      _slots.add(
        _SlotDraft(
          slotId: 's1',
          kind: SlotKind.teaching,
          label: '',
          start: '09:00',
          end: '09:40',
        ),
      );
      _nextId = 2;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  void _add(SlotKind kind) {
    final last = _slots.isEmpty
        ? null
        : MinuteOfDay.parse(_slots.last.end.text.trim());
    final start = last ?? 540;
    final len = kind.isTeaching ? 40 : 15;
    setState(
      () => _slots.add(
        _SlotDraft(
          slotId: 's${_nextId++}',
          kind: kind,
          label: kind.isTeaching ? '' : kind.displayName,
          start: MinuteOfDay.format(start),
          end: MinuteOfDay.format((start + len).clamp(0, 1440)),
        ),
      ),
    );
  }

  PeriodSet? _build() {
    final slots = <PeriodSlot>[];
    for (final d in _slots) {
      final s = MinuteOfDay.parse(d.start.text);
      final e = MinuteOfDay.parse(d.end.text);
      if (s == null || e == null) {
        setState(() => _error = 'Enter times as HH:MM (24-hour), e.g. 09:40.');
        return null;
      }
      slots.add(
        PeriodSlot(
          slotId: d.slotId,
          number: d.kind.isTeaching ? 1 : null,
          kind: d.kind,
          label: d.label.text.trim(),
          startMin: s,
          endMin: e,
        ),
      );
    }
    final tt = widget.tt;
    return PeriodSet(
      periodSetId:
          widget.existing?.periodSetId ??
          PeriodSet.idFor(tt.year.academicYearId, _name.text),
      schoolId: tt.schoolId,
      branchId: tt.branchId,
      academicYearId: tt.year.academicYearId,
      name: _name.text.trim(),
      slots: slots,
      status: ActivationStatus.active,
    ).normalized();
  }

  Future<void> _save() async {
    final set = _build();
    if (set == null) return;
    final problem = set.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(periodSetRepositoryProvider)
          .savePeriodSet(set, isNew: _isNew, actorId: widget.tt.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isNew ? 'Schedule created.' : 'Schedule saved.'),
        ),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isNew ? 'New bell schedule' : 'Edit bell schedule',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _name,
          enabled: _isNew,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < _slots.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<SlotKind>(
                    value: _slots[i].kind,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      for (final k in SlotKind.values)
                        DropdownMenuItem(value: k, child: Text(k.displayName)),
                    ],
                    onChanged: (v) => setState(() {
                      _slots[i].kind = v ?? SlotKind.teaching;
                      if (!_slots[i].kind.isTeaching &&
                          _slots[i].label.text.isEmpty) {
                        _slots[i].label.text = _slots[i].kind.displayName;
                      }
                    }),
                  ),
                ),
                if (!_slots[i].kind.isTeaching)
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _slots[i].label,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Label',
                      ),
                    ),
                  ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _slots[i].start,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Start',
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _slots[i].end,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'End',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: _slots.length <= 1
                      ? null
                      : () => setState(() {
                          _slots.removeAt(i).dispose();
                        }),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _add(SlotKind.teaching),
              icon: const Icon(Icons.add),
              label: const Text('Period'),
            ),
            OutlinedButton.icon(
              onPressed: () => _add(SlotKind.breakSlot),
              icon: const Icon(Icons.add),
              label: const Text('Break'),
            ),
            OutlinedButton.icon(
              onPressed: () => _add(SlotKind.lunch),
              icon: const Icon(Icons.add),
              label: const Text('Lunch'),
            ),
          ],
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
              onPressed: _busy ? null : widget.onDone,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
