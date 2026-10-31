import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../content/manual_content.dart';
import '../../domain/manual_models.dart';
import '../providers/manual_providers.dart';

/// One guide as a step-by-step walkthrough with saved progress.
///
/// Marking a step done only saves progress; nothing here ever performs an
/// action in the school's data. The "open screen" buttons just navigate.
class ManualGuidePage extends ConsumerStatefulWidget {
  final String guideId;
  const ManualGuidePage({super.key, required this.guideId});

  @override
  ConsumerState<ManualGuidePage> createState() => _ManualGuidePageState();
}

class _ManualGuidePageState extends ConsumerState<ManualGuidePage> {
  int? _current;

  Future<void> _save(
    String userId,
    ManualGuide guide,
    Set<int> completed,
    int lastStep,
  ) async {
    try {
      await ref
          .read(manualProgressRepositoryProvider)
          .save(
            userId,
            ManualProgress(
              guideId: guide.id,
              version: guide.version,
              completed: completed,
              lastStep: lastStep,
            ),
          );
    } catch (error) {
      if (mounted) {
        context.showSnackBar(
          'Could not save your progress: ${userMessageFor(error)}',
          isError: true,
        );
      }
    }
  }

  Future<void> _restart(String userId, ManualGuide guide) async {
    setState(() => _current = 0);
    try {
      await ref.read(manualProgressRepositoryProvider).reset(userId, guide.id);
    } catch (error) {
      if (mounted) {
        context.showSnackBar(
          'Could not restart the guide: ${userMessageFor(error)}',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantContextProvider).value;
    final guide = manualCatalog.byId(widget.guideId);
    if (tenant == null) return const SizedBox.shrink();
    if (guide == null ||
        !manualCatalog.visibleTo(tenant.can).any((g) => g.id == guide.id)) {
      return const EmptyView(
        icon: Icons.menu_book_outlined,
        message: 'This guide is not available for your role.',
      );
    }
    if (guide.steps.isEmpty) {
      return _ReferencePage(guide: guide, canSee: tenant.can);
    }
    final userId = tenant.user.userId;
    final saved = ref.watch(manualProgressProvider).value?[guide.id];
    final valid = saved != null && saved.version == guide.version;
    final completed = valid ? saved.completed : const <int>{};
    final total = guide.steps.length;
    final current = (_current ?? (valid ? saved.lastStep : 0)).clamp(
      0,
      total - 1,
    );
    final step = guide.steps[current];
    final isDone = completed.contains(current);
    final finished = completed.length >= total;

    void goTo(int i) {
      setState(() => _current = i);
      _save(userId, guide, completed, i);
    }

    void toggle() {
      final next = {...completed};
      isDone ? next.remove(current) : next.add(current);
      _save(userId, guide, next, current);
    }

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget progressBar() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          finished
              ? 'Guide completed'
              : 'Step ${current + 1} of $total · ${completed.length} completed',
          style: text.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        LinearProgressIndicator(value: completed.length / total),
      ],
    );

    Widget stepList({bool dense = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < total; i++)
          ListTile(
            dense: dense,
            selected: i == current,
            leading: Icon(
              completed.contains(i)
                  ? Icons.check_circle
                  : i == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(guide.steps[i].title),
            onTap: () => goTo(i),
          ),
      ],
    );

    final canOpen =
        step.route != null &&
        (AppRoutes.requiredPermissions[step.route] == null ||
            tenant.can(AppRoutes.requiredPermissions[step.route]!));

    final main = <Widget>[
      if (guide.prerequisites.isNotEmpty)
        Card(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Before you start',
                        style: text.titleSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final p in guide.prerequisites)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '• $p',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      progressBar(),
      const SizedBox(height: AppSpacing.md),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step ${current + 1} – ${step.title}',
                style: text.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(step.instruction, style: text.bodyLarge),
              if (step.check != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Callout(
                  icon: Icons.fact_check_outlined,
                  label: 'Check',
                  body: step.check!,
                  background: scheme.primaryContainer,
                  foreground: scheme.onPrimaryContainer,
                ),
              ],
              if (step.mistake != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _Callout(
                  icon: Icons.error_outline,
                  label: 'Common mistake',
                  body: step.mistake!,
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (canOpen)
                    OutlinedButton.icon(
                      onPressed: () => context.go(step.route!),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(step.actionLabel ?? 'Open screen'),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: toggle,
                    icon: Icon(
                      isDone ? Icons.undo : Icons.check_circle_outline,
                    ),
                    label: Text(isDone ? 'Mark as not done' : 'Mark as done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          OutlinedButton.icon(
            onPressed: current == 0 ? null : () => goTo(current - 1),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Previous'),
          ),
          FilledButton.icon(
            onPressed: current >= total - 1 ? null : () => goTo(current + 1),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next'),
          ),
        ],
      ),
      if (finished || completed.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _restart(userId, guide),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restart this guide'),
          ),
        ),
      ],
      if (guide.troubleshooting.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text('Troubleshooting', style: text.titleMedium),
        for (final t in guide.troubleshooting)
          ExpansionTile(
            title: Text(t.problem),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            expandedAlignment: Alignment.centerLeft,
            children: [Text(t.solution)],
          ),
      ],
      if (guide.related.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text('Related guides', style: text.titleMedium),
        for (final id in guide.related)
          if (manualCatalog.byId(id) != null &&
              manualCatalog.visibleTo(tenant.can).any((g) => g.id == id))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(manualCatalog.byId(id)!.title),
              onTap: () => context.go(AppRoutes.helpGuidePath(id)),
            ),
      ],
      const SizedBox(height: AppSpacing.xl),
    ];

    return SectionPage(
      title: guide.title,
      description: '${guide.minutes} min · $total steps',
      parentRoute: AppRoutes.help,
      parentLabel: 'Help',
      child: ResponsiveBuilder(
        builder: (context, size) {
          if (size.isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: main,
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 320,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text('Steps', style: text.titleSmall),
                      ),
                      stepList(),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ExpansionTile(
                leading: const Icon(Icons.list_alt_outlined),
                title: const Text('All steps'),
                children: [stepList(dense: true)],
              ),
              ...main,
            ],
          );
        },
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final String label;
  final String body;
  final Color background;
  final Color foreground;

  const _Callout({
    required this.icon,
    required this.label,
    required this.body,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: body),
                ],
              ),
              style: text.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// A guide with no steps: questions and answers only (FAQ, troubleshooting).
class _ReferencePage extends StatelessWidget {
  final ManualGuide guide;
  final bool Function(Permission) canSee;
  const _ReferencePage({required this.guide, required this.canSee});

  @override
  Widget build(BuildContext context) {
    return SectionPage(
      title: guide.title,
      description: guide.summary,
      parentRoute: AppRoutes.help,
      parentLabel: 'Help',
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (final t in guide.troubleshooting)
            ExpansionTile(
              title: Text(t.problem),
              childrenPadding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              expandedAlignment: Alignment.centerLeft,
              children: [Text(t.solution)],
            ),
          for (final id in guide.related)
            if (manualCatalog.byId(id) != null &&
                manualCatalog.visibleTo(canSee).any((g) => g.id == id))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(manualCatalog.byId(id)!.title),
                onTap: () => context.go(AppRoutes.helpGuidePath(id)),
              ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
