import 'dart:async';
import 'dart:typed_data';

import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/announcements/domain/announcement.dart';
import 'package:eazy_school_360/features/announcements/domain/announcement_file_policy.dart';
import 'package:eazy_school_360/features/announcements/domain/announcement_file_uploader.dart';
import 'package:eazy_school_360/features/announcements/domain/announcement_save_flow.dart';
import 'package:eazy_school_360/features/announcements/domain/attachment_upload_controller.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';
import 'package:eazy_school_360/features/homework/domain/homework_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/homework_fakes.dart';

Uint8List _png([int extra = 0]) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...List.filled(extra + 8, 1), //
]);
Uint8List _jpg([int extra = 0]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(extra + 8, 2)]);
Uint8List _webp() => Uint8List.fromList([
  0x52,
  0x49,
  0x46,
  0x46,
  0,
  0,
  0,
  0,
  0x57,
  0x45,
  0x42,
  0x50,
  1,
  2,
]);
Uint8List _pdf() => Uint8List.fromList('%PDF-1.4 circular'.codeUnits);
Uint8List _zip() => Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]);
Uint8List _ole() =>
    Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0]);

class _FakeUploader implements AnnouncementFileUploader {
  final List<String> uploaded = [];
  final List<String> deleted = [];
  final Set<String> failNames = {};
  int inFlight = 0;
  int maxInFlight = 0;
  Completer<void>? gate;

  @override
  Future<FileAttachment> upload({
    required String path,
    required String displayName,
    required String contentType,
    required Uint8List bytes,
    required String uploadedBy,
    void Function(double progress)? onProgress,
  }) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      onProgress?.call(0.5);
      await gate?.future;
      await Future<void>.delayed(Duration.zero);
      if (failNames.contains(displayName)) {
        throw const NetworkFailure('offline');
      }
      uploaded.add(path);
      return FileAttachment(
        path: path,
        name: displayName,
        contentType: contentType,
        sizeBytes: bytes.length,
        uploadedBy: uploadedBy,
      );
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);

  @override
  Future<String> downloadUrl(String path) async => 'https://example.test/$path';
}

String _pathFor(String f) => 'schools/s/branches/b/announcements/an1/files/$f';

AttachmentUploadController _ctrl(_FakeUploader u, {int concurrency = 3}) =>
    AttachmentUploadController(u, concurrency: concurrency);

Announcement _announcement(AttachmentUploadController c) => Announcement(
  announcementId: 'an1',
  schoolId: 's',
  branchId: 'b',
  audience: AnnouncementAudience.branch,
  title: 'Holiday notice',
  body: 'School is closed on Friday.',
  attachments: c.attachments,
  authorId: 'u1',
  authorName: 'Admin',
  authorRole: 'SCHOOL_ADMIN',
);

const _actor = HomeworkActor(userId: 'u1', name: 'Admin', role: 'SCHOOL_ADMIN');

class _Repo extends FakeAnnouncementRepository {
  int failSaveDraftAt = 0; // 1-based call number that fails
  bool failPublish = false;
  int saveCalls = 0;
  int publishCalls = 0;

  @override
  Future<void> saveDraft(
    Announcement announcement, {
    required HomeworkActor actor,
  }) async {
    saveCalls++;
    if (saveCalls == failSaveDraftAt) throw const NetworkFailure('offline');
    await super.saveDraft(announcement, actor: actor);
  }

  @override
  Future<void> publish(
    Announcement announcement, {
    required DateTime publishAt,
    required HomeworkActor actor,
  }) async {
    publishCalls++;
    if (failPublish) throw const NetworkFailure('offline');
    await super.publish(announcement, publishAt: publishAt, actor: actor);
  }
}

Future<AnnouncementSaveOutcome> _run(
  _Repo repo,
  AttachmentUploadController c, {
  bool publish = true,
  bool editingPublished = false,
}) => AnnouncementSaveFlow(repo, c).run(
  build: () => _announcement(c),
  editingPublished: editingPublished,
  publish: publish,
  publishAt: DateTime(2026, 1, 1),
  notify: true,
  actor: _actor,
  pathFor: _pathFor,
  uploadedBy: 'u1',
);

