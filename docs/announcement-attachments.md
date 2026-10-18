# Announcement attachments

Extends Milestone 9 announcements (`docs/milestone-9-homework-assignments-announcements.md`). Announcements already carried up to 5 files; this raises that to 10 and adds images, Word/Excel, thumbnails, progress, retry and safe cleanup.

## Behaviour
* **Create / edit form → Attachments:** *Upload images* (JPG, PNG, WebP) and *Upload documents* (PDF, DOC/DOCX, XLS/XLSX, TXT); multi-select; thumbnails for images, type icon + size for documents; per-file progress, **Retry** on a failed file, **Remove**.
* **Limits** (`AnnouncementFilePolicy`): 10 files, 10 MB each (inclusive), extension allowlist, file signature must match the extension (a renamed executable is refused before upload). Storage rules enforce the same type/size/extension independently.
* **Save order** (`AnnouncementSaveFlow`): save draft (same id every time) → upload what is not uploaded (3 at a time) → save draft with metadata → delete objects the user removed → publish. A failed upload stops before publish: draft kept, no notice written, failed files listed for retry/removal. Retrying never duplicates the announcement, history or notice (deterministic ids). Editing a published announcement: new files upload when added, one `update` commit, removed objects are deleted only after it succeeds.
* **Orphans:** files uploaded but never saved are deleted when removed or when the form is left (best effort). A crash can still leave an unreferenced object; a periodic cleanup function is recommended (not built).
* **Viewing:** detail page shows image thumbnails (decoded small), tap → zoomable preview with Download; documents show type · size with open and download. Links are short-lived, minted per tap; no URL is stored. Expired/unavailable files show a message. There is no in-app PDF viewer: PDFs open in the browser/device viewer (no new dependency).
* **Notification:** unchanged flow; the notice body becomes `<title> · N attachment(s)`. Written in the publish commit only.

## Data
Metadata stays in `announcements.attachments[]` (existing `FileAttachment`): `path` (= storagePath; embeds schoolId, branchId, announcementId, and the generated id `att_<id>.<ext>`), `name` (sanitised display name), `contentType`, `sizeBytes`, `uploadedBy`, `uploadedAt`. Objects: `schools/{s}/branches/{b}/announcements/{id}/files/att_<id>.<ext>`.

## Rules
* `firestore.rules`: `attachments` ≤ 10 on create, draft edit and published update (was 5, create only).
* `storage.rules` (announcement files): create-only (no overwrite); name must be `[A-Za-z0-9_]+.<allowed ext>`; content type allowlist; 1 byte – 10 MB; **create/delete only by branch admin or the announcement's author (teacher)**; read by branch admins and the author, otherwise only PUBLISHED announcements whose `publishAt` has passed, never STAFF-only to parents or PARENTS-only to staff. Different school ⇒ denied.
* Tests: `firestore-tests/announcement-attachment-storage-rules.test.mjs`, `homework-storage-rules.test.mjs`, `homework-rules.test.mjs`.

## Limitations
* Storage rules cannot sniff bytes or scan for malware; the app checks signatures but **no malware scanning exists**. Production recommendation: the Firebase "Scan files with Cloud Storage Antivirus"-style extension or a Cloud Function on `finalize` that scans and quarantines.
* Finer audience scoping (a parent of another class/section who knows the path) needs more Firestore lookups than Storage rules allow; as before, the app lists only what is addressed to the viewer, and the rule enforces school, published/due and staff-vs-parent audience.
* Interrupted uploads are retried by the user (Retry), not resumed.
* Web needs the bucket CORS from `storage.cors.json` for thumbnails (already in the repo; see DEVELOPMENT_GUIDE.md).

## Deploy
`firebase deploy --only firestore:rules,storage --project <id>`, then the web build / APK. No new secrets or Console settings. Check the rules release size (`firestore.rules` is ~7,250 operators; limit ~8,600).
