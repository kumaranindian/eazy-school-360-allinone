import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/regional/regional_settings.dart';
import '../../../../core/regional/time_zones.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../../shared/regional/regional_settings_editor.dart';
import '../providers/school_profile_providers.dart';

/// Settings -> Regional: the school's country, currency, time zone and date
/// format. One setting for the whole school; every branch and every screen
/// (fees, receipts, attendance "today", deadlines, reminders) follows it.
class RegionalSettingsPage extends ConsumerStatefulWidget {
  const RegionalSettingsPage({super.key});

  @override
  ConsumerState<RegionalSettingsPage> createState() =>
      _RegionalSettingsPageState();
}

class _RegionalSettingsPageState extends ConsumerState<RegionalSettingsPage> {
  RegionalSettings? _draft;
  bool _saving = false;
  String? _error;

  Future<void> _save(
    RegionalSettings saved,
    RegionalSettings draft,
    String userId,
  ) async {
    if (_saving) return;
    final problem = draft.validate(isKnownZone: TimeZones.isKnown);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final tenant = ref.read(tenantContextProvider).value;
    final school = tenant?.school;
    if (school == null) return;
    final zoneChanged = draft.timezone != saved.timezone;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save regional settings?'),
        content: Text(
          zoneChanged
              ? 'Changing the time zone changes what "today" means for '
                    'attendance, fee due dates, deadlines and reminders for '
                    'every branch. Records already saved keep their dates.'
              : 'These settings apply to every branch of the school.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved0 = await ref
        .read(schoolProfileWriteControllerProvider.notifier)
        .updateRegional(school.copyWith(regional: draft), updatedBy: userId);
    if (!mounted) return;
    if (saved0) {
      setState(() {
        _saving = false;
        _draft = null;
      });
      context.showSnackBar('Regional settings saved.');
    } else {
      final e = ref.read(schoolProfileWriteControllerProvider).error;
      setState(() {
        _saving = false;
        _error = e == null ? 'Could not save.' : userMessageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null) {
          return const EmptyView(
            icon: Icons.public_outlined,
            message: 'No school found for your account.',
          );
        }
        if (!tenant!.can(Permission.manageSchool)) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'Only school administrators can change regional settings.',
          );
        }
        final school = tenant.school!;
        final saved = school.regional;
        final draft = _draft ?? saved;
        final dirty = draft != saved || !school.regionalConfigured;
        return SectionPage(
          title: 'Regional settings',
          description:
              'Country, currency, time zone and date format for the whole '
              'school. Every branch and every screen follows these.',
          parentRoute: AppRoutes.settings,
          parentLabel: 'Settings',
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (!school.regionalConfigured)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Not set up yet'),
                    subtitle: Text(
                      'This school is using ${saved.countryCode} / '
                      '${saved.currency} / ${saved.timezone} until you save '
                      'its settings.',
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              RegionalSettingsEditor(
                value: draft,
                enabled: !_saving,
                currencyLocked: school.currencyLocked,
                onChanged: (v) => setState(() {
                  _draft = v;
                  _error = null;
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: dirty && !_saving
                      ? () => _save(saved, draft, tenant.user.userId)
                      : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
