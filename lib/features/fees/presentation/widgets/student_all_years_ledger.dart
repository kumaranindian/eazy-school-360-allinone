import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_planners.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';

/// A student's position across EVERY academic year in one place — what was
/// billed, paid, waived and is still owed per year, with a prominent line for
/// dues left over from earlier years. The year-scoped ledger below it only
/// covers the year chosen in the picker.
class StudentAllYearsLedger extends StatelessWidget {
  final Future<List<Invoice>> future;
  final String currency;

  /// The year currently selected in the fees year picker.
  final String selectedYearId;

  const StudentAllYearsLedger({
    super.key,
    required this.future,
    required this.currency,
    required this.selectedYearId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Invoice>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final today = FeeDates.todayKey();
        final live = snapshot.data!.where((i) => !i.isVoid).toList();
        if (live.isEmpty) return const SizedBox.shrink();

        final byYear = <String, List<Invoice>>{};
        final yearNames = <String, String>{};
        for (final i in live) {
          byYear.putIfAbsent(i.academicYearId, () => []).add(i);
          yearNames[i.academicYearId] = i.academicYearName;
        }
        // Newest year first (names are like "2026-27"; fall back to id).
        final yearIds = byYear.keys.toList()
          ..sort((a, b) => (yearNames[b] ?? b).compareTo(yearNames[a] ?? a));

        final total = StudentFeeSummary.of(live, todayKey: today);
        final earlierBalance = yearIds
            .where((y) => y != selectedYearId)
            .fold<int>(
              0,
              (sum, y) =>
                  sum +
                  StudentFeeSummary.of(
                    byYear[y]!,
                    todayKey: today,
                  ).balanceMinor,
            );
        final theme = Theme.of(context);
        String m(int v) => Money.format(v, currency: currency);

        return Card(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: ExpansionTile(
            initiallyExpanded: earlierBalance > 0,
            title: Text(
              'All academic years — total due ${m(total.balanceMinor)}',
              style: theme.textTheme.titleSmall,
            ),
            subtitle: earlierBalance > 0
                ? Text(
                    '${m(earlierBalance)} pending from earlier years',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : const Text('No dues from earlier years'),
            childrenPadding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Academic year')),
                    DataColumn(label: Text('Billed'), numeric: true),
                    DataColumn(label: Text('Paid'), numeric: true),
                    DataColumn(label: Text('Waived'), numeric: true),
                    DataColumn(label: Text('Balance'), numeric: true),
                    DataColumn(label: Text('Overdue'), numeric: true),
                  ],
                  rows: [
                    for (final y in yearIds)
                      () {
                        final s = StudentFeeSummary.of(
                          byYear[y]!,
                          todayKey: today,
                        );
                        return DataRow(
                          selected: y == selectedYearId,
                          cells: [
                            DataCell(Text(yearNames[y] ?? y)),
                            DataCell(Text(m(s.payableMinor))),
                            DataCell(Text(m(s.paidMinor))),
                            DataCell(Text(m(s.waivedMinor))),
                            DataCell(Text(m(s.balanceMinor))),
                            DataCell(Text(m(s.overdueMinor))),
                          ],
                        );
                      }(),
                    DataRow(
                      cells: [
                        const DataCell(
                          Text(
                            'Total',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text(m(total.payableMinor))),
                        DataCell(Text(m(total.paidMinor))),
                        DataCell(Text(m(total.waivedMinor))),
                        DataCell(
                          Text(
                            m(total.balanceMinor),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text(m(total.overdueMinor))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The cards and list below show only the academic year '
                'selected at the top. Switch the year to see an earlier '
                "year's invoices and collect its dues.",
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
