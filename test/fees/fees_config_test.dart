import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/fee_structure.dart';
import 'package:eazy_school_360/features/fees/domain/student_fee_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

FeeStructure _structure({
  String code = 'TUITION-5',
  int amount = 150000,
  FeeFrequency frequency = FeeFrequency.monthly,
  FeeCategory category = FeeCategory.tuition,
  String? classId,
  String? sectionId,
  String? from,
  String? to,
  int dueDays = 15,
  String? customCategory,
  ActivationStatus status = ActivationStatus.active,
}) {
  return FeeStructure(
    structureId: FeeStructure.idFor('y26', code),
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: 'y26',
    code: code,
    name: 'Tuition',
    category: category,
    customCategoryLabel: customCategory,
    frequency: frequency,
    amountMinor: amount,
    classId: classId,
    sectionId: sectionId,
    effectiveFromKey: from,
    effectiveToKey: to,
    dueOffsetDays: dueDays,
    status: status,
  );
}

void main() {
  group('FeeStructure configuration validation', () {
    test('a sensible structure has no problems', () {
      expect(_structure().validate(), isEmpty);
      expect(_structure(classId: 'c5', sectionId: 'a').validate(), isEmpty);
    });

    test('invalid amounts are rejected: zero, negative, absurdly large', () {
      expect(_structure(amount: 0).validate(), isNotEmpty);
      expect(_structure(amount: -100).validate(), isNotEmpty);
      expect(
        _structure(amount: FeeStructure.maxAmountMinor + 1).validate(),
        isNotEmpty,
      );
      expect(
        _structure(amount: FeeStructure.maxAmountMinor).validate(),
        isEmpty,
      );
    });

    test('invalid dates are rejected: effective-from after effective-to', () {
      expect(
        _structure(from: '2026-09-01', to: '2026-06-01').validate().join(),
        contains('after'),
      );
      expect(
        _structure(from: '2026-06-01', to: '2026-06-01').validate(),
        isEmpty,
      );
      expect(_structure(from: '2026-06-01').validate(), isEmpty);
    });

    test('codes must be safe document-id fragments', () {
      for (final bad in ['', 'a', 'has space', 'a/b', 'x' * 21, 'ünï']) {
        expect(_structure(code: bad).validate(), isNotEmpty, reason: bad);
      }
    });

    test(
      'a section needs a class; days-until-due is bounded; "Other" needs a name',
      () {
        expect(_structure(sectionId: 'a').validate().join(), contains('class'));
        expect(_structure(dueDays: -1).validate(), isNotEmpty);
        expect(_structure(dueDays: 366).validate(), isNotEmpty);
        expect(
          _structure(category: FeeCategory.other).validate().join(),
          contains('category'),
        );
        expect(
          _structure(
            category: FeeCategory.other,
            customCategory: 'Library',
          ).validate(),
          isEmpty,
        );
      },
    );
  });

  group('duplicate configurations are structurally impossible', () {
    test(
      'the id is year + lower-cased code, so a code exists once per academic year',
      () {
        expect(FeeStructure.idFor('y26', 'TUITION-5'), 'y26__tuition-5');
        expect(
          FeeStructure.idFor('y26', 'tuition-5'),
          FeeStructure.idFor('y26', ' Tuition-5 '),
        );
        expect(
          FeeStructure.idFor('y26', 'TUITION-5'),
          isNot(FeeStructure.idFor('y27', 'TUITION-5')),
        );
      },
    );
  });

  group('scope: class / section / effective dates', () {
    test('a structure for all classes applies everywhere', () {
      final s = _structure();
      expect(s.appliesTo(classId: 'c5', sectionId: 'a'), isTrue);
      expect(s.appliesTo(classId: 'c9', sectionId: null), isTrue);
    });

    test('a class-specific structure applies only to that class', () {
      final s = _structure(classId: 'c5');
      expect(s.appliesTo(classId: 'c5', sectionId: 'b'), isTrue);
      expect(s.appliesTo(classId: 'c6', sectionId: 'a'), isFalse);
    });

    test('a section-specific structure applies only to that section', () {
      final s = _structure(classId: 'c5', sectionId: 'a');
      expect(s.appliesTo(classId: 'c5', sectionId: 'a'), isTrue);
      expect(s.appliesTo(classId: 'c5', sectionId: 'b'), isFalse);
      expect(s.appliesTo(classId: 'c5', sectionId: null), isFalse);
    });

    test('effective window is inclusive and open-ended when unset', () {
      final s = _structure(from: '2026-06-01', to: '2026-08-31');
      expect(s.isEffectiveOn('2026-05-31'), isFalse);
      expect(s.isEffectiveOn('2026-06-01'), isTrue);
      expect(s.isEffectiveOn('2026-08-31'), isTrue);
      expect(s.isEffectiveOn('2026-09-01'), isFalse);
      expect(_structure().isEffectiveOn('1999-01-01'), isTrue);
    });
  });

  group('serialization matches the firestore.rules allow-lists', () {
    test(
      'create writes integer minor units and the wire values rules check',
      () {
        final data = _structure().toFirestoreCreate(createdBy: 'admin-1');
        expect(data['amountMinor'], 150000);
        expect(data['amountMinor'], isA<int>());
        expect(data['frequency'], 'MONTHLY');
        expect(data['category'], 'TUITION');
        expect(data['status'], 'ACTIVE');
        expect(data['code'], 'TUITION-5');
        expect(data['academicYearId'], 'y26');
        expect(data['createdBy'], 'admin-1');
        expect(data['createdAt'], isA<FieldValue>());
      },
    );

    test(
      'update never touches identity (year, code, tenant) or creation audit',
      () {
        const allowed = {
          'name',
          'category',
          'customCategoryLabel',
          'frequency',
          'amountMinor',
          'classId',
          'sectionId',
          'isOptional',
          'effectiveFromKey',
          'effectiveToKey',
          'dueOffsetDays',
          'description',
          'paymentInstructions',
          'status',
          'updatedAt',
          'updatedBy',
        };
        final keys = _structure()
            .toFirestoreUpdate(updatedBy: 'a')
            .keys
            .toSet();
        expect(
          allowed.containsAll(keys),
          isTrue,
          reason: '${keys.difference(allowed)}',
        );
        for (final protectedKey in [
          'code',
          'academicYearId',
          'schoolId',
          'branchId',
          'createdAt',
          'createdBy',
        ]) {
          expect(keys.contains(protectedKey), isFalse, reason: protectedKey);
        }
      },
    );

    test('fromFirestore round-trips', () {
      final written =
          _structure(
              classId: 'c5',
              from: '2026-06-01',
            ).toFirestoreCreate(createdBy: 'a')
            ..['createdAt'] = Timestamp.now()
            ..['updatedAt'] = Timestamp.now();
      final read = FeeStructure.fromFirestore(
        'school-1',
        'main',
        'y26__tuition-5',
        written,
      );
      expect(read.amountMinor, 150000);
      expect(read.classId, 'c5');
      expect(read.effectiveFromKey, '2026-06-01');
      expect(read.frequency, FeeFrequency.monthly);
      expect(read.isActive, isTrue);
    });
  });

  group('StudentFeeAssignment — concessions, scholarships and duplicates', () {
    StudentFeeAssignment assignment({
      ConcessionType type = ConcessionType.none,
      int value = 0,
    }) => StudentFeeAssignment(
      assignmentId: 'stu-1__s1',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      studentId: 'stu-1',
      structureId: 's1',
      structureName: 'Tuition',
      classId: 'c5',
      concessionType: type,
      concessionValue: value,
    );

    test(
      'the id is student + fee head: a student can hold a fee head only once',
      () {
        expect(StudentFeeAssignment.idFor('stu-1', 's1'), 'stu-1__s1');
        expect(
          StudentFeeAssignment.idFor('stu-1', 's1'),
          isNot(StudentFeeAssignment.idFor('stu-2', 's1')),
        );
      },
    );

    test('no concession leaves the amount alone', () {
      expect(assignment().concessionFor(150000), 0);
      expect(assignment().hasConcession, isFalse);
    });

    test('percentage concessions are in basis points and round half up', () {
      expect(
        assignment(
          type: ConcessionType.percent,
          value: 2500,
        ).concessionFor(150000),
        37500,
      ); // 25%
      expect(
        assignment(
          type: ConcessionType.percent,
          value: 3333,
        ).concessionFor(100000),
        33330,
      );
      expect(
        assignment(
          type: ConcessionType.percent,
          value: 1000,
        ).concessionFor(100005),
        10001,
      );
      expect(
        assignment(
          type: ConcessionType.percent,
          value: 10000,
        ).concessionFor(150000),
        150000,
      ); // scholarship: 100%
    });

    test(
      'a percentage above 100% is clamped on use (and rejected on entry)',
      () {
        expect(
          assignment(
            type: ConcessionType.percent,
            value: 99999,
          ).concessionFor(150000),
          150000,
        );
        expect(
          StudentFeeAssignment.validateConcession(
            ConcessionType.percent,
            10001,
            'reason',
          ),
          contains('100'),
        );
      },
    );

    test('a fixed concession never exceeds the line it applies to', () {
      expect(
        assignment(
          type: ConcessionType.fixed,
          value: 50000,
        ).concessionFor(150000),
        50000,
      );
      expect(
        assignment(
          type: ConcessionType.fixed,
          value: 900000,
        ).concessionFor(150000),
        150000,
      );
    });

    test('a concession needs a value and a reason; "none" needs neither', () {
      expect(
        StudentFeeAssignment.validateConcession(ConcessionType.none, 0, null),
        isNull,
      );
      expect(
        StudentFeeAssignment.validateConcession(
          ConcessionType.fixed,
          0,
          'reason',
        ),
        isNotNull,
      );
      expect(
        StudentFeeAssignment.validateConcession(
          ConcessionType.fixed,
          5000,
          null,
        ),
        contains('reason'),
      );
      expect(
        StudentFeeAssignment.validateConcession(
          ConcessionType.fixed,
          5000,
          '  ',
        ),
        contains('reason'),
      );
      expect(
        StudentFeeAssignment.validateConcession(
          ConcessionType.percent,
          2500,
          'Sibling discount',
        ),
        isNull,
      );
    });

    test('create records the approver only when there is a concession', () {
      final plain = assignment().toFirestoreCreate(createdBy: 'fin-1');
      expect(plain['concessionApprovedBy'], isNull);
      final conceded = assignment(
        type: ConcessionType.percent,
        value: 2500,
      ).toFirestoreCreate(createdBy: 'admin-1');
      expect(conceded['concessionApprovedBy'], 'admin-1');
      expect(conceded['concessionType'], 'PERCENT');
      expect(conceded['concessionValue'], 2500);
      expect(conceded['status'], 'ACTIVE');
    });
  });

  test('enum wire values are the ones firestore.rules lists', () {
    expect(FeeFrequency.values.map((e) => e.wireValue), [
      'ONE_TIME',
      'MONTHLY',
      'QUARTERLY',
      'HALF_YEARLY',
      'ANNUAL',
      'CUSTOM',
    ]);
    expect(FeeCategory.values.map((e) => e.wireValue), [
      'TUITION',
      'ADMISSION',
      'EXAMINATION',
      'TRANSPORT',
      'BOOKS',
      'UNIFORM',
      'ACTIVITY',
      'OTHER',
    ]);
    expect(PaymentMethod.values.map((e) => e.wireValue), [
      'CASH',
      'UPI',
      'BANK_TRANSFER',
      'CHEQUE',
      'OTHER',
    ]);
    expect(InvoiceStatus.values.map((e) => e.wireValue), [
      'ISSUED',
      'PARTIALLY_PAID',
      'PAID',
      'VOID',
    ]);
    expect(ReversalKind.values.map((e) => e.wireValue), ['REVERSAL', 'REFUND']);
    for (final e in [...FeeFrequency.values]) {
      expect(FeeFrequency.fromWireValue(e.wireValue), e);
    }
  });

  test('which payment methods demand a reference', () {
    expect(PaymentMethod.cash.needsReference, isFalse);
    expect(PaymentMethod.other.needsReference, isFalse);
    for (final m in [
      PaymentMethod.upi,
      PaymentMethod.bankTransfer,
      PaymentMethod.cheque,
    ]) {
      expect(m.needsReference, isTrue, reason: m.name);
    }
  });
}
