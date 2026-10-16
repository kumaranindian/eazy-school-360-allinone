import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/student.dart';

/// Chips to pick which linked child a parent page is about. Hidden for a
/// single child (nothing to choose).
class ChildSwitcher extends StatelessWidget {
  final List<Student> children;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const ChildSwitcher({
    super.key,
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (children.length < 2) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final c in children)
          ChoiceChip(
            avatar: const Icon(Icons.child_care_outlined, size: 18),
            label: Text(c.firstName),
            selected: c.studentId == selectedId,
            onSelected: (_) => onSelected(c.studentId),
          ),
      ],
    );
  }
}
