import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_settings.dart';
import '../providers/admission_providers.dart';

/// School-wide admission settings: the module switch, number prefixes, the
/// enquiry sources and the default follow-up interval. Saved through the
/// `saveAdmissionSettings` callable (school administrators only — the server
/// refuses everyone else, so a hidden button is never the only guard).
class AdmissionSettingsPage extends ConsumerStatefulWidget {
  const AdmissionSettingsPage({super.key});

  @override
  ConsumerState<AdmissionSettingsPage> createState() =>
      _AdmissionSettingsPageState();
}

class _AdmissionSettingsPageState extends ConsumerState<AdmissionSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _enquiryPrefix = TextEditingController();
  final _applicationPrefix = TextEditingController();
  final _followUp = TextEditingController();
  final _newSource = TextEditingController();
  bool _enabled = false;
  List<String> _sources = [];
  AdmissionSettings? _loaded;

  @override
  void dispose() {
    _enquiryPrefix.dispose();
    _applicationPrefix.dispose();
    _followUp.dispose();
    _newSource.dispose();
    super.dispose();
  }

  void _seed(AdmissionSettings s) {
    if (_loaded != null) return;
    _loaded = s;
    _enabled = s.enabled;
    _enquiryPrefix.text = s.enquiryPrefix;
    _applicationPrefix.text = s.applicationPrefix;
    _followUp.text = '${s.followUpDays}';
    _sources = [...s.sources];
  }

  Future<void> _save(String schoolId) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final base = _loaded ?? const AdmissionSettings();
    final next = base.copyWith(
      enabled: _enabled,
      enquiryPrefix: _enquiryPrefix.text.trim().toUpperCase(),
      applicationPrefix: _applicationPrefix.text.trim().toUpperCase(),
      followUpDays: int.tryParse(_followUp.text.trim()) ?? base.followUpDays,
      sources: _sources,
    );
    final ok = await ref
        .read(admissionWriteControllerProvider.notifier)
        .saveSettings(schoolId: schoolId, settings: next);
    if (!mounted) return;
    if (ok) {
      // Re-seed from the saved values (and the new version) on the next build.
      setState(() => _loaded = null);
      context.showSnackBar('Admission settings saved.');
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'Could not save the settings.' : userMessageFor(err),
        isError: true,
      );
    }
  }

  void _addSource() {
    final v = _newSource.text.trim();
    if (v.length < 2 || v.length > 40 || _sources.contains(v)) return;
    if (_sources.length >= 20) return;
    setState(() {
      _sources = [..._sources, v];
      _newSource.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        if (tenant?.school == null) {
          return const EmptyView(
            icon: Icons.tune_outlined,
            message: 'No school found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final settings = ref.watch(admissionSettingsProvider(schoolId));
        final saving = ref.watch(admissionWriteControllerProvider).isLoading;
        final wide = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        return settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              EmptyView(icon: Icons.error_outline, message: userMessageFor(e)),
          data: (s) {
            _seed(s);
            return Scaffold(
              body: Column(
                children: [
                  ParentsPageBar(
                    title: 'Admission settings',
                    onBack: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.admissions),
                  ),
                  Expanded(
                    child: Form(
                      key: _form,
                      child: ListView(
                        padding: EdgeInsets.all(wide.isMobile ? 16 : 24),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ParentsCard(
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Admission module'),
                                      subtitle: const Text(
                                        'Turn on to record enquiries. Turning '
                                        'it off keeps all existing data and '
                                        'only stops new enquiries.',
                                      ),
                                      value: _enabled,
                                      onChanged: saving
                                          ? null
                                          : (v) => setState(() => _enabled = v),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ParentsCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const ParentsSectionTitle(
                                          icon: Icons.numbers,
                                          title: 'Numbers',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Numbers look like '
                                          '${_enquiryPrefix.text.isEmpty ? 'ENQ' : _enquiryPrefix.text.toUpperCase()}'
                                          '-2026-00001 and are generated by '
                                          'the server, one series per branch '
                                          'and year.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _enquiryPrefix,
                                                textCapitalization:
                                                    TextCapitalization
                                                        .characters,
                                                maxLength: 6,
                                                onChanged: (_) =>
                                                    setState(() {}),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText:
                                                          'Enquiry prefix',
                                                    ),
                                                validator: _prefix,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: TextFormField(
                                                controller: _applicationPrefix,
                                                textCapitalization:
                                                    TextCapitalization
                                                        .characters,
                                                maxLength: 6,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText:
                                                          'Application prefix',
                                                    ),
                                                validator: _prefix,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ParentsCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const ParentsSectionTitle(
                                          icon: Icons.campaign_outlined,
                                          title: 'Enquiry sources',
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            for (final src in _sources)
                                              InputChip(
                                                label: Text(src),
                                                onDeleted: _sources.length <= 1
                                                    ? null
                                                    : () => setState(
                                                        () => _sources = [
                                                          for (final x
                                                              in _sources)
                                                            if (x != src) x,
                                                        ],
                                                      ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _newSource,
                                                maxLength: 40,
                                                onSubmitted: (_) =>
                                                    _addSource(),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Add a source',
                                                      counterText: '',
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton.filledTonal(
                                              tooltip: 'Add source',
                                              onPressed: _addSource,
                                              icon: const Icon(Icons.add),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ParentsCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const ParentsSectionTitle(
                                          icon: Icons.event_repeat_outlined,
                                          title: 'Follow-ups',
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _followUp,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Default days to the next follow-up',
                                          ),
                                          validator: (v) {
                                            final n = int.tryParse(
                                              (v ?? '').trim(),
                                            );
                                            return n == null || n < 1 || n > 60
                                                ? 'Enter a number from 1 to 60'
                                                : null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: saving
                                        ? null
                                        : () => _save(schoolId),
                                    child: saving
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Save settings'),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String? _prefix(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2,6}$').hasMatch(t)) return '2–6 capital letters';
    if (_enquiryPrefix.text.trim().toUpperCase() ==
        _applicationPrefix.text.trim().toUpperCase()) {
      return 'The two prefixes must differ';
    }
    return null;
  }
}
