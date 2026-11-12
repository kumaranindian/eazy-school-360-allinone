import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_status.dart';
import '../../domain/enquiry_query.dart';
import '../providers/admission_providers.dart';
import '../widgets/admission_widgets.dart';

/// All enquiries of the branch: search (name, mobile or enquiry number), the
/// filters, cursor paging, and a card per enquiry (one column on a phone, two
/// on wide screens).
class EnquiryListPage extends ConsumerStatefulWidget {
  const EnquiryListPage({super.key});

  @override
  ConsumerState<EnquiryListPage> createState() => _EnquiryListPageState();
}

class _EnquiryListPageState extends ConsumerState<EnquiryListPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  EnquiryFilters _filters = const EnquiryFilters();

  final List<AdmissionEnquiry> _items = [];
  Object? _cursor;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;
  String? _schoolId;
  String? _branchId;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  EnquirySearch? get _searching => EnquirySearch.parse(_search.text);

  void _reset() {
    _generation++;
    _items.clear();
    _cursor = null;
    _error = null;
    _load();
  }

  Future<void> _load() async {
    final schoolId = _schoolId;
    final branchId = _branchId;
    if (schoolId == null || branchId == null || _loading) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(admissionRepositoryProvider)
          .fetchEnquiries(
            schoolId: schoolId,
            branchId: branchId,
            filters: _filters,
            search: _searching,
            cursor: _cursor,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loadedOnce = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loadedOnce = true;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _reset();
    });
    setState(() {});
  }

  void _setFilters(EnquiryFilters f) {
    setState(() => _filters = f);
    _reset();
  }

  Future<void> _pickDate(bool from) async {
    final now = SchoolTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    _setFilters(
      from ? _filters.copyWith(fromDate: iso) : _filters.copyWith(toDate: iso),
    );
  }

  List<FilterField> _fields(
    List<String> sources,
    List<({String id, String name})> years,
    List<({String id, String name})> classes,
  ) => [
    FilterField.dropdown<AdmissionStatus>(
      label: 'Status',
      value: _filters.status,
      options: [
        (null, 'All statuses'),
        for (final s in AdmissionStatus.values) (s, s.label),
      ],
      onChanged: (v) => _setFilters(_filters.copyWith(status: v)),
    ),
    FilterField.dropdown<String>(
      label: 'Source',
      value: _filters.source,
      options: [(null, 'All sources'), for (final s in sources) (s, s)],
      onChanged: (v) => _setFilters(_filters.copyWith(source: v)),
    ),
    FilterField.dropdown<String>(
      label: 'Academic year',
      value: _filters.academicYearId,
      options: [(null, 'All years'), for (final y in years) (y.id, y.name)],
      onChanged: (v) =>
          _setFilters(_filters.copyWith(academicYearId: v, classId: null)),
    ),
    FilterField.dropdown<String>(
      label: 'Class',
      value: _filters.classId,
      options: [(null, 'All classes'), for (final c in classes) (c.id, c.name)],
      onChanged: _filters.academicYearId == null
          ? null
          : (v) => _setFilters(_filters.copyWith(classId: v)),
    ),
    FilterField.picker(
      label: 'From date',
      value: _filters.fromDate == null ? null : shortDate(_filters.fromDate),
      onPick: () => _pickDate(true),
      onClear: () => _setFilters(_filters.copyWith(fromDate: null)),
    ),
    FilterField.picker(
      label: 'To date',
      value: _filters.toDate == null ? null : shortDate(_filters.toDate),
      onPick: () => _pickDate(false),
      onClear: () => _setFilters(_filters.copyWith(toDate: null)),
    ),
  ];

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
        if (_schoolId != schoolId || _branchId != branchId) {
          _schoolId = schoolId;
          _branchId = branchId;
          _loadedOnce = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reset();
          });
        }
        final settings = ref.watch(admissionSettingsProvider(schoolId)).value;
        final branchKey = (schoolId: schoolId, branchId: branchId);
        final years =
            ref.watch(academicYearsProvider(branchKey)).value ?? const [];
        final yearId = _filters.academicYearId;
        final classes = yearId == null
            ? const []
            : (ref
                      .watch(
                        classesProvider((
                          schoolId: schoolId,
                          branchId: branchId,
                          academicYearId: yearId,
                        )),
                      )
                      .value ??
                  const []);
        final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              await context.push(AppRoutes.admissionNewEnquiry);
              if (mounted) _reset();
            },
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('New enquiry'),
          ),
          body: Column(
            children: [
              ParentsPageBar(
                title: 'Enquiries',
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.admissions),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(layout.isMobile ? 16 : 24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilterBar(
                              searchController: _search,
                              searchHint: 'Search name, mobile or enquiry no.',
                              onSearchChanged: _onSearchChanged,
                              filtersEnabled: _searching == null,
                              fieldsBuilder: () => _fields(
                                settings?.sources ?? const [],
                                [
                                  for (final y in years)
                                    (id: y.academicYearId, name: y.name),
                                ],
                                [
                                  for (final c in classes)
                                    (id: c.classId, name: c.name),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _body(layout, years, classes),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(ScreenSize layout, List<dynamic> years, List<dynamic> classes) {
    final p = AdminDashboardPalette.of(context);
    if (!_loadedOnce && _loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _items.isEmpty) {
      return EmptyView(
        icon: Icons.error_outline,
        message: userMessageFor(_error!),
      );
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.contact_phone_outlined,
        message: _searching != null || !_filters.isEmpty
            ? 'No enquiries match your search or filters.'
            : 'No enquiries yet. Add the first one with “New enquiry”.',
      );
    }
    String? className(String id) {
      for (final c in classes) {
        if (c.classId == id) return c.name as String;
      }
      return null;
    }

    final cards = [
      for (final e in _items)
        EnquiryCard(
          enquiry: e,
          className: className(e.interestedClassId),
          onTap: () async {
            await context.push('/admissions/enquiries/${e.id}');
            if (mounted) _reset();
          },
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _cursor == null
                ? '${_items.length} ${_items.length == 1 ? 'enquiry' : 'enquiries'}'
                : '${_items.length}+ enquiries',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final two = box.maxWidth >= 900;
            const gap = 12.0;
            final width = two ? (box.maxWidth - gap) / 2 : box.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in cards) SizedBox(width: width, child: c),
              ],
            );
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              userMessageFor(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_cursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: _load,
                      child: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}
