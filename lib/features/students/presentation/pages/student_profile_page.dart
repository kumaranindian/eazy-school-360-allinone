import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/academic_record_status.dart';
import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/widgets/login_access_dialog.dart';
import '../../domain/parent_student_link.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/parent_providers.dart';
import '../providers/student_providers.dart';
import '../widgets/link_parent_dialog.dart';
import '../widgets/person_photo_picker.dart';
import '../widgets/student_branch_transfer_dialog.dart';
import '../widgets/student_status_dialog.dart';
import '../widgets/student_transfer_dialog.dart';

/// Student profile (brief §17-18): Overview, Personal, Parent/Guardian,
/// Academic (history), Documents (foundation only — see brief §27, not a
/// full document-management module this milestone).
class StudentProfilePage extends ConsumerWidget {
  final String studentId;

  const StudentProfilePage({super.key, required this.studentId});

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
          studentId: studentId,
        );
        final studentAsync = ref.watch(studentProvider(key));

        return AsyncValueWidget(
          value: studentAsync,
          data: (student) {
            if (student == null) {
              return const EmptyView(
                icon: Icons.person_off_outlined,
                message: 'This student could not be found.',
              );
            }

            return DefaultTabController(
              length: 4,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(student.displayName),
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Parent / Guardian'),
                      Tab(text: 'Academic'),
                      Tab(text: 'Documents'),
                    ],
                  ),
                  actions: canManage
                      ? [
                          IconButton(
                            icon: const Icon(Icons.swap_horiz),
                            tooltip: 'Transfer',
                            onPressed: () => showAdaptiveAppDialog<bool>(
                              context: context,
                              builder: (context) => StudentTransferDialog(
                                student: student,
                                currentUserId: tenant.user.userId,
                              ),
                            ),
                          ),
                          if (tenant.user.homeRole == UserRole.schoolAdmin &&
                              student.status == StudentStatus.active)
                            IconButton(
                              icon: const Icon(Icons.apartment_outlined),
                              tooltip: 'Move to another branch',
                              onPressed: () async {
                                final moved = await showAdaptiveAppDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) =>
                                      StudentBranchTransferDialog(
                                        student: student,
                                        currentUserId: tenant.user.userId,
                                      ),
                                );
                                if (moved == true && context.mounted) {
                                  context.showSnackBar(
                                    '${student.displayName} was moved to the new branch.',
                                  );
                                }
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.flag_outlined),
                            tooltip: 'Change status',
                            onPressed: () => showAdaptiveAppDialog<bool>(
                              context: context,
                              builder: (context) => StudentStatusDialog(
                                student: student,
                                currentUserId: tenant.user.userId,
                              ),
                            ),
                          ),
                        ]
                      : null,
                ),
                body: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PersonPhotoPicker(
                            photoUrl: student.photoUrl,
                            isUploading: ref
                                .watch(studentWriteControllerProvider)
                                .isLoading,
                            readError: () =>
                                ref.read(studentWriteControllerProvider).error,
                            onUpload: canManage
                                ? (bytes, extension) => ref
                                      .read(
                                        studentWriteControllerProvider.notifier,
                                      )
                                      .uploadPhoto(
                                        schoolId: schoolId,
                                        branchId: branchId,
                                        studentId: studentId,
                                        fileBytes: bytes,
                                        fileExtension: extension,
                                        updatedBy: tenant.user.userId,
                                      )
                                : (_, __) async => false,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _InfoRow(
                            label: 'Admission number',
                            value: student.admissionNumber,
                          ),
                          _InfoRow(
                            label: 'Student code',
                            value: student.studentCode,
                          ),
                          _InfoRow(
                            label: 'Status',
                            value: student.status.displayName,
                          ),
                          _InfoRow(
                            label: 'Date of birth',
                            value: formatDisplayDate(student.dateOfBirth),
                          ),
                          _InfoRow(
                            label: 'Gender',
                            value: student.gender.displayName,
                          ),
                          if (student.bloodGroup != null)
                            _InfoRow(
                              label: 'Blood group',
                              value: student.bloodGroup!.displayName,
                            ),
                          if (student.email != null)
                            _InfoRow(label: 'Email', value: student.email!),
                          if (student.phone != null)
                            _InfoRow(label: 'Phone', value: student.phone!),
                          if (student.addressLine1 != null)
                            _InfoRow(
                              label: 'Address',
                              value: [
                                student.addressLine1,
                                student.city,
                              ].whereType<String>().join(', '),
                            ),
                          _InfoRow(
                            label: 'Admission date',
                            value: formatDisplayDate(student.admissionDate),
                          ),
                        ],
                      ),
                    ),
                    _ParentsTab(
                      student: student,
                      canManage: canManage,
                      currentUserId: tenant.user.userId,
                    ),
                    _AcademicHistoryTab(studentKey: key),
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: EmptyView(
                        icon: Icons.folder_outlined,
                        message:
                            'Document management is not part of this milestone — this tab is a placeholder for a future one.',
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

class _ParentsTab extends ConsumerWidget {
  final Student student;
  final bool canManage;
  final String currentUserId;

  const _ParentsTab({
    required this.student,
    required this.canManage,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: student.schoolId,
      branchId: student.branchId,
      studentId: student.studentId,
    );
    final linksAsync = ref.watch(studentParentLinksProvider(key));

    return AsyncValueWidget(
      value: linksAsync,
      data: (links) {
        return Column(
          children: [
            if (canManage)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add parent'),
                    onPressed: () => showAdaptiveAppDialog<bool>(
                      context: context,
                      builder: (context) => LinkParentDialog(
                        schoolId: key.schoolId,
                        branchId: key.branchId,
                        studentId: key.studentId,
                        currentUserId: currentUserId,
                        alreadyLinkedParentIds: links
                            .map((l) => l.parentId)
                            .toSet(),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: links.isEmpty
                  ? const EmptyView(
                      icon: Icons.family_restroom_outlined,
                      message: 'No parent or guardian linked yet.',
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      children: [
                        for (final link in links)
                          _ParentLinkTile(
                            link: link,
                            canManage: canManage,
                            currentUserId: currentUserId,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ParentLinkTile extends ConsumerWidget {
  final ParentStudentLink link;
  final bool canManage;
  final String currentUserId;

  const _ParentLinkTile({
    required this.link,
    required this.canManage,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentKey = (
      schoolId: link.schoolId,
      branchId: link.branchId,
      parentId: link.parentId,
    );
    final parentAsync = ref.watch(parentProvider(parentKey));

    return parentAsync.when(
      data: (parent) {
        if (parent == null) return const SizedBox.shrink();
        final badges = [
          if (link.isPrimary) 'Primary',
          if (link.isEmergencyContact) 'Emergency contact',
          if (link.canAccessPortal) 'Portal access',
          if (parent.hasPortalAccess) 'Has login',
        ];
        return Card(
          child: ListTile(
            title: Text(parent.displayName),
            subtitle: Text(
              '${link.relationshipType.displayName} · ${parent.phone}${badges.isEmpty ? '' : ' · ${badges.join(', ')}'}',
            ),
            trailing: canManage
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.vpn_key_outlined),
                        tooltip: 'Login access',
                        onPressed: () async {
                          final changed = await showLoginAccessDialog(
                            context: context,
                            schoolId: link.schoolId,
                            branchId: link.branchId,
                            kind: LoginKind.parent,
                            id: parent.parentId,
                            fallbackName: parent.displayName,
                          );
                          if (changed == true) {
                            ref.invalidate(parentProvider(parentKey));
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit link',
                        onPressed: () => showAdaptiveAppDialog<void>(
                          context: context,
                          builder: (context) => _EditParentLinkDialog(
                            link: link,
                            currentUserId: currentUserId,
                          ),
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _EditParentLinkDialog extends ConsumerStatefulWidget {
  final ParentStudentLink link;
  final String currentUserId;

  const _EditParentLinkDialog({
    required this.link,
    required this.currentUserId,
  });

  @override
  ConsumerState<_EditParentLinkDialog> createState() =>
      _EditParentLinkDialogState();
}

class _EditParentLinkDialogState extends ConsumerState<_EditParentLinkDialog> {
  late bool _isPrimary = widget.link.isPrimary;
  late bool _isEmergencyContact = widget.link.isEmergencyContact;
  late bool _canAccessPortal = widget.link.canAccessPortal;

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(studentWriteControllerProvider).isLoading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Edit relationship',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          value: _isPrimary,
          onChanged: (v) => setState(() => _isPrimary = v ?? false),
          title: const Text('Primary contact'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: _isEmergencyContact,
          onChanged: (v) => setState(() => _isEmergencyContact = v ?? false),
          title: const Text('Emergency contact'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: _canAccessPortal,
          onChanged: (v) => setState(() => _canAccessPortal = v ?? false),
          title: const Text('Allow parent portal access'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final updated = widget.link.copyWith(
                        isPrimary: _isPrimary,
                        isEmergencyContact: _isEmergencyContact,
                        canAccessPortal: _canAccessPortal,
                      );
                      final success = await ref
                          .read(studentWriteControllerProvider.notifier)
                          .updateParentLink(
                            updated,
                            updatedBy: widget.currentUserId,
                          );
                      if (context.mounted && success) {
                        Navigator.of(context).pop();
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AcademicHistoryTab extends ConsumerWidget {
  final ({String schoolId, String branchId, String studentId}) studentKey;

  const _AcademicHistoryTab({required this.studentKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(academicHistoryProvider(studentKey));

    return AsyncValueWidget(
      value: historyAsync,
      data: (records) {
        if (records.isEmpty) {
          return const EmptyView(
            icon: Icons.history_edu_outlined,
            message: 'No academic history yet.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            for (final record in records.reversed)
              Card(
                child: ListTile(
                  leading: Icon(
                    record.status == AcademicRecordStatus.active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(
                    '${formatDisplayDate(record.startDate)}${record.endDate != null ? ' – ${formatDisplayDate(record.endDate!)}' : ' – present'}',
                  ),
                  subtitle: Text(
                    'Roll no: ${record.rollNumber ?? '—'} · ${record.status.displayName}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
