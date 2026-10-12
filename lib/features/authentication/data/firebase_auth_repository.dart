import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/google_sign_in_cancelled.dart';

AppUser _toAppUser(fb.User user) =>
    AppUser(uid: user.uid, email: user.email, displayName: user.displayName);

/// [AuthRepository] implementation backed by Firebase Authentication.
class FirebaseAuthRepository implements AuthRepository {
  final fb.FirebaseAuth _firebaseAuth;
  bool _googleSignInInitialized = false;

  FirebaseAuthRepository(this._firebaseAuth);

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
}
