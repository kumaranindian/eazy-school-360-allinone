import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../homework/domain/homework_repositories.dart';
import '../domain/announcement.dart';

/// The documents the announcement workflow writes (see `HomeworkWrites` for
/// why they are pure functions: a contract test replays them through the
/// real rules).
abstract final class AnnouncementWrites {
  static Map<String, dynamic> stamp(String uid) => {
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: uid,
  };

  static String historyId(String id, int revision) => '${id}__$revision';

  static Map<String, dynamic> history({
    required Announcement a,
    required int revision,
    required AnnouncementEvent event,
    required AnnouncementStatus toStatus,
    required HomeworkActor actor,
  }) => {
    FirestoreFields.schoolId: a.schoolId,
    FirestoreFields.branchId: a.branchId,
    'announcementId': a.announcementId,
    'revision': revision,
    'event': event.wireValue,
    'toStatus': toStatus.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'at': FieldValue.serverTimestamp(),
  };

  static Map<String, dynamic> draftEdit(
    Announcement a,
    int revision,
    String uid,
  ) => {
    ...a.body_(),
    'revision': revision,
    'lastEvent': AnnouncementEvent.edited.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> publish({
    required DateTime publishAt,
    required DateTime? expiresAt,
    required int revision,
    required String uid,
  }) => {
    FirestoreFields.status: AnnouncementStatus.published.wireValue,
    'publishAt': Timestamp.fromDate(publishAt),
    'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
    'publishedBy': uid,
    'publishedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': AnnouncementEvent.published.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> updatePublished(
    Announcement a,
    int revision,
    String uid,
  ) => {
    'title': a.title.trim(),
    'body': a.body.trim(),
    'attachments': [for (final x in a.attachments) x.toMap()],
    'expiresAt': a.expiresAt == null ? null : Timestamp.fromDate(a.expiresAt!),
    'revision': revision,
    'lastEvent': AnnouncementEvent.updated.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> archive(int revision, String uid) => {
    FirestoreFields.status: AnnouncementStatus.archived.wireValue,
    'revision': revision,
    'lastEvent': AnnouncementEvent.archived.wireValue,
    ...stamp(uid),
  };
}
