import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/providers/homework_providers.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../domain/announcement.dart';
import '../widgets/current_announcements_card.dart';

/// `/announcements/detail/:announcementId?branchId=…`
class AnnouncementDetailPage extends ConsumerStatefulWidget {
  final String announcementId;
  final String? branchId;

  const AnnouncementDetailPage({
    super.key,
    required this.announcementId,
    this.branchId,
  });

  @override
  ConsumerState<AnnouncementDetailPage> createState() =>
      _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState
    extends ConsumerState<AnnouncementDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantContextProvider).value;
    final schoolId = tenant?.school?.schoolId;
    final branchId =
        widget.branchId ?? tenant?.user.branchId ?? tenant?.branch?.branchId;
    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: tenant == null || schoolId == null || branchId == null
          ? const EmptyView(message: 'No school found for your account.')
          : _content(tenant, schoolId, branchId),
    );
  }

  Widget _content(TenantContext tenant, String schoolId, String branchId) {
    final key = (
      schoolId: schoolId,
      branchId: branchId,
      announcementId: widget.announcementId,
    );
    final a = ref.watch(announcementProvider(key));
    return a.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(announcementProvider(key)),
      ),
      data: (a) {
        if (a == null) {
          return const EmptyView(
            icon: Icons.search_off,
            message: 'This announcement could not be found.',
          );
        }
        final isAdmin =
            tenant.role == UserRole.schoolAdmin ||
            tenant.role == UserRole.branchAdmin ||
            tenant.role == UserRole.platformAdmin;
        final canManage =
            tenant.can(Permission.manageAnnouncements) &&
            (isAdmin || a.authorId == tenant.user.userId);
        final repo = ref.read(announcementRepositoryProvider);
        final actor = actorFor(tenant);
        return PageColumn(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  StatusPill(label: a.status.displayName),
                  StatusPill(
                    label: a.audienceLabel ?? a.audience.displayName,
                    icon: Icons.groups_outlined,
                  ),
                  if (a.isExpired)
                    StatusPill(
                      label: 'Expired',
                      color: Theme.of(context).colorScheme.outline,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${a.authorName} · ${formatInstant(a.publishAt ?? a.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SelectableText(a.body),
                    if (a.attachments.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      AttachmentList(attachments: a.attachments),
                    ],
                    if (a.expiresAt != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text('Expires ${formatInstant(a.expiresAt)}'),
                    ],
                  ],
                ),
              ),
              if (canManage && a.status != AnnouncementStatus.archived)
                SectionCard(
                  title: 'Actions',
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => context.go(announcementEditLocation(a)),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                      if (a.status == AnnouncementStatus.draft)
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final problem = a.validate(
                                    now: DateTime.now(),
                                  );
                                  if (problem != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(problem)),
                                    );
                                    return;
                                  }
                                  await _run(
                                    () => repo.publish(
                                      a,
                                      publishAt: a.publishAt ?? DateTime.now(),
                                      actor: actor,
                                    ),
                                    'Announcement published.',
                                  );
                                },
                          icon: const Icon(Icons.campaign),
                          label: const Text('Publish'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text(
                                      'Archive this announcement?',
                                    ),
                                    content: const Text(
                                      'It stops showing to its audience and '
                                      'is kept in history.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text('Archive'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                await _run(
                                  () => repo.archive(a, actor: actor),
                                  'Announcement archived.',
                                );
                              },
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Archive'),
                      ),
                      if (_busy)
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
                ),
              if (canManage)
                SectionCard(
                  title: 'Record',
                  child: Text(
                    'Created ${formatInstant(a.createdAt)}'
                    '${a.publishedAt == null ? '' : '\nPublished ${formatInstant(a.publishedAt)}'}'
                    '${a.updatedAt == null ? '' : '\nLast changed ${formatInstant(a.updatedAt)}'}'
                    '\nRevision ${a.revision}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
