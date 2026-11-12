import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_application.dart';
import '../../domain/admission_enquiry.dart';
import '../providers/admission_providers.dart';
import '../widgets/admission_widgets.dart';

/// Edit the details of a DRAFT application. They start as a copy of the enquiry
/// and can be corrected here without touching the enquiry itself.
class ApplicationFormPage extends ConsumerStatefulWidget {
  final String enquiryId;
  const ApplicationFormPage({super.key, required this.enquiryId});

  @override
  ConsumerState<ApplicationFormPage> createState() =>
      _ApplicationFormPageState();
}

class _ApplicationFormPageState extends ConsumerState<ApplicationFormPage> {
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
  final _notes = TextEditingController();
  String? _dob;
  String? _gender;
  String? _yearId;
  String? _classId;
  bool _seeded = false;

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
    _notes,
  ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(AdmissionApplication a) {
    if (_seeded) return;
    _seeded = true;
    _first.text = a.firstName;
    _last.text = a.lastName;
    _dob = a.dateOfBirth;
    _gender = a.gender;
    _yearId = a.academicYearId;
    _classId = a.classId;
    final g = a.guardians;
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
    _address.text = a.addressLine1 ?? '';
    _city.text = a.city ?? '';
    _state.text = a.state ?? '';
    _country.text = a.country ?? '';
    _prevSchool.text = a.previousSchool ?? '';
    _prevClass.text = a.previousClass ?? '';
    _special.text = a.specialRequirements ?? '';
    _notes.text = a.submissionNotes ?? '';
  }

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  ApplicationInput _input() => ApplicationInput(
    details: EnquiryInput(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      dateOfBirth: _dob,
      gender: _gender,
      academicYearId: _yearId ?? '',
      interestedClassId: _classId ?? '',
      source: '',
      guardians: [
        EnquiryGuardian(
          name: _g1Name.text.trim(),
          phone: _g1Phone.text.trim(),
          relationship: _t(_g1Relation),
          email: _t(_g1Email),
          primary: true,
        ),
        if (_g2Name.text.trim().isNotEmpty || _g2Phone.text.trim().isNotEmpty)
          EnquiryGuardian(
            name: _g2Name.text.trim(),
            phone: _g2Phone.text.trim(),
          ),
      ],
      addressLine1: _t(_address),
      city: _t(_city),
      state: _t(_state),
      country: _t(_country),
      previousSchool: _t(_prevSchool),
      previousClass: _t(_prevClass),
      specialRequirements: _t(_special),
    ),
    submissionNotes: _t(_notes),
  );

  Future<void> _save(
    String schoolId,
    String branchId,
    AdmissionApplication a,
  ) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final ok = await ref
        .read(admissionWriteControllerProvider.notifier)
        .updateApplication(
          schoolId: schoolId,
          branchId: branchId,
          application: a,
          input: _input(),
        );
    if (!mounted) return;
    if (ok) {
      context.showSnackBar('Application saved.');
      context.pop();
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'Could not save the application.' : userMessageFor(err),
        isError: true,
      );
    }
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
            icon: Icons.description_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final key = (
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: widget.enquiryId,
        );
        final app = ref.watch(applicationProvider(key));
        if (app.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final a = app.value;
        if (a == null) {
          return const EmptyView(
            icon: Icons.search_off,
            message: 'This application could not be found.',
          );
        }
        if (a.status != ApplicationStatus.draft) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'Only a draft application can be edited.',
          );
        }
        _seed(a);
        final saving = ref.watch(admissionWriteControllerProvider).isLoading;
        final wide = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        final bk = (schoolId: schoolId, branchId: branchId);
        final years = ref.watch(academicYearsProvider(bk)).value ?? const [];
        final classes = _yearId == null
            ? const []
            : (ref
                      .watch(
                        classesProvider((
                          schoolId: schoolId,
                          branchId: branchId,
                          academicYearId: _yearId!,
                        )),
                      )
                      .value ??
                  const []);

        Widget two(Widget x, Widget y) => wide.isMobile
            ? Column(children: [x, const SizedBox(height: 12), y])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: x),
                  const SizedBox(width: 12),
                  Expanded(child: y),
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
        final today = SchoolTime.today();

        return Scaffold(
          body: Column(
            children: [
              ParentsPageBar(
                title: 'Edit application ${a.applicationNumber}',
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go('/admissions/enquiries/${a.enquiryId}'),
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
                                      FormField<String>(
                                        validator: (_) => _dob == null
                                            ? 'Date of birth is required'
                                            : null,
                                        builder: (state) => InkWell(
                                          onTap: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate:
                                                  DateTime.tryParse(
                                                    _dob ?? '',
                                                  ) ??
                                                  DateTime(today.year - 5),
                                              firstDate: DateTime(
                                                today.year - 25,
                                              ),
                                              lastDate: today,
                                            );
                                            if (picked != null) {
                                              setState(
                                                () => _dob = SchoolTime.keyOf(
                                                  picked,
                                                ),
                                              );
                                            }
                                          },
                                          child: InputDecorator(
                                            decoration: InputDecoration(
                                              labelText: 'Date of birth *',
                                              errorText: state.errorText,
                                              suffixIcon: const Icon(
                                                Icons.calendar_today_outlined,
                                                size: 18,
                                              ),
                                            ),
                                            child: Text(
                                              _dob == null
                                                  ? 'Select date'
                                                  : shortDate(_dob),
                                            ),
                                          ),
                                        ),
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
                                              value: y.academicYearId,
                                              child: Text(y.name),
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
                                          labelText: 'Class *',
                                        ),
                                        items: [
                                          for (final c in classes)
                                            DropdownMenuItem(
                                              value: c.classId,
                                              child: Text(c.name),
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
                                      icon: Icons.notes_outlined,
                                      title: 'Submission notes',
                                    ),
                                    const SizedBox(height: 12),
                                    field(
                                      _notes,
                                      'Notes for the reviewer',
                                      maxLines: 3,
                                    ),
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
                                                    '/admissions/enquiries/${a.enquiryId}',
                                                  ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: saving
                                          ? null
                                          : () => _save(schoolId, branchId, a),
                                      child: saving
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Save'),
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
