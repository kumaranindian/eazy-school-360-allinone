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
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../school_setup/presentation/providers/school_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_application.dart';
import '../../domain/admission_settings.dart';
import '../providers/admission_providers.dart';

/// School-wide admission settings: the module switch, number prefixes, the
/// enquiry sources and the default follow-up interval. Saved through the
/// `saveAdmissionSettings` callable (school administrators only — the server
/// refuses everyone else, so a hidden button is never the only guard).
/// Reminder times offered (the server accepts 06:00–21:00).
const _reminderTimes = [
  '06:00',
  '07:00',
  '08:00',
  '09:00',
  '10:00',
  '12:00',
  '14:00',
  '16:00',
  '18:00',
  '20:00',
];

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
  bool _reminders = true;
  bool _branchApprove = false;
  bool _portalOn = false;
  Set<String> _openYears = {};
  Set<String> _openClasses = {};
  Map<String, bool> _notify = {};
  String _portalBranch = '';
  final _slug = TextEditingController();
  final _intro = TextEditingController();
  final _consent = TextEditingController();
  Set<String> _requiredDocs = {};
  List<CustomDocumentType> _customDocs = [];
  final _newDocType = TextEditingController();
  String _reminderTime = '09:00';
  List<String> _sources = [];
  AdmissionSettings? _loaded;

  @override
  void dispose() {
    _enquiryPrefix.dispose();
    _applicationPrefix.dispose();
    _followUp.dispose();
    _newSource.dispose();
    _newDocType.dispose();
    _slug.dispose();
    _intro.dispose();
    _consent.dispose();
    super.dispose();
  }

  void _seed(AdmissionSettings s) {
    if (_loaded != null) return;
    _loaded = s;
    _enabled = s.enabled;
    _enquiryPrefix.text = s.enquiryPrefix;
    _applicationPrefix.text = s.applicationPrefix;
    _followUp.text = '${s.followUpDays}';
    _reminders = s.remindersEnabled;
    _branchApprove = s.branchAdminsMayApprove;
    _portalOn = s.publicPortal.enabled;
    _openYears = {...s.academicYearIds};
    _openClasses = {...s.classIds};
    _notify = {
      for (final (key, _) in admissionNotificationSwitches)
        key: s.notifies(key),
    };
    _portalBranch = s.publicPortal.branchId;
    _slug.text = s.publicPortal.slug;
    _intro.text = s.publicPortal.introText;
    _consent.text = s.publicPortal.consentText;
    _requiredDocs = {...s.requiredDocumentTypes};
    _customDocs = [...s.customDocumentTypes];
    _reminderTime = s.reminderTime;
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
      remindersEnabled: _reminders,
      reminderTime: _reminderTime,
      branchAdminsMayApprove: _branchApprove,
      notifications: _notify,
      academicYearIds: _openYears.toList()..sort(),
      classIds: _openClasses.toList()..sort(),
      publicPortal: PublicPortalSettings(
        enabled: _portalOn,
        slug: _slug.text.trim().toLowerCase(),
        branchId: _portalBranch,
        introText: _intro.text.trim(),
        consentText: _consent.text.trim(),
        consentVersion: base.publicPortal.consentVersion,
      ),
      customDocumentTypes: _customDocs,
      requiredDocumentTypes: [
        for (final k in {
          ...builtInDocumentTypes.keys,
          ..._customDocs.map((c) => c.id),
        })
          if (_requiredDocs.contains(k)) k,
      ],
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

  void _addDocType() {
    final label = _newDocType.text.trim();
    if (label.length < 2 || label.length > 40 || _customDocs.length >= 10) {
      return;
    }
    final id = CustomDocumentType.idFor(label);
    if (builtInDocumentTypes.containsKey(id) ||
        _customDocs.any((c) => c.id == id)) {
      return;
    }
    setState(() {
      _customDocs = [..._customDocs, CustomDocumentType(id: id, label: label)];
      _newDocType.clear();
    });
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
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            'Daily follow-up reminders',
                                          ),
                                          subtitle: const Text(
                                            'Staff are reminded of follow-ups '
                                            'due today and overdue, once a '
                                            'day, in the school\'s time zone.',
                                          ),
                                          value: _reminders,
                                          onChanged: saving
                                              ? null
                                              : (v) => setState(
                                                  () => _reminders = v,
                                                ),
                                        ),
                                        if (_reminders)
                                          DropdownButtonFormField<String>(
                                            value:
                                                _reminderTimes.contains(
                                                  _reminderTime,
                                                )
                                                ? _reminderTime
                                                : null,
                                            decoration: const InputDecoration(
                                              labelText: 'Reminder time',
                                            ),
                                            items: [
                                              for (final t in _reminderTimes)
                                                DropdownMenuItem(
                                                  value: t,
                                                  child: Text(t),
                                                ),
                                            ],
                                            onChanged: (v) => setState(
                                              () => _reminderTime =
                                                  v ?? _reminderTime,
                                            ),
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
                                          icon: Icons.folder_open_outlined,
                                          title: 'Application documents',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tick the documents that must be verified before an application can be approved.',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        for (final e in {
                                          ...builtInDocumentTypes,
                                          for (final c in _customDocs)
                                            c.id: c.label,
                                        }.entries)
                                          CheckboxListTile(
                                            contentPadding: EdgeInsets.zero,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            title: Text(e.value),
                                            value: _requiredDocs.contains(
                                              e.key,
                                            ),
                                            onChanged: saving
                                                ? null
                                                : (v) => setState(() {
                                                    v == true
                                                        ? _requiredDocs.add(
                                                            e.key,
                                                          )
                                                        : _requiredDocs.remove(
                                                            e.key,
                                                          );
                                                  }),
                                          ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _newDocType,
                                                maxLength: 40,
                                                onSubmitted: (_) =>
                                                    _addDocType(),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText:
                                                          'Add a document type',
                                                      counterText: '',
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton.filledTonal(
                                              tooltip: 'Add document type',
                                              onPressed: _addDocType,
                                              icon: const Icon(Icons.add),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ParentsCard(
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Branch administrators may approve applications',
                                      ),
                                      subtitle: const Text(
                                        'Off: only school administrators approve or reject. On: a branch administrator may for their own branch.',
                                      ),
                                      value: _branchApprove,
                                      onChanged: saving
                                          ? null
                                          : (v) => setState(
                                              () => _branchApprove = v,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _OpenForAdmission(
                                    schoolId: schoolId,
                                    branchId: tenant.branch!.branchId,
                                    years: _openYears,
                                    classes: _openClasses,
                                    enabled: !saving,
                                    onChanged: (y, c) => setState(() {
                                      _openYears = y;
                                      _openClasses = c;
                                    }),
                                  ),
                                  const SizedBox(height: 16),
                                  ParentsCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const ParentsSectionTitle(
                                          icon: Icons.notifications_outlined,
                                          title: 'Notifications',
                                        ),
                                        for (final (key, label)
                                            in admissionNotificationSwitches)
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(label),
                                            value: _notify[key] ?? true,
                                            onChanged: saving
                                                ? null
                                                : (v) => setState(
                                                    () => _notify[key] = v,
                                                  ),
                                          ),
                                        const Text(
                                          'Notices name only the enquiry number. Remarks and reasons are never included.',
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
                                          icon: Icons.public_outlined,
                                          title: 'Public enquiry page',
                                        ),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            'Let families send an enquiry online',
                                          ),
                                          subtitle: const Text(
                                            'Anyone with the link can send an enquiry. It arrives as a new enquiry from "Website".',
                                          ),
                                          value: _portalOn,
                                          onChanged: saving
                                              ? null
                                              : (v) => setState(
                                                  () => _portalOn = v,
                                                ),
                                        ),
                                        if (_portalOn) ...[
                                          TextFormField(
                                            controller: _slug,
                                            decoration: const InputDecoration(
                                              labelText: 'Page address *',
                                              helperText:
                                                  'Lowercase letters, digits and hyphens, e.g. rosewood-high',
                                            ),
                                            validator: (v) =>
                                                PublicPortalSettings.slugPattern
                                                    .hasMatch(
                                                      (v ?? '')
                                                          .trim()
                                                          .toLowerCase(),
                                                    )
                                                ? null
                                                : '3-40 lowercase letters, digits or hyphens',
                                          ),
                                          const SizedBox(height: 12),
                                          DropdownButtonFormField<String>(
                                            value: _portalBranch.isEmpty
                                                ? null
                                                : _portalBranch,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Branch that receives enquiries *',
                                            ),
                                            items: [
                                              for (final b
                                                  in ref
                                                          .watch(
                                                            branchesStreamProvider(
                                                              schoolId,
                                                            ),
                                                          )
                                                          .value ??
                                                      const [])
                                                DropdownMenuItem(
                                                  value: b.branchId,
                                                  child: Text(b.name),
                                                ),
                                            ],
                                            onChanged: (v) => setState(
                                              () => _portalBranch = v ?? '',
                                            ),
                                            validator: (v) => v == null
                                                ? 'Choose a branch'
                                                : null,
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _intro,
                                            maxLines: 2,
                                            maxLength: 500,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Welcome text (optional)',
                                            ),
                                          ),
                                          TextFormField(
                                            controller: _consent,
                                            maxLines: 3,
                                            maxLength: 1000,
                                            decoration: const InputDecoration(
                                              labelText: 'Consent statement *',
                                              helperText:
                                                  'Shown beside the checkbox. Changing it asks every visitor to agree again.',
                                            ),
                                            validator: (v) =>
                                                (v ?? '').trim().length < 20
                                                ? 'At least 20 characters'
                                                : null,
                                          ),
                                        ],
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

