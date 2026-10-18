import '../../homework/domain/homework_repositories.dart';
import 'announcement.dart';
import 'attachment_upload_controller.dart';

enum AnnouncementSaveOutcome {
  /// Saved (as a draft, or an edit of a published announcement).
  saved,

  /// Published; the audience notice was written in the same commit.
  published,

  /// Some files could not be uploaded. The draft is saved, nothing was
  /// published and no notice was written; retry the files or remove them.
  uploadsFailed,
}

/// The order of work when an announcement with attachments is saved or
/// published. Each step is safe to repeat, so a retry after any failure never
/// duplicates the announcement, its history or its notice:
///
/// 1. save the draft (same id every time) so the files have an announcement
///    to belong to — the Storage rules require it;
/// 2. upload what is not uploaded yet (already uploaded files are kept);
/// 3. save the draft again with the files' metadata;
/// 4. delete Storage objects of attachments the user removed (only now that
///    the saved announcement no longer references them);
/// 5. publish — the notice is written in that commit, never before it.
///
/// An already published announcement is edited in one commit
/// ([AnnouncementRepository.update]); its new files were uploaded when added.
class AnnouncementSaveFlow {
  final AnnouncementRepository repository;
  final AttachmentUploadController files;

  const AnnouncementSaveFlow(this.repository, this.files);

  Future<AnnouncementSaveOutcome> run({
    required Announcement Function() build,
    required bool editingPublished,
    required bool publish,
    required DateTime publishAt,
    required bool notify,
    required HomeworkActor actor,
    required String Function(String attachmentFileName) pathFor,
    required String uploadedBy,
    void Function()? onDraftSaved,
  }) async {
    if (editingPublished) {
      await repository.update(build(), actor: actor, notify: notify);
      files.markPersisted();
      await files.deleteRemoved();
      return AnnouncementSaveOutcome.saved;
    }
    await repository.saveDraft(build(), actor: actor);
    onDraftSaved?.call();
    if (files.hasUnresolved) {
      final ok = await files.uploadAll(
        pathFor: pathFor,
        uploadedBy: uploadedBy,
      );
      if (!ok) return AnnouncementSaveOutcome.uploadsFailed;
      await repository.saveDraft(build(), actor: actor);
    }
    files.markPersisted();
    await files.deleteRemoved();
    if (!publish) return AnnouncementSaveOutcome.saved;
    await repository.publish(build(), publishAt: publishAt, actor: actor);
    return AnnouncementSaveOutcome.published;
  }
}
