import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/regional/country.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/platform_ops_models.dart';
import '../providers/platform_ops_providers.dart';

/// An owner creates a school and its first administrator. The administrator is
/// emailed a link to choose a password; nobody ever knows it.
class CreateSchoolDialog extends ConsumerStatefulWidget {
  const CreateSchoolDialog({super.key});

  @override
  ConsumerState<CreateSchoolDialog> createState() => _CreateSchoolDialogState();
}

class _CreateSchoolDialogState extends ConsumerState<CreateSchoolDialog> {
  final _form = GlobalKey<FormState>();
  final _school = TextEditingController();
  final _admin = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  Country _country = Countries.all.first;
  late String _zone = _country.timezones.first;
  String? _error;

  @override
  void dispose() {
    for (final c in [_school, _admin, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final out = await ref
        .read(platformOpsActionsProvider.notifier)
        .createSchool(
          NewSchoolInput(
            schoolName: _school.text,
            adminName: _admin.text,
            adminEmail: _email.text,
            phone: _phone.text,
            countryCode: _country.code,
            countryName: _country.name,
            currency: _country.currency,
            timezone: _zone,
            dateFormat: _country.dateFormat,
          ),
        );
    if (!mounted) return;
    if (out == null) {
      setState(
        () => _error = userMessageFor(
          ref.read(platformOpsActionsProvider).error!,
        ),
      );
    } else {
      Navigator.pop(context, out);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Create a school'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('cs-school'),
                  controller: _school,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'School name'),
                  validator: (v) => (v ?? '').trim().length < 2
                      ? 'Enter the school name'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<Country>(
                  key: const ValueKey('cs-country'),
                  value: _country,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Country'),
                  items: [
                    for (final c in Countries.all)
                      DropdownMenuItem(
                        value: c,
                        child: Text('${c.name} (${c.currency})'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (c) => setState(() {
                          _country = c ?? _country;
                          _zone = _country.timezones.first;
                        }),
                ),
                if (_country.timezones.length > 1) ...[
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('cs-zone'),
                    value: _zone,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Time zone'),
                    items: [
                      for (final z in _country.timezones)
                        DropdownMenuItem(value: z, child: Text(z)),
                    ],
                    onChanged: busy
                        ? null
                        : (z) => setState(() => _zone = z ?? _zone),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('cs-phone'),
                  controller: _phone,
                  enabled: !busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'School phone (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('First administrator', style: text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  key: const ValueKey('cs-admin'),
                  controller: _admin,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? 'Enter their name' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('cs-email'),
                  controller: _email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : 'Enter a valid email address',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'They are emailed a link to choose a password. Currency '
                  '(${_country.currency}) and date format follow the country; '
                  'the school can fine-tune them later.',
                  style: text.bodySmall,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('cs-create'),
          onPressed: busy ? null : _create,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create school'),
        ),
      ],
    );
  }
}
