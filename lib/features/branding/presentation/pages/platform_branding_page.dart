import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Settings → Platform branding (platform admins only): the default theme for
/// schools that have not set their own, and the custom presets every school
/// can pick. A school's own theme always wins over the default.
class PlatformBrandingPage extends ConsumerStatefulWidget {
  /// Where the back link goes. Inside the school app that is Settings; on the
  /// platform home (a platform admin has no school) it is the platform home.
  final String parentRoute;
  final String parentLabel;

  const PlatformBrandingPage({
    super.key,
    this.parentRoute = AppRoutes.settings,
    this.parentLabel = 'Settings',
  });

  @override
  ConsumerState<PlatformBrandingPage> createState() =>
      _PlatformBrandingPageState();
}

class _PlatformBrandingPageState extends ConsumerState<PlatformBrandingPage> {
  String? _default;
  List<BrandPreset>? _custom;
  bool _saving = false;
  String? _error;

  /// A preset id from a label: lower-case letters, digits and `_`, 2-24 long,
  /// starting with a letter, and not already taken.
  static String idFor(String label, Iterable<String> taken) {
    var base = label.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    base = base.replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty || !RegExp('^[a-z]').hasMatch(base)) base = 'p_$base';
    if (base.length > 20) base = base.substring(0, 20);
    var id = base;
    var n = 2;
    while (id.length < 2 || taken.contains(id)) {
      id = '${base}_$n';
      n++;
    }
    return id;
  }

  Future<void> _edit(
    List<BrandPreset> current,
    BrandPreset? existing,
    PlatformBranding saved,
  ) async {
    final result = await showDialog<({String label, BrandColors colors})>(
      context: context,
      builder: (_) => _PresetDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final all = [...BrandPresets.builtIn, ...current];
    setState(() {
      final list = [...current];
      if (existing == null) {
        list.add(
          BrandPreset(
            idFor(result.label, all.map((p) => p.id)),
            result.label,
            result.colors,
          ),
        );
      } else {
        final i = list.indexWhere((p) => p.id == existing.id);
        list[i] = BrandPreset(existing.id, result.label, result.colors);
      }
      _custom = list;
      _error = null;
    });
  }

  Future<void> _save(
    PlatformBranding saved,
    String def,
    List<BrandPreset> custom,
  ) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(brandingRepositoryProvider)
          .savePlatform(
            PlatformBranding(
              version: saved.version,
              defaultPreset: def,
              customPresets: custom,
            ),
          );
      if (!mounted) return;
      setState(() {
        _default = null;
        _custom = null;
      });
      context.showSnackBar('Platform branding saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant == null || !tenant.can(Permission.managePlatform)) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message:
                'Only platform administrators can change platform branding.',
          );
        }
        final async = ref.watch(platformBrandingProvider);
        return AsyncValueWidget(
          value: async,
          errorMessage: userMessageFor,
          onRetry: () => ref.invalidate(platformBrandingProvider),
          data: (saved) {
            final custom = _custom ?? saved.customPresets;
            final merged = PlatformBranding(
              version: saved.version,
              defaultPreset: _default ?? saved.defaultPreset,
              customPresets: custom,
            );
            final all = merged.presets;
            final def = all.any((p) => p.id == merged.defaultPreset)
                ? merged.defaultPreset
                : BrandPresets.defaultId;
            final dirty =
                def != saved.defaultPreset ||
                custom.length != saved.customPresets.length ||
                [for (final p in custom) '${p.id}${p.label}${p.colors.toMap()}']
                        .join() !=
                    [
                      for (final p in saved.customPresets)
                        '${p.id}${p.label}${p.colors.toMap()}',
                    ].join();
            final text = Theme.of(context).textTheme;
            return SectionPage(
              title: 'Platform branding',
              description:
                  'The default theme for schools that have not set their own, '
                  'and the presets every school can choose from.',
              parentRoute: widget.parentRoute,
              parentLabel: widget.parentLabel,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Default for new schools', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('platform-default-preset'),
                      value: def,
                      decoration: const InputDecoration(
                        labelText: 'Default preset',
                      ),
                      items: [
                        for (final p in all)
                          DropdownMenuItem(value: p.id, child: Text(p.label)),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _default = v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    BrandPreview(
                      colors: merged.presetById(def).colors,
                      appearance: BrandingAppearance.light,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Custom presets',
                            style: text.titleMedium,
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('platform-add-preset'),
                          onPressed: _saving
                              ? null
                              : () => _edit(custom, null, saved),
                          icon: const Icon(Icons.add),
                          label: const Text('Add preset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (custom.isEmpty)
                      Text(
                        'No custom presets yet. The built-in presets '
                        '(${BrandPresets.builtIn.map((p) => p.label).join(', ')}) '
                        'are always available.',
                        style: text.bodySmall,
                      ),
                    for (final p in custom)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: p.colors.primary,
                          ),
                          title: Text(p.label),
                          subtitle: Text(p.id),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Edit ${p.label}',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: _saving
                                    ? null
                                    : () => _edit(custom, p, saved),
                              ),
                              IconButton(
                                tooltip: 'Remove ${p.label}',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _saving || p.id == def
                                    ? null
                                    : () => setState(
                                        () => _custom = [
                                          for (final q in custom)
                                            if (q.id != p.id) q,
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const ValueKey('platform-save'),
                        onPressed: _saving || !dirty
                            ? null
                            : () => _save(saved, def, custom),
                        child: Text(_saving ? 'Saving…' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PresetDialog extends StatefulWidget {
  final BrandPreset? existing;
  const _PresetDialog({this.existing});

  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late BrandColors _colors = widget.existing?.colors ?? BrandColors.emerald;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _label.text.trim().isNotEmpty && _colors.isReadable;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add preset' : 'Edit preset'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('preset-label'),
                controller: _label,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              BrandColorEditor(
                colors: _colors,
                onChanged: (c) => setState(() => _colors = c),
              ),
              BrandPreview(
                colors: _colors,
                appearance: BrandingAppearance.light,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('preset-ok'),
          onPressed: ok
              ? () => Navigator.of(
                  context,
                ).pop((label: _label.text.trim(), colors: _colors))
              : null,
          child: const Text('Use preset'),
        ),
      ],
    );
  }
}
