import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/exam_enums.dart';
import '../../domain/grading_scheme.dart';
import '../providers/exam_providers.dart';

/// `/exams/schemes` — the school's grading schemes. A scheme is just
/// configuration; an examination keeps a **snapshot** of the scheme it was
/// finalised under, so editing a scheme never rewrites a published result.
class GradingSchemesPage extends ConsumerWidget {
  const GradingSchemesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grading schemes')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) =>
            _Schemes(tenant: tenant, schoolId: schoolId, branchId: branchId),
      ),
    );
  }
}

class _Schemes extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;

  const _Schemes({
    required this.tenant,
    required this.schoolId,
    required this.branchId,
  });

  Future<void> _edit(BuildContext context, GradingScheme? scheme) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SchemeEditorPage(
          tenant: tenant,
          schoolId: schoolId,
          branchId: branchId,
          scheme: scheme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemes = ref.watch(
      schemesProvider((schoolId: schoolId, branchId: branchId)),
    );
    return schemes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(schemesProvider),
      ),
      data: (list) => PageColumn(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _edit(context, null),
                icon: const Icon(Icons.add),
                label: const Text('New grading scheme'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: EmptyView(
                  icon: Icons.rule,
                  message:
                      'No grading scheme yet. Create one to grade '
                      'examinations — nothing is assumed for you.',
                ),
              )
            else
              for (final s in list)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    title: Text(s.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            s.sortedBands
                                .map((b) => '${b.grade} ≥${_n(b.minPercent)}%')
                                .join(' · '),
                          ),
                          Text('pass ${_n(s.passPercent)}%'),
                          if (s.gpaEnabled) const StatusPill(label: 'GPA'),
                          if (s.rankingEnabled)
                            const StatusPill(label: 'Ranks'),
                          if (!s.active) const StatusPill(label: 'Inactive'),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(context, s),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _BandRow {
  final TextEditingController grade;
  final TextEditingController label;
  final TextEditingController min;
  final TextEditingController point;

  _BandRow(GradeBand? b)
    : grade = TextEditingController(text: b?.grade ?? ''),
      label = TextEditingController(text: b?.label ?? ''),
      min = TextEditingController(text: b == null ? '' : _fmt(b.minPercent)),
      point = TextEditingController(
        text: b?.gradePoint == null ? '' : _fmt(b!.gradePoint!),
      );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void dispose() {
    grade.dispose();
    label.dispose();
    min.dispose();
    point.dispose();
  }
}

/// Create / edit one scheme. Validation runs live: overlapping boundaries,
/// a missing 0% band, duplicate grades and partial grade points are reported
/// before anything is saved.
class SchemeEditorPage extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final GradingScheme? scheme;

  const SchemeEditorPage({
    super.key,
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    this.scheme,
  });

  @override
  ConsumerState<SchemeEditorPage> createState() => _SchemeEditorState();
}

