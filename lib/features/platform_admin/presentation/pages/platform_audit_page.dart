import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../attendance/domain/attendance_csv.dart';
import '../../domain/audit_entry.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_console_providers.dart';
import '../widgets/platform_scaffold.dart';

/// What platform administrators did: the newest 200 actions, searchable, with a
/// CSV copy. Read-only; the log is written by the server and cannot be edited.
class PlatformAuditPage extends ConsumerStatefulWidget {
  const PlatformAuditPage({super.key});

  @override
  ConsumerState<PlatformAuditPage> createState() => _PlatformAuditPageState();
}

class _PlatformAuditPageState extends ConsumerState<PlatformAuditPage> {
  final _search = TextEditingController();
  String? _action;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _csv(List<AuditEntry> rows) => AttendanceCsv.encode(
    [
      'When',
      'Action',
      'Actor',
      'Actor role',
      'Target',
      'School',
      'Reason',
      'Result',
      'Source',
    ],
    [
      for (final r in rows)
        [
          r.at?.toUtc().toIso8601String() ?? '',
          r.action,
          r.actorEmail,
          r.actorRole,
          r.targetEmail,
          r.schoolId,
          r.reason,
          r.result,
          r.source,
        ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(tenantContextProvider).value?.user.platformRole;
    final allowed =
        role == PlatformRole.owner || role == PlatformRole.compliance;
    return PlatformScaffold(
      title: 'Audit log',
      child: !allowed
          ? const EmptyView(
              icon: Icons.lock_outline,
              message: 'Only owners and compliance reviewers can see the log.',
            )
          : AsyncValueWidget(
              value: ref.watch(auditLogProvider),
              errorMessage: userMessageFor,
              onRetry: () => ref.invalidate(auditLogProvider),
              data: (all) {
                final actions = {for (final r in all) r.action}.toList()
                  ..sort();
                final rows = [
                  for (final r in all)
                    if ((_action == null || r.action == _action) &&
                        r.matches(_search.text))
                      r,
                ];
                return PlatformBody(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 260,
                              child: TextField(
                                key: const ValueKey('audit-search'),
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: 'Search the log',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: DropdownButtonFormField<String?>(
                                key: const ValueKey('audit-action'),
                                value: actions.contains(_action)
                                    ? _action
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Action',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('All actions'),
                                  ),
                                  for (final a in actions)
                                    DropdownMenuItem(
                                      value: a,
                                      child: Text(
                                        AuditEntry(
                                          id: '',
                                          action: a,
                                          actorEmail: '',
                                          actorRole: '',
                                          targetEmail: '',
                                          schoolId: '',
                                          reason: '',
                                          result: '',
                                          source: '',
                                          at: null,
                                        ).actionLabel,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _action = v),
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const ValueKey('audit-copy'),
                              icon: const Icon(Icons.copy_all_outlined),
                              label: const Text('Copy CSV'),
                              onPressed: rows.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: _csv(rows)),
                                      );
                                      if (context.mounted) {
                                        context.showSnackBar(
                                          'Copied ${rows.length} rows as CSV.',
                                        );
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: rows.isEmpty
                            ? const EmptyView(
                                icon: Icons.history,
                                message: 'No matching entries.',
                              )
                            : RefreshIndicator(
                                onRefresh: () async {
                                  ref.invalidate(auditLogProvider);
                                  await ref.read(auditLogProvider.future);
                                },
                                child: ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.md,
                                    0,
                                    AppSpacing.md,
                                    AppSpacing.lg,
                                  ),
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, i) =>
                                      _AuditRow(entry: rows[i]),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEntry entry;

  const _AuditRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final detail = [
      if (entry.actorEmail.isNotEmpty) entry.actorEmail,
      if (entry.targetEmail.isNotEmpty) '→ ${entry.targetEmail}',
      if (entry.schoolId.isNotEmpty) 'school ${entry.schoolId}',
    ].join('  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              Text(entry.actionLabel, style: text.titleSmall),
              Text(formatInstant(entry.at), style: text.bodySmall),
              if (entry.source == 'SCRIPT')
                Text('(script)', style: text.bodySmall),
            ],
          ),
          if (detail.isNotEmpty) Text(detail, style: text.bodyMedium),
          if (entry.reason.isNotEmpty)
            Text('Reason: ${entry.reason}', style: text.bodySmall),
        ],
      ),
    );
  }
}
