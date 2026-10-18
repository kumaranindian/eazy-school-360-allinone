import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/error_mapper.dart';
import '../../homework/domain/file_attachment.dart';
import 'announcement_file_policy.dart';
import 'announcement_file_uploader.dart';

enum AttachmentState { queued, uploading, uploaded, failed }

/// One attachment on the form: either one already saved with the
/// announcement, or a picked file on its way up.
class AttachmentItem {
  final String id;
  final String name;
  final String contentType;
  final int sizeBytes;

  /// Null for files that were already uploaded when the form opened.
  final Uint8List? bytes;

  AttachmentState state;
  double progress;
  String? error;
  FileAttachment? file;

  /// True once the saved announcement references [file]. Removing such a
  /// file only deletes the object after the announcement save succeeds.
  bool persisted;

  AttachmentItem({
    required this.id,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    this.bytes,
    this.state = AttachmentState.queued,
    this.progress = 0,
    this.error,
    this.file,
    this.persisted = false,
  });

  bool get isImage => AnnouncementFilePolicy.isImageType(contentType);
  bool get isUploaded => state == AttachmentState.uploaded;
}

/// A picked file as the platform returned it.
typedef PickedBytes = ({String name, Uint8List bytes});

/// The attachment state of the announcement form: validation, bounded
/// parallel uploads with per-file progress, retry of a failed file, and the
/// bookkeeping that makes removal safe (an object is deleted only after the
/// announcement no longer references it). Pure Dart so it is unit-testable.
class AttachmentUploadController extends ChangeNotifier {
  final AnnouncementFileUploader _uploader;
  final int concurrency;
  final List<AttachmentItem> items = [];
  final List<AttachmentItem> _removedPersisted = [];
  bool _disposed = false;
  bool _running = false;

  AttachmentUploadController(this._uploader, {this.concurrency = 3});

  /// Seeds the files an announcement already has.
  void loadExisting(List<FileAttachment> files) {
    items
      ..clear()
      ..addAll([
        for (final f in files)
          AttachmentItem(
            id: f.path,
            name: f.name,
            contentType: f.contentType,
            sizeBytes: f.sizeBytes,
            state: AttachmentState.uploaded,
            progress: 1,
            file: f,
            persisted: true,
          ),
      ]);
    _notify();
  }

  bool get isUploading => _running;
  bool get hasUnresolved => items.any((i) => !i.isUploaded);
  List<AttachmentItem> get failed =>
      items.where((i) => i.state == AttachmentState.failed).toList();
  List<AttachmentItem> get waiting => items
      .where(
        (i) =>
            i.state == AttachmentState.queued ||
            i.state == AttachmentState.uploading,
      )
      .toList();

  /// Files the announcement should reference right now.
  List<FileAttachment> get attachments => [
    for (final i in items)
      if (i.isUploaded && i.file != null) i.file!,
  ];

  /// Overall progress 0..1 over the files not yet uploaded when [uploadAll]
  /// started (1 when nothing is pending).
  double get overallProgress {
    final pending = items.where((i) => i.bytes != null).toList();
    if (pending.isEmpty) return 1;
    return pending.fold<double>(0, (s, i) => s + i.progress) / pending.length;
  }

  /// Validates and queues [picked]; returns a message for every file refused
  /// (type, size, signature, duplicate, over the count limit).
  List<String> add(List<PickedBytes> picked) {
    final problems = <String>[];
    var room = AnnouncementFilePolicy.maxFiles - items.length;
    for (final p in picked) {
      final name = AnnouncementFilePolicy.displayName(p.name);
      final problem = AnnouncementFilePolicy.validate(
        fileName: p.name,
        bytes: p.bytes,
      );
      if (problem != null) {
        problems.add('$name: $problem');
        continue;
      }
      if (room <= 0) {
        problems.add(
          '$name: ${AnnouncementFilePolicy.validateCount(current: items.length, adding: 1)}',
        );
        continue;
      }
      if (items.any(
        (i) =>
            i.name == name && i.sizeBytes == p.bytes.length && i.bytes != null,
      )) {
        problems.add('$name: already added.');
        continue;
      }
      room--;
      items.add(
        AttachmentItem(
          id: AnnouncementFilePolicy.newAttachmentId(),
          name: name,
          contentType: AnnouncementFilePolicy.contentTypeFor(p.name)!,
          sizeBytes: p.bytes.length,
          bytes: p.bytes,
        ),
      );
    }
    _notify();
    return problems;
  }

