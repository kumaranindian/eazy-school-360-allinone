import 'dart:async';
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
  if (error is TimeoutException) {
    return const NetworkFailure(
      'This is taking too long. Please check your connection and try again.',
    );
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

  if (error.plugin == 'firebase_storage') return _mapStorageException(error);

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

/// Firebase Storage reports its own codes (`unauthorized`, `object-not-found`,
/// ...). Left unmapped they reach the user as "Firebase error (unauthorized):
/// ...", which does not say what to do.
AppFailure _mapStorageException(FirebaseException error) {
  switch (error.code) {
    case 'unauthorized':
    case 'unauthenticated':
      AppLogger.warning(
        'Storage ${error.code}. Either the signed-in user is not allowed to '
        'write this path (see storage.rules), or the Storage rules cannot read '
        'Firestore: the cross-service rule needs the Firebase Rules service '
        'agent granted on the project (see DEVELOPMENT_GUIDE.md → '
        '"Firebase Storage").',
        tag: 'ErrorMapper',
      );
      return const PermissionFailure(
        "You don't have permission to upload this file. If you should, ask "
        'your administrator to check the storage setup.',
      );
    case 'bucket-not-found':
    case 'project-not-found':
    case 'no-default-bucket':
      return const ConfigurationFailure(
        "File storage isn't set up for this project yet. Please contact "
        'support.',
      );
    case 'quota-exceeded':
      return const UnknownFailure(
        'The storage quota has been reached. Please contact support.',
      );
    case 'retry-limit-exceeded':
    case 'canceled':
      return const NetworkFailure(
        'The upload was interrupted. Please check your connection and try '
        'again.',
      );
    case 'object-not-found':
      // Also what Storage answers when an upload targets a bucket that was
      // never created, so say both rather than just "file not found".
      AppLogger.warning(
        'Storage object-not-found. For an upload this means the bucket does '
        'not exist: enable Storage in the Firebase console (see '
        'DEVELOPMENT_GUIDE.md → "Firebase Storage").',
        tag: 'ErrorMapper',
      );
      return const NotFoundFailure(
        'The file, or the storage area for this project, could not be found. '
        'If you were uploading, file storage may not be enabled yet — please '
        'contact your administrator.',
      );
    case 'invalid-checksum':
      return const UnknownFailure(
        'The file was damaged while uploading. Please try again.',
      );
    default:
      return UnknownFailure(
        'Upload failed (${error.code}). Please try again, or contact support '
        'if it keeps happening.',
      );
  }
}
