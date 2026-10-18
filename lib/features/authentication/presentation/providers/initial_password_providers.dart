import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/functions_region.dart';

/// True once the person has been let past the "change your initial password"
/// screen without changing it — only done for sign-ins that do not use a
/// password (Google, phone code), where the password is not in play.
class InitialPasswordGateDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final initialPasswordGateDismissedProvider =
    NotifierProvider<InitialPasswordGateDismissed, bool>(
      InitialPasswordGateDismissed.new,
    );

/// Calls the `changeInitialPassword` function. The new password is sent over
/// the callable and nowhere else; the server checks the policy and that the
/// account is actually flagged.
final changeInitialPasswordProvider =
    Provider<Future<void> Function(String newPassword)>((ref) {
      return (newPassword) async {
        await appFunctions().httpsCallable('changeInitialPassword').call({
          'newPassword': newPassword,
        });
      };
    });