/// Which academic years and classes are open for admissions. Nothing chosen
/// means every year and class is open (the default).
class _OpenForAdmission extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final Set<String> years;
  final Set<String> classes;
  final bool enabled;
  final void Function(Set<String> years, Set<String> classes) onChanged;
  const _OpenForAdmission({
    required this.schoolId,
    required this.branchId,
    required this.years,
    required this.classes,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all =
        ref
            .watch(
              academicYearsProvider((schoolId: schoolId, branchId: branchId)),
            )
            .value ??
        const [];
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ParentsSectionTitle(
            icon: Icons.school_outlined,
            title: 'Open for admissions',
          ),
          const SizedBox(height: 4),
          Text(
            years.isEmpty && classes.isEmpty
                ? 'Every academic year and class is open. Choose years or classes to limit the enquiry form and the public page.'
                : 'Only the chosen years and classes are offered.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final y in all)
                FilterChip(
                  label: Text(y.name),
                  selected: years.contains(y.academicYearId),
                  onSelected: enabled
                      ? (on) {
                          final next = {...years};
                          var nextClasses = classes;
                          if (on) {
                            next.add(y.academicYearId);
                          } else {
                            next.remove(y.academicYearId);
                            // Classes of a year that is no longer chosen go too.
                            final ids =
                                (ref
                                            .read(
                                              classesProvider((
                                                schoolId: schoolId,
                                                branchId: branchId,
                                                academicYearId:
                                                    y.academicYearId,
                                              )),
                                            )
                                            .value ??
                                        const [])
                                    .map((c) => c.classId)
                                    .toSet();
                            nextClasses = classes.difference(ids);
                          }
                          onChanged(next, nextClasses);
                        }
                      : null,
                ),
            ],
          ),
          for (final y in all.where((y) => years.contains(y.academicYearId)))
            _YearClasses(
              schoolId: schoolId,
              branchId: branchId,
              yearId: y.academicYearId,
              yearName: y.name,
              selected: classes,
              enabled: enabled,
              onChanged: (c) => onChanged(years, c),
            ),
        ],
      ),
    );
  }
}

class _YearClasses extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String yearId;
  final String yearName;
  final Set<String> selected;
  final bool enabled;
  final void Function(Set<String>) onChanged;
  const _YearClasses({
    required this.schoolId,
    required this.branchId,
    required this.yearId,
    required this.yearName,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref
            .watch(
              classesProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: yearId,
              )),
            )
            .value ??
        const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Classes in $yearName (none chosen: all)'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in list)
                FilterChip(
                  label: Text(c.name),
                  selected: selected.contains(c.classId),
                  onSelected: enabled
                      ? (on) {
                          final next = {...selected};
                          on ? next.add(c.classId) : next.remove(c.classId);
                          onChanged(next);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
