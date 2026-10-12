import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_auth_repository.dart';
import '../../domain/app_user.dart';
import '../../domain/auth_repository.dart';
import '../../domain/google_sign_in_cancelled.dart';

final firebaseAuthProvider = Provider<fb.FirebaseAuth>(
  (ref) => fb.FirebaseAuth.instance,
);

/// Swap this override in tests to inject a fake [AuthRepository] without
/// touching real Firebase.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(ref.watch(firebaseAuthProvider));
});

/// The current signed-in user, or `null` when signed out. The router watches
/// this to decide whether to redirect to `/login`.
final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Drives the login form's submit button: idle → loading → success/error.
class SignInController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmailAndPassword(email: email, password: password);
    });
  }
}

final signInControllerProvider = AsyncNotifierProvider<SignInController, void>(
  SignInController.new,
);

/// Drives the "Sign in with Google" button. A cancelled picker/popup
/// ([GoogleSignInCancelled]) resets straight back to idle — it's not an
/// error worth showing the user.
class GoogleSignInController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      state = const AsyncData(null);
    } on GoogleSignInCancelled {
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final googleSignInControllerProvider =
    AsyncNotifierProvider<GoogleSignInController, void>(
      GoogleSignInController.new,
    );

/// Drives the "forgot password" form's submit button.
class PasswordResetController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> sendResetEmail(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
    });
  }
}

final passwordResetControllerProvider =
    AsyncNotifierProvider<PasswordResetController, void>(
      PasswordResetController.new,
    );

/// Drives the sign up form's submit button.
class SignUpController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signUp({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authRepositoryProvider)
          .signUpWithEmailAndPassword(email: email, password: password);
    });
  }
}

final signUpControllerProvider = AsyncNotifierProvider<SignUpController, void>(
  SignUpController.new,
);
