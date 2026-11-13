import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A platform admin's current read-only support session in ONE school. Held in
/// memory only (a reload ends it; the grant itself lives on the server and can
/// be resumed from the platform home).
class SupportSession {
  final String schoolId;
  final String schoolName;
  final DateTime expiresAt;

  const SupportSession({
    required this.schoolId,
    required this.schoolName,
    required this.expiresAt,
  });

  bool isActiveAt(DateTime now) => now.isBefore(expiresAt);
}

/// Starts, ends and times out the support session. The tenant context watches
/// this, so starting a session opens that school in the app and ending it
/// returns the person to the platform home.
class SupportSessionNotifier extends Notifier<SupportSession?> {
  Timer? _timer;

  @override
  SupportSession? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void start(SupportSession session) {
    _timer?.cancel();
    final left = session.expiresAt.difference(DateTime.now());
    if (left <= Duration.zero) {
      state = null;
      return;
    }
    state = session;
    _timer = Timer(left, end);
  }

  void end() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

final supportSessionProvider =
    NotifierProvider<SupportSessionNotifier, SupportSession?>(
      SupportSessionNotifier.new,
    );
