import 'dart:typed_data';

import 'package:eazy_school_360/features/announcements/domain/announcement_file_uploader.dart';
import 'package:eazy_school_360/features/announcements/domain/attachment_upload_controller.dart';
import 'package:eazy_school_360/features/announcements/presentation/providers/announcement_providers.dart';
import 'package:eazy_school_360/features/announcements/presentation/widgets/announcement_attachments.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _sizes = <(String, Size, double)>[
  ('phone', Size(360, 740), 1.0),
  ('phone large text', Size(360, 740), 1.5),
  ('tablet', Size(820, 1180), 1.0),
  ('desktop', Size(1440, 900), 1.0),
];

class _Uploader implements AnnouncementFileUploader {
  @override
  Future<FileAttachment> upload({
    required String path,
    required String displayName,
    required String contentType,
    required Uint8List bytes,
    required String uploadedBy,
    void Function(double progress)? onProgress,
  }) async => throw UnimplementedError();

  @override
  Future<void> delete(String path) async {}

  @override
  Future<String> downloadUrl(String path) async => throw StateError('expired');
}

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5, 6, 7, 8, //
]);
final _pdf = Uint8List.fromList('%PDF-1.4 x'.codeUnits);

FileAttachment _file(String name, String type, [int size = 2048]) =>
    FileAttachment(
      path: 'schools/s/branches/b/announcements/a/files/$name',
      name: name,
      contentType: type,
      sizeBytes: size,
      uploadedBy: 'u',
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  Size size,
  double scale,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        announcementFileUploaderProvider.overrideWithValue(_Uploader()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

AttachmentUploadController _busyController() {
  final c = AttachmentUploadController(_Uploader())
    ..loadExisting([
      _file(
        'Holiday-list-with-a-very-long-descriptive-file-name-2026.pdf',
        'application/pdf',
        3 * 1024 * 1024,
      ),
      _file(
        'Fee bill October.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      _file('poster.webp', 'image/webp'),
    ]);
  c.add([
    (name: 'event-photo-one.png', bytes: _png),
    (name: 'circular.pdf', bytes: _pdf),
  ]);
  return c;
}

void main() {
  group('attachments editor', () {
    for (final (name, size, scale) in _sizes) {
      testWidgets('lays out without overflow on $name', (tester) async {
        final c = _busyController();
        c.items.last
          ..state = AttachmentState.failed
          ..error = 'No connection. Check your internet and try again.';
        await _pump(
          tester,
          AnnouncementAttachmentsEditor(
            controller: c,
            enabled: true,
            onPickImages: () {},
            onPickDocuments: () {},
            onRetry: (_) {},
          ),
          size,
          scale,
        );
        expect(find.text('Upload images'), findsOneWidget);
        expect(find.text('Upload documents'), findsOneWidget);
        expect(find.text('5 of 10'), findsOneWidget);
        expect(find.text('circular.pdf'), findsOneWidget);
        expect(find.textContaining('No connection'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a failed file shows Retry, and Remove drops it', (
      tester,
    ) async {
      final c = _busyController();
      final failed = c.items.last
        ..state = AttachmentState.failed
        ..error = 'Upload failed.';
      AttachmentItem? retried;
      await _pump(
        tester,
        AnnouncementAttachmentsEditor(
          controller: c,
          enabled: true,
          onPickImages: () {},
          onPickDocuments: () {},
          onRetry: (i) => retried = i,
        ),
        const Size(820, 1180),
        1.0,
      );
      await tester.tap(find.byTooltip('Retry circular.pdf'));
      expect(retried, failed);
      await tester.tap(find.byTooltip('Remove circular.pdf'));
      await tester.pump();
      expect(find.text('circular.pdf'), findsNothing);
      expect(c.items, hasLength(4));
    });

    testWidgets('uploads show progress and cannot be removed mid-upload', (
      tester,
    ) async {
      final c = AttachmentUploadController(_Uploader())
        ..add([(name: 'a.png', bytes: _png)]);
      c.items.single
        ..state = AttachmentState.uploading
        ..progress = 0.4;
      await _pump(
        tester,
        AnnouncementAttachmentsEditor(
          controller: c,
          enabled: true,
          onPickImages: () {},
          onPickDocuments: () {},
          onRetry: (_) {},
        ),
        const Size(360, 740),
        1.0,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final remove = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(remove.onPressed, isNull);
    });

    testWidgets(
      'at 10 files picking is disabled; while saving everything is disabled',
      (tester) async {
        final c = AttachmentUploadController(_Uploader())
          ..add([for (var i = 0; i < 10; i++) (name: 'p$i.pdf', bytes: _pdf)]);
        var enabled = true;
        late StateSetter set;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (_, setState) {
              set = setState;
              return AnnouncementAttachmentsEditor(
                controller: c,
                enabled: enabled,
                onPickImages: () {},
                onPickDocuments: () {},
                onRetry: (_) {},
              );
            },
          ),
          const Size(820, 1180),
          1.0,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.ancestor(
                  of: find.text('Upload images'),
                  matching: find.bySubtype<OutlinedButton>(),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.ancestor(
                  of: find.text('Upload documents'),
                  matching: find.bySubtype<OutlinedButton>(),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('10 of 10'), findsOneWidget);
        set(() => enabled = false);
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.close).first,
              )
              .onPressed,
          isNull,
        );
      },
    );
  });

  group('attachments viewer', () {
    final files = [
      _file('poster.png', 'image/png'),
      _file('Circular-2026.pdf', 'application/pdf', 1024 * 1024),
      _file(
        'Fee bill.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      _file(
        'Rules.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
    ];

    for (final (name, size, scale) in _sizes) {
      testWidgets('lays out without overflow on $name', (tester) async {
        await _pump(
          tester,
          AnnouncementAttachmentsView(attachments: files),
          size,
          scale,
        );
        expect(find.text('Attachments (4)'), findsOneWidget);
        expect(find.text('Circular-2026.pdf'), findsOneWidget);
        expect(find.textContaining('PDF · 1.0 MB'), findsOneWidget);
        expect(find.byTooltip('Download Fee bill.xlsx'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'an unavailable image shows a placeholder, and tapping opens the preview with a download action',
      (tester) async {
        await _pump(
          tester,
          AnnouncementAttachmentsView(attachments: files),
          const Size(820, 1180),
          1.0,
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Open image poster.png'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Download poster.png'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a download that cannot get a link says so instead of failing silently',
      (tester) async {
        await _pump(
          tester,
          AnnouncementAttachmentsView(attachments: files),
          const Size(820, 1180),
          1.0,
        );
        await tester.tap(find.byTooltip('Download Circular-2026.pdf'));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  });
}
