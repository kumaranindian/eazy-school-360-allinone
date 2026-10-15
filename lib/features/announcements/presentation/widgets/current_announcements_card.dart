import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../students/domain/student.dart';
import '../../domain/announcement.dart';
import '../providers/announcement_providers.dart';

/// The newest current announcements addressed to a parent's children — a
/// compact card for the parent's homework page and dashboard.
class CurrentAnnouncementsCard extends ConsumerWidget {
  final List<Student> children;
  final int limit;

  const CurrentAnnouncementsCard({
    super.key,
    required this.children,
    this.limit = 3,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final schoolId = tenant?.school?.schoolId;
    if (tenant == null || schoolId == null || children.isEmpty) {
      return const SizedBox.shrink();
    }
    final branches = {for (final c in children) c.branchId}.toList()..sort();
    final viewer = ref.watch(
      announcementViewerProvider((
        schoolId: schoolId,
        branchId: branches.first,
        userId: tenant.user.userId,
        role: tenant.role.wireValue,
        parentId: tenant.user.linkedParentId,
      )),
    );
    final list = ref.watch(
      visibleAnnouncementsProvider((
        schoolId: schoolId,
        branchIds: branches.join(','),
        role: tenant.role.wireValue,
        userId: tenant.user.userId,
        parentId: tenant.user.linkedParentId,
        includeDrafts: false,
      )),
    );
    final v = viewer.value;
    final all = list.value;
    if (v == null || all == null) return const SizedBox.shrink();
    final current = AnnouncementVisibility.currentFor(
      all,
      v,
      DateTime.now(),
    ).take(limit).toList();
    if (current.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: 'Announcements',
      actions: [
        TextButton(
          onPressed: () => context.go(AppRoutes.announcements),
          child: const Text('All'),
        ),
      ],
      child: Column(
        children: [
          for (final a in current)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.campaign_outlined),
              title: Text(a.title, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                a.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => context.go(announcementDetailLocation(a)),
            ),
        ],
      ),
    );
  }
}

/// `/announcements/detail/:id?branchId=…` — the branch is part of the link
/// because announcements live under their branch.
String announcementDetailLocation(Announcement a) =>
    '${AppRoutes.announcementDetail.replaceFirst(':announcementId', a.announcementId)}'
    '?branchId=${a.branchId}';

String announcementEditLocation(Announcement a) =>
    '${AppRoutes.announcementEdit.replaceFirst(':announcementId', a.announcementId)}'
    '?branchId=${a.branchId}';
