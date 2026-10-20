import 'package:eazy_school_360/features/account_deletion/data/firebase_account_deletion_repository.dart';
import 'package:eazy_school_360/features/account_deletion/domain/account_deletion_repository.dart';
import 'package:eazy_school_360/features/account_deletion/domain/deletion_copy.dart';
import 'package:eazy_school_360/features/account_deletion/domain/deletion_request.dart';
import 'package:flutter_test/flutter_test.dart';

DeletionRequest _r(DeletionStatus s, {DeletionReason? reason}) =>
    DeletionRequest(
      reference: 'DEL-AAAAAAAAAAAAAAAA',
      status: s,
      reason: reason,
    );

void main() {
  group('DeletionStatus', () {
    test('parses every server value and keeps unknown ones as unknown', () {
      for (final s in DeletionStatus.values) {
        if (s == DeletionStatus.unknown) continue;
        expect(DeletionStatus.parse(s.wire), s);
      }
      expect(DeletionStatus.parse('SOMETHING_NEW'), DeletionStatus.unknown);
      expect(DeletionStatus.parse(null), DeletionStatus.unknown);
    });

    test('open requests block a second one; final ones do not', () {
      const open = [
        DeletionStatus.underReview,
        DeletionStatus.actionRequired,
        DeletionStatus.approved,
        DeletionStatus.processing,
        DeletionStatus.failedRetryable,
        DeletionStatus.unknown, // when in doubt, do not offer a second request
      ];
      for (final s in DeletionStatus.values) {
        expect(s.isOpen, open.contains(s), reason: s.name);
      }
    });

    test('a request can be withdrawn only before it is approved', () {
      const cancellable = [
        DeletionStatus.pendingVerification,
        DeletionStatus.underReview,
        DeletionStatus.actionRequired,
      ];
      for (final s in DeletionStatus.values) {
        expect(s.canCancel, cancellable.contains(s), reason: s.name);
      }
    });
  });

  test('DeletionRequest.fromMap reads the server shape and tolerates gaps', () {
    final r = DeletionRequest.fromMap({
      'reference': 'DEL-ABCDEFGHJKLMNPQR',
      'status': 'ACTION_REQUIRED',
      'reason': 'SOLE_ADMIN',
      'createdAt': 1760000000000,
      'updatedAt': 1760000100000,
    });
    expect(r.reference, 'DEL-ABCDEFGHJKLMNPQR');
    expect(r.status, DeletionStatus.actionRequired);
    expect(r.reason, DeletionReason.soleAdmin);
    expect(r.createdAt, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    final bare = DeletionRequest.fromMap({
      'reference': 'x',
      'status': 'COMPLETED',
    });
    expect(bare.reason, isNull);
    expect(bare.createdAt, isNull);
  });

  group('DeletionCopy', () {
    test('only COMPLETED claims the account was deleted', () {
      for (final s in DeletionStatus.values) {
        final text = DeletionCopy.forRequest(_r(s));
        final claimsDone =
            RegExp(
              r'\b(were|was|has been|have been) deleted\b',
              caseSensitive: false,
            ).hasMatch(
              // "Nothing was deleted" is a denial, not a claim.
              '${text.title} ${text.body}'.replaceAll(
                'Nothing was deleted',
                '',
              ),
            );
        expect(
          claimsDone,
          s == DeletionStatus.completed,
          reason: '${s.name}: "${text.title} / ${text.body}"',
        );
      }
    });

    test(
      'a request in review says nothing is deleted yet and gives the target',
      () {
        final t = DeletionCopy.forRequest(_r(DeletionStatus.underReview));
        expect(t.body, contains('has not been deleted yet'));
        expect(t.body, contains(DeletionCopy.reviewTarget));
      },
    );

    test('the sole-admin hold explains what to do', () {
      final t = DeletionCopy.forRequest(
        _r(DeletionStatus.actionRequired, reason: DeletionReason.soleAdmin),
      );
      expect(t.body, contains('only administrator'));
      expect(t.body, contains('hi@avail404.com'));
    });

    test('every status has a title and body', () {
      for (final s in DeletionStatus.values) {
        final t = DeletionCopy.forRequest(_r(s));
        expect(t.title, isNotEmpty, reason: s.name);
        expect(t.body, isNotEmpty, reason: s.name);
      }
    });
  });

  group('server error mapping', () {
    final kind = FirebaseAccountDeletionRepository.kindOf;
    test('uses the server reason first', () {
      expect(
        kind('failed-precondition', 'REAUTH_REQUIRED'),
        DeletionFailureKind.reauthRequired,
      );
      expect(
        kind('failed-precondition', 'PLATFORM_ADMIN'),
        DeletionFailureKind.platformAdmin,
      );
      expect(
        kind('failed-precondition', 'NOT_CANCELLABLE'),
        DeletionFailureKind.notCancellable,
      );
      expect(kind('not-found', 'NOT_FOUND'), DeletionFailureKind.notFound);
    });
    test('falls back on the transport code', () {
      expect(kind('unavailable', null), DeletionFailureKind.offline);
      expect(kind('deadline-exceeded', null), DeletionFailureKind.offline);
      expect(kind('internal', null), DeletionFailureKind.unavailable);
      expect(
        kind('permission-denied', 'SOMETHING_ELSE'),
        DeletionFailureKind.unavailable,
      );
    });
    test('every failure has a message that is safe to show', () {
      for (final k in DeletionFailureKind.values) {
        expect(DeletionFailure(k).message, isNotEmpty);
        expect(DeletionFailure(k).message, isNot(contains('Exception')));
      }
    });
  });
}
