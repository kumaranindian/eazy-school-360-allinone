import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/fee_structure.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/copy_structures_dialog.dart';
import '../widgets/fee_scope.dart';
import '../widgets/fee_structure_form_dialog.dart';

/// `/fees/structures` — fee heads for the chosen academic year. Anyone with
/// `viewFees` can read them; only `manageFeeStructures` holders get the
/// add/edit controls (the rules enforce it regardless).
class FeeStructuresPage extends ConsumerStatefulWidget {
  const FeeStructuresPage({super.key});

  @override
  ConsumerState<FeeStructuresPage> createState() => _FeeStructuresPageState();
}

class _FeeStructuresPageState extends ConsumerState<FeeStructuresPage> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fee structures')),
      body: FeeScope(
        builder: (context, fee) {
          final canManage = fee.tenant.can(Permission.manageFeeStructures);
          final structures = ref.watch(feeStructuresProvider(fee.yearKey));
          final classNames = {
            for (final c
                in ref.watch(classesProvider(fee.yearKey)).value ?? const [])
              c.classId: c.name,
          };

          Future<void> open({FeeStructure? existing}) async {
            final saved = await showAdaptiveAppDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) =>
                  FeeStructureFormDialog(fee: fee, existing: existing),
            );
            if (saved == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    existing == null
                        ? 'Fee created successfully.'
                        : 'Fee updated successfully.',
                  ),
                ),
              );
            }
          }

          return Stack(
            children: [
              AsyncValueWidget(
                value: structures,
                errorMessage: userMessageFor,
                data: (all) {
                  final list = all
                      .where((s) => _showInactive || s.isActive)
                      .toList();
                  return Column(
                    children: [
                      if (canManage)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16, top: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => showDialog<bool>(
                                context: context,
                                builder: (context) =>
                                    CopyStructuresDialog(fee: fee),
                              ),
                              icon: const Icon(Icons.copy_all_outlined),
                              label: const Text('Copy from another year'),
                            ),
                          ),
                        ),
                      SwitchListTile(
                        title: const Text('Show inactive fees'),
                        value: _showInactive,
                        onChanged: (v) => setState(() => _showInactive = v),
                      ),
                      Expanded(
                        child: ResponsiveDataList<FeeStructure>(
                          items: list,
                          columnHeaders: const [
                            'Code',
                            'Fee',
                            'Category',
                            'Billed',
                            'Amount',
                            'Applies to',
                            'Status',
                            '',
                          ],
                          emptyState: EmptyView(
                            icon: Icons.sell_outlined,
                            message:
                                'No fees configured for this academic year.${canManage ? ' Add the first one.' : ''}',
                          ),
                          cellsBuilder: (s) => [
                            DataCell(Text(s.code)),
                            DataCell(
                              Text(
                                s.name + (s.isOptional ? ' (optional)' : ''),
                              ),
                            ),
                            DataCell(Text(s.categoryLabel)),
                            DataCell(Text(s.frequency.displayName)),
                            DataCell(
                              Text(
                                Money.format(
                                  s.amountMinor,
                                  currency: fee.currency,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                s.classId == null
                                    ? 'All classes'
                                    : (classNames[s.classId] ?? 'Class') +
                                          (s.sectionId == null
                                              ? ''
                                              : ' (one section)'),
                              ),
                            ),
                            DataCell(Text(s.isActive ? 'Active' : 'Inactive')),
                            DataCell(
                              canManage
                                  ? TextButton(
                                      onPressed: () => open(existing: s),
                                      child: const Text('Edit'),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                          cardBuilder: (s) => Card(
                            child: ListTile(
                              title: Text(
                                '${s.name}${s.isOptional ? ' (optional)' : ''}',
                              ),
                              subtitle: Text(
                                '${s.code} · ${s.frequency.displayName} · ${s.isActive ? 'Active' : 'Inactive'}',
                              ),
                              trailing: Text(
                                Money.format(
                                  s.amountMinor,
                                  currency: fee.currency,
                                ),
                              ),
                              onTap: canManage ? () => open(existing: s) : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (canManage)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () => open(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add fee'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
