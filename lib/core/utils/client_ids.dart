import 'dart:math';

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// A random document id made on the device, in the same shape as a Firestore
/// auto id (20 characters). A form makes one when it opens and reuses it for
/// every attempt, so a double click or a retried save addresses the same
/// document instead of creating a second one.
String newClientId([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(20, (_) => _alphabet.codeUnitAt(r.nextInt(_alphabet.length))),
  );
}
