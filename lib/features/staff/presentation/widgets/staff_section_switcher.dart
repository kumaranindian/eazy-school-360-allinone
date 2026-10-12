import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum StaffSection { staff, teachers }

/// Staff | Teachers toggle shown at the top of both directory pages — they
/// are two views of the same people, so they share one navigation entry.
class StaffSectionSwitcher extends StatelessWidget {
  final StaffSection current;

  const StaffSectionSwitcher({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StaffSection>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: StaffSection.staff,
          icon: Icon(Icons.badge_outlined),
          label: Text('Staff'),
        ),
        ButtonSegment(
          value: StaffSection.teachers,
          icon: Icon(Icons.school_outlined),
          label: Text('Teachers'),
        ),
      ],
      selected: {current},
      onSelectionChanged: (selection) {
        final target = selection.first;
        if (target == current) return;
        context.go(target == StaffSection.staff ? '/staff' : '/teachers');
      },
    );
  }
}
