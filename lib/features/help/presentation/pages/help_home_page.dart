import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive.dart';
import '../../content/manual_content.dart';
import '../../domain/manual_models.dart';
import '../providers/manual_providers.dart';

/// The manual's front page: search, categories and the guides the signed-in
/// user is allowed to use. Phones get one expandable list; wider screens get a
/// category sidebar beside the guide list.
class HelpHomePage extends ConsumerStatefulWidget {
  const HelpHomePage({super.key});

  @override
  ConsumerState<HelpHomePage> createState() => _HelpHomePageState();
}

class _HelpHomePageState extends ConsumerState<HelpHomePage> {
  final _search = TextEditingController();
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantContextProvider).value;
    if (tenant == null) return const SizedBox.shrink();
    final can = tenant.can;
    final progress =
        ref.watch(manualProgressProvider).value ??
        const <String, ManualProgress>{};
    final visible = manualCatalog.visibleTo(can);
    final query = _search.text.trim();
    final results = query.isEmpty ? null : manualCatalog.search(query, can);
    final categories = [
      for (final c in manualCatalog.categories)
        if (visible.any((g) => g.categoryId == c.id)) c,
    ];

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Search the manual, e.g. "generate invoices"',
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_search.clear),
                ),
        ),
      ),
    );

    Widget guideCard(ManualGuide g) =>
        _GuideCard(guide: g, progress: progress[g.id]);

    Widget list() {
      if (results != null) {
        if (results.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'No guide matches "$query". Try a shorter word such as '
              '"invoice", "parent" or "attendance".',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return Column(children: [for (final g in results) guideCard(g)]);
      }
      final shown = _categoryId == null
          ? categories
          : [
              for (final c in categories)
                if (c.id == _categoryId) c,
            ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in shown) ...[
            _CategoryHeader(category: c),
            for (final g in visible.where((g) => g.categoryId == c.id))
              guideCard(g),
          ],
        ],
      );
    }

    return ResponsiveBuilder(
      builder: (context, size) {
        if (size.isMobile) {
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              searchField,
              if (results != null)
                list()
              else
                for (final c in categories)
                  ExpansionTile(
                    leading: Icon(c.icon),
                    title: Text(c.title),
                    subtitle: Text(c.description),
                    initiallyExpanded: c.id == 'start',
                    children: [
                      for (final g in visible.where(
                        (g) => g.categoryId == c.id,
                      ))
                        guideCard(g),
                    ],
                  ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                children: [
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('All guides'),
                    selected: _categoryId == null,
                    onTap: () => setState(() => _categoryId = null),
                  ),
                  for (final c in categories)
                    ListTile(
                      leading: Icon(c.icon),
                      title: Text(c.title),
                      selected: _categoryId == c.id,
                      onTap: () => setState(() => _categoryId = c.id),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                children: [searchField, list()],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final ManualCategory category;
  const _CategoryHeader({required this.category});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(category.icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              category.title,
              style: text.titleMedium,
              semanticsLabel: category.title,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final ManualGuide guide;
  final ManualProgress? progress;
  const _GuideCard({required this.guide, required this.progress});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = progress != null && progress!.version == guide.version
        ? progress
        : null;
    final total = guide.steps.length;
    final done = p?.completed.length ?? 0;
    final status = done == 0
        ? 'Not started'
        : done >= total
        ? 'Completed'
        : '$done of $total steps';
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(AppRoutes.helpGuidePath(guide.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(guide.title, style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                guide.summary,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  if (total > 0) ...[
                    Text('${guide.minutes} min', style: text.labelMedium),
                    Text('$total steps', style: text.labelMedium),
                  ] else
                    Text('Questions and answers', style: text.labelMedium),
                  if (total > 0)
                    Text(
                      status,
                      style: text.labelMedium?.copyWith(
                        color: done >= total && total > 0
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (done > 0 && done < total) ...[
                const SizedBox(height: AppSpacing.sm),
                LinearProgressIndicator(value: done / total),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
