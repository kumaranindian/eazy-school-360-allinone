import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/presentation/providers/fee_providers.dart';
import 'package:eazy_school_360/features/fees/presentation/widgets/student_fees_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fee_fakes.dart';

const _key = (schoolId: 'school-1', branchId: 'main', studentId: 'stu-1');

Future<void> _pump(
  WidgetTester tester, {
  required FakeInvoiceRepository invoices,
  required FakePaymentRepository payments,
  Size size = const Size(1000, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        invoiceRepositoryProvider.overrideWithValue(invoices),
        paymentRepositoryProvider.overrideWithValue(payments),
      ],
      child: const MaterialApp(
        home: Scaffold(body: StudentFeesTab(studentKey: _key)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows totals, every invoice and the payments', (tester) async {
    await _pump(
      tester,
      invoices: FakeInvoiceRepository(
        invoices: [
          fakeInvoice(number: 'INV-2026-000001', payable: 100000, paid: 30000),
          fakeInvoice(
            id: 'stu-1__y1__M-2026-07',
            number: 'INV-2026-000002',
            payable: 50000,
            paid: 50000,
          ),
        ],
      ),
      payments: FakePaymentRepository(payments: [fakePayment()]),
    );
    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('INV-2026-000001'), findsOneWidget);
    expect(find.text('INV-2026-000002'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('No payments recorded yet.'), findsNothing);
  });

  testWidgets('a student with nothing billed gets a clear empty state', (
    tester,
  ) async {
    await _pump(
      tester,
      invoices: FakeInvoiceRepository(),
      payments: FakePaymentRepository(),
    );
    expect(
      find.textContaining('No invoices have been generated'),
      findsOneWidget,
    );
  });

  testWidgets('reversed payments are marked and void invoices still listed', (
    tester,
  ) async {
    await _pump(
      tester,
      invoices: FakeInvoiceRepository(
        invoices: [fakeInvoice(status: InvoiceStatus.voided)],
      ),
      payments: FakePaymentRepository(
        payments: [fakePayment(status: PaymentStatus.reversed)],
      ),
    );
    expect(find.text('Reversed'), findsWidgets);
  });

  for (final size in const [Size(360, 640), Size(768, 1024), Size(1400, 900)]) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets('lays out without overflow at $size, text x$scale', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          size: size,
          invoices: FakeInvoiceRepository(
            invoices: [
              fakeInvoice(payable: 123456789, paid: 3000),
              fakeInvoice(id: 'stu-1__y1__M-2026-07', number: 'INV-2'),
            ],
          ),
          payments: FakePaymentRepository(payments: [fakePayment()]),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
