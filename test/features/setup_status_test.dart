import 'package:eazy_school_360/features/academic_setup/domain/setup_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'isRequiredSetupComplete is true only when every required item is complete',
    () {
      const incomplete = SetupStatus(
        items: [
          SetupItem(
            label: 'School Profile',
            isComplete: true,
            isRequired: true,
          ),
          SetupItem(
            label: 'Academic Year',
            isComplete: false,
            isRequired: true,
          ),
          SetupItem(
            label: 'Holiday Calendar',
            isComplete: false,
            isRequired: false,
          ),
        ],
      );
      expect(incomplete.isRequiredSetupComplete, isFalse);

      const complete = SetupStatus(
        items: [
          SetupItem(
            label: 'School Profile',
            isComplete: true,
            isRequired: true,
          ),
          SetupItem(label: 'Academic Year', isComplete: true, isRequired: true),
          SetupItem(
            label: 'Holiday Calendar',
            isComplete: false,
            isRequired: false,
          ),
        ],
      );
      expect(complete.isRequiredSetupComplete, isTrue);
    },
  );

  test('an incomplete OPTIONAL item never blocks isRequiredSetupComplete', () {
    const status = SetupStatus(
      items: [
        SetupItem(label: 'Working Days', isComplete: true, isRequired: true),
        SetupItem(
          label: 'Holiday Calendar',
          isComplete: false,
          isRequired: false,
        ),
      ],
    );
    expect(status.isRequiredSetupComplete, isTrue);
  });

  test('requiredItems and optionalItems partition correctly', () {
    const status = SetupStatus(
      items: [
        SetupItem(label: 'A', isComplete: true, isRequired: true),
        SetupItem(label: 'B', isComplete: false, isRequired: true),
        SetupItem(label: 'C', isComplete: false, isRequired: false),
      ],
    );
    expect(status.requiredItems.map((i) => i.label), ['A', 'B']);
    expect(status.optionalItems.map((i) => i.label), ['C']);
  });
}
