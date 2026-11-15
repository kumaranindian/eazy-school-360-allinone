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
import '../../domain/audit_trail.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_ops_providers.dart';
import '../widgets/platform_scaffold.dart';

/// The central audit trail: who did what, where, and how far to trust each
/// line. Platform owners and compliance only; read-only (the trail is written
/// by the server). Opening and exporting it are themselves audited.
class PlatformAuditTrailPage extends ConsumerStatefulWidget {
  const PlatformAuditTrailPage({super.key});

  @override
  ConsumerState<PlatformAuditTrailPage> createState() =>
      _PlatformAuditTrailPageState();
}

class _PlatformAuditTrailPageState
    extends ConsumerState<PlatformAuditTrailPage> {
  final _school = TextEditingController();
  final _actor = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _school.dispose();
    _actor.dispose();
    super.dispose();
  }

  void _apply(AuditFilter f) {
    ref.read(auditFilterProvider.notifier).set(f);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final out = await ref
          .read(platformOpsRepositoryProvider)
          .exportAudit(ref.read(auditFilterProvider));
      await Clipboard.setData(ClipboardData(text: out.csv));
      if (!mounted) return;
      context.showSnackBar(
        out.capped
            ? '${out.rows} rows copied (the maximum). Narrow the filters for the rest.'
            : '${out.rows} rows copied as CSV (times in UTC).',
      );
    } catch (e) {
      if (mounted) context.showSnackBar(userMessageFor(e), isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(tenantContextProvider).value?.user.platformRole;
    final allowed =
        role == PlatformRole.owner || role == PlatformRole.compliance;
    if (!allowed) {
      return const PlatformScaffold(
        title: 'Audit trail',
        child: EmptyView(
          icon: Icons.lock_outline,
          message: 'Your platform role cannot open the audit trail.',
        ),
      );
    }
    final filter = ref.watch(auditFilterProvider);
    final text = Theme.of(context).textTheme;
    return PlatformScaffold(
      title: 'Audit trail',
      actions: [
        IconButton(
          key: const ValueKey('audit-export'),
          tooltip: 'Copy as CSV',
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          onPressed: _exporting ? null : _export,
        ),
      ],
      child: PlatformBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _Summary(),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final p in <(String, AuditFilter)>[
                  ('Everything', AuditFilter(hours: filter.hours)),
                  (
                    'Security',
                    AuditFilter(hours: filter.hours, category: 'SECURITY'),
                  ),
                  (
                    'Denied',
                    AuditFilter(hours: filter.hours, result: 'DENIED'),
                  ),
                  (
                    'Failures',
                    AuditFilter(hours: filter.hours, result: 'FAILURE'),
                  ),
                  (
                    'Reported by the app',
                    AuditFilter(hours: filter.hours, source: 'CLIENT_REPORTED'),
                  ),
                ])
                  ChoiceChip(
                    key: ValueKey('audit-preset-${p.$1}'),
                    label: Text(p.$1),
                    selected: _sameView(filter, p.$2),
                    onSelected: (_) {
                      _school.clear();
                      _actor.clear();
                      _apply(p.$2);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('audit-window'),
                    isExpanded: true,
                    value: filter.hours,
                    decoration: const InputDecoration(labelText: 'Time window'),
                    items: [
                      for (final h in AuditFilter.windows)
                        DropdownMenuItem(
                          value: h,
                          child: Text(AuditFilter.windowLabel(h)),
                        ),
                    ],
                    onChanged: (v) => _apply(filter.copyWith(hours: v)),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('audit-category'),
                    isExpanded: true,
                    value: filter.category,
                    decoration: const InputDecoration(labelText: 'Area'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All areas'),
                      ),
                      for (final c in auditCategories)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                            auditCategoryLabel(c),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => _apply(filter.copyWith(category: v)),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    key: const ValueKey('audit-school'),
                    controller: _school,
                    decoration: const InputDecoration(labelText: 'School id'),
                    onSubmitted: (v) => _apply(
                      filter.copyWith(
                        schoolId: v.trim().isEmpty ? null : v.trim(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    key: const ValueKey('audit-actor'),
                    controller: _actor,
                    decoration: const InputDecoration(labelText: 'User id'),
                    onSubmitted: (v) => _apply(
                      filter.copyWith(
                        actorUserId: v.trim().isEmpty ? null : v.trim(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AsyncValueWidget(
              value: ref.watch(auditTrailProvider),
              errorMessage: userMessageFor,
              onRetry: () => ref.invalidate(auditTrailProvider),
              data: (s) => s.events.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: EmptyView(
                        icon: Icons.history,
                        message: 'Nothing recorded for these filters.',
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in s.events) _EventTile(event: e),
                        if (s.truncated)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Text(
                              'This search is wide: only part of it was scanned. Narrow the filters or the time window.',
                              key: const ValueKey('audit-truncated'),
                              style: text.bodySmall,
                            ),
                          ),
                        if (s.moreError != null)
                          Text(
                            userMessageFor(s.moreError!),
                            style: text.bodySmall,
                          ),
                        if (s.nextCursor != null)
                          Center(
                            child: TextButton(
                              key: const ValueKey('audit-more'),
                              onPressed: s.loadingMore
                                  ? null
                                  : () => ref
                                        .read(auditTrailProvider.notifier)
                                        .loadMore(),
                              child: s.loadingMore
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Load more'),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The preset matches when everything but the window is the same.
  bool _sameView(AuditFilter a, AuditFilter b) =>
      a.category == b.category &&
      a.result == b.result &&
      a.source == b.source &&
      a.schoolId == b.schoolId &&
      a.actorUserId == b.actorUserId &&
      a.eventType == b.eventType;
}

class _Summary extends ConsumerWidget {
  const _Summary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(auditSummaryProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (s) => Wrap(
            key: const ValueKey('audit-summary'),
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _Stat('Last 24 hours', '${s.total}'),
              _Stat('Denied', '${s.denied}', warn: s.denied > 0),
              _Stat('Failures', '${s.failures}', warn: s.failures > 0),
              _Stat('Reported by the app', '${s.clientReported}'),
            ],
          ),
        );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;

  const _Stat(this.label, this.value, {this.warn = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: warn ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final AuditEventView event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final who = (event.actor ?? '').isNotEmpty
        ? event.actor!
        : (event.actorUserId ?? 'System');
    return Card(
      key: ValueKey('audit-${event.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        title: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(event.title, style: text.titleSmall),
            if (event.result != 'SUCCESS')
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(event.result.toLowerCase()),
                backgroundColor: event.denied || event.failed
                    ? scheme.errorContainer
                    : scheme.tertiaryContainer,
              ),
            if (event.clientReported)
              const Chip(
                key: ValueKey('audit-client-reported'),
                visualDensity: VisualDensity.compact,
                label: Text('reported by the app'),
              ),
          ],
        ),
        subtitle: Text(
          '${formatInstant(event.at)} · $who'
          '${(event.schoolId ?? '').isEmpty ? '' : ' · school ${event.schoolId}'}',
        ),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _EventDialog(event: event),
        ),
      ),
    );
  }
}

class _EventDialog extends StatelessWidget {
  final AuditEventView event;

  const _EventDialog({required this.event});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String k, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$k: ', style: text.labelLarge),
                  TextSpan(text: v),
                ],
              ),
            ),
          );
    return AlertDialog(
      key: const ValueKey('audit-detail'),
      title: Text(event.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('When', formatInstant(event.at)),
              row('Result', event.result.toLowerCase()),
              row('Trust', event.trustLabel),
              row('Who', event.actor ?? event.actorUserId),
              row('Role', event.actorRole),
              row(
                'App',
                [
                  event.application,
                  event.platform,
                ].whereType<String>().join(' · '),
              ),
              row('School', event.schoolId),
              row('Branch', event.branchId),
              row(
                'About',
                [
                  event.targetEntity,
                  event.targetEntityId,
                ].whereType<String>().join(' '),
              ),
              row('Summary', event.description),
              if (event.changes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text('Changes', style: text.labelLarge),
                for (final c in event.changes)
                  Text(
                    c.hasValues
                        ? '${c.field}: ${c.from ?? '—'} → ${c.to ?? '—'}'
                        : '${c.field}: changed (value not recorded)',
                    key: ValueKey('audit-change-${c.field}'),
                  ),
              ],
              row('Reference', event.correlationId),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
