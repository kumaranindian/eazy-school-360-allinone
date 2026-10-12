import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/presentation/widgets/person_photo_picker.dart';
import '../../domain/staff.dart';
import '../providers/staff_providers.dart';
import '../widgets/link_user_dialog.dart';
import '../widgets/staff_branch_scope.dart';
import '../widgets/staff_documents_tab.dart';
import '../widgets/staff_status_chip.dart';
import '../widgets/staff_status_dialog.dart';
import '../widgets/teaching_tab.dart';

/// `/staff/:staffId` — the staff profile (and, for a teacher, the teacher
/// profile: the same page with a Teaching tab; there is no second record).
class StaffProfilePage extends StatelessWidget {
  final String staffId;

  const StaffProfilePage({super.key, required this.staffId});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) => StaffProfileView(
        tenant: tenant,
        schoolId: schoolId,
        branchId: branchId,
        staffId: staffId,
      ),
    );
  }
}

class StaffProfileView extends ConsumerWidget {
  final TenantContext tenant;
  final String schoolId;
  final String branchId;
  final String staffId;

  const StaffProfileView({
    super.key,
    required this.tenant,
    required this.schoolId,
    required this.branchId,
    required this.staffId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = tenant.can(Permission.manageStaff);
    final staffAsync = ref.watch(
      staffProvider((schoolId: schoolId, branchId: branchId, staffId: staffId)),
    );

    return AsyncValueWidget(
      value: staffAsync,
      errorMessage: userMessageFor,
      data: (staff) {
        if (staff == null) {
          return const EmptyView(
            icon: Icons.person_off_outlined,
            message: 'This staff member could not be found.',
          );
        }
        final userId = tenant.user.userId;
        final tabs = <(Tab, Widget)>[
          (
            const Tab(text: 'Profile'),
            _ProfileTab(
              staff: staff,
              canManage: canManage,
              currentUserId: userId,
            ),
          ),
          if (staff.isTeacher)
            (
              const Tab(text: 'Teaching'),
              TeachingTab(
                staff: staff,
                canManage: canManage,
                currentUserId: userId,
              ),
            ),
          if (canManage)
            (
              const Tab(text: 'Documents'),
              StaffDocumentsTab(staff: staff, currentUserId: userId),
            ),
        ];

        return DefaultTabController(
          // Recreated if tabs are added/removed (e.g. teaching switched on)
          // so the controller length never disagrees with the views.
          key: ValueKey(tabs.length),
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(staff.displayName),
              bottom: tabs.length > 1
                  ? TabBar(tabs: [for (final t in tabs) t.$1])
                  : null,
              actions: canManage
                  ? [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () =>
                            context.push('/staff/${staff.staffId}/edit'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.link),
                        tooltip: 'Application account',
                        onPressed: () => showAdaptiveAppDialog<bool>(
                          context: context,
                          builder: (context) => LinkUserDialog(
                            staff: staff,
                            currentUserId: userId,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.flag_outlined),
                        tooltip: 'Change status',
                        onPressed: () async {
                          final changed = await showAdaptiveAppDialog<bool>(
                            context: context,
                            builder: (context) => StaffStatusDialog(
                              staff: staff,
                              currentUserId: userId,
                            ),
                          );
                          if (changed == true && context.mounted) {
                            context.showSnackBar(
                              'Status updated successfully.',
                            );
                          }
                        },
                      ),
                    ]
                  : null,
            ),
            body: TabBarView(children: [for (final t in tabs) t.$2]),
          ),
        );
      },
    );
  }
}

class _ProfileTab extends ConsumerWidget {
  final Staff staff;
  final bool canManage;
  final String currentUserId;

  const _ProfileTab({
    required this.staff,
    required this.canManage,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchKey = (schoolId: staff.schoolId, branchId: staff.branchId);
    final departmentName =
        (ref.watch(departmentsProvider(branchKey)).value ?? const [])
            .where((d) => d.departmentId == staff.departmentId)
            .firstOrNull
            ?.name ??
        '—';
    final designationName =
        (ref.watch(designationsProvider(branchKey)).value ?? const [])
            .where((d) => d.designationId == staff.designationId)
            .firstOrNull
            ?.name ??
        '—';
    final isSaving = ref.watch(staffWriteControllerProvider).isLoading;
    final controller = ref.read(staffWriteControllerProvider.notifier);

    final address = [
      staff.address,
      staff.city,
      staff.state,
      staff.country,
      staff.postalCode,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    final sections = <Widget>[
      _SectionCard(
        title: 'Personal',
        rows: [
          _Row('Date of birth', formatDisplayDate(staff.dateOfBirth)),
          _Row('Gender', staff.gender.displayName),
          if (staff.bloodGroup != null)
            _Row('Blood group', staff.bloodGroup!.displayName),
          if (address.isNotEmpty) _Row('Address', address),
        ],
      ),
      _SectionCard(
        title: 'Contact',
        rows: [
          _Row('Phone', staff.phone),
          if (staff.alternatePhone != null)
            _Row('Alternate phone', staff.alternatePhone!),
          _Row('Email', staff.email ?? '—'),
        ],
      ),
      _SectionCard(
        title: 'Employment',
        rows: [
          _Row('Employee code', staff.employeeCode),
          _Row('Joining date', formatDisplayDate(staff.joiningDate)),
          _Row('Employment type', staff.employmentType.displayName),
          _Row('Department', departmentName),
          _Row('Designation', designationName),
          _Row('Status', staff.status.displayName),
          _Row('Teaching', staff.isTeacher ? 'Yes' : 'No'),
          if (staff.statusChangeDate != null)
            _Row('Status changed', formatDisplayDate(staff.statusChangeDate!)),
          if (staff.statusChangeReason != null)
            _Row('Reason', staff.statusChangeReason!),
          if (staff.statusChangeNotes != null)
            _Row('Notes', staff.statusChangeNotes!),
        ],
      ),
      if (canManage)
        _SectionCard(
          title: 'Application account',
          rows: [
            _Row(
              'Account',
              staff.userId == null
                  ? 'Not linked — this person does not sign in'
                  : 'Linked (ID ${staff.userId})',
            ),
          ],
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (canManage)
          PersonPhotoPicker(
            photoUrl: staff.photoUrl,
            isUploading: isSaving,
            onUpload: (bytes, extension) => controller.uploadPhoto(
              staff,
              bytes,
              extension,
              updatedBy: currentUserId,
            ),
            onRemove: () =>
                controller.removePhoto(staff, updatedBy: currentUserId),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: CircleAvatar(
              radius: 36,
              backgroundColor: context.colors.surfaceContainerHighest,
              backgroundImage: staff.photoUrl != null
                  ? NetworkImage(staff.photoUrl!)
                  : null,
              child: staff.photoUrl == null
                  ? Icon(
                      Icons.person_outline,
                      size: 32,
                      color: context.colors.outline,
                    )
                  : null,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(staff.displayName, style: context.textStyles.headlineSmall),
            StaffStatusChip(status: staff.status),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${staff.employeeCode} · $designationName · $departmentName',
          style: context.textStyles.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 800 ? 2 : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * AppSpacing.md) /
                columns;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final section in sections)
                  SizedBox(width: width, child: section),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Row {
  final String label;
  final String value;

  const _Row(this.label, this.value);
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _SectionCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.textStyles.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        row.label,
                        style: context.textStyles.bodySmall,
                      ),
                    ),
                    Expanded(child: Text(row.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
