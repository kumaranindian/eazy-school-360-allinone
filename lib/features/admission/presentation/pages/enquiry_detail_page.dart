import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_status.dart';
import '../providers/admission_providers.dart';
import '../widgets/admission_widgets.dart';

enum _Tab { overview, timeline, notes }

/// One enquiry: overview, status history and internal notes, with the actions
/// that are allowed from its current status (change status, assign, edit).
class EnquiryDetailPage extends ConsumerStatefulWidget {
  final String enquiryId;
  const EnquiryDetailPage({super.key, required this.enquiryId});

  @override
  ConsumerState<EnquiryDetailPage> createState() => _EnquiryDetailPageState();
}

class _EnquiryDetailPageState extends ConsumerState<EnquiryDetailPage> {
  _Tab _tab = _Tab.overview;

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
        final key = (
          schoolId: schoolId,
          branchId: branchId,
          enquiryId: widget.enquiryId,
        );
        return AsyncValueWidget(
          value: ref.watch(enquiryProvider(key)),
          data: (e) {
            if (e == null) {
              return const EmptyView(
                icon: Icons.search_off,
                message: 'This enquiry could not be found.',
              );
            }
            return _content(context, e, key);
          },
        );
      },
    );
  }

  Widget _content(BuildContext context, AdmissionEnquiry e, EnquiryKey key) {
    // Keeps the write controller alive while a callable is in flight (the
    // actions only `read` it).
    ref.watch(admissionWriteControllerProvider);
    final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);
    final options = e.status.manualOptions();
    return Scaffold(
      body: Column(
        children: [
          ParentsPageBar(
            title: e.enquiryNumber,
            onBack: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.admissionEnquiries),
            trailing: e.status.isClosed
                ? null
                : IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        context.push('/admissions/enquiries/${e.id}/edit'),
                  ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(layout.isMobile ? 16 : 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(enquiry: e, schoolBranch: key),
                        if (e.duplicateOf.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _DuplicateCard(ids: e.duplicateOf),
                        ],
                        const SizedBox(height: 12),
                        _Actions(
                          enquiry: e,
                          canChange: options.isNotEmpty,
                          onStatus: () => _changeStatus(context, e, key),
                          onAssign: e.status.isClosed
                              ? null
                              : () => _assign(context, e, key),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final t in _Tab.values)
                              ChoiceChip(
                                label: Text(switch (t) {
                                  _Tab.overview => 'Overview',
                                  _Tab.timeline => 'Timeline',
                                  _Tab.notes => 'Internal notes',
                                }),
                                selected: _tab == t,
                                onSelected: (_) => setState(() => _tab = t),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        switch (_tab) {
                          _Tab.overview => _Overview(
                            enquiry: e,
                            key: ValueKey(e.revision),
                          ),
                          _Tab.timeline => _Timeline(enquiry: e, keyData: key),
                          _Tab.notes => _Notes(enquiry: e),
                        },
                        const SizedBox(height: 24),
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
  }

  Future<void> _changeStatus(
    BuildContext context,
    AdmissionEnquiry e,
    EnquiryKey key,
  ) async {
    final result = await showDialog<({String status, String? reason})>(
      context: context,
      builder: (_) => _StatusDialog(enquiry: e),
    );
    if (result == null || !mounted) return;
    final ok = await ref
        .read(admissionWriteControllerProvider.notifier)
        .changeStatus(
          schoolId: key.schoolId,
          branchId: key.branchId,
          enquiryId: key.enquiryId,
          status: result.status,
          reason: result.reason,
          baseRevision: e.revision,
        );
    if (!mounted) return;
    _report(ok, 'Status updated.');
  }

  Future<void> _assign(
    BuildContext context,
    AdmissionEnquiry e,
    EnquiryKey key,
  ) async {
    final people = await ref.read(
      assigneesProvider((
        schoolId: key.schoolId,
        branchId: key.branchId,
      )).future,
    );
    if (!mounted) return;
    final choice = await showDialog<({String? userId})>(
      // The page is still mounted (checked above).
      // ignore: use_build_context_synchronously
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Assign to'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, (userId: null)),
            child: const Text('Unassigned'),
          ),
          for (final p in people)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, (userId: p.userId)),
              child: Text(
                p.name,
                style: e.assignedTo == p.userId
                    ? const TextStyle(fontWeight: FontWeight.w800)
                    : null,
              ),
            ),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No staff with a login were found in this branch.'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ok = await ref
        .read(admissionWriteControllerProvider.notifier)
        .assign(
          schoolId: key.schoolId,
          branchId: key.branchId,
          enquiryId: key.enquiryId,
          assignedTo: choice.userId,
        );
    if (!mounted) return;
    _report(ok, 'Assignment updated.');
  }

  void _report(bool ok, String success) {
    if (ok) {
      context.showSnackBar(success);
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'That did not work.' : userMessageFor(err),
        isError: true,
      );
    }
  }
}

