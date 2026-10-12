import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/staff/domain/staff_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateFile', () {
    test('accepts PDF, JPG and PNG under 5MB, any case', () {
      for (final name in ['id.pdf', 'scan.JPG', 'photo.jpeg', 'cert.PNG']) {
        expect(
          StaffDocument.validateFile(fileName: name, sizeBytes: 1000),
          isNull,
          reason: name,
        );
      }
    });

    test('rejects other types', () {
      for (final name in [
        'malware.exe',
        'page.html',
        'sheet.xlsx',
        'noextension',
      ]) {
        expect(
          StaffDocument.validateFile(fileName: name, sizeBytes: 10),
          isNotNull,
          reason: name,
        );
      }
    });

    test('rejects 5MB and over, accepts just under', () {
      expect(
        StaffDocument.validateFile(
          fileName: 'a.pdf',
          sizeBytes: StaffDocument.maxSizeBytes - 1,
        ),
        isNull,
      );
      expect(
        StaffDocument.validateFile(
          fileName: 'a.pdf',
          sizeBytes: StaffDocument.maxSizeBytes + 1,
        ),
        contains('5MB'),
      );
    });
  });

  test('content types match what storage.rules allows (pdf, jpeg, png)', () {
    expect(StaffDocument.contentTypeForExtension('pdf'), 'application/pdf');
    expect(StaffDocument.contentTypeForExtension('PNG'), 'image/png');
    expect(StaffDocument.contentTypeForExtension('jpg'), 'image/jpeg');
    expect(StaffDocument.contentTypeForExtension('jpeg'), 'image/jpeg');
  });

  test(
    'metadata holds a storage path, never the file bytes or a download URL',
    () {
      final data = const StaffDocument(
        documentId: 'd1',
        schoolId: 'school-1',
        branchId: 'main',
        staffId: 'staff-1',
        type: StaffDocumentType.qualificationCertificate,
        title: 'B.Ed',
        fileName: 'bed.pdf',
        contentType: 'application/pdf',
        sizeBytes: 2048,
        storagePath:
            'schools/school-1/branches/main/staff/staff-1/documents/d1/bed.pdf',
      ).toFirestoreCreate(createdBy: 'admin-1');

      expect(data['type'], 'QUALIFICATION_CERTIFICATE');
      expect(data['status'], 'ACTIVE');
      expect(
        data['storagePath'],
        startsWith('schools/school-1/branches/main/staff/staff-1/documents/'),
      );
      expect(data.keys, isNot(contains('url')));
      expect(data.keys, isNot(contains('downloadUrl')));
      expect(data.keys, isNot(contains('bytes')));
      expect(data['createdAt'], isA<FieldValue>());
    },
  );

  test('a REMOVED document reads as removed; types round-trip', () {
    final read = StaffDocument.fromFirestore('s', 'b', 'staff-1', 'd1', {
      'type': 'ID_PROOF',
      'title': 'Passport',
      'fileName': 'p.pdf',
      'contentType': 'application/pdf',
      'sizeBytes': 10,
      'storagePath': 'x',
      'status': 'REMOVED',
    });
    expect(read.isRemoved, isTrue);
    for (final type in StaffDocumentType.values) {
      expect(StaffDocumentType.fromWireValue(type.wireValue), type);
    }
  });
}
