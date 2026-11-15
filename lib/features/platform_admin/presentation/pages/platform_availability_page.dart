import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../domain/platform_ops_models.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_ops_providers.dart';
import '../widgets/platform_scaffold.dart';

/// Maintenance mode and the oldest app build still allowed. Owner only.
/// Maintenance blocks school users (never platform admins, so it can be lifted);
/// a minimum build forces old Android/iOS builds to update.
class PlatformAvailabilityPage extends ConsumerWidget {
  const PlatformAvailabilityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner =
        ref.watch(tenantContextProvider).value?.user.platformRole ==
        PlatformRole.owner;
    final req =
        ref.watch(appRequirementsProvider).value ?? AppRequirements.none;
    return PlatformScaffold(
      title: 'App availability',
      child: !owner
          ? const EmptyView(
              icon: Icons.lock_outline,
              message: 'Only a platform owner can change this.',
            )
          : _Form(
              key: ValueKey(
                '${req.minBuildAndroid}-${req.minBuildIos}-${req.maintenanceOn}',
              ),
              current: req,
            ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  final AppRequirements current;

  const _Form({super.key, required this.current});

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _form = GlobalKey<FormState>();
  late final _android = TextEditingController(
    text: '${widget.current.minBuildAndroid}',
  );
  late final _ios = TextEditingController(
    text: '${widget.current.minBuildIos}',
  );
  late final _message = TextEditingController(
    text: widget.current.maintenanceMessage,
  );
  late bool _on = widget.current.maintenanceOn;
  int _hours = 2;
  String? _error;

  @override
  void dispose() {
    _android.dispose();
    _ios.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final ok = await ref
        .read(platformOpsActionsProvider.notifier)
        .setAppRequirements(
          minBuildAndroid: int.parse(_android.text.trim()),
          minBuildIos: int.parse(_ios.text.trim()),
          maintenanceOn: _on,
          message: _message.text,
          until: _on && _hours > 0
              ? DateTime.now().add(Duration(hours: _hours))
              : null,
        );
    if (!mounted) return;
    if (ok) {
      context.showSnackBar('Saved.');
    } else {
      setState(
        () => _error = userMessageFor(
          ref.read(platformOpsActionsProvider).error!,
        ),
      );
    }
  }

  String? _build(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < 0 ? 'Enter a whole number (0 = no minimum)' : null;
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    return PlatformBody(
      maxWidth: 640,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('Maintenance mode', style: text.titleMedium),
            SwitchListTile(
              key: const ValueKey('av-maintenance'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause the app for schools'),
              subtitle: const Text(
                'Staff and parents see your message instead of the app. Platform admins are not affected.',
              ),
              value: _on,
              onChanged: busy ? null : (v) => setState(() => _on = v),
            ),
            if (_on) ...[
              TextFormField(
                key: const ValueKey('av-message'),
                controller: _message,
                enabled: !busy,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Message people will see',
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Write the message' : null,
              ),
              DropdownButtonFormField<int>(
                key: const ValueKey('av-hours'),
                value: _hours,
                decoration: const InputDecoration(
                  labelText: 'Ends automatically after',
                ),
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text('Only when I switch it off'),
                  ),
                  for (final h in const [1, 2, 4, 12, 24])
                    DropdownMenuItem(
                      value: h,
                      child: Text('$h hour${h == 1 ? '' : 's'}'),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => _hours = v ?? _hours),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text('Minimum app version', style: text.titleMedium),
            Text(
              'Builds older than this must update before they can be used. Use the build number '
              '(the number in brackets in the app footer). 0 = no minimum. The web app is always current.',
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('av-android'),
                    controller: _android,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Android build',
                    ),
                    validator: _build,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('av-ios'),
                    controller: _ios,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'iOS build'),
                    validator: _build,
                  ),
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
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('av-save'),
                onPressed: busy ? null : _save,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
