import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/fee_structure.dart';
import '../providers/fee_providers.dart';
import 'fee_scope.dart';

/// "Copy fee structures from another academic year": the year-end step that
/// otherwise means re-typing every fee. Copies ACTIVE structures into the
/// year currently selected, skipping any code that already exists there.
/// Class/section-specific fees are matched to the same-named class/section in
/// the target year; a fee whose class does not exist there is reported, never
/// guessed. Effective-date windows are cleared (they belong to the old year).
class CopyStructuresDialog extends ConsumerStatefulWidget {
  final FeeContext fee;
  const CopyStructuresDialog({super.key, required this.fee});

  @override
  ConsumerState<CopyStructuresDialog> createState() =>
      _CopyStructuresDialogState();
}

class _CopyStructuresDialogState extends ConsumerState<CopyStructuresDialog> {
  String? _sourceYearId;
  bool _busy = false;
  String? _result;
  String? _error;

  static String _n(String s) => s.trim().toLowerCase();

  Future<void> _copy(List<AcademicYear> years) async {
    final fee = widget.fee;
    final sourceId = _sourceYearId;
    if (sourceId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final config = ref.read(feeConfigRepositoryProvider);
      final academic = ref.read(academicStructureRepositoryProvider);
      final targetId = fee.year.academicYearId;

      final source =
          (await config
                  .watchStructures(fee.schoolId, fee.branchId, sourceId)
                  .first)
              .where((s) => s.isActive)
              .toList();
      final existing =
          (await config
                  .watchStructures(fee.schoolId, fee.branchId, targetId)
                  .first)
              .map((s) => s.code.toLowerCase())
              .toSet();

      Future<Map<String, String>> classIdsByName(String yearId) async => {
        for (final c
            in await academic
                .watchClasses(fee.schoolId, fee.branchId, yearId)
                .first)
          _n(c.name): c.classId,
      };
      final srcClasses = {
        for (final c
            in await academic
                .watchClasses(fee.schoolId, fee.branchId, sourceId)
                .first)
          c.classId: c,
      };
      final targetClassIds = await classIdsByName(targetId);

      var created = 0, already = 0;
      final unmapped = <String>[];
      final failures = <String>[];

      for (final s in source) {
        if (existing.contains(s.code.toLowerCase())) {
          already++;
          continue;
        }
        String? classId;
        String? sectionId;
        if (s.classId != null) {
          final srcClass = srcClasses[s.classId];
          classId = srcClass == null ? null : targetClassIds[_n(srcClass.name)];
          if (classId == null) {
            unmapped.add('${s.name} (${srcClass?.name ?? 'unknown class'})');
            continue;
          }
          if (s.sectionId != null) {
            final srcSections = await academic
                .watchSections(fee.schoolId, fee.branchId, sourceId, s.classId!)
                .first;
            final name = srcSections
                .where((x) => x.sectionId == s.sectionId)
                .map((x) => x.name)
                .firstOrNull;
            final targetSections = await academic
                .watchSections(fee.schoolId, fee.branchId, targetId, classId)
                .first;
            sectionId = name == null
                ? null
                : targetSections
                      .where((x) => _n(x.name) == _n(name))
                      .map((x) => x.sectionId)
                      .firstOrNull;
            if (sectionId == null) {
              unmapped.add('${s.name} (section ${name ?? '?'})');
              continue;
            }
          }
        }
        try {
          await config.createStructure(
            FeeStructure(
              structureId: FeeStructure.idFor(targetId, s.code),
              schoolId: fee.schoolId,
              branchId: fee.branchId,
              academicYearId: targetId,
              code: s.code,
              name: s.name,
              category: s.category,
              customCategoryLabel: s.customCategoryLabel,
              frequency: s.frequency,
              amountMinor: s.amountMinor,
              classId: classId,
              sectionId: sectionId,
              isOptional: s.isOptional,
              dueOffsetDays: s.dueOffsetDays,
              description: s.description,
              paymentInstructions: s.paymentInstructions,
              status: s.status,
            ),
            actorId: fee.userId,
          );
          created++;
        } catch (error, stackTrace) {
          AppLogger.error(
            'Copy fee structure "${s.code}" failed',
            tag: 'Fees',
            error: error,
            stackTrace: stackTrace,
          );
          failures.add('${s.name}: ${userMessageFor(error)}');
        }
      }

      AppLogger.debug(
        'Copy fee structures $sourceId -> $targetId: created=$created '
        'already=$already unmapped=${unmapped.length} failed=${failures.length}',
        tag: 'Fees',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = [
          'Copied $created fee(s) into ${fee.year.name}.',
          if (already > 0) '$already already existed here and were left as is.',
          if (unmapped.isNotEmpty)
            'Not copied — class/section not found in ${fee.year.name}: '
                '${unmapped.join(', ')}. Create the class/section first, '
                'then copy again.',
          for (final f in failures) 'Failed — $f',
          if (created > 0)
            'Review amounts and effective dates; assign the fees to students '
                'under Fees → Assign.',
        ].join('\n');
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Copy fee structures failed',
        tag: 'Fees',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _error = userMessageFor(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final years =
        (ref
                    .watch(
                      academicYearsProvider((
                        schoolId: fee.schoolId,
                        branchId: fee.branchId,
                      )),
                    )
                    .value ??
                const <AcademicYear>[])
            .where((y) => y.academicYearId != fee.year.academicYearId)
            .toList();

    return AlertDialog(
      title: Text('Copy fees into ${fee.year.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copies the active fee structures of another academic year '
              'into this one. Existing codes are skipped; effective dates '
              'are cleared.',
            ),
            const SizedBox(height: 12),
            if (years.isEmpty)
              const Text('There is no other academic year to copy from.')
            else
              DropdownButtonFormField<String>(
                value: _sourceYearId,
                decoration: const InputDecoration(labelText: 'Copy from'),
                items: [
                  for (final y in years)
                    DropdownMenuItem(
                      value: y.academicYearId,
                      child: Text(y.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _sourceYearId = v),
              ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pop(_result != null),
          child: Text(_result == null ? 'Cancel' : 'Close'),
        ),
        if (_result == null)
          FilledButton(
            onPressed: (_busy || _sourceYearId == null)
                ? null
                : () => _copy(years),
            child: const Text('Copy fees'),
          ),
      ],
    );
  }
}