class _SchemeEditorState extends ConsumerState<SchemeEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _pass;
  late final TextEditingController _overall;
  late List<_BandRow> _bands;
  late int _decimals;
  late RoundingMode _rounding;
  late AbsentPolicy _absent;
  late AggregateMethod _aggregate;
  late bool _ranking;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s =
        widget.scheme ??
        GradingScheme.sample(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
        );
    _name = TextEditingController(text: widget.scheme == null ? '' : s.name);
    _description = TextEditingController(text: s.description);
    _pass = TextEditingController(text: _BandRow._fmt(s.passPercent));
    _overall = TextEditingController(
      text: s.overallPassPercent == null
          ? ''
          : _BandRow._fmt(s.overallPassPercent!),
    );
    _bands = [for (final b in s.sortedBands) _BandRow(b)];
    _decimals = s.decimals;
    _rounding = s.rounding;
    _absent = s.absentPolicy;
    _aggregate = s.aggregate;
    _ranking = s.rankingEnabled;
    _active = s.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _pass.dispose();
    _overall.dispose();
    for (final b in _bands) {
      b.dispose();
    }
    super.dispose();
  }

  GradingScheme _build() => GradingScheme(
    schemeId: widget.scheme?.schemeId ?? '',
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    name: _name.text,
    description: _description.text,
    bands: [
      for (final b in _bands)
        GradeBand(
          grade: b.grade.text.trim(),
          label: b.label.text.trim(),
          minPercent: double.tryParse(b.min.text.trim()) ?? -1,
          gradePoint: b.point.text.trim().isEmpty
              ? null
              : double.tryParse(b.point.text.trim()) ?? -1,
        ),
    ],
    passPercent: double.tryParse(_pass.text.trim()) ?? -1,
    overallPassPercent: _overall.text.trim().isEmpty
        ? null
        : double.tryParse(_overall.text.trim()) ?? -1,
    decimals: _decimals,
    rounding: _rounding,
    absentPolicy: _absent,
    aggregate: _aggregate,
    rankingEnabled: _ranking,
    active: _active,
    revision: widget.scheme?.revision ?? 1,
  );

  Future<void> _save() async {
    if (_saving) return;
    final scheme = _build();
    final problem = scheme.validate();
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(gradingSchemeRepositoryProvider)
          .save(scheme, actor: examActorFor(widget.tenant));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _build().validate();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.scheme == null ? 'New grading scheme' : 'Edit scheme',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close without saving',
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: PageColumn(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (widget.scheme != null)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Finalised results keep their own copy'),
                  subtitle: Text(
                    'Changes apply to examinations finalised from now on. '
                    'Published report cards are not rewritten.',
                  ),
                ),
              ),
            SectionCard(
              title: 'Scheme',
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  TextField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available for new examinations'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: 'Grades',
              actions: [
                TextButton.icon(
                  onPressed: () => setState(() => _bands.add(_BandRow(null))),
                  icon: const Icon(Icons.add),
                  label: const Text('Add grade'),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A grade applies from its minimum percentage up to the '
                    'next grade\'s minimum. The lowest grade must start at 0. '
                    'Grade points are optional; give them to every grade or '
                    'to none (GPA is only produced when defined).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (var i = 0; i < _bands.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _bands[i].grade,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Grade',
                                isDense: true,
                                semanticCounterText: 'Grade ${i + 1}',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _bands[i].min,
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'From %',
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _bands[i].label,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _bands[i].point,
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Grade point',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove grade ${i + 1}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _bands.length <= 1
                                ? null
                                : () => setState(() {
                                    _bands.removeAt(i).dispose();
                                  }),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Pass rule and calculation',
              child: Column(
                children: [
                  TextField(
                    controller: _pass,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Subject pass percentage',
                      helperText:
                          'Used when a subject has no passing marks of its own.',
                    ),
                  ),
                  TextField(
                    controller: _overall,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Overall pass percentage (optional)',
                    ),
                  ),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: _decimals,
                    decoration: const InputDecoration(
                      labelText: 'Decimal places for percentages',
                    ),
                    items: [
                      for (final d in [0, 1, 2, 3])
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (v) => setState(() => _decimals = v!),
                  ),
                  DropdownButtonFormField<RoundingMode>(
                    isExpanded: true,
                    value: _rounding,
                    decoration: const InputDecoration(labelText: 'Rounding'),
                    items: [
                      for (final r in RoundingMode.values)
                        DropdownMenuItem(value: r, child: Text(r.displayName)),
                    ],
                    onChanged: (v) => setState(() => _rounding = v!),
                  ),
                  DropdownButtonFormField<AbsentPolicy>(
                    isExpanded: true,
                    value: _absent,
                    decoration: const InputDecoration(
                      labelText: 'An absent subject',
                    ),
                    items: [
                      for (final a in AbsentPolicy.values)
                        DropdownMenuItem(value: a, child: Text(a.displayName)),
                    ],
                    onChanged: (v) => setState(() => _absent = v!),
                  ),
                  DropdownButtonFormField<AggregateMethod>(
                    isExpanded: true,
                    value: _aggregate,
                    decoration: const InputDecoration(
                      labelText: 'Overall percentage',
                    ),
                    items: [
                      for (final a in AggregateMethod.values)
                        DropdownMenuItem(value: a, child: Text(a.displayName)),
                    ],
                    onChanged: (v) => setState(() => _aggregate = v!),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rank students'),
                    subtitle: const Text(
                      'Off by default. When on, ranks appear on results.',
                    ),
                    value: _ranking,
                    onChanged: (v) => setState(() => _ranking = v),
                  ),
                ],
              ),
            ),
            if (live != null || _error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error ?? live!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                FilledButton(
                  onPressed: _saving || live != null ? null : _save,
                  child: const Text('Save scheme'),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