  /// Removes [item] from the form. A file the saved announcement still
  /// references is only deleted from Storage by [deleteRemoved], after the
  /// announcement is saved without it; one that was never referenced is
  /// deleted at once.
  Future<void> remove(AttachmentItem item) async {
    if (!items.remove(item)) return;
    if (item.persisted && item.file != null) {
      _removedPersisted.add(item);
    } else if (item.isUploaded && item.file != null) {
      unawaited(_deleteQuietly(item.file!.path));
    }
    _notify();
  }

  /// Call after the announcement was saved without the removed files.
  Future<void> deleteRemoved() async {
    final todo = List.of(_removedPersisted);
    _removedPersisted.clear();
    for (final i in todo) {
      await _deleteQuietly(i.file!.path);
    }
  }

  /// Marks everything uploaded so far as referenced by the saved announcement.
  void markPersisted() {
    for (final i in items) {
      if (i.isUploaded) i.persisted = true;
    }
  }

  /// Deletes files uploaded in this session that no saved announcement
  /// references (the form was left without saving).
  void discardUnsaved() {
    for (final i in items) {
      if (i.isUploaded && !i.persisted && i.file != null) {
        unawaited(_deleteQuietly(i.file!.path));
      }
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await _uploader.delete(path);
    } catch (_) {
      // The object is unreferenced either way; a leftover is harmless.
    }
  }

  /// Uploads every queued or failed file with at most [concurrency] in
  /// flight. Returns true when nothing is left unresolved. Safe to call
  /// again after failures: only files that are not uploaded are sent.
  Future<bool> uploadAll({
    required String Function(String attachmentFileName) pathFor,
    required String uploadedBy,
  }) async {
    if (_running) return false;
    _running = true;
    final todo = items.where((i) => !i.isUploaded && i.bytes != null).toList();
    for (final i in todo) {
      i.state = AttachmentState.queued;
      i.progress = 0;
      i.error = null;
    }
    _notify();
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length && !_disposed) {
        final item = todo[next++];
        await _uploadOne(item, pathFor: pathFor, uploadedBy: uploadedBy);
      }
    }

    try {
      await Future.wait([
        for (var w = 0; w < concurrency && w < todo.length; w++) worker(),
      ]);
    } finally {
      _running = false;
      _notify();
    }
    return !hasUnresolved;
  }

  /// Retries one failed file.
  Future<bool> retry(
    AttachmentItem item, {
    required String Function(String attachmentFileName) pathFor,
    required String uploadedBy,
  }) async {
    if (item.isUploaded || item.bytes == null) return item.isUploaded;
    await _uploadOne(item, pathFor: pathFor, uploadedBy: uploadedBy);
    return item.isUploaded;
  }

  Future<void> _uploadOne(
    AttachmentItem item, {
    required String Function(String attachmentFileName) pathFor,
    required String uploadedBy,
  }) async {
    item
      ..state = AttachmentState.uploading
      ..progress = 0
      ..error = null;
    _notify();
    try {
      item.file = await _uploader.upload(
        path: pathFor(
          AnnouncementFilePolicy.storageFileName(item.id, item.name),
        ),
        displayName: item.name,
        contentType: item.contentType,
        bytes: item.bytes!,
        uploadedBy: uploadedBy,
        onProgress: (p) {
          item.progress = p.clamp(0.0, 1.0);
          _notify();
        },
      );
      item
        ..state = AttachmentState.uploaded
        ..progress = 1;
    } catch (e) {
      item
        ..state = AttachmentState.failed
        ..error = userMessageFor(e);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
