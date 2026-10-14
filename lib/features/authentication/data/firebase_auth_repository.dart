import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/google_sign_in_cancelled.dart';
import '../domain/login_method.dart';
import '../domain/phone_otp.dart';
import '../domain/access_messages.dart';
import '../../../core/errors/app_failure.dart';

AppUser _toAppUser(fb.User user) =>
    AppUser(uid: user.uid, email: user.email, displayName: user.displayName);

/// [AuthRepository] implementation backed by Firebase Authentication.
class FirebaseAuthRepository implements AuthRepository {
  final fb.FirebaseAuth _firebaseAuth;
  final FirebaseFunctions _functions;
  bool _googleSignInInitialized = false;

  FirebaseAuthRepository(this._firebaseAuth, [FirebaseFunctions? functions])
    : _functions = functions ?? appFunctions();

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _firebaseAuth.authStateChanges().map(
      (user) => user == null ? null : _toAppUser(user),
    );
  }

  @override
  AppUser? get currentUser {
    final user = _firebaseAuth.currentUser;
    return user == null ? null : _toAppUser(user);
  }

  @override
  Future<AppUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.debug('Sign-in: email/password attempt', tag: 'Auth');
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw fb.FirebaseAuthException(code: 'user-not-found');
      }
      AppLogger.debug('Sign-in OK uid=${user.uid}', tag: 'Auth');
      return _toAppUser(user);
    } catch (error, stackTrace) {
      if (error is fb.FirebaseAuthException) {
        AppLogger.error(
          'Sign-in failed: code=${error.code} message=${error.message}',
          tag: 'Auth',
        );
      }
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    try {
      fb.UserCredential credential;
      if (kIsWeb) {
        credential = await _firebaseAuth.signInWithPopup(
          fb.GoogleAuthProvider(),
        );
      } else {
        await _ensureGoogleSignInInitialized();
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw fb.FirebaseAuthException(code: 'invalid-credential');
        }
        credential = await _firebaseAuth.signInWithCredential(
          fb.GoogleAuthProvider.credential(idToken: idToken),
        );
      }
      final user = credential.user;
      if (user == null) {
        throw fb.FirebaseAuthException(code: 'user-not-found');
      }
      return _toAppUser(user);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleSignInCancelled();
      }
      throw mapExceptionToFailure(error, StackTrace.current);
    } on fb.FirebaseAuthException catch (error, stackTrace) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        throw const GoogleSignInCancelled();
      }
      throw mapExceptionToFailure(error, stackTrace);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } on fb.FirebaseAuthException catch (error, stackTrace) {
      // Projects without email-enumeration protection still report this;
      // treat it as success so the UI can't be used to probe for accounts.
      if (error.code == 'user-not-found') return;
      throw mapExceptionToFailure(error, stackTrace);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw fb.FirebaseAuthException(code: 'user-not-found');
      }
      AppLogger.debug('Sign-up OK uid=${user.uid}', tag: 'Auth');
      return _toAppUser(user);
    } catch (error, stackTrace) {
      // Log detailed error information for debugging
      AppLogger.error(
        'Sign up failed for email: $email',
        error: error,
        stackTrace: stackTrace,
        tag: 'Auth',
      );

      // Add additional context for Firebase errors
      if (error is fb.FirebaseAuthException) {
        AppLogger.error(
          'Firebase Auth error details: code=${error.code}, message=${error.message}',
          tag: 'Auth',
        );
      }

      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
    if (!kIsWeb && _googleSignInInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (error, stackTrace) {
        // The Firebase session is already gone; a stale Google session only
        // means the account picker may preselect next time.
        AppLogger.warning(
          'Google sign-out failed after Firebase sign-out: $error',
        );
        AppLogger.debug(stackTrace.toString());
      }
    }
  }

  @override
  Future<OtpChallenge> requestPhoneOtp(String phone) async {
    try {
      final res = await _functions.httpsCallable('requestPhoneOtp').call({
        'phone': phone.trim(),
      });
      final m = Map<String, dynamic>.from(res.data as Map);
      return OtpChallenge(
        challengeId: m['challengeId'] as String,
        expiresIn: Duration(seconds: (m['expiresInSec'] as num).toInt()),
        resendAfter: Duration(seconds: (m['resendAfterSec'] as num).toInt()),
      );
    } on FirebaseFunctionsException catch (error) {
      throw accessFailureFrom(error);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<AppUser> verifyPhoneOtp({
    required String challengeId,
    required String code,
  }) async {
    try {
      final res = await _functions.httpsCallable('verifyPhoneOtp').call({
        'challengeId': challengeId,
        'code': code.trim(),
      });
      final token = (res.data as Map)['token'] as String;
      final credential = await _firebaseAuth.signInWithCustomToken(token);
      final user = credential.user;
      if (user == null) {
        throw fb.FirebaseAuthException(code: 'user-not-found');
      }
      return _toAppUser(user);
    } on FirebaseFunctionsException catch (error) {
      throw accessFailureFrom(error);
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<LoginMethod?> currentSignInMethod() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    try {
      final result = await user.getIdTokenResult();
      switch (result.signInProvider) {
        case 'password':
          return LoginMethod.password;
        case 'google.com':
          return LoginMethod.google;
        case 'custom':
          return result.claims?['via'] == 'PHONE_OTP'
              ? LoginMethod.phoneOtp
              : null;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

/// Maps a callable's error to an [AccessPolicyFailure] with user-facing text.
AccessPolicyFailure accessFailureFrom(FirebaseFunctionsException error) {
  final details = error.details is Map
      ? Map<String, dynamic>.from(error.details as Map)
      : const <String, dynamic>{};
  final reason = (details['reason'] as String?) ?? _byCode(error.code);
  final retry = (details['retryAfterSec'] as num?)?.toInt();
  return AccessPolicyFailure(
    accessMessageFor(
      reason,
      cause: details['cause'] as String?,
      retryAfterSec: retry,
    ),
    reason: reason,
    retryAfterSec: retry,
    attemptsLeft: (details['attemptsLeft'] as num?)?.toInt(),
  );
}

String _byCode(String code) => switch (code) {
  'permission-denied' => 'PERMISSION_DENIED',
  'not-found' => 'NOT_FOUND',
  'invalid-argument' => 'INVALID_ARGUMENT',
  'resource-exhausted' => 'RATE_LIMITED',
  'unavailable' || 'deadline-exceeded' => 'DELIVERY_FAILED',
  _ => 'UNKNOWN',
};
