import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/branding/tenant_branding.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/branding_providers.dart';
import '../widgets/brand_color_editor.dart';
import '../widgets/brand_preview.dart';

/// Settings → School theme: the one theme every user of the school sees (all
/// roles, every branch, every device). Presets or custom colours, a live
/// preview, save, and reset to the platform default. The server checks
/// readability and the rules let only the school's admin (or a platform admin)
/// change it.
class SchoolBrandingPage extends ConsumerStatefulWidget {
  const SchoolBrandingPage({super.key});

  @override
  ConsumerState<SchoolBrandingPage> createState() => _SchoolBrandingPageState();
}

class _SchoolBrandingPageState extends ConsumerState<SchoolBrandingPage> {
  String? _preset;
  BrandColors? _colors;
  BrandingAppearance? _appearance;
  bool _saving = false;
  String? _error;

  void _clear() {
    _preset = null;
    _colors = null;
    _appearance = null;
    _error = null;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      await ref.read(tenantThemeProvider.notifier).refresh();
      if (!mounted) return;
      setState(_clear);
      context.showSnackBar(done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset(String schoolId, int? version) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to the platform default?'),
        content: const Text(
          'Everyone at your school will see the standard EazySchool colours '
          'again. Your logo is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(brandingRepositoryProvider)
          .resetSchool(schoolId: schoolId, baseVersion: version)
          .then((_) {}),
      'School theme reset to the default.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'No school found for your account.',
          );
        }
        if (!tenant!.can(Permission.manageSchool)) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'Only school administrators can change the school theme.',
          );
        }
        final schoolId = tenant.school!.schoolId;
        final platform =
            ref.watch(platformBrandingProvider).value ??
            PlatformBranding.builtIn;
        final async = ref.watch(schoolBrandingConfigProvider(schoolId));
        return AsyncValueWidget(
          value: async,
          errorMessage: userMessageFor,
          onRetry: () => ref.invalidate(schoolBrandingConfigProvider(schoolId)),
          data: (saved) {
            final base = BrandingResolver.resolve(
              schoolId: schoolId,
              school: saved,
              platform: platform,
            );
            final colors = _colors ?? base.colors;
            final preset = _preset ?? base.presetId;
            final appearance = _appearance ?? base.appearance;
            final problems = colors.problems();
            final dirty =
                colors != base.colors ||
                appearance != base.appearance ||
                (saved?.colors == null && _colors != null);
            return SectionPage(
              title: 'School theme',
              description:
                  'The colours everyone at your school sees — teachers, '
                  'parents, finance and every branch — on every device.',
              parentRoute: AppRoutes.settings,
              parentLabel: 'Settings',
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 900;
                    final editor = _Editor(
                      presets: platform.presets,
                      presetId: preset,
                      colors: colors,
                      appearance: appearance,
                      enabled: !_saving,
                      onPreset: (p) => setState(() {
                        _preset = p.id;
                        _colors = p.colors;
                        _error = null;
                      }),
                      onColors: (v) => setState(() {
                        _colors = v;
                        _error = null;
                      }),
                      onAppearance: (v) => setState(() => _appearance = v),
                    );
                    final side = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Preview',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        BrandPreview(colors: colors, appearance: appearance),
                        const SizedBox(height: AppSpacing.md),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => context.go(AppRoutes.school),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text(
                              'Change the logo in School profile',
                            ),
                          ),
                        ),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: editor),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(child: side),
                            ],
                          )
                        else ...[
                          side,
                          const SizedBox(height: AppSpacing.lg),
                          editor,
                        ],
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        if (problems.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: Text(
                              'Fix the highlighted colours so text stays readable, '
                              'then save.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            OutlinedButton(
                              key: const ValueKey('branding-reset'),
                              onPressed:
                                  _saving || (saved?.colors == null && !dirty)
                                  ? null
                                  : () => _reset(schoolId, saved?.version),
                              child: const Text('Reset to default'),
                            ),
                            FilledButton(
                              key: const ValueKey('branding-save'),
                              onPressed:
                                  _saving || !dirty || problems.isNotEmpty
                                  ? null
                                  : () => _run(
                                      () => ref
                                          .read(brandingRepositoryProvider)
                                          .saveSchool(
                                            schoolId: schoolId,
                                            presetId: preset,
                                            colors: colors,
                                            appearance: appearance,
                                            baseVersion: saved?.version ?? 0,
                                          )
                                          .then((_) {}),
                                      'School theme saved for everyone at your school.',
                                    ),
                              child: Text(_saving ? 'Saving…' : 'Save theme'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Editor extends StatelessWidget {
  final List<BrandPreset> presets;
  final String presetId;
  final BrandColors colors;
  final BrandingAppearance appearance;
  final bool enabled;
  final ValueChanged<BrandPreset> onPreset;
  final ValueChanged<BrandColors> onColors;
  final ValueChanged<BrandingAppearance> onAppearance;

  const _Editor({
    required this.presets,
    required this.presetId,
    required this.colors,
    required this.appearance,
    required this.enabled,
    required this.onPreset,
    required this.onColors,
    required this.onAppearance,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final matching = presets.any((p) => p.colors == colors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Preset', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final p in presets)
              ChoiceChip(
                key: ValueKey('preset-${p.id}'),
                avatar: CircleAvatar(
                  backgroundColor: p.colors.primary,
                  radius: 9,
                ),
                label: Text(p.label),
                selected: p.colors == colors,
                onSelected: enabled ? (_) => onPreset(p) : null,
              ),
            if (!matching)
              Chip(
                avatar: Icon(Icons.tune, size: 16, color: scheme.primary),
                label: const Text('Custom'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Appearance', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<BrandingAppearance>(
          segments: [
            for (final a in BrandingAppearance.values)
              ButtonSegment(value: a, label: Text(a.label)),
          ],
          selected: {appearance},
          onSelectionChanged: enabled ? (s) => onAppearance(s.first) : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Colours', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Status colours (paid, due, overdue, error) are fixed so they always '
          'mean the same thing.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        BrandColorEditor(colors: colors, onChanged: onColors, enabled: enabled),
      ],
    );
  }
}
