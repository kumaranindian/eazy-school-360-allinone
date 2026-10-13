import 'dart:async';

import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/errors/error_mapper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException _storage(String code) =>
    FirebaseException(plugin: 'firebase_storage', code: code, message: 'raw');

void main() {
  test('unauthorized is a permission failure that does not leak the code', () {
    final failure = mapExceptionToFailure(_storage('unauthorized'));
    expect(failure, isA<PermissionFailure>());
    expect(failure.message, contains("don't have permission"));
    expect(failure.message, isNot(contains('unauthorized')));
  });

  test('a missing bucket is a configuration problem, not "try again"', () {
    for (final code in ['bucket-not-found', 'project-not-found']) {
      expect(
        mapExceptionToFailure(_storage(code)),
        isA<ConfigurationFailure>(),
      );
    }
    expect(
      mapExceptionToFailure(_storage('bucket-not-found')).message,
      contains("isn't set up"),
    );
  });

  test('interrupted uploads and timeouts are network failures', () {
    expect(
      mapExceptionToFailure(_storage('retry-limit-exceeded')),
      isA<NetworkFailure>(),
    );
    expect(
      mapExceptionToFailure(TimeoutException('slow')),
      isA<NetworkFailure>(),
    );
  });

  test('an unknown storage code still gives an actionable message', () {
    final failure = mapExceptionToFailure(_storage('something-new'));
    expect(failure, isA<UnknownFailure>());
    expect(failure.message, contains('Upload failed'));
  });

  test('Firestore errors are not routed through the storage mapping', () {
    final failure = mapExceptionToFailure(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    expect(failure, isA<PermissionFailure>());
    expect(failure.message, isNot(contains('upload')));
  });
}
