import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
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
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Card(
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
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (school.logoUrl != null) ...[
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: NetworkImage(school.logoUrl!),
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: Text(
                          school.name,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      if (tenant.can(Permission.manageSchool))
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _isEditing = true),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                    ],
                  ),
                  if (school.shortName != null && school.shortName!.isNotEmpty)
                    Text(
                      school.shortName!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Email: ${school.email}'),
                  if (school.phone != null && school.phone!.isNotEmpty)
                    Text('Phone: ${school.phone}'),
                  if (school.website != null && school.website!.isNotEmpty)
                    Text('Website: ${school.website}'),
                  if ([
                    school.addressLine1,
                    school.city,
                    school.state,
                    school.country,
                  ].any((v) => v != null && v.isNotEmpty)) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      [
                        school.addressLine1,
                        school.addressLine2,
                        school.city,
                        school.state,
                        school.country,
                        school.postalCode,
                      ].where((v) => v != null && v.isNotEmpty).join(', '),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
