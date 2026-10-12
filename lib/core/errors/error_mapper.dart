import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../logging/app_logger.dart';
import 'app_failure.dart';

/// Maps low-level, source-specific exceptions to a domain-level
/// [AppFailure], logging the technical detail before discarding it.
///
/// Call this from repository catch blocks — never let a raw
/// `FirebaseException`/`SocketException` reach the presentation layer.
AppFailure mapExceptionToFailure(Object error, [StackTrace? stackTrace]) {
  AppLogger.error(
    'Mapping exception to failure',
    error: error,
    stackTrace: stackTrace,
  );

  if (error is fb.FirebaseAuthException) {
    return _mapFirebaseAuthException(error);
  }
  if (error is FirebaseException) {
    return _mapFirebaseException(error);
  }
  if (error is GoogleSignInException) {
    return _mapGoogleSignInException(error);
  }
  if (error is SocketException) {
    return const NetworkFailure();
  }
  if (error is AppFailure) {
    return error;
  }
  return const UnknownFailure();
}

/// The user-facing message for any error that reaches the presentation
/// layer — an [AppFailure]'s own message, or the mapped message for
/// anything that escaped a repository unmapped (e.g. a provider that
/// failed to construct because Firebase isn't initialised).
String userMessageFor(Object error) {
  if (error is AppFailure) return error.message;
  return mapExceptionToFailure(error).message;
}

AppFailure _mapGoogleSignInException(GoogleSignInException error) {
  switch (error.code) {
    case GoogleSignInExceptionCode.interrupted:
    case GoogleSignInExceptionCode.uiUnavailable:
      return const UnknownFailure(
        'Google sign-in is unavailable right now. Please try again.',
      );
    case GoogleSignInExceptionCode.clientConfigurationError:
    case GoogleSignInExceptionCode.providerConfigurationError:
      return const ConfigurationFailure(
        "Google sign-in isn't configured for this app yet. Please use email and password.",
      );
    default:
      return const UnknownFailure('Google sign-in failed. Please try again.');
  }
}

AppFailure _mapFirebaseAuthException(fb.FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return const ValidationFailure('That email address looks invalid.');
    case 'user-disabled':
      return const PermissionFailure(
        'This account has been disabled. Contact your administrator.',
      );
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return const AuthFailure('Incorrect email or password.');
    case 'too-many-requests':
      return const AuthFailure(
        'Too many attempts. Please wait a moment and try again.',
      );
    case 'network-request-failed':
      return const NetworkFailure();
    case 'account-exists-with-different-credential':
      return const AuthFailure(
        'An account already exists for this email with a different sign-in method.',
      );
    case 'popup-blocked':
      return const AuthFailure(
        'Your browser blocked the sign-in popup. Allow popups for this site and try again.',
      );
    case 'operation-not-allowed':
    case 'unauthorized-domain':
    case 'invalid-api-key':
    case 'api-key-not-valid':
    case 'app-not-authorized':
    case 'configuration-not-found':
      return const ConfigurationFailure();
    default:
      return const AuthFailure();
  }
}

AppFailure _mapFirebaseException(FirebaseException error) {
  // Log the error code and message for debugging
  AppLogger.error(
    'FirebaseException mapped: code=${error.code}, message=${error.message}',
    tag: 'ErrorMapper',
  );

  switch (error.code) {
    case 'permission-denied':
      return const PermissionFailure();
    case 'not-found':
      return const NotFoundFailure();
    case 'unavailable':
    case 'deadline-exceeded':
      AppLogger.warning(
        'Firestore ${error.code} is reported to the user as "no internet". '
        'If the device is online, the usual cause is that the Firestore '
        'database was never created for this Firebase project '
        '(Console → Firestore Database → Create database), or the Cloud '
        'Firestore API is disabled.',
        tag: 'ErrorMapper',
      );
      return const NetworkFailure();
    case 'no-app':
    case 'not-initialized':
      return const ConfigurationFailure();
    default:
      // For unknown Firebase errors, include the message in the user-facing error
      // for debugging purposes
      return UnknownFailure(
        'Firebase error (${error.code}): ${error.message ?? "Unknown error"}',
      );
  }
}
