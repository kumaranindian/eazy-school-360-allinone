import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/parent_providers.dart';
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

            return Scaffold(
              appBar: AppBar(
                title: Text(parent.displayName),
                actions: canManage
                    ? [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () => showAdaptiveAppDialog<bool>(
                            context: context,
                            builder: (context) => ParentFormDialog(
                              schoolId: schoolId,
                              branchId: branchId,
                              currentUserId: tenant.user.userId,
                              existing: parent,
                            ),
                          ),
                        ),
                      ]
                    : null,
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PersonPhotoPicker(
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
                                  updatedBy: tenant.user.userId,
                                )
                          : (_, __) async => false,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Contact details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(label: 'Phone', value: parent.phone),
                    if (parent.alternatePhone != null)
                      _InfoRow(
                        label: 'Alternate phone',
                        value: parent.alternatePhone!,
                      ),
                    if (parent.email != null)
                      _InfoRow(label: 'Email', value: parent.email!),
                    if (parent.occupation != null)
                      _InfoRow(label: 'Occupation', value: parent.occupation!),
                    if (parent.addressLine1 != null)
                      _InfoRow(
                        label: 'Address',
                        value: [
                          parent.addressLine1,
                          parent.city,
                        ].whereType<String>().join(', '),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Portal access',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      parent.hasPortalAccess
                          ? 'This parent has a linked login account.'
                          : 'No login account linked yet. Portal access is granted from Users management once an account exists for this parent.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Children',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AsyncValueWidget(
                      value: childrenAsync,
                      data: (children) {
                        if (children.isEmpty) {
                          return const EmptyView(
                            icon: Icons.groups_outlined,
                            message: 'No students linked to this parent yet.',
                          );
                        }
                        return Column(
                          children: [
                            for (final student in children)
                              Card(
                                child: ListTile(
                                  title: Text(student.displayName),
                                  subtitle: Text(
                                    '${student.admissionNumber} · ${student.status.displayName}',
                                  ),
                                  onTap: () => context.push(
                                    '/students/${student.studentId}',
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
