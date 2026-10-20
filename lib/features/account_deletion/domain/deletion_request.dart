/// Where a deletion request stands. Mirrors the server lifecycle
/// (functions/account_deletion.js); an unknown value from a newer server is
/// kept as [unknown] and shown as "in progress", never as completed.
enum DeletionStatus {
  pendingVerification('PENDING_VERIFICATION'),
  underReview('UNDER_REVIEW'),
  actionRequired('ACTION_REQUIRED'),
  approved('APPROVED'),
  processing('PROCESSING'),
  failedRetryable('FAILED_RETRYABLE'),
  completed('COMPLETED'),
  rejected('REJECTED'),
  cancelled('CANCELLED'),
  expired('EXPIRED'),
  unknown('');

  final String wire;
  const DeletionStatus(this.wire);

  static DeletionStatus parse(String? value) {
    for (final s in values) {
      if (s != unknown && s.wire == value) return s;
    }
    return unknown;
  }

  /// A request that still blocks a second one.
  bool get isOpen => switch (this) {
    underReview ||
    actionRequired ||
    approved ||
    processing ||
    failedRetryable ||
    unknown => true,
    _ => false,
  };

  /// The person may withdraw it. After approval only Avail404 can stop it.
  bool get canCancel => switch (this) {
    pendingVerification || underReview || actionRequired => true,
    _ => false,
  };
}

/// Why a request is not moving (server `reason` codes).
enum DeletionReason {
  soleAdmin('SOLE_ADMIN'),
  noAccount('NO_ACCOUNT'),
  platformAdmin('PLATFORM_ADMIN'),
  duplicate('DUPLICATE'),
  declined('DECLINED');

  final String wire;
  const DeletionReason(this.wire);

  static DeletionReason? parse(String? value) {
    for (final r in values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// One deletion request as the server reports it. Carries an opaque reference
/// and a status - no personal details.
class DeletionRequest {
  final String reference;
  final DeletionStatus status;
  final DeletionReason? reason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DeletionRequest({
    required this.reference,
    required this.status,
    this.reason,
    this.createdAt,
    this.updatedAt,
  });

  factory DeletionRequest.fromMap(Map<dynamic, dynamic> map) {
    DateTime? time(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return DeletionRequest(
      reference: map['reference'] as String? ?? '',
      status: DeletionStatus.parse(map['status'] as String?),
      reason: DeletionReason.parse(map['reason'] as String?),
      createdAt: time(map['createdAt']),
      updatedAt: time(map['updatedAt']),
    );
  }
}
