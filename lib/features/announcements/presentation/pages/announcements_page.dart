import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/family_scope.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../domain/announcement.dart';
import '../providers/announcement_providers.dart';
import '../widgets/current_announcements_card.dart';

/// `/announcements` — what is addressed to the person right now (published,
/// started, not expired), plus recent updates. Managers also see drafts,
/// scheduled, expired and archived ones; nothing is ever deleted.
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final canManage = tenant?.can(Permission.manageAnnouncements) ?? false;
    final isParent = tenant?.role == UserRole.parent;
    return Scaffold(
      appBar: pageAppBar(context, title: const Text('Announcements')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.announcementNew),
              icon: const Icon(Icons.add),
              label: const Text('New announcement'),
            )
          : null,
      body: isParent
          ? FamilyScope(
              builder: (context, tenant, children, child) {
                final branches = {for (final c in children) c.branchId}.toList()
                  ..sort();
                return _AnnouncementList(
                  tenant: tenant,
                  schoolId: tenant.school!.schoolId,
                  branchIds: branches,
                );
              },
            )
          : StaffBranchScope(
              builder: (context, tenant, schoolId, branchId) =>
                  _AnnouncementList(
                    tenant: tenant,
                    schoolId: schoolId,
                    branchIds: [branchId],
                  ),
            ),
    );
  }
}

enum _View {
  current('Current'),
  scheduled('Scheduled'),
  expired('Expired'),
  drafts('Drafts'),
  archived('Archived');

  final String label;
  const _View(this.label);
}

class _AnnouncementList extends ConsumerStatefulWidget {
  final TenantContext tenant;
  final String schoolId;
  final List<String> branchIds;

  const _AnnouncementList({
    required this.tenant,
    required this.schoolId,
    required this.branchIds,
  });

  @override
  ConsumerState<_AnnouncementList> createState() => _AnnouncementListState();
}

class _AnnouncementListState extends ConsumerState<_AnnouncementList> {
  _View _view = _View.current;

  bool get _manages => widget.tenant.can(Permission.manageAnnouncements);

  @override
  Widget build(BuildContext context) {
    final t = widget.tenant;
    final role = t.role.wireValue;
    final vKey = (
      schoolId: widget.schoolId,
      branchIds: widget.branchIds.join(','),
      role: role,
      userId: t.user.userId,
      includeDrafts: _manages,
    );
    final list = ref.watch(visibleAnnouncementsProvider(vKey));
    final viewer = ref.watch(
      announcementViewerProvider((
        schoolId: widget.schoolId,
        branchId: widget.branchIds.first,
        userId: t.user.userId,
        role: role,
        parentId: t.user.linkedParentId,
      )),
    );
    final notices = ref.watch(
      visibleNoticesProvider((
        schoolId: widget.schoolId,
        branchIds: widget.branchIds.join(','),
        role: role,
      )),
    );
    if (list.isLoading || viewer.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.hasError || viewer.hasError) {
      return ErrorView(
        message: userMessageFor((list.error ?? viewer.error)!),
        onRetry: () {
          ref.invalidate(visibleAnnouncementsProvider(vKey));
        },
      );
    }
    final v = viewer.requireValue;
    final all = list.requireValue;
    final now = DateTime.now();
    // Only announcements actually addressed to the person (managers see all
    // of their branch's, in the manager views).
    final addressed = [
      for (final a in all)
        if (AnnouncementVisibility.addressedTo(a, v) ||
            (_manages && (a.authorId == t.user.userId || _isAdmin(t.role))))
          a,
    ];
    List<Announcement> listFor(_View view) => switch (view) {
      _View.current => [
        for (final a in addressed)
          if (a.isCurrent(now)) a,
      ],
      _View.scheduled => [
        for (final a in addressed)
          if (a.status == AnnouncementStatus.published &&
              a.publishAt != null &&
              a.publishAt!.isAfter(now))
            a,
      ],
      _View.expired => [
        for (final a in addressed)
          if (a.status == AnnouncementStatus.published &&
              a.expiresAt != null &&
              !now.isBefore(a.expiresAt!))
            a,
      ],
      _View.drafts => [
        for (final a in addressed)
          if (a.status == AnnouncementStatus.draft) a,
      ],
      _View.archived => [
        for (final a in addressed)
          if (a.status == AnnouncementStatus.archived) a,
      ],
    };
    final shown = listFor(_view);
    shown.sort(
      (a, b) => (b.publishAt ?? b.createdAt ?? DateTime(0)).compareTo(
        a.publishAt ?? a.createdAt ?? DateTime(0),
      ),
    );

    // Updates: notices addressed to the person; an announcement's notice is
    // shown only once that announcement is actually current.
    final currentIds = {
      for (final a in addressed)
        if (a.isCurrent(now)) a.announcementId,
    };
    final recent = [
      for (final n in notices.value ?? const <BroadcastNotice>[])
        if (noticeAddressedTo(n, v) &&
            (n.refType != 'ANNOUNCEMENT' || currentIds.contains(n.refId)))
          n,
    ].take(5).toList();

    return PageColumn(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(visibleAnnouncementsProvider(vKey));
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_manages)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: StatChipsBar(
                  chips: [
                    for (final view in _View.values)
                      StatChip(
                        label: view.label,
                        count: listFor(view).length,
                        selected: _view == view,
                        onTap: () => setState(() => _view = view),
                      ),
                  ],
                ),
              ),
            if (recent.isNotEmpty && _view == _View.current)
              SectionCard(
                title: 'Recent updates',
                child: Column(
                  children: [
                    for (final n in recent)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          n.refType == 'HOMEWORK'
                              ? Icons.menu_book_outlined
                              : Icons.campaign_outlined,
                        ),
                        title: Text(n.title),
                        subtitle: Text(
                          '${n.body ?? ''} · ${formatInstant(n.createdAt)}',
                        ),
                      ),
                  ],
                ),
              ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: EmptyView(
                  icon: Icons.campaign_outlined,
                  message: 'No announcements here.',
                ),
              )
            else
              for (final a in shown)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    title: Text(
                      a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusPill(
                                label:
                                    a.audienceLabel ?? a.audience.displayName,
                                icon: Icons.groups_outlined,
                              ),
                              if (_manages)
                                StatusPill(label: a.status.displayName),
                              Text(formatInstant(a.publishAt ?? a.createdAt)),
                              if (a.expiresAt != null)
                                Text('until ${formatInstant(a.expiresAt)}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(announcementDetailLocation(a)),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  bool _isAdmin(UserRole r) =>
      r == UserRole.schoolAdmin ||
      r == UserRole.branchAdmin ||
      r == UserRole.platformAdmin;
}
