import 'package:flutter/material.dart';

import '../../domain/academic_year.dart';

/// Dropdown used at the top of the Classes/Subjects/Holidays pages to pick
/// *which* academic year's data is being viewed/edited — since those
/// collections all nest under a specific year (see
/// FIRESTORE_ARCHITECTURE.md), the page needs this before it can query
/// anything. Defaults to the most recently started year.
class AcademicYearSelector extends StatelessWidget {
  final List<AcademicYear> years;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  const AcademicYearSelector({
    super.key,
    required this.years,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (years.isEmpty) return const SizedBox.shrink();
    final value = years.any((y) => y.academicYearId == selectedId)
        ? selectedId
        : years.first.academicYearId;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value,
      decoration: const InputDecoration(
        labelText: 'Academic year',
        isDense: true,
      ),
      items: [
        for (final year in years)
          DropdownMenuItem(value: year.academicYearId, child: Text(year.name)),
      ],
      onChanged: (newValue) {
        if (newValue != null) onChanged(newValue);
      },
    );
  }
}
