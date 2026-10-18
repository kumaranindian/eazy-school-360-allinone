import '../../../../core/regional/currency.dart';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/fee_dates.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';

/// Printable invoice and receipt documents.
///
/// The built-in PDF fonts have no rupee glyph, so amounts here are written
/// "INR 1,500.00" (the currency code) instead of "₹1,500.00" — a deliberate
/// choice that avoids bundling or downloading a font. Everything printed is
/// read from the stored snapshot (names, lines, amounts), never recomputed
/// from live fee structures.
abstract final class FeePdf {
  /// "INR 1,500.00", "JPY 1,500", "KWD 1,500.250": the currency's own number
  /// of decimals, thousands grouping (the built-in PDF fonts have no
  /// currency symbols, so the code is printed instead).
  static String _money(int minor, String currency) {
    final decimals = Currencies.of(currency).decimals;
    final negative = minor < 0;
    final abs = minor.abs();
    var unit = 1;
    for (var i = 0; i < decimals; i++) {
      unit *= 10;
    }
    final grouped = (abs ~/ unit).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    final fraction = decimals == 0
        ? ''
        : '.${(abs % unit).toString().padLeft(decimals, '0')}';
    return '${negative ? '-' : ''}$currency $grouped$fraction';
  }

  static pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          k,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          v,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  static pw.Widget _header(
    String school,
    String branch,
    String title,
    String number,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        school,
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      if (branch.isNotEmpty) pw.Text(branch),
      pw.SizedBox(height: 12),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            number,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
      pw.Divider(),
    ],
  );

  static Future<Uint8List> invoice(Invoice i) async {
    final doc = pw.Document(title: i.invoiceNumber);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _header(
            i.schoolName,
            i.branchName,
            i.isVoid ? 'INVOICE (VOID)' : 'INVOICE',
            i.invoiceNumber,
          ),
          _kv('Student', i.studentName),
          _kv('Admission no.', i.admissionNumber),
          _kv('Class', '${i.className} ${i.sectionName}'.trim()),
          _kv('Academic year', i.academicYearName),
          _kv('Billing period', i.periodLabel),
          _kv('Issue date', FeeDates.display(i.issueDateKey)),
          _kv('Due date', FeeDates.display(i.dueDateKey)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Fee', 'Amount', 'Concession', 'Net'],
            data: [
              for (final l in i.lines)
                [
                  l.name,
                  _money(l.amountMinor, i.currency),
                  l.discountMinor > 0
                      ? '-${_money(l.discountMinor, i.currency)}'
                      : '',
                  _money(l.netMinor, i.currency),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 12),
          _kv('Subtotal', _money(i.subtotalMinor, i.currency)),
          _kv('Concessions', '-${_money(i.discountMinor, i.currency)}'),
          _kv('Payable', _money(i.payableMinor, i.currency), bold: true),
          if (i.waivedMinor > 0)
            _kv('Waived', '-${_money(i.waivedMinor, i.currency)}'),
          _kv('Paid', _money(i.paidMinor, i.currency)),
          _kv('Balance due', _money(i.balanceMinor, i.currency), bold: true),
          if (i.isVoid)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'This invoice has been voided${i.voidReason == null ? '' : ': ${i.voidReason}'}.',
              ),
            ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Amounts shown are as billed on the issue date.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> receipt(Receipt r) async {
    final doc = pw.Document(title: r.receiptNumber);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              r.schoolName,
              r.branchName,
              r.isReversed ? 'PAYMENT RECEIPT (REVERSED)' : 'PAYMENT RECEIPT',
              r.receiptNumber,
            ),
            _kv('Received from', r.studentName),
            _kv('Admission no.', r.admissionNumber),
            _kv('Class', '${r.className} ${r.sectionName}'.trim()),
            _kv('Academic year', r.academicYearName),
            _kv('Invoice', '${r.invoiceNumber} · ${r.periodLabel}'),
            _kv('Payment date', FeeDates.display(r.paymentDateKey)),
            _kv('Method', r.methodDisplay),
            if ((r.referenceNo ?? '').isNotEmpty)
              _kv('Reference', r.referenceNo!),
            pw.SizedBox(height: 8),
            _kv(
              'Amount received',
              _money(r.amountMinor, r.currency),
              bold: true,
            ),
            _kv(
              'Balance after payment',
              _money(r.balanceAfterMinor, r.currency),
            ),
            pw.SizedBox(height: 8),
            _kv('Collected by', r.collectorName),
            if (r.isReversed)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text(
                  'This payment has since been reversed. The receipt is retained for the record.',
                ),
              ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

// Re-exported so callers need a single import for money text in the UI layer.
String formatMoney(int minor, String currency) =>
    Money.format(minor, currency: currency);
