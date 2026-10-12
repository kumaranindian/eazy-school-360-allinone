import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const branch = Branch(
    branchId: 'main',
    schoolId: 'school-1',
    name: 'Main Branch',
    status: BranchStatus.active,
  );

  test(
    'fromFirestore parses the structured address fields (not a single "address" string)',
    () {
      final parsed = Branch.fromFirestore('school-1', 'main', {
        'name': 'Main Branch',
        'code': 'MB',
        'email': 'main@rosewood.example',
        'addressLine1': '1 Main St',
        'addressLine2': 'Suite 2',
        'city': 'Springfield',
        'postalCode': '12345',
        'status': 'ACTIVE',
      });

      expect(parsed.code, 'MB');
      expect(parsed.addressLine1, '1 Main St');
      expect(parsed.addressLine2, 'Suite 2');
      expect(parsed.city, 'Springfield');
    },
  );

  test('copyWith can change status independently of other fields', () {
    final deactivated = branch.copyWith(status: BranchStatus.inactive);
    expect(deactivated.status, BranchStatus.inactive);
    expect(deactivated.name, branch.name);
  });

  test(
    'toFirestoreUpdate includes status (branch admins/school admins can activate/deactivate)',
    () {
      final data = branch.toFirestoreUpdate(updatedBy: 'uid-1');
      expect(data['status'], 'ACTIVE');
      expect(
        data.containsKey('schoolId'),
        isFalse,
      ); // immutable — never resent on update
    },
  );

  test(
    'toFirestoreCreate always stamps schoolId — ownership is set once, at creation',
    () {
      final data = branch.toFirestoreCreate(createdBy: 'uid-1');
      expect(data['schoolId'], 'school-1');
    },
  );
}
