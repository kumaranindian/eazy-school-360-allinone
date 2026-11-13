import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/regional/regional_providers.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../fees/domain/money.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_application.dart';
import '../../domain/admission_conversion.dart';
import '../../domain/admission_fee.dart';
import '../providers/admission_providers.dart';

/// Shown on an APPROVED application: converts it into a student (admission
/// number, placement, parents and links, all in one server step), or shows
/// the student it became.
class ConversionCard extends ConsumerWidget {
  final AdmissionApplication application;
  final EnquiryKey keyData;
  final bool canConvert;
  const ConversionCard({
    super.key,
    required this.application,
    required this.keyData,
    required this.canConvert,
  });

  Future<void> _convert(
    BuildContext context,
    WidgetRef ref,
    int balanceMinor,
    String currency,
  ) async {
    final input = await showDialog<ConversionInput>(
      context: context,
      builder: (_) => _ConvertDialog(
        application: application,
        keyData: keyData,
        balanceMinor: balanceMinor,
        currency: currency,
      ),
    );
    if (input == null || !context.mounted) return;
    final r = await ref
        .read(admissionWriteControllerProvider.notifier)
        .convertToStudent(key: keyData, input: input);
    ref.invalidate(enquiryConversionProvider(keyData));
    ref.invalidate(enquiryFeesProvider(keyData));
    if (!context.mounted) return;
    if (r != null) {
      context.showSnackBar('Student created: ${r.admissionNumber}.');
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'That did not work.' : userMessageFor(err),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversion = ref.watch(enquiryConversionProvider(keyData));
    final fees = ref.watch(enquiryFeesProvider(keyData)).value ?? const [];
    final currency = ref.watch(regionalSettingsProvider).currency;
    final busy = ref.watch(admissionWriteControllerProvider).isLoading;
    final balance = AdmissionFeeSummary.of(fees).balanceMinor;
    return conversion.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ParentsCard(child: Text(userMessageFor(e))),
      data: (c) {
        if (c != null) {
          return ParentsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ParentsSectionTitle(
                  icon: Icons.school_outlined,
                  title: 'Converted to student',
                ),
                const SizedBox(height: 8),
                ParentsFactRow(
                  icon: Icons.badge_outlined,
                  label: 'Admission number',
                  text: c.admissionNumber,
                ),
                ParentsFactRow(
                  icon: Icons.family_restroom_outlined,
                  label: 'Parents linked',
                  text: '${c.parentIds.length}',
                ),
                if (c.studentId.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/students/${c.studentId}'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open student'),
                    ),
                  ),
                ],
                if (c.feeNetPaidMinor > 0 || c.feeBalanceMinor > 0)
                  ParentsFactRow(
                    icon: Icons.payments_outlined,
                    label: 'Admission fees',
                    text:
                        'Paid ${Money.format(c.feeNetPaidMinor, currency: currency)}'
                        ' · Balance ${Money.format(c.feeBalanceMinor, currency: currency)}',
                  ),
              ],
            ),
          );
        }
        if (!canConvert) {
          return const ParentsCard(
            child: Text(
              'An administrator who may decide admissions converts this '
              'approved application into a student.',
            ),
          );
        }
        return ParentsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ParentsSectionTitle(
                icon: Icons.school_outlined,
                title: 'Convert to student',
              ),
              const SizedBox(height: 8),
              const Text(
                'Creates the student with the next admission number, places '
                'them in a section, and links the parents. This cannot be '
                'done twice.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _convert(context, ref, balance, currency),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Convert to student'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConvertDialog extends ConsumerStatefulWidget {
  final AdmissionApplication application;
  final EnquiryKey keyData;
  final int balanceMinor;
  final String currency;
  const _ConvertDialog({
    required this.application,
    required this.keyData,
    required this.balanceMinor,
    required this.currency,
  });

  @override
  ConsumerState<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends ConsumerState<_ConvertDialog> {
  String? _sectionId;
  final _roll = TextEditingController();
  bool _accept = false;
  String? _error;

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  void _submit() {
    if (_sectionId == null) {
      setState(() => _error = 'Choose a section.');
      return;
    }
    if (widget.balanceMinor > 0 && !_accept) {
      setState(() => _error = 'Confirm that the unpaid fees may remain due.');
      return;
    }
    final roll = _roll.text.trim();
    Navigator.pop(
      context,
      ConversionInput(
        academicYearId: widget.application.academicYearId,
        classId: widget.application.classId,
        sectionId: _sectionId!,
        rollNumber: roll.isEmpty ? null : roll,
        acceptOutstandingFees: _accept,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    final sections =
        ref
            .watch(
              sectionsProvider((
                schoolId: widget.keyData.schoolId,
                branchId: widget.keyData.branchId,
                academicYearId: a.academicYearId,
                classId: a.classId,
              )),
            )
            .value ??
        const [];
    return AlertDialog(
      title: const Text('Convert to student'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.studentName),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _sectionId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Section *'),
              items: [
                for (final s in sections)
                  DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _sectionId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roll,
              decoration: const InputDecoration(
                labelText: 'Roll number (optional)',
              ),
            ),
            if (widget.balanceMinor > 0) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accept,
                onChanged: (v) => setState(() => _accept = v ?? false),
                title: Text(
                  'Admission fees of '
                  '${Money.format(widget.balanceMinor, currency: widget.currency)}'
                  ' are still due. Convert anyway.',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Convert')),
      ],
    );
  }
}
