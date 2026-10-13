import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/layouts/detail_grid.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../widgets/school_profile_form.dart';

/// View/edit/save/cancel for the school profile — only reachable by
/// roles with [Permission.manageSchool] (see `app_shell.dart`), which
/// also gates whether the Edit button appears at all here (view-only for
/// anyone who somehow lacks it, rather than hiding the whole page).
class SchoolSetupPage extends ConsumerStatefulWidget {
  const SchoolSetupPage({super.key});

  @override
  ConsumerState<SchoolSetupPage> createState() => _SchoolSetupPageState();
}

class _SchoolSetupPageState extends ConsumerState<SchoolSetupPage> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        final school = tenant?.school;
        if (school == null || tenant == null) {
          return const EmptyView(
            icon: Icons.school_outlined,
            message: 'No school found for your account.',
          );
        }

        if (_isEditing) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SchoolProfileForm(
                      school: school,
                      updatedBy: tenant.user.userId,
                      onSaved: () => setState(() => _isEditing = false),
                      onCancel: () => setState(() => _isEditing = false),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final address = [
          school.addressLine1,
          school.addressLine2,
          school.city,
          school.state,
          school.country,
          school.postalCode,
        ].where((v) => v != null && v.isNotEmpty).join(', ');

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (school.logoUrl != null) ...[
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: NetworkImage(school.logoUrl!),
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              school.name,
                              style: theme.textTheme.titleLarge,
                            ),
                            if (school.shortName != null &&
                                school.shortName!.isNotEmpty)
                              Text(
                                school.shortName!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (tenant.can(Permission.manageSchool)) ...[
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _isEditing = true),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ],
                    ],
                  ),
                  const Divider(height: AppSpacing.xl),
                  DetailGrid(
                    items: [
                      DetailItem(
                        'Email',
                        school.email,
                        icon: Icons.mail_outline,
                      ),
                      DetailItem(
                        'Phone',
                        school.phone ?? '',
                        icon: Icons.phone_outlined,
                      ),
                      DetailItem(
                        'Website',
                        school.website ?? '',
                        icon: Icons.language,
                      ),
                      DetailItem(
                        'Address',
                        address,
                        icon: Icons.location_on_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
