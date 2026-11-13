import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/regional/currency.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_letterhead.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';

/// Printable invoice and receipt documents.
///
/// Every document is ONE landscape A5 sheet holding two identical copies side
/// by side, divided by a cut line: the left half is the school's office copy,
/// the right half the parent's copy. An invoice with more fee lines than fit a
/// half continues on further sheets (both halves repeat the same lines, each
/// marked "Page n of m", totals on the last).
///
/// The built-in PDF fonts have no rupee glyph, so amounts are written
/// "INR 1,500.00" (the currency code). Everything printed is read from the
/// stored snapshot (names, lines, amounts), never recomputed from live fee
/// structures; only the letterhead (address/contacts) is the school's current
/// details.
abstract final class FeePdf {
  /// A5 landscape: 210 x 148 mm.
  static final PdfPageFormat pageFormat = PdfPageFormat.a5.landscape;

  static const double _margin = 16;
  static const double _gutter = 14;
  static const int _linesPerSheet = 7;
  static const String officeCopy = 'OFFICE COPY';
  static const String parentCopy = 'PARENT COPY';

  /// The same text, for other printable documents (admission reports).
  static String money(int minor, String currency) => _money(minor, currency);

  /// "INR 1,500.00", "JPY 1,500", "KWD 1,500.250".
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

  static const double _body = 8;

