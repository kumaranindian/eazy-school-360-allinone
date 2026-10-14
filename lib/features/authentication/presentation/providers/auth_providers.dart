import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_auth_repository.dart';
import '../../domain/app_user.dart';
import '../../domain/auth_repository.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_mapper.dart';
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

enum OtpStep { enterPhone, enterCode }

class PhoneOtpState {
  final OtpStep step;
  final String phone;
  final String? challengeId;
  final DateTime? resendAt;
  final DateTime? expiresAt;
  final bool busy;
  final String? error;

  const PhoneOtpState({
    this.step = OtpStep.enterPhone,
    this.phone = '',
    this.challengeId,
    this.resendAt,
    this.expiresAt,
    this.busy = false,
    this.error,
  });

  PhoneOtpState copyWith({
    OtpStep? step,
    String? phone,
    String? challengeId,
    DateTime? resendAt,
    DateTime? expiresAt,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => PhoneOtpState(
    step: step ?? this.step,
    phone: phone ?? this.phone,
    challengeId: challengeId ?? this.challengeId,
    resendAt: resendAt ?? this.resendAt,
    expiresAt: expiresAt ?? this.expiresAt,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Phone + WhatsApp one-time-code sign-in. The server generates, delivers
/// and verifies the code; this only relays what the user typed and signs in
/// with the session the server returns after a correct code.
class PhoneOtpController extends Notifier<PhoneOtpState> {
  @override
  PhoneOtpState build() => const PhoneOtpState();

  /// Sends (or re-sends) the code. Ignored while a request is in flight.
  Future<void> requestCode(String phone) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, phone: phone, clearError: true);
    try {
      final c = await ref.read(authRepositoryProvider).requestPhoneOtp(phone);
      final now = DateTime.now();
      state = state.copyWith(
        step: OtpStep.enterCode,
        challengeId: c.challengeId,
        resendAt: now.add(c.resendAfter),
        expiresAt: now.add(c.expiresIn),
        busy: false,
      );
    } catch (e) {
      state = state.copyWith(busy: false, error: userMessageFor(e));
    }
  }

  Future<void> verify(String code) async {
    final id = state.challengeId;
    if (state.busy || id == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPhoneOtp(challengeId: id, code: code);
      state = state.copyWith(busy: false);
    } catch (e) {
      // A locked or expired code cannot be retried: go back to resend.
      final terminal =
          e is AccessPolicyFailure &&
          (e.reason == 'OTP_LOCKED' || e.reason == 'OTP_EXPIRED');
      state = state.copyWith(
        busy: false,
        error: userMessageFor(e),
        resendAt: terminal ? DateTime.now() : null,
      );
    }
  }

  void changeNumber() => state = const PhoneOtpState();
}

final phoneOtpControllerProvider =
    NotifierProvider.autoDispose<PhoneOtpController, PhoneOtpState>(
      PhoneOtpController.new,
    );
