import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/platform_ops_models.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_console_providers.dart';
import '../providers/platform_ops_providers.dart';
import '../widgets/platform_dialogs.dart';
import '../widgets/platform_scaffold.dart';

/// Notices from Avail404 to school administrators (an in-app banner). Owners and
/// support publish and withdraw; every platform role can read the list.
class PlatformNoticesPage extends ConsumerWidget {
  const PlatformNoticesPage({super.key});

  Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ComposeDialog(),
    );
    if (ok == true && context.mounted) {
      context.showSnackBar('Notice published.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(tenantContextProvider).value?.user.platformRole;
    final canPublish =
        role == PlatformRole.owner || role == PlatformRole.support;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    return PlatformScaffold(
      title: 'Notices to schools',
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              key: const ValueKey('notice-new'),
              onPressed: () => _compose(context, ref),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('New notice'),
            )
          : null,
      child: AsyncValueWidget(
        value: ref.watch(platformNoticesProvider),
        errorMessage: userMessageFor,
        onRetry: () => ref.invalidate(platformNoticesProvider),
        data: (list) => list.isEmpty
            ? const EmptyView(
                icon: Icons.campaign_outlined,
                message: 'No notices yet.',
              )
            : PlatformBody(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    96,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final n = list[i];
                    return Card(
                      key: ValueKey('notice-${n.id}'),
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(n.title, style: text.titleSmall),
                                Chip(
                                  label: Text(
                                    n.live
                                        ? 'Live'
                                        : n.status == 'WITHDRAWN'
                                        ? 'Withdrawn'
                                        : 'Not showing',
                                  ),
                                ),
                                Chip(label: Text(n.severity.label)),
                              ],
                            ),
                            Text(n.body),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${n.audienceAll ? 'All school administrators' : '${n.schoolIds.length} school(s)'}'
                              ' · until ${formatInstant(n.endsAt)} · ${n.createdByEmail}',
                              style: text.bodySmall,
                            ),
                            if (canPublish && n.live)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  key: ValueKey('withdraw-${n.id}'),
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          final yes = await confirm(
                                            context,
                                            title: 'Withdraw this notice?',
                                            message:
                                                'It stops showing to school administrators now.',
                                            confirmLabel: 'Withdraw',
                                          );
                                          if (!yes || !context.mounted) return;
                                          final ok = await ref
                                              .read(
                                                platformOpsActionsProvider
                                                    .notifier,
                                              )
                                              .withdrawNotice(n.id);
                                          if (!context.mounted) return;
                                          context.showSnackBar(
                                            ok
                                                ? 'Withdrawn.'
                                                : userMessageFor(
                                                    ref
                                                        .read(
                                                          platformOpsActionsProvider,
                                                        )
                                                        .error!,
                                                  ),
                                            isError: !ok,
                                          );
                                        },
                                  child: const Text('Withdraw'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _ComposeDialog extends ConsumerStatefulWidget {
  const _ComposeDialog();

  @override
  ConsumerState<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends ConsumerState<_ComposeDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  NoticeSeverity _severity = NoticeSeverity.info;
  bool _all = true;
  final Set<String> _schools = {};
  int _days = 3;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_all && _schools.isEmpty) {
      setState(
        () => _error = 'Choose at least one school, or send it to everyone.',
      );
      return;
    }
    setState(() => _error = null);
    final ok = await ref
        .read(platformOpsActionsProvider.notifier)
        .publishNotice(
          title: _title.text,
          body: _body.text,
          severity: _severity,
          audienceAll: _all,
          schoolIds: _schools.toList(),
          endsAt: DateTime.now().add(Duration(days: _days)),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(
        () => _error = userMessageFor(
          ref.read(platformOpsActionsProvider).error!,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final schools = ref.watch(platformSchoolsProvider).value ?? const [];
    return AlertDialog(
      title: const Text('New notice'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('nt-title'),
                  controller: _title,
                  enabled: !busy,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) =>
                      (v ?? '').trim().length < 3 ? 'Write a title' : null,
                ),
                TextFormField(
                  key: const ValueKey('nt-body'),
                  controller: _body,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Message'),
                  validator: (v) =>
                      (v ?? '').trim().length < 3 ? 'Write the message' : null,
                ),
                DropdownButtonFormField<NoticeSeverity>(
                  key: const ValueKey('nt-severity'),
                  value: _severity,
                  decoration: const InputDecoration(labelText: 'Importance'),
                  items: [
                    for (final s in NoticeSeverity.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _severity = v ?? _severity),
                ),
                DropdownButtonFormField<int>(
                  key: const ValueKey('nt-days'),
                  value: _days,
                  decoration: const InputDecoration(labelText: 'Show for'),
                  items: [
                    for (final d in const [1, 3, 7, 14, 30])
                      DropdownMenuItem(
                        value: d,
                        child: Text('$d day${d == 1 ? '' : 's'}'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _days = v ?? _days),
                ),
                SwitchListTile(
                  key: const ValueKey('nt-all'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Every school administrator'),
                  value: _all,
                  onChanged: busy ? null : (v) => setState(() => _all = v),
                ),
                if (!_all)
                  SizedBox(
                    height: 180,
                    child: ListView(
                      children: [
                        for (final s in schools)
                          CheckboxListTile(
                            dense: true,
                            value: _schools.contains(s.id),
                            title: Text(s.name.isEmpty ? s.id : s.name),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _schools.add(s.id)
                                  : _schools.remove(s.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('nt-publish'),
          onPressed: busy ? null : _publish,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Publish'),
        ),
      ],
    );
  }
}
