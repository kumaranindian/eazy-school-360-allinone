import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../notifications/presentation/providers/notification_providers.dart'
    show noRetry;
import '../../data/firebase_account_deletion_repository.dart';
import '../../data/firebase_reauthenticator.dart';
import '../../domain/account_deletion_repository.dart';
import '../../domain/deletion_request.dart';
import '../../domain/reauthenticator.dart';

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => FirebaseAccountDeletionRepository(),
  retry: noRetry,
);

final reauthenticatorProvider = Provider<Reauthenticator>(
  (ref) => FirebaseReauthenticator(ref.watch(firebaseAuthProvider)),
  retry: noRetry,
);

/// The signed-in person's deletion requests, newest first.
class AccountDeletionController extends AsyncNotifier<List<DeletionRequest>> {
  @override
  Future<List<DeletionRequest>> build() =>
      ref.read(accountDeletionRepositoryProvider).mine();

  /// Files the request, then reloads the list. Returns the request the server
  /// holds (an existing open one if there already was one).
  Future<DeletionRequest> submit() async {
    final repo = ref.read(accountDeletionRepositoryProvider);
    final created = await repo.request();
    state = AsyncData(await repo.mine());
    return created;
  }

  Future<void> cancel(String reference) async {
    final repo = ref.read(accountDeletionRepositoryProvider);
    await repo.cancel(reference);
    state = AsyncData(await repo.mine());
  }
}

final accountDeletionControllerProvider =
    AsyncNotifierProvider.autoDispose<
      AccountDeletionController,
      List<DeletionRequest>
    >(AccountDeletionController.new, retry: noRetry);