  static pw.Widget _kv(String k, String v, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: _body,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: style),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(v, style: style, textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  static pw.Widget _letterhead(
    FeeLetterhead l,
    String title,
    String number,
    String copy,
  ) {
    final name = l.schoolName.isEmpty ? 'School' : l.schoolName;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          name.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        if (l.branchName.isNotEmpty && l.branchName != l.schoolName)
          pw.Text(
            l.branchName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        for (final line in l.addressLines)
          pw.Text(
            line,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7.5),
          ),
        if (l.contactLine.isNotEmpty)
          pw.Text(
            l.contactLine,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7.5),
          ),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.6),
            color: PdfColors.grey200,
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                number,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              copy,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 2),
      ],
    );
  }

  static pw.Widget _signatures(String left, String right) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        children: [
          pw.Container(width: 80, height: 0.5, color: PdfColors.black),
          pw.SizedBox(height: 2),
          pw.Text(left, style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
      pw.Column(
        children: [
          pw.Container(width: 80, height: 0.5, color: PdfColors.black),
          pw.SizedBox(height: 2),
          pw.Text(right, style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    ],
  );

  /// One sheet: [copy] builds a half for the given label; the halves are
  /// separated by a dashed cut line.
  static pw.Page _sheet(pw.Widget Function(String label) copy) => pw.Page(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.all(_margin),
    build: (context) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(child: copy(officeCopy)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: _gutter / 2),
          child: pw.LayoutBuilder(
            builder: (context, constraints) => pw.CustomPaint(
              size: PdfPoint(0.5, constraints?.maxHeight ?? 0),
              painter: (canvas, size) {
                canvas
                  ..setLineDashPattern([4, 3])
                  ..setLineWidth(0.5)
                  ..setStrokeColor(PdfColors.grey700)
                  ..moveTo(0, 0)
                  ..lineTo(0, size.y)
                  ..strokePath();
              },
            ),
          ),
        ),
        pw.Expanded(child: copy(parentCopy)),
      ],
    ),
  );

  static pw.Widget _lineTable(List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: ['Fee', 'Amount', 'Concession', 'Net'],
        data: rows,
        headerStyle: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
        border: pw.TableBorder.all(width: 0.4),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.4),
          1: const pw.FlexColumnWidth(1.6),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.6),
        },
        cellAlignments: {
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
        },
      );

  static Future<Uint8List> invoice(
    Invoice i, {
    FeeLetterhead? letterhead,
  }) async {
    final head = letterhead ?? FeeLetterhead.named(i.schoolName, i.branchName);
    final doc = pw.Document(title: i.invoiceNumber, author: head.schoolName);

    final rows = [
      for (final l in i.lines)
        [
          l.name,
          _money(l.amountMinor, i.currency),
          l.discountMinor > 0 ? '-${_money(l.discountMinor, i.currency)}' : '',
          _money(l.netMinor, i.currency),
        ],
    ];
    final chunks = <List<List<String>>>[];
    for (var n = 0; n < rows.length; n += _linesPerSheet) {
      chunks.add(
        rows.sublist(
          n,
          n + _linesPerSheet > rows.length ? rows.length : n + _linesPerSheet,
        ),
      );
    }
    if (chunks.isEmpty) chunks.add(const []);

    for (var c = 0; c < chunks.length; c++) {
      final last = c == chunks.length - 1;
      final pageNote = chunks.length > 1
          ? 'Page ${c + 1} of ${chunks.length}'
          : null;
      doc.addPage(
        _sheet(
          (label) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _letterhead(
                head,
                i.isVoid ? 'INVOICE (VOID)' : 'INVOICE',
                i.invoiceNumber,
                pageNote == null ? label : '$label  -  $pageNote',
              ),
              _kv('Student', i.studentName),
              _kv('Admission no.', i.admissionNumber),
              _kv('Class', '${i.className} ${i.sectionName}'.trim()),
              _kv('Academic year', i.academicYearName),
              _kv('Billing period', i.periodLabel),
              _kv(
                'Issued / Due',
                '${FeeDates.display(i.issueDateKey)} / ${FeeDates.display(i.dueDateKey)}',
              ),
              pw.SizedBox(height: 4),
              _lineTable(chunks[c]),
              pw.SizedBox(height: 4),
              if (last) ...[
                _kv('Subtotal', _money(i.subtotalMinor, i.currency)),
                if (i.discountMinor > 0)
                  _kv('Concessions', '-${_money(i.discountMinor, i.currency)}'),
                _kv('Payable', _money(i.payableMinor, i.currency), bold: true),
                if (i.waivedMinor > 0)
                  _kv('Waived', '-${_money(i.waivedMinor, i.currency)}'),
                _kv('Paid', _money(i.paidMinor, i.currency)),
                _kv(
                  'Balance due',
                  _money(i.balanceMinor, i.currency),
                  bold: true,
                ),
                if (i.isVoid)
                  pw.Text(
                    'This invoice has been voided${i.voidReason == null ? '' : ': ${i.voidReason}'}.',
                    style: const pw.TextStyle(fontSize: 7.5),
                  ),
                pw.Spacer(),
                _signatures(
                  label == officeCopy ? 'Prepared by' : 'Parent signature',
                  'Authorised signatory',
                ),
              ] else
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Continued on next page',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  static Future<Uint8List> receipt(
    Receipt r, {
    FeeLetterhead? letterhead,
  }) async {
    final head = letterhead ?? FeeLetterhead.named(r.schoolName, r.branchName);
    final doc = pw.Document(title: r.receiptNumber, author: head.schoolName);
    doc.addPage(
      _sheet(
        (label) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _letterhead(
              head,
              r.isReversed ? 'RECEIPT (REVERSED)' : 'PAYMENT RECEIPT',
              r.receiptNumber,
              label,
            ),
            _kv('Received from', r.studentName),
            _kv('Admission no.', r.admissionNumber),
            _kv('Class', '${r.className} ${r.sectionName}'.trim()),
            _kv('Academic year', r.academicYearName),
            _kv('Invoice', '${r.invoiceNumber} - ${r.periodLabel}'),
            _kv('Payment date', FeeDates.display(r.paymentDateKey)),
            _kv('Method', r.methodDisplay),
            if ((r.referenceNo ?? '').isNotEmpty)
              _kv('Reference', r.referenceNo!),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 3,
                horizontal: 4,
              ),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
              child: _kv(
                'Amount received',
                _money(r.amountMinor, r.currency),
                bold: true,
              ),
            ),
            _kv(
              'Balance after payment',
              _money(r.balanceAfterMinor, r.currency),
            ),
            _kv('Collected by', r.collectorName),
            if (r.isReversed)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  'This payment has since been reversed. The receipt is retained for the record.',
                  style: const pw.TextStyle(fontSize: 7.5),
                ),
              ),
            pw.Spacer(),
            _signatures(
              label == officeCopy ? 'Collected by' : 'Parent signature',
              'Authorised signatory',
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
