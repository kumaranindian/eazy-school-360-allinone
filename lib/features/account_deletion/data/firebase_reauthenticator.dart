import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../authentication/domain/google_sign_in_cancelled.dart';
import '../domain/reauthenticator.dart';

/// Re-confirms the signed-in account with Firebase Auth, then forces a fresh
/// ID token so the new sign-in time reaches the server.
class FirebaseReauthenticator implements Reauthenticator {
  final fb.FirebaseAuth _auth;
  FirebaseReauthenticator(this._auth);

  fb.User _user() {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('You are signed out.');
    return user;
  }

  @override
  Future<void> withPassword(String password) async {
    final user = _user();
    final email = user.email;
    if (email == null) {
      throw const AuthFailure('This account has no email to confirm with.');
    }
    try {
      await user.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );
      await user.getIdToken(true);
    } on fb.FirebaseAuthException catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> withGoogle() async {
    final user = _user();
    try {
      if (kIsWeb) {
        await user.reauthenticateWithPopup(fb.GoogleAuthProvider());
      } else {
        await GoogleSignIn.instance.initialize();
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthFailure('Google could not confirm your account.');
        }
        await user.reauthenticateWithCredential(
          fb.GoogleAuthProvider.credential(idToken: idToken),
        );
      }
      await user.getIdToken(true);
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
    }
  }
}