class _Header extends ConsumerWidget {
  final AdmissionEnquiry enquiry;
  final EnquiryKey schoolBranch;
  const _Header({required this.enquiry, required this.schoolBranch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    final years =
        ref
            .watch(
              academicYearsProvider((
                schoolId: schoolBranch.schoolId,
                branchId: schoolBranch.branchId,
              )),
            )
            .value ??
        const [];
    final classes =
        ref
            .watch(
              classesProvider((
                schoolId: schoolBranch.schoolId,
                branchId: schoolBranch.branchId,
                academicYearId: enquiry.academicYearId,
              )),
            )
            .value ??
        const [];
    final year = years
        .where((y) => y.academicYearId == enquiry.academicYearId)
        .map((y) => y.name)
        .firstOrNull;
    final cls = classes
        .where((c) => c.classId == enquiry.interestedClassId)
        .map((c) => c.name)
        .firstOrNull;
    return ParentsCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ParentsAvatar(name: enquiry.studentName, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      enquiry.studentName,
                      style: t.titleLarge?.copyWith(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AdmissionStatusBadge(enquiry.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (cls != null) 'Class $cls',
                    if (year != null) year,
                    'Enquired ${shortDate(enquiry.enquiryDate)}',
                  ].join(' · '),
                  style: t.bodyMedium?.copyWith(color: p.textSecondary),
                ),
                if (enquiry.statusReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Reason: ${enquiry.statusReason}',
                      style: t.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  final List<String> ids;
  const _DuplicateCard({required this.ids});

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ParentsSectionTitle(
            icon: Icons.warning_amber_outlined,
            title: 'Possible duplicate',
            color: p.warning,
          ),
          const SizedBox(height: 6),
          const Text(
            'An enquiry with the same mobile number, student name and date of '
            'birth already exists for this academic year. Nothing was merged — '
            'please check and close this one if it is a repeat.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final id in ids)
                ActionChip(
                  label: const Text('Open the earlier enquiry'),
                  onPressed: () => context.push('/admissions/enquiries/$id'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final AdmissionEnquiry enquiry;
  final bool canChange;
  final VoidCallback onStatus;
  final VoidCallback? onAssign;
  const _Actions({
    required this.enquiry,
    required this.canChange,
    required this.onStatus,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: canChange ? onStatus : null,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Change status'),
        ),
        OutlinedButton.icon(
          onPressed: onAssign,
          icon: const Icon(Icons.person_add_alt_outlined),
          label: const Text('Assign'),
        ),
      ],
    );
  }
}

class _Overview extends ConsumerWidget {
  final AdmissionEnquiry enquiry;
  const _Overview({super.key, required this.enquiry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = enquiry;
    final assignee = e.assignedTo == null
        ? null
        : (ref
                      .watch(
                        assigneesProvider((
                          schoolId: e.schoolId,
                          branchId: e.branchId,
                        )),
                      )
                      .value ??
                  const [])
              .where((a) => a.userId == e.assignedTo)
              .map((a) => a.name)
              .firstOrNull;
    Widget card(IconData icon, String title, List<Widget> rows) => ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ParentsSectionTitle(icon: icon, title: title),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
    final left = [
      card(Icons.child_care_outlined, 'Student', [
        ParentsFactRow(
          icon: Icons.badge_outlined,
          label: 'Name',
          text: e.studentName,
        ),
        if (e.dateOfBirth != null)
          ParentsFactRow(
            icon: Icons.cake_outlined,
            label: 'Date of birth',
            text: shortDate(e.dateOfBirth),
          ),
        if (e.gender != null)
          ParentsFactRow(
            icon: Icons.wc_outlined,
            label: 'Gender',
            text: _gender(e.gender!),
          ),
        if (e.previousSchool != null)
          ParentsFactRow(
            icon: Icons.school_outlined,
            label: 'Previous school',
            text: [
              e.previousSchool,
              e.previousClass,
            ].whereType<String>().join(' · '),
          ),
        if (e.specialRequirements != null)
          ParentsFactRow(
            icon: Icons.accessibility_new_outlined,
            label: 'Special requirements',
            text: e.specialRequirements!,
          ),
      ]),
      card(Icons.contact_phone_outlined, 'Enquiry', [
        ParentsFactRow(
          icon: Icons.tag,
          label: 'Enquiry number',
          text: e.enquiryNumber,
        ),
        ParentsFactRow(
          icon: Icons.campaign_outlined,
          label: 'Source',
          text: e.source,
        ),
        ParentsFactRow(
          icon: Icons.support_agent_outlined,
          label: 'Assigned to',
          text: e.assignedTo == null
              ? 'Unassigned'
              : (assignee ?? 'Staff member'),
        ),
        if (e.nextFollowUpDate != null)
          ParentsFactRow(
            icon: Icons.event_outlined,
            label: 'Next follow-up',
            text: shortDate(e.nextFollowUpDate),
          ),
      ]),
    ];
    final right = [
      card(Icons.family_restroom_outlined, 'Parent / guardian', [
        for (final g in e.guardians) ...[
          ParentsFactRow(
            icon: Icons.person_outline,
            label: g.primary ? 'Primary contact' : 'Guardian',
            text: [g.name, g.relationship].whereType<String>().join(' · '),
          ),
          ParentsFactRow(icon: Icons.phone_outlined, text: g.phone),
          if (g.email != null)
            ParentsFactRow(icon: Icons.mail_outline, text: g.email!),
        ],
        if ([e.addressLine1, e.city, e.state, e.country].any((s) => s != null))
          ParentsFactRow(
            icon: Icons.home_outlined,
            label: 'Address',
            text: [
              e.addressLine1,
              e.city,
              e.state,
              e.country,
            ].whereType<String>().join(', '),
          ),
      ]),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 700) {
          return Column(
            children: [
              for (final w in [...left, ...right]) ...[
                w,
                const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final w in left) ...[w, const SizedBox(height: 12)],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final w in right) ...[w, const SizedBox(height: 12)],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _gender(String g) => switch (g) {
    'MALE' => 'Male',
    'FEMALE' => 'Female',
    _ => 'Other',
  };
}

class _Timeline extends ConsumerWidget {
  final AdmissionEnquiry enquiry;
  final EnquiryKey keyData;
  const _Timeline({required this.enquiry, required this.keyData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AdminDashboardPalette.of(context);
    final history = ref.watch(
      enquiryHistoryProvider((keyData, enquiry.revision)),
    );
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ParentsSectionTitle(
            icon: Icons.timeline,
            title: 'Status history',
          ),
          const SizedBox(height: 8),
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => Text(userMessageFor(err)),
            data: (entries) => entries.isEmpty
                ? const Text('No history yet.')
                : Column(
                    children: [
                      for (final h in entries.reversed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.circle,
                            size: 12,
                            color: p.primary,
                          ),
                          title: Text(
                            h.from == null
                                ? 'Enquiry created (${h.to.label})'
                                : h.resumed
                                ? 'Resumed: ${h.from!.label} → ${h.to.label}'
                                : '${h.from!.label} → ${h.to.label}',
                          ),
                          subtitle: Text(
                            [
                              if (h.at != null) _stamp(h.at!),
                              if (h.reason != null) 'Reason: ${h.reason}',
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${shortDate('${l.year}-${two(l.month)}-${two(l.day)}')} '
        '${two(l.hour)}:${two(l.minute)}';
  }
}

class _Notes extends StatelessWidget {
  final AdmissionEnquiry enquiry;
  const _Notes({required this.enquiry});

  @override
  Widget build(BuildContext context) {
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ParentsSectionTitle(
            icon: Icons.sticky_note_2_outlined,
            title: 'Internal notes',
          ),
          const SizedBox(height: 4),
          Text(
            'Only school staff see these. They are never shown to parents.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(enquiry.remarks ?? 'No notes yet. Add them with Edit.'),
        ],
      ),
    );
  }
}

class _StatusDialog extends StatefulWidget {
  final AdmissionEnquiry enquiry;
  const _StatusDialog({required this.enquiry});

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  String? _choice;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _label(String wire) => wire == 'RESUME'
      ? 'Resume (back to ${widget.enquiry.heldFrom?.label ?? 'previous status'})'
      : AdmissionStatus.tryParse(wire)?.label ?? wire;

  bool get _needsReason =>
      _choice != null &&
      (AdmissionStatus.tryParse(_choice)?.needsReason ?? false);

  @override
  Widget build(BuildContext context) {
    final options = widget.enquiry.status.manualOptions();
    final reasonOk = !_needsReason || _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Change status'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Currently ${widget.enquiry.status.label}.'),
              const SizedBox(height: 8),
              for (final o in options)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: o,
                  groupValue: _choice,
                  onChanged: (v) => setState(() => _choice = v),
                  title: Text(_label(o)),
                ),
              if (_choice != null && _choice != 'RESUME')
                TextField(
                  controller: _reason,
                  onChanged: (_) => setState(() {}),
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: _needsReason ? 'Reason *' : 'Reason (optional)',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _choice == null || !reasonOk
              ? null
              : () => Navigator.pop(context, (
                  status: _choice!,
                  reason: _reason.text.trim().isEmpty
                      ? null
                      : _reason.text.trim(),
                )),
          child: const Text('Update'),
        ),
      ],
    );
  }
}
