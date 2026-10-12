import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../providers/homework_providers.dart';
import '../widgets/homework_widgets.dart';
import 'homework_form_page.dart';

/// `/homework/detail/:homeworkId` — the homework as families see it, its
/// state, submission counts, history, and the actions the person may take.
class HomeworkDetailPage extends ConsumerStatefulWidget {
  final String homeworkId;

  const HomeworkDetailPage({super.key, required this.homeworkId});

  @override
  ConsumerState<HomeworkDetailPage> createState() => _HomeworkDetailPageState();
}

class _HomeworkDetailPageState extends ConsumerState<HomeworkDetailPage> {
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

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Homework')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) {
          final key = (
            schoolId: schoolId,
            branchId: branchId,
            homeworkId: widget.homeworkId,
          );
          return AsyncValueWidget(
            value: ref.watch(homeworkProvider(key)),
            errorMessage: userMessageFor,
            onRetry: () => ref.invalidate(homeworkProvider(key)),
            data: (h) {
              if (h == null) {
                return const EmptyView(
                  icon: Icons.search_off,
                  message: 'This homework could not be found.',
                );
              }
              return _content(tenant, h, key);
            },
          );
        },
      ),
    );
  }

  Widget _content(TenantContext tenant, Homework h, HomeworkKey key) {
    final canManage = tenant.can(Permission.manageHomework);
    final canReview = tenant.can(Permission.reviewSubmissions);
    final actor = actorFor(tenant);
    final repo = ref.read(homeworkRepositoryProvider);
    final history = ref.watch(homeworkHistoryProvider(key));
    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              HomeworkStatusPill(h.status),
              const SizedBox(width: AppSpacing.sm),
              if (h.status == HomeworkStatus.draft)
                const Expanded(child: Text('Families cannot see this yet.')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          HomeworkContent(homework: h),
          if (h.status == HomeworkStatus.published ||
              h.status == HomeworkStatus.closed)
            _Counts(homeworkKey: key, homework: h, canReview: canReview),
          if (canManage)
            SectionCard(
              title: 'Actions',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (h.status == HomeworkStatus.draft ||
                      h.status == HomeworkStatus.published)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => context.go(
                              AppRoutes.homeworkEdit.replaceFirst(
                                ':homeworkId',
                                h.homeworkId,
                              ),
                            ),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        h.status == HomeworkStatus.draft
                            ? 'Edit draft'
                            : 'Edit / extend deadline',
                      ),
                    ),
                  if (h.status == HomeworkStatus.draft)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) =>
                                      HomeworkPreviewScreen(homework: [h]),
                                ),
                              );
                              if (ok != true || !mounted) return;
                              await _run(
                                () => repo.publish(homework: h, actor: actor),
                                'Homework published.',
                              );
                            },
                      icon: const Icon(Icons.public),
                      label: const Text('Preview & publish'),
                    ),
                  if (h.status == HomeworkStatus.published)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (!await _confirm(
                                'Close this homework?',
                                'Families can no longer submit. You can '
                                    'still review and grade what was handed in.',
                                'Close',
                              )) {
                                return;
                              }
                              await _run(
                                () => repo.close(homework: h, actor: actor),
                                'Homework closed.',
                              );
                            },
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Close'),
                    ),
                  if (h.status == HomeworkStatus.draft ||
                      h.status == HomeworkStatus.closed)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (!await _confirm(
                                'Archive this homework?',
                                'It is kept in history but leaves the active '
                                    'lists. This cannot be undone.',
                                'Archive',
                              )) {
                                return;
                              }
                              await _run(
                                () => repo.archive(homework: h, actor: actor),
                                'Homework archived.',
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
          SectionCard(
            title: 'History',
            child: history.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (entries) => entries.isEmpty
                  ? const Text('No history yet.')
                  : Column(
                      children: [
                        for (final e in entries.reversed)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history, size: 20),
                            title: Text(
                              '${e.event.wireValue.replaceAll('_', ' ').toLowerCase()} → '
                              '${e.toStatus.displayName}',
                            ),
                            subtitle: Text(
                              '${e.actorName} · ${formatInstant(e.at)}',
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Counts extends ConsumerWidget {
  final HomeworkKey homeworkKey;
  final Homework homework;
  final bool canReview;

  const _Counts({
    required this.homeworkKey,
    required this.homework,
    required this.canReview,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!homework.requiresSubmission) return const SizedBox.shrink();
    final counts = ref.watch(submissionCountsProvider(homeworkKey));
    return SectionCard(
      title: 'Submissions',
      actions: [
        if (canReview)
          TextButton.icon(
            onPressed: () => context.go(
              AppRoutes.homeworkReview.replaceFirst(
                ':homeworkId',
                homework.homeworkId,
              ),
            ),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Review'),
          ),
      ],
      child: counts.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => ErrorView(
          message: userMessageFor(e),
          onRetry: () => ref.invalidate(submissionCountsProvider(homeworkKey)),
        ),
        data: (c) => Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            CountTile(
              label: 'Handed in',
              value: c.submitted,
              icon: Icons.upload_file,
            ),
            CountTile(label: 'Late', value: c.late, icon: Icons.schedule),
            CountTile(
              label: 'To review',
              value: c.awaitingReview,
              icon: Icons.rate_review_outlined,
            ),
            CountTile(label: 'Returned', value: c.returned, icon: Icons.undo),
            CountTile(
              label: 'Graded',
              value: c.graded,
              icon: Icons.check_circle_outline,
            ),
          ],
        ),
      ),
    );
  }
}
