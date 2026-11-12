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
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_settings.dart';
import '../providers/admission_providers.dart';
import '../widgets/admission_widgets.dart';

/// New enquiry / edit enquiry. The server validates and numbers it; this form
/// checks the obvious things first so a person is not sent to the network for
/// an empty name.
class EnquiryFormPage extends ConsumerStatefulWidget {
  /// Null for a new enquiry.
  final String? enquiryId;
  const EnquiryFormPage({super.key, this.enquiryId});

  @override
  ConsumerState<EnquiryFormPage> createState() => _EnquiryFormPageState();
}

class _EnquiryFormPageState extends ConsumerState<EnquiryFormPage> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _g1Name = TextEditingController();
  final _g1Phone = TextEditingController();
  final _g1Email = TextEditingController();
  final _g1Relation = TextEditingController();
  final _g2Name = TextEditingController();
  final _g2Phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController();
  final _prevSchool = TextEditingController();
  final _prevClass = TextEditingController();
  final _special = TextEditingController();
  final _remarks = TextEditingController();

  String? _dob;
  String? _gender;
  String? _yearId;
  String? _classId;
  String? _source;
  String? _followUp;
  String? _enquiryDate;
  bool _seeded = false;
  int? _baseRevision;

  late final List<TextEditingController> _all = [
    _first,
    _last,
    _g1Name,
    _g1Phone,
    _g1Email,
    _g1Relation,
    _g2Name,
    _g2Phone,
    _address,
    _city,
    _state,
    _country,
    _prevSchool,
    _prevClass,
    _special,
    _remarks,
  ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(AdmissionEnquiry e) {
    if (_seeded) return;
    _seeded = true;
    _baseRevision = e.revision;
    _first.text = e.firstName;
    _last.text = e.lastName;
    _dob = e.dateOfBirth;
    _gender = e.gender;
    _yearId = e.academicYearId;
    _classId = e.interestedClassId;
    _source = e.source;
    _followUp = e.nextFollowUpDate;
    final g = e.guardians;
    if (g.isNotEmpty) {
      _g1Name.text = g[0].name;
      _g1Phone.text = g[0].phone;
      _g1Email.text = g[0].email ?? '';
      _g1Relation.text = g[0].relationship ?? '';
    }
    if (g.length > 1) {
      _g2Name.text = g[1].name;
      _g2Phone.text = g[1].phone;
    }
    _address.text = e.addressLine1 ?? '';
    _city.text = e.city ?? '';
    _state.text = e.state ?? '';
    _country.text = e.country ?? '';
    _prevSchool.text = e.previousSchool ?? '';
    _prevClass.text = e.previousClass ?? '';
    _special.text = e.specialRequirements ?? '';
    _remarks.text = e.remarks ?? '';
  }

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  EnquiryInput _input() {
    final guardians = [
      EnquiryGuardian(
        name: _g1Name.text.trim(),
        phone: _g1Phone.text.trim(),
        relationship: _t(_g1Relation),
        email: _t(_g1Email),
        primary: true,
      ),
      if (_g2Name.text.trim().isNotEmpty || _g2Phone.text.trim().isNotEmpty)
        EnquiryGuardian(name: _g2Name.text.trim(), phone: _g2Phone.text.trim()),
    ];
    return EnquiryInput(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      dateOfBirth: _dob,
      gender: _gender,
      academicYearId: _yearId ?? '',
      interestedClassId: _classId ?? '',
      source: _source ?? '',
      guardians: guardians,
      addressLine1: _t(_address),
      city: _t(_city),
      state: _t(_state),
      country: _t(_country),
      previousSchool: _t(_prevSchool),
      previousClass: _t(_prevClass),
      specialRequirements: _t(_special),
      remarks: _t(_remarks),
      nextFollowUpDate: _followUp,
      enquiryDate: widget.enquiryId == null ? _enquiryDate : null,
    );
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<String?> _pickDate({
    String? current,
    required DateTime first,
    required DateTime last,
  }) async {
    final initial = DateTime.tryParse(current ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    return picked == null ? null : _iso(picked);
  }

  Future<void> _save(String schoolId, String branchId) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final controller = ref.read(admissionWriteControllerProvider.notifier);
    if (widget.enquiryId == null) {
      final created = await controller.create(
        schoolId: schoolId,
        branchId: branchId,
        input: _input(),
      );
      if (!mounted) return;
      if (created == null) return _showError();
      context.showSnackBar(
        created.duplicateOf.isEmpty
            ? 'Enquiry ${created.enquiryNumber} saved.'
            : 'Enquiry ${created.enquiryNumber} saved. It looks like a '
                  'possible duplicate — please review.',
      );
      context.pushReplacement('/admissions/enquiries/${created.id}');
    } else {
      final ok = await controller.updateEnquiry(
        schoolId: schoolId,
        branchId: branchId,
        enquiryId: widget.enquiryId!,
        input: _input(),
        baseRevision: _baseRevision,
      );
      if (!mounted) return;
      if (!ok) return _showError();
      context.showSnackBar('Enquiry updated.');
      context.pop();
    }
  }

  void _showError() {
    final err = ref.read(admissionWriteControllerProvider).error;
    context.showSnackBar(
      err == null ? 'Could not save the enquiry.' : userMessageFor(err),
      isError: true,
    );
  }

  String? _required(String? v, String what) =>
      (v == null || v.trim().isEmpty) ? '$what is required' : null;

  @override
  Widget build(BuildContext context) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.contact_phone_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final settings =
            ref.watch(admissionSettingsProvider(schoolId)).value ??
            const AdmissionSettings();
        final editing = widget.enquiryId != null;
        if (editing) {
          final existing = ref.watch(
            enquiryProvider((
              schoolId: schoolId,
              branchId: branchId,
              enquiryId: widget.enquiryId!,
            )),
          );
          if (existing.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final e = existing.value;
          if (e == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This enquiry could not be found.',
            );
          }
          _seed(e);
        }
        final saving = ref.watch(admissionWriteControllerProvider).isLoading;
        final wide = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        final key = (schoolId: schoolId, branchId: branchId);
        final years = [
          for (final y
              in ref.watch(academicYearsProvider(key)).value ?? const [])
            if (settings.academicYearIds.isEmpty ||
                settings.academicYearIds.contains(y.academicYearId))
              y,
        ];
        final classes = _yearId == null
            ? const []
            : [
                for (final c
                    in ref
                            .watch(
                              classesProvider((
                                schoolId: schoolId,
                                branchId: branchId,
                                academicYearId: _yearId!,
                              )),
                            )
                            .value ??
                        const [])
                  if (settings.classIds.isEmpty ||
                      settings.classIds.contains(c.classId))
                    c,
              ];
        final sources = settings.sources;

        Widget two(Widget a, Widget b) => wide.isMobile
            ? Column(children: [a, const SizedBox(height: 12), b])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 12),
                  Expanded(child: b),
                ],
              );
        Widget field(
          TextEditingController c,
          String label, {
          bool required = false,
          TextInputType? type,
          int maxLines = 1,
        }) => TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: required ? '$label *' : label),
          keyboardType: type,
          maxLines: maxLines,
          validator: required ? (v) => _required(v, label) : null,
        );
        Widget dateField(
          String label,
          String? value,
          ValueChanged<String?> onChanged, {
          required DateTime first,
          required DateTime last,
          bool required = false,
        }) => FormField<String>(
          validator: required
              ? (_) => value == null ? '$label is required' : null
              : null,
          builder: (state) => InkWell(
            onTap: () async {
              final v = await _pickDate(
                current: value,
                first: first,
                last: last,
              );
              if (v != null) setState(() => onChanged(v));
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: required ? '$label *' : label,
                errorText: state.errorText,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
              ),
              child: Text(value == null ? 'Select date' : shortDate(value)),
            ),
          ),
        );
        final now = DateTime.now();

        return Scaffold(
          body: Column(
            children: [
              ParentsPageBar(
                title: editing ? 'Edit enquiry' : 'New enquiry',
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.admissionEnquiries),
              ),
              Expanded(
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: EdgeInsets.all(wide.isMobile ? 16 : 24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ParentsCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const ParentsSectionTitle(
                                      icon: Icons.child_care_outlined,
                                      title: 'Student',
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      field(
                                        _first,
                                        'First name',
                                        required: true,
                                      ),
                                      field(_last, 'Last name'),
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      dateField(
                                        'Date of birth',
                                        _dob,
                                        (v) => _dob = v,
                                        first: DateTime(now.year - 25),
                                        last: now,
                                      ),
                                      DropdownButtonFormField<String>(
                                        value: _gender,
                                        decoration: const InputDecoration(
                                          labelText: 'Gender',
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'MALE',
                                            child: Text('Male'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'FEMALE',
                                            child: Text('Female'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'OTHER',
                                            child: Text('Other'),
                                          ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _gender = v),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      field(_prevSchool, 'Previous school'),
                                      field(_prevClass, 'Previous class'),
                                    ),
                                    const SizedBox(height: 12),
                                    field(
                                      _special,
                                      'Special requirements',
                                      maxLines: 2,
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
                                      title: 'Enquiry',
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      DropdownButtonFormField<String>(
                                        value:
                                            years.any(
                                              (y) =>
                                                  y.academicYearId == _yearId,
                                            )
                                            ? _yearId
                                            : null,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Academic year *',
                                        ),
                                        items: [
                                          for (final y in years)
                                            DropdownMenuItem(
                                              value: y.academicYearId as String,
                                              child: Text(y.name as String),
                                            ),
                                        ],
                                        validator: (v) => v == null
                                            ? 'Academic year is required'
                                            : null,
                                        onChanged: (v) => setState(() {
                                          _yearId = v;
                                          _classId = null;
                                        }),
                                      ),
                                      DropdownButtonFormField<String>(
                                        value:
                                            classes.any(
                                              (c) => c.classId == _classId,
                                            )
                                            ? _classId
                                            : null,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Interested class *',
                                        ),
                                        items: [
                                          for (final c in classes)
                                            DropdownMenuItem(
                                              value: c.classId as String,
                                              child: Text(c.name as String),
                                            ),
                                        ],
                                        validator: (v) => v == null
                                            ? 'Class is required'
                                            : null,
                                        onChanged: _yearId == null
                                            ? null
                                            : (v) =>
                                                  setState(() => _classId = v),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      DropdownButtonFormField<String>(
                                        value: sources.contains(_source)
                                            ? _source
                                            : null,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Source *',
                                        ),
                                        items: [
                                          for (final s in sources)
                                            DropdownMenuItem(
                                              value: s,
                                              child: Text(s),
                                            ),
                                        ],
                                        validator: (v) => v == null
                                            ? 'Source is required'
                                            : null,
                                        onChanged: (v) =>
                                            setState(() => _source = v),
                                      ),
                                      dateField(
                                        'Next follow-up',
                                        _followUp,
                                        (v) => _followUp = v,
                                        first: now.subtract(
                                          const Duration(days: 1),
                                        ),
                                        last: DateTime(now.year + 2),
                                      ),
                                    ),
                                    if (!editing) ...[
                                      const SizedBox(height: 12),
                                      dateField(
                                        'Enquiry date (today if left empty)',
                                        _enquiryDate,
                                        (v) => _enquiryDate = v,
                                        first: DateTime(now.year - 1),
                                        last: now,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ParentsCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const ParentsSectionTitle(
                                      icon: Icons.family_restroom_outlined,
                                      title: 'Parent / guardian',
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      field(_g1Name, 'Name', required: true),
                                      field(_g1Relation, 'Relationship'),
                                    ),
                                    const SizedBox(height: 12),
                                    two(
                                      field(
                                        _g1Phone,
                                        'Mobile',
                                        required: true,
                                        type: TextInputType.phone,
                                      ),
                                      field(
                                        _g1Email,
                                        'Email',
                                        type: TextInputType.emailAddress,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Second guardian (optional)',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 8),
                                    two(
                                      field(_g2Name, 'Name'),
                                      field(
                                        _g2Phone,
                                        'Mobile',
                                        type: TextInputType.phone,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    field(_address, 'Address'),
                                    const SizedBox(height: 12),
                                    two(
                                      field(_city, 'City'),
                                      field(_state, 'State'),
                                    ),
                                    const SizedBox(height: 12),
                                    field(_country, 'Country'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ParentsCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const ParentsSectionTitle(
                                      icon: Icons.sticky_note_2_outlined,
                                      title: 'Internal notes',
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Only school staff see this. It is never '
                                      'shown to parents.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 12),
                                    field(_remarks, 'Remarks', maxLines: 3),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: saving
                                          ? null
                                          : () => context.canPop()
                                                ? context.pop()
                                                : context.go(
                                                    AppRoutes
                                                        .admissionEnquiries,
                                                  ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: saving
                                          ? null
                                          : () => _save(schoolId, branchId),
                                      child: saving
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              editing ? 'Save' : 'Save enquiry',
                                            ),
                                    ),
                                  ),
                                ],
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
  }
}
