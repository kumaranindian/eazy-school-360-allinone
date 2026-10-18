import 'package:eazy_school_360/features/authentication/domain/access_messages.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an email already used by another login says what to do about it', () {
    final m = accessMessageFor('EMAIL_IN_USE');
    expect(m, contains('separate login'));
    expect(m, contains('different email'));
    expect(ProvisionOutcome.emailInUse.label, contains('different email'));
  });
}
