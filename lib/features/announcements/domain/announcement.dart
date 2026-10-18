import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../homework/domain/file_attachment.dart';
import 'announcement_file_policy.dart';

/// Who an announcement is for. Each value is a relationship the system
/// actually holds: school/branch membership, staff roles, parents' children's
/// placement, and teachers' class/section assignments.
enum AnnouncementAudience {
  all('ALL', 'Everyone in the school'),
  branch('BRANCH', 'This branch (staff and parents)'),
  staff('STAFF', 'Staff of this branch'),
  parents('PARENTS', 'Parents of this branch'),
  classGroup('CLASS', 'A class (parents and its teachers)'),
  section('SECTION', 'A section (parents and its teachers)');

  final String wireValue;
  final String displayName;
  const AnnouncementAudience(this.wireValue, this.displayName);

  bool get needsClass => this == classGroup || this == section;
  bool get needsSection => this == section;

  static AnnouncementAudience fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum AnnouncementStatus {
  draft('DRAFT', 'Draft'),
  published('PUBLISHED', 'Published'),
  archived('ARCHIVED', 'Archived');

  final String wireValue;
  final String displayName;
  const AnnouncementStatus(this.wireValue, this.displayName);

  static AnnouncementStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum AnnouncementEvent {
  created('CREATED'),
  edited('EDITED'),
  published('PUBLISHED'),
  updated('UPDATED'),
  archived('ARCHIVED');

  final String wireValue;
  const AnnouncementEvent(this.wireValue);
}

/// `.../branches/{b}/announcements/{id}`. The audience of a published
/// announcement is immutable: changing who it is for would change what was
/// already published, so a different audience is a new announcement.
class Announcement {
  final String announcementId;
  final String schoolId;
  final String branchId;
  final String? academicYearId;
  final AnnouncementAudience audience;
  final String? classId;
  final String? sectionId;
  final String? audienceLabel;
  final String title;
  final String body;
  final List<FileAttachment> attachments;

  /// When it becomes visible. Null on a draft.
  final DateTime? publishAt;

  /// After this it is no longer shown as current (kept in history).
  final DateTime? expiresAt;
  final AnnouncementStatus status;
  final int revision;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String? publishedBy;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Announcement({
    required this.announcementId,
    required this.schoolId,
    required this.branchId,
    this.academicYearId,
    required this.audience,
    this.classId,
    this.sectionId,
    this.audienceLabel,
    required this.title,
    required this.body,
    this.attachments = const [],
    this.publishAt,
    this.expiresAt,
    this.status = AnnouncementStatus.draft,
    this.revision = 1,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    this.publishedBy,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
  });

  static String newId() =>
      'an_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  bool get isExpired =>
      expiresAt != null && !DateTime.now().isBefore(expiresAt!);

  /// Published, already visible, and not expired.
  bool isCurrent(DateTime now) =>
      status == AnnouncementStatus.published &&
      publishAt != null &&
      !publishAt!.isAfter(now) &&
      (expiresAt == null || now.isBefore(expiresAt!));

  /// A user-readable reason the announcement cannot be saved/published.
  String? validate({DateTime? now}) {
    final t = title.trim();
    if (t.length < 3 || t.length > 120) {
      return 'The title must be 3-120 characters.';
    }
    final b = body.trim();
    if (b.isEmpty) return 'Write the message.';
    if (b.length > 4000) return 'Keep the message under 4000 characters.';
    if (audience.needsClass && classId == null) {
      return 'Choose the class.';
    }
    if (audience.needsSection && sectionId == null) {
      return 'Choose the section.';
    }
    if (attachments.length > AnnouncementFilePolicy.maxFiles) {
      return 'Attach at most ${AnnouncementFilePolicy.maxFiles} files.';
    }
    if (publishAt != null &&
        expiresAt != null &&
        !expiresAt!.isAfter(publishAt!)) {
      return 'The expiry must be after the publish time.';
    }
    if (now != null && expiresAt != null && !expiresAt!.isAfter(now)) {
      return 'The expiry is already in the past.';
    }
    return null;
  }

  factory Announcement.fromFirestore(Map<String, dynamic> d, String id) =>
      Announcement(
        announcementId: id,
        schoolId: d[FirestoreFields.schoolId] as String,
        branchId: d[FirestoreFields.branchId] as String,
        academicYearId: d['academicYearId'] as String?,
        audience: AnnouncementAudience.fromWireValue(
          d['audienceKind'] as String,
        ),
        classId: d['classId'] as String?,
        sectionId: d['sectionId'] as String?,
        audienceLabel: d['audienceLabel'] as String?,
        title: d['title'] as String,
        body: d['body'] as String? ?? '',
        attachments: [
          for (final a in d['attachments'] as List? ?? [])
            FileAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
        ],
        publishAt: (d['publishAt'] as Timestamp?)?.toDate(),
        expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
        status: AnnouncementStatus.fromWireValue(
          d[FirestoreFields.status] as String,
        ),
        revision: (d['revision'] as num?)?.toInt() ?? 1,
        authorId: d['authorId'] as String,
        authorName: d['authorName'] as String? ?? '',
        authorRole: d['authorRole'] as String? ?? '',
        publishedBy: d['publishedBy'] as String?,
        publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> body_() => {
    'title': title.trim(),
    'body': body.trim(),
    'attachments': [for (final a in attachments) a.toMap()],
    'publishAt': publishAt == null ? null : Timestamp.fromDate(publishAt!),
    'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
  };

  Map<String, dynamic> toFirestoreCreate() => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'academicYearId': academicYearId,
    'audienceKind': audience.wireValue,
    'classId': classId,
    'sectionId': sectionId,
    'audienceLabel': audienceLabel,
    ...body_(),
    FirestoreFields.status: AnnouncementStatus.draft.wireValue,
    'revision': 1,
    'lastEvent': AnnouncementEvent.created.wireValue,
    'authorId': authorId,
    'authorName': authorName,
    'authorRole': authorRole,
    'publishedBy': null,
    'publishedAt': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: authorId,
    FirestoreFields.updatedBy: authorId,
  };
}

/// Who is looking: resolved from the signed-in user and their trusted
/// relationships (placement of linked children, teaching assignments).
class AnnouncementViewer {
  final String role; // wire value of UserRole
  final String? branchId;

  /// Parents: (branchId, classId, sectionId) of each linked child.
  final List<({String branchId, String classId, String sectionId})> children;

  /// Teachers: (classId, sectionId) they teach or are class teacher of.
  final List<({String classId, String sectionId})> teaching;

  const AnnouncementViewer({
    required this.role,
    this.branchId,
    this.children = const [],
    this.teaching = const [],
  });
}

abstract final class AnnouncementVisibility {
  static bool _isAdmin(String role) =>
      role == 'SCHOOL_ADMIN' ||
      role == 'BRANCH_ADMIN' ||
      role == 'PLATFORM_ADMIN';

  /// Whether [a] is addressed to [v]. (Time and status are checked
  /// separately by [Announcement.isCurrent].)
  static bool addressedTo(Announcement a, AnnouncementViewer v) {
    if (_isAdmin(v.role)) {
      return v.role != 'BRANCH_ADMIN' || a.branchId == v.branchId;
    }
    final isParent = v.role == 'PARENT';
    final isStaff = v.role == 'TEACHER' || v.role == 'FINANCE';
    switch (a.audience) {
      case AnnouncementAudience.all:
        return true;
      case AnnouncementAudience.branch:
        return isParent
            ? v.children.any((c) => c.branchId == a.branchId)
            : v.branchId == a.branchId;
      case AnnouncementAudience.staff:
        return isStaff && v.branchId == a.branchId;
      case AnnouncementAudience.parents:
        return isParent && v.children.any((c) => c.branchId == a.branchId);
      case AnnouncementAudience.classGroup:
        if (isParent) {
          return v.children.any(
            (c) => c.branchId == a.branchId && c.classId == a.classId,
          );
        }
        return v.role == 'TEACHER' &&
            v.branchId == a.branchId &&
            v.teaching.any((t) => t.classId == a.classId);
      case AnnouncementAudience.section:
        if (isParent) {
          return v.children.any(
            (c) =>
                c.branchId == a.branchId &&
                c.classId == a.classId &&
                c.sectionId == a.sectionId,
          );
        }
        return v.role == 'TEACHER' &&
            v.branchId == a.branchId &&
            v.teaching.any(
              (t) => t.classId == a.classId && t.sectionId == a.sectionId,
            );
    }
  }

  /// Announcements a person should see right now.
  static List<Announcement> currentFor(
    Iterable<Announcement> all,
    AnnouncementViewer v,
    DateTime now,
  ) {
    final list = [
      for (final a in all)
        if (a.isCurrent(now) && addressedTo(a, v)) a,
    ];
    list.sort(
      (a, b) =>
          (b.publishAt ?? DateTime(0)).compareTo(a.publishAt ?? DateTime(0)),
    );
    return list;
  }
}

/// `.../broadcastNotices/{id}` — one audience-addressed in-app notice per
/// event (homework published, deadline changed, announcement published).
/// Written in the commit of the event, with a deterministic id, so a retry
/// cannot duplicate it. Recipients are resolved **on read** from the reader's
/// own trusted relationships — no per-recipient fan-out, which would be
/// unbounded without a backend. Carries only a title, a short line and a
/// reference: never a student's work or feedback.
class BroadcastNotice {
  final String noticeId;
  final String type;
  final AnnouncementAudience audience;
  final String branchId;
  final String? classId;
  final String? sectionId;
  final String title;
  final String? body;
  final String refType;
  final String refId;
  final DateTime? createdAt;

  const BroadcastNotice({
    required this.noticeId,
    required this.type,
    required this.audience,
    required this.branchId,
    this.classId,
    this.sectionId,
    required this.title,
    this.body,
    required this.refType,
    required this.refId,
    this.createdAt,
  });

  factory BroadcastNotice.fromFirestore(Map<String, dynamic> d, String id) =>
      BroadcastNotice(
        noticeId: id,
        type: d['type'] as String,
        audience: AnnouncementAudience.fromWireValue(
          d['audienceKind'] as String,
        ),
        branchId: d[FirestoreFields.branchId] as String,
        classId: d['classId'] as String?,
        sectionId: d['sectionId'] as String?,
        title: d['title'] as String? ?? '',
        body: d['body'] as String?,
        refType: d['refType'] as String? ?? '',
        refId: d['refId'] as String? ?? '',
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      );
}
