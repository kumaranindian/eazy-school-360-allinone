import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../../core/constants/activation_status.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../domain/parent.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/parent_providers.dart';
import '../widgets/parents/parents_ui.dart';
import '../widgets/parent_form_dialog.dart';
import '../widgets/person_photo_picker.dart';

/// Parent profile (brief §21-22): contact details, every linked child
/// (brief §22 — a parent may have several, each keeping its own academic/
/// attendance/fee/leave/homework records independently), and portal-
/// access status.
class ParentProfilePage extends ConsumerWidget {
  final String parentId;

  const ParentProfilePage({super.key, required this.parentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.person_outline,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageStudentData);
        final key = (
          schoolId: schoolId,
          branchId: branchId,
          parentId: parentId,
        );
        final parentAsync = ref.watch(parentProvider(key));

        return AsyncValueWidget(
          value: parentAsync,
          data: (parent) {
            if (parent == null) {
              return const EmptyView(
                icon: Icons.person_off_outlined,
                message: 'This parent could not be found.',
              );
            }
            final childrenAsync = ref.watch(
              childrenForParentProvider((
                schoolId: schoolId,
                parentId: parentId,
                branchId: branchId,
              )),
            );

            final p = AdminDashboardPalette.of(context);
            final active = parent.status == ActivationStatus.active;
            final address = [
              parent.addressLine1,
              parent.city,
            ].whereType<String>().join(', ');

            return Scaffold(
              backgroundColor: p.background,
              body: SafeArea(
                child: Column(
                  children: [
                    ParentsPageBar(
                      title: parent.displayName,
                      onBack: () => context.canPop()
                          ? context.pop()
                          : context.go('/parents'),
                      trailing: canManage
                          ? IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit',
                              onPressed: () =>
                                  showAdaptiveAppDialog<ParentFormResult>(
                                    context: context,
                                    builder: (context) => ParentFormDialog(
                                      schoolId: schoolId,
                                      branchId: branchId,
                                      currentUserId: tenant.user.userId,
                                      existing: parent,
                                    ),
                                  ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 960),
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final wide = box.maxWidth >= 720;
                                final left = _leftColumn(
                                  context,
                                  ref,
                                  parent: parent,
                                  active: active,
                                  address: address,
                                  schoolId: schoolId,
                                  branchId: branchId,
                                  canManage: canManage,
                                  userId: tenant.user.userId,
                                );
                                final right = _rightColumn(
                                  context,
                                  parent: parent,
                                  childrenAsync: childrenAsync,
                                  canManage: canManage,
                                );
                                if (!wide) {
                                  return Column(
                                    children: [
                                      ...left,
                                      const SizedBox(height: 16),
                                      ...right,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: Column(children: left)),
                                    const SizedBox(width: 16),
                                    Expanded(child: Column(children: right)),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
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

  List<Widget> _leftColumn(
    BuildContext context,
    WidgetRef ref, {
    required Parent parent,
    required bool active,
    required String address,
    required String schoolId,
    required String branchId,
    required bool canManage,
    required String userId,
  }) {
    final theme = Theme.of(context);
    return [
      ParentsCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: PersonPhotoPicker(
                      photoUrl: parent.photoUrl,
                      isUploading: ref
                          .watch(parentWriteControllerProvider)
                          .isLoading,
                      readError: () =>
                          ref.read(parentWriteControllerProvider).error,
                      onUpload: canManage
                          ? (bytes, extension) => ref
                                .read(parentWriteControllerProvider.notifier)
                                .uploadPhoto(
                                  schoolId: schoolId,
                                  branchId: branchId,
                                  parentId: parentId,
                                  fileBytes: bytes,
                                  fileExtension: extension,
                                  updatedBy: userId,
                                )
                          : (_, __) async => false,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        parent.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ParentsBadge(
                        active ? 'Active' : 'Inactive',
                        tone: active
                            ? ParentsTone.success
                            : ParentsTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Parent / Guardian', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ParentsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ParentsSectionTitle(
              icon: Icons.contact_phone_outlined,
              title: 'Contact details',
            ),
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(label: 'Phone', value: parent.phone),
            if (parent.alternatePhone != null)
              _InfoRow(label: 'Alternate phone', value: parent.alternatePhone!),
            if (parent.email != null)
              _InfoRow(label: 'Email', value: parent.email!),
            if (parent.occupation != null)
              _InfoRow(label: 'Occupation', value: parent.occupation!),
            if (parent.addressLine1 != null)
              _InfoRow(label: 'Address', value: address),
          ],
        ),
      ),
    ];
  }

  List<Widget> _rightColumn(
    BuildContext context, {
    required Parent parent,
    required AsyncValue<List<Student>> childrenAsync,
    required bool canManage,
  }) {
    final theme = Theme.of(context);
    return [
      ParentsCard(
        onTap: canManage
            ? () => context.push(
                '/parents/$parentId/login-access',
                extra: parent.displayName,
              )
            : null,
        semanticLabel: 'Portal access',
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ParentsSectionTitle(
                    icon: Icons.lock_open_outlined,
                    title: 'Portal access',
                  ),
                  const SizedBox(height: 6),
                  ParentsBadge(
                    parent.hasPortalAccess ? 'Enabled' : 'Not set up',
                    tone: parent.hasPortalAccess
                        ? ParentsTone.success
                        : ParentsTone.warning,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    parent.hasPortalAccess
                        ? 'This parent has a linked login account.'
                        : 'No login account linked yet. Portal access is granted from Users management once an account exists for this parent.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (canManage) const Icon(Icons.chevron_right),
          ],
        ),
      ),
      const SizedBox(height: 16),
      AsyncValueWidget(
        value: childrenAsync,
        data: (children) => ParentsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ParentsSectionTitle(
                icon: Icons.groups_outlined,
                title: 'Children (${children.length})',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (children.isEmpty)
                const EmptyView(
                  icon: Icons.groups_outlined,
                  message: 'No students linked to this parent yet.',
                )
              else
                for (final student in children)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ParentsChildCard(
                      name: student.displayName,
                      photoUrl: student.photoUrl,
                      admissionNumber: student.admissionNumber,
                      statusLabel: student.status.displayName,
                      active: student.status == StudentStatus.active,
                      onTap: () =>
                          context.push('/students/${student.studentId}'),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Text(value),
        ],
      ),
    );
  }
}
