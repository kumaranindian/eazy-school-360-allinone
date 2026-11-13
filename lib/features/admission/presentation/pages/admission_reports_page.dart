import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/regional/regional_providers.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../fees/domain/money.dart';
import '../../../school_setup/presentation/providers/school_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_report.dart';
import '../providers/admission_providers.dart';
import '../widgets/report_pdf.dart';

/// Admission reports: conversion, sources, classes, staff, branches, lost
/// enquiries, follow-up performance and fee collection. The figures are
/// computed on the server; this page only shows (and exports) them.
class AdmissionReportsPage extends ConsumerStatefulWidget {
  const AdmissionReportsPage({super.key});

  @override
  ConsumerState<AdmissionReportsPage> createState() => _State();
}

class _State extends ConsumerState<AdmissionReportsPage> {
  String? _branch; // null = the user's own branch / all for school admins
  bool _allBranches = false;
  String? _yearId;
  DateTime? _from;
  DateTime? _to;

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 6),
      lastDate: DateTime(now.year + 1),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.insights_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final ownBranch = tenant.branch!.branchId;
        final isSchoolAdmin = tenant.can(Permission.manageSchool);
        final branchId = _allBranches ? null : (_branch ?? ownBranch);
        final key = (
          schoolId: schoolId,
          branchId: branchId,
          academicYearId: _yearId,
          from: _from == null ? null : _key(_from!),
          to: _to == null ? null : _key(_to!),
        );
        final report = ref.watch(admissionReportProvider(key));
        final branches = isSchoolAdmin
            ? ref.watch(branchesStreamProvider(schoolId)).value ?? const []
            : const [];
        final years =
            ref
                .watch(
                  academicYearsProvider((
                    schoolId: schoolId,
                    branchId: branchId ?? ownBranch,
                  )),
                )
                .value ??
            const [];
        final currency = ref.watch(regionalSettingsProvider).currency;
        final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        return Scaffold(
          body: ListView(
            padding: EdgeInsets.all(layout.isMobile ? 16 : 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ParentsCard(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isSchoolAdmin)
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<String>(
                                  // Only a value that is in the list (the list loads a moment later).
                                  value: _allBranches
                                      ? '*'
                                      : branches.any(
                                          (b) =>
                                              b.branchId ==
                                              (_branch ?? ownBranch),
                                        )
                                      ? (_branch ?? ownBranch)
                                      : null,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: '*',
                                      child: Text('All branches'),
                                    ),
                                    for (final b in branches)
                                      DropdownMenuItem(
                                        value: b.branchId,
                                        child: Text(b.name),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _allBranches = v == '*';
                                    _branch = v == '*' ? null : v;
                                    _yearId = null;
                                  }),
                                ),
                              ),
                            SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<String?>(
                                value: _yearId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Academic year',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('All years'),
                                  ),
                                  for (final y in years)
                                    DropdownMenuItem(
                                      value: y.academicYearId,
                                      child: Text(y.name),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _yearId = v),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _pick(true),
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                _from == null ? 'From' : 'From ${_key(_from!)}',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _pick(false),
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                _to == null ? 'To' : 'To ${_key(_to!)}',
                              ),
                            ),
                            if (_from != null || _to != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  _from = null;
                                  _to = null;
                                }),
                                child: const Text('Clear dates'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      report.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) =>
                            ParentsCard(child: Text(userMessageFor(e))),
                        data: (r) => _ReportBody(
                          report: r,
                          currency: currency,
                          schoolName: tenant.school!.name,
                          scopeLabel: _allBranches
                              ? 'All branches'
                              : (branches
                                        .where(
                                          (b) =>
                                              b.branchId ==
                                              (_branch ?? ownBranch),
                                        )
                                        .map((b) => b.name)
                                        .firstOrNull ??
                                    tenant.branch!.name),
                          periodLabel: [
                            if (_from != null) 'from ${_key(_from!)}',
                            if (_to != null) 'to ${_key(_to!)}',
                            if (_from == null && _to == null) 'all dates',
                          ].join(' '),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportBody extends StatelessWidget {
  final AdmissionReport report;
  final String currency;
  final String schoolName;
  final String scopeLabel;
  final String periodLabel;
  const _ReportBody({
    required this.report,
    required this.currency,
    required this.schoolName,
    required this.scopeLabel,
    required this.periodLabel,
  });

  String _m(int v) => Money.format(v, currency: currency);

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r.total == 0) {
      return const ParentsCard(
        child: Text('No enquiries match these filters yet.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.truncated)
          const ParentsCard(
            child: Text(
              'Only the most recent enquiries were counted. Narrow the dates for exact figures.',
            ),
          ),
        ParentsCard(
          child: Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _Figure('Enquiries', '${r.total}'),
              _Figure('Admitted', '${r.confirmed}'),
              _Figure('Conversion', '${r.conversionPercent}%'),
              _Figure('Follow-ups done', '${r.followUpCompletionPercent}%'),
              _Figure('Fees collected', _m(r.feeNetPaidMinor)),
              _Figure('Fees due', _m(r.feeBalanceMinor)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: r.toCsv(money: _m)),
                );
                if (context.mounted) {
                  context.showSnackBar('Report copied as CSV.');
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy CSV'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final bytes = await AdmissionReportPdf.build(
                  r,
                  schoolName: schoolName,
                  scopeLabel: scopeLabel,
                  periodLabel: periodLabel,
                );
                await Printing.layoutPdf(
                  name: 'admission-report.pdf',
                  onLayout: (_) async => bytes,
                );
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Print / PDF'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Bars(
          title: 'Pipeline',
          icon: Icons.filter_alt_outlined,
          rows: [
            for (final e in r.byStatus.entries)
              (label: e.key.label, count: e.value, note: null),
          ],
        ),
        _Bars(
          title: 'By source',
          icon: Icons.campaign_outlined,
          rows: [
            for (final x in r.bySource)
              (
                label: x.label,
                count: x.count,
                note: '${x.confirmed} admitted · ${x.ratePercent}%',
              ),
          ],
        ),
        _Bars(
          title: 'By class',
          icon: Icons.class_outlined,
          rows: [
            for (final x in r.byClass)
              (
                label: x.label,
                count: x.count,
                note: '${x.confirmed} admitted · ${x.ratePercent}%',
              ),
          ],
        ),
        _Bars(
          title: 'By assigned staff',
          icon: Icons.badge_outlined,
          rows: [
            for (final x in r.byAssignee)
              (
                label: x.label,
                count: x.count,
                note: '${x.confirmed} admitted · ${x.ratePercent}%',
              ),
          ],
        ),
        if (r.schoolWide)
          _Bars(
            title: 'By branch',
            icon: Icons.apartment_outlined,
            rows: [
              for (final x in r.byBranch)
                (
                  label: x.label,
                  count: x.count,
                  note: '${x.confirmed} admitted · ${x.ratePercent}%',
                ),
            ],
          ),
        _Bars(
          title: 'By month',
          icon: Icons.calendar_month_outlined,
          rows: [
            for (final x in r.byMonth)
              (label: x.month, count: x.count, note: '${x.confirmed} admitted'),
          ],
        ),
        ParentsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ParentsSectionTitle(
                icon: Icons.person_off_outlined,
                title: 'Lost enquiries',
              ),
              const SizedBox(height: 8),
              Text(
                '${r.lostTotal} lost: ${r.lostByStatus['NOT_INTERESTED']} not interested, '
                '${r.lostByStatus['REJECTED']} not approved, '
                '${r.lostByStatus['WITHDRAWN']} withdrawn.',
              ),
              for (final x in r.lostReasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(x.reason),
                  trailing: Text('${x.count}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ParentsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ParentsSectionTitle(
                icon: Icons.event_note_outlined,
                title: 'Follow-ups',
              ),
              const SizedBox(height: 8),
              Text(
                '${r.followUpsTotal} in total: ${r.followUpsCompleted} completed, '
                '${r.followUpsOpen} open (${r.followUpsOverdue} overdue). '
                'Completion ${r.followUpCompletionPercent}%.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ParentsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ParentsSectionTitle(
                icon: Icons.payments_outlined,
                title: 'Admission fees',
              ),
              const SizedBox(height: 8),
              Text(
                'Asked ${_m(r.feeAmountMinor)} · collected ${_m(r.feeNetPaidMinor)} · due ${_m(r.feeBalanceMinor)}',
              ),
              for (final c in r.feeCategories)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.category),
                  subtitle: Text(
                    'Asked ${_m(c.amountMinor)} · collected ${_m(c.netPaidMinor)}',
                  ),
                  trailing: Text(_m(c.balanceMinor)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  const _Figure(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

typedef _BarRow = ({String label, int count, String? note});

class _Bars extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_BarRow> rows;
  const _Bars({required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.fold<int>(1, (m, r) => r.count > m ? r.count : m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ParentsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ParentsSectionTitle(icon: icon, title: title),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.label)),
                        Text('${r.count}'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    LinearProgressIndicator(value: r.count / max),
                    if (r.note != null)
                      Text(
                        r.note!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