void main() {
  group('AnnouncementFilePolicy', () {
    test(
      'accepts images, PDF, Word, Excel and text by extension + signature',
      () {
        for (final (name, bytes) in <(String, Uint8List)>[
          ('a.jpg', _jpg()),
          ('a.JPEG', _jpg()),
          ('a.png', _png()),
          ('a.webp', _webp()),
          ('circular.pdf', _pdf()),
          ('rules.docx', _zip()),
          ('fees.xlsx', _zip()),
          ('old.doc', _ole()),
          ('old.xls', _ole()),
          ('n.txt', Uint8List.fromList('hello'.codeUnits)),
        ]) {
          expect(
            AnnouncementFilePolicy.validate(fileName: name, bytes: bytes),
            isNull,
            reason: name,
          );
        }
      },
    );

    test('refuses executables, scripts, unknown and double extensions', () {
      for (final name in [
        'run.exe', 'x.sh', 'x.js', 'x.html', 'x.svg', 'x.bat', 'noext', 'x.', //
        'evil.exe.pdf.exe',
      ]) {
        expect(
          AnnouncementFilePolicy.validate(fileName: name, bytes: _pdf()),
          isNotNull,
          reason: name,
        );
      }
    });

    test('a renamed file whose contents do not match is refused', () {
      final exe = Uint8List.fromList([0x4D, 0x5A, 0x90, 0, 3, 0]); // MZ
      for (final name in ['fake.pdf', 'fake.png', 'fake.docx', 'fake.jpg']) {
        expect(
          AnnouncementFilePolicy.validate(fileName: name, bytes: exe),
          contains('do not match'),
          reason: name,
        );
      }
      expect(
        AnnouncementFilePolicy.validate(
          fileName: 'bin.txt',
          bytes: Uint8List.fromList([65, 0, 66]),
        ),
        isNotNull,
      );
    });

    test(
      'size: exactly 10 MB is accepted, one byte more is refused, empty too',
      () {
        final ok = Uint8List(AnnouncementFilePolicy.maxBytes)
          ..setRange(0, 5, '%PDF-'.codeUnits);
        final big = Uint8List(AnnouncementFilePolicy.maxBytes + 1)
          ..setRange(0, 5, '%PDF-'.codeUnits);
        expect(
          AnnouncementFilePolicy.validate(fileName: 'a.pdf', bytes: ok),
          isNull,
        );
        expect(
          AnnouncementFilePolicy.validate(fileName: 'a.pdf', bytes: big),
          contains('10 MB'),
        );
        expect(
          AnnouncementFilePolicy.validate(
            fileName: 'a.pdf',
            bytes: Uint8List(0),
          ),
          contains('empty'),
        );
      },
    );

    test('count limit is 10', () {
      expect(
        AnnouncementFilePolicy.validateCount(current: 9, adding: 1),
        isNull,
      );
      expect(
        AnnouncementFilePolicy.validateCount(current: 10, adding: 1),
        contains('at most 10'),
      );
    });

    test(
      'display names are sanitised; storage names never contain the user name',
      () {
        expect(
          AnnouncementFilePolicy.displayName('../../etc/passwd.pdf'),
          isNot(contains('/')),
        );
        expect(
          AnnouncementFilePolicy.displayName('..\\..\\x.pdf'),
          isNot(contains('\\')),
        );
        expect(AnnouncementFilePolicy.displayName('...'), 'file');
        expect(
          AnnouncementFilePolicy.displayName('a\u0000b.pdf'),
          isNot(contains('\u0000')),
        );
        expect(
          AnnouncementFilePolicy.displayName('${'x' * 300}.pdf').length,
          100,
        );
        expect(
          AnnouncementFilePolicy.displayName('${'x' * 300}.pdf'),
          endsWith('.pdf'),
        );
        final id1 = AnnouncementFilePolicy.newAttachmentId();
        final id2 = AnnouncementFilePolicy.newAttachmentId();
        expect(id1, isNot(id2));
        final name = AnnouncementFilePolicy.storageFileName(
          id1,
          '../../Fee Bill.PDF',
        );
        expect(name, matches(RegExp(r'^att_[a-z0-9_]+\.pdf$')));
      },
    );
  });

  group('AttachmentUploadController', () {
    test(
      'queues several images and a PDF, uploads them all with progress',
      () async {
        final u = _FakeUploader();
        final c = _ctrl(u);
        final problems = c.add([
          (name: 'one.jpg', bytes: _jpg()),
          (name: 'two.png', bytes: _png()),
          (name: 'three.webp', bytes: _webp()),
          (name: 'circular.pdf', bytes: _pdf()),
        ]);
        expect(problems, isEmpty);
        expect(c.items, hasLength(4));
        expect(c.hasUnresolved, isTrue);
        expect(await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1'), isTrue);
        expect(c.hasUnresolved, isFalse);
        expect(c.attachments.map((f) => f.name), [
          'one.jpg', 'two.png', 'three.webp', 'circular.pdf', //
        ]);
        expect(
          u.uploaded.every(
            (p) => p.startsWith(
              'schools/s/branches/b/announcements/an1/files/att_',
            ),
          ),
          isTrue,
        );
        expect(
          u.uploaded.any((p) => p.contains('one')),
          isFalse,
          reason: 'the user filename never reaches the path',
        );
        expect(c.overallProgress, 1);
      },
    );

    test('a fee bill (xlsx) and a Word circular upload', () async {
      final u = _FakeUploader();
      final c = _ctrl(u)
        ..add([
          (name: 'Bill.xlsx', bytes: _zip()),
          (name: 'c.docx', bytes: _zip()),
        ]);
      expect(await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1'), isTrue);
      expect(
        c.attachments.map((f) => f.contentType),
        contains(
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      );
    });

    test('refuses unsupported, oversize, duplicate and over-limit files', () {
      final c = _ctrl(_FakeUploader());
      var problems = c.add([
        (name: 'run.exe', bytes: _pdf()),
        (
          name: 'big.pdf',
          bytes: Uint8List(AnnouncementFilePolicy.maxBytes + 1),
        ),
        (name: 'ok.pdf', bytes: _pdf()),
        (name: 'ok.pdf', bytes: _pdf()),
      ]);
      expect(problems, hasLength(3));
      expect(c.items, hasLength(1));
      problems = c.add([
        for (var i = 0; i < 12; i++) (name: 'p$i.png', bytes: _png(i)),
      ]);
      expect(c.items, hasLength(10));
      expect(problems.where((p) => p.contains('at most 10')), hasLength(3));
    });

    test(
      'a file can be removed before publishing; nothing is uploaded for it',
      () async {
        final u = _FakeUploader();
        final c = _ctrl(u)
          ..add([
            (name: 'a.png', bytes: _png()),
            (name: 'b.pdf', bytes: _pdf()),
          ]);
        await c.remove(c.items.first);
        expect(await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1'), isTrue);
        expect(c.attachments.map((f) => f.name), ['b.pdf']);
        expect(u.deleted, isEmpty);
      },
    );

    test('uploads are bounded by the concurrency limit', () async {
      final u = _FakeUploader();
      final c = _ctrl(u, concurrency: 2)
        ..add([for (var i = 0; i < 6; i++) (name: 'p$i.png', bytes: _png(i))]);
      await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1');
      expect(u.maxInFlight, lessThanOrEqualTo(2));
      expect(u.uploaded, hasLength(6));
    });

    test(
      'a failed upload is reported per file, kept, and can be retried',
      () async {
        final u = _FakeUploader()..failNames.add('b.pdf');
        final c = _ctrl(u)
          ..add([
            (name: 'a.png', bytes: _png()),
            (name: 'b.pdf', bytes: _pdf()),
          ]);
        expect(await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1'), isFalse);
        expect(c.failed.single.name, 'b.pdf');
        expect(c.failed.single.error, isNotNull);
        expect(c.items, hasLength(2), reason: 'nothing is silently dropped');
        expect(c.attachments.map((f) => f.name), ['a.png']);
        // the network comes back: only the failed file is sent again
        u.failNames.clear();
        u.uploaded.clear();
        expect(await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1'), isTrue);
        expect(u.uploaded, hasLength(1));
        expect(c.attachments, hasLength(2));
      },
    );

    test('retrying one failed file by itself', () async {
      final u = _FakeUploader()..failNames.add('a.png');
      final c = _ctrl(u)..add([(name: 'a.png', bytes: _png())]);
      await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1');
      u.failNames.clear();
      expect(
        await c.retry(c.items.single, pathFor: _pathFor, uploadedBy: 'u1'),
        isTrue,
      );
      expect(c.hasUnresolved, isFalse);
    });

    test(
      'a second uploadAll while one runs is ignored (no duplicate uploads)',
      () async {
        final u = _FakeUploader()..gate = Completer<void>();
        final c = _ctrl(u)..add([(name: 'a.png', bytes: _png())]);
        final first = c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1');
        expect(await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1'), isFalse);
        u.gate!.complete();
        expect(await first, isTrue);
        expect(u.uploaded, hasLength(1));
      },
    );

    test(
      'editing: existing files are kept, one can be added, one removed (deleted only after the save)',
      () async {
        final u = _FakeUploader();
        final c = _ctrl(u)
          ..loadExisting([
            const FileAttachment(
              path: 'p/old1.pdf',
              name: 'old1.pdf',
              contentType: 'application/pdf',
              sizeBytes: 5,
              uploadedBy: 'u1',
            ),
            const FileAttachment(
              path: 'p/old2.png',
              name: 'old2.png',
              contentType: 'image/png',
              sizeBytes: 5,
              uploadedBy: 'u1',
            ),
          ]);
        expect(c.hasUnresolved, isFalse);
        c.add([(name: 'new.png', bytes: _png())]);
        await c.remove(c.items.first); // old1.pdf, already saved
        expect(
          u.deleted,
          isEmpty,
          reason: 'still referenced by the saved announcement',
        );
        await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1');
        expect(c.attachments.map((f) => f.name), ['old2.png', 'new.png']);
        await c.deleteRemoved();
        expect(u.deleted, ['p/old1.pdf']);
      },
    );

    test(
      'a file uploaded but never saved is deleted when removed or discarded',
      () async {
        final u = _FakeUploader();
        final c = _ctrl(u)
          ..add([
            (name: 'a.png', bytes: _png()),
            (name: 'b.png', bytes: _png(1)),
          ]);
        await c.uploadAll(pathFor: _pathFor, uploadedBy: 'u1');
        await c.remove(c.items.first);
        c.discardUnsaved();
        await Future<void>.delayed(Duration.zero);
        expect(u.deleted, hasLength(2));
      },
    );
  });

  group('AnnouncementSaveFlow', () {
    test('without attachments: publishes once', () async {
      final repo = _Repo();
      final c = _ctrl(_FakeUploader());
      expect(await _run(repo, c), AnnouncementSaveOutcome.published);
      expect(repo.published, ['an1']);
      expect(repo.saveCalls, 1);
    });

    test(
      'with an image and a PDF: draft, upload, draft again, publish',
      () async {
        final repo = _Repo();
        final u = _FakeUploader();
        final c = _ctrl(u)
          ..add([
            (name: 'poster.png', bytes: _png()),
            (name: 'circular.pdf', bytes: _pdf()),
          ]);
        expect(await _run(repo, c), AnnouncementSaveOutcome.published);
        expect(repo.saveCalls, 2);
        expect(repo.docs['an1']!.attachments, hasLength(2));
        expect(repo.published, ['an1']);
      },
    );

    test(
      'an upload failure stops before publishing; the retry publishes exactly once',
      () async {
        final repo = _Repo();
        final u = _FakeUploader()..failNames.add('bill.pdf');
        final c = _ctrl(u)
          ..add([
            (name: 'bill.pdf', bytes: _pdf()),
            (name: 'a.png', bytes: _png()),
          ]);
        expect(await _run(repo, c), AnnouncementSaveOutcome.uploadsFailed);
        expect(repo.published, isEmpty);
        expect(repo.publishCalls, 0, reason: 'no notice for a failed publish');
        expect(c.failed.single.name, 'bill.pdf');
        u.failNames.clear();
        expect(await _run(repo, c), AnnouncementSaveOutcome.published);
        expect(repo.published, ['an1']);
        expect(repo.docs['an1']!.attachments, hasLength(2));
      },
    );

    test(
      'saving the announcement fails after the files uploaded: nothing is re-uploaded on retry',
      () async {
        final repo = _Repo()..failSaveDraftAt = 2;
        final u = _FakeUploader();
        final c = _ctrl(u)..add([(name: 'a.png', bytes: _png())]);
        await expectLater(_run(repo, c), throwsA(isA<NetworkFailure>()));
        expect(u.uploaded, hasLength(1));
        expect(repo.published, isEmpty);
        expect(await _run(repo, c), AnnouncementSaveOutcome.published);
        expect(u.uploaded, hasLength(1), reason: 'the uploaded file was kept');
        expect(repo.published, ['an1']);
      },
    );

    test(
      'a publish failure leaves a draft; the retry publishes once',
      () async {
        final repo = _Repo()..failPublish = true;
        final c = _ctrl(_FakeUploader())..add([(name: 'a.png', bytes: _png())]);
        await expectLater(_run(repo, c), throwsA(isA<NetworkFailure>()));
        expect(repo.published, isEmpty);
        repo.failPublish = false;
        expect(await _run(repo, c), AnnouncementSaveOutcome.published);
        expect(repo.published, ['an1'], reason: 'one publish, one notice');
      },
    );

    test(
      'editing a published announcement: removed objects are deleted after the update',
      () async {
        final repo = _Repo();
        final u = _FakeUploader();
        final c = _ctrl(u)
          ..loadExisting([
            const FileAttachment(
              path: 'p/old.pdf',
              name: 'old.pdf',
              contentType: 'application/pdf',
              sizeBytes: 5,
              uploadedBy: 'u1',
            ),
          ]);
        await c.remove(c.items.single);
        expect(
          await _run(repo, c, editingPublished: true),
          AnnouncementSaveOutcome.saved,
        );
        expect(repo.docs['an1']!.attachments, isEmpty);
        expect(u.deleted, ['p/old.pdf']);
      },
    );

    test(
      'if the update fails the removed object is NOT deleted (no dangling reference)',
      () async {
        final repo = _ThrowingUpdate();
        final u = _FakeUploader();
        final c = _ctrl(u)
          ..loadExisting([
            const FileAttachment(
              path: 'p/old.pdf',
              name: 'old.pdf',
              contentType: 'application/pdf',
              sizeBytes: 5,
              uploadedBy: 'u1',
            ),
          ]);
        await c.remove(c.items.single);
        await expectLater(
          _run(repo, c, editingPublished: true),
          throwsA(isA<NetworkFailure>()),
        );
        expect(u.deleted, isEmpty);
      },
    );

    test('saving as a draft never publishes', () async {
      final repo = _Repo();
      final c = _ctrl(_FakeUploader())..add([(name: 'a.png', bytes: _png())]);
      expect(
        await _run(repo, c, publish: false),
        AnnouncementSaveOutcome.saved,
      );
      expect(repo.publishCalls, 0);
    });
  });
}

class _ThrowingUpdate extends _Repo {
  @override
  Future<void> update(
    Announcement announcement, {
    required HomeworkActor actor,
    required bool notify,
  }) async => throw const NetworkFailure('offline');
}
