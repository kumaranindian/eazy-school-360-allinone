import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../fees/domain/fee_letterhead.dart';
import '../../../fees/presentation/widgets/fee_pdf.dart';
import '../../domain/payroll_preview.dart';
import '../../domain/payslip_document.dart';

/// The printable payslip: one A4 portrait page on the school's letterhead.
///
/// The built-in PDF fonts have no rupee glyph, so amounts are written
/// "INR 21,000.00" (the same text as invoices and receipts, [FeePdf.money]).
/// Everything printed comes from the stored payslip; nothing is recomputed.
abstract final class PayslipPdf {
  static final PdfPageFormat pageFormat = PdfPageFormat.a4;

  static pw.Widget _headerLine(String text, double size, {bool bold = false}) =>
      pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );

  static pw.Widget _letterhead(FeeLetterhead l, PayslipDocument d) {
    final name = (l.schoolName.isEmpty ? d.schoolName : l.schoolName).trim();
    final branch = (l.branchName.isEmpty ? d.branchName : l.branchName).trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _headerLine(
          (name.isEmpty ? 'School' : name).toUpperCase(),
          16,
          bold: true,
        ),
        if (branch.isNotEmpty && branch != name)
          _headerLine(branch, 11, bold: true),
        for (final line in l.addressLines) _headerLine(line, 9),
        if (l.contactLine.isNotEmpty) _headerLine(l.contactLine, 9),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.7),
            color: PdfColors.grey200,
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'PAYSLIP',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                periodLabel(d.period),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _kv(
    String k,
    String v, {
    bool bold = false,
    double size = 10,
  }) {
    final style = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(k, style: style)),
          pw.SizedBox(width: 8),
          pw.Text(v, style: style, textAlign: pw.TextAlign.right),
        ],
      ),
    );
  }

  static pw.Widget _section(String title, List<pw.Widget> rows) => pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.Divider(thickness: 0.4),
        ...rows,
      ],
    ),
  );

  static List<pw.Widget> _rows(
    Iterable<PayslipDocLine> lines,
    String currency,
  ) {
    final out = <pw.Widget>[];
    for (final l in lines) {
      out.add(
        _kv(
          l.oneOff ? '${l.name} (one-off)' : l.name,
          FeePdf.money(l.amountMinor, currency),
        ),
      );
      if (l.reduced) {
        out.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
            child: pw.Text(
              'Structure amount ${FeePdf.money(l.plannedMinor, currency)}, '
              'reduced for days not paid',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ),
        );
      }
    }
    if (out.isEmpty) {
      out.add(pw.Text('None', style: const pw.TextStyle(fontSize: 10)));
    }
    return out;
  }

  static Future<Uint8List> build(
    PayslipDocument d, {
    FeeLetterhead letterhead = const FeeLetterhead(),
  }) {
    final c = d.currency;
    final doc = pw.Document(
      title: 'Payslip ${d.period} ${d.staffName}',
      author: d.schoolName,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          _letterhead(letterhead, d),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      d.staffName,
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (d.employeeCode.isNotEmpty)
                      pw.Text(
                        'Employee code ${d.employeeCode}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Paid ${daysText(d.paidDays)} of ${d.workingDays} school days',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  if (d.unpaidDays > 0)
                    pw.Text(
                      'Not paid: ${daysText(d.unpaidDays)} days',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _section('Earnings', _rows(d.earnings, c)),
          pw.SizedBox(height: 8),
          _section('Deductions', _rows(d.deductions, c)),
          pw.SizedBox(height: 8),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8),
              color: PdfColors.grey100,
            ),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              children: [
                _kv('Total earnings', FeePdf.money(d.grossMinor, c)),
                _kv('Total deductions', FeePdf.money(d.deductionsMinor, c)),
                pw.Divider(thickness: 0.5),
                _kv(
                  'NET PAY',
                  FeePdf.money(d.netMinor, c),
                  bold: true,
                  size: 12,
                ),
              ],
            ),
          ),
          if (d.unrecoveredDeductionMinor > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                '${FeePdf.money(d.unrecoveredDeductionMinor, c)} of deductions could not be taken from this month\'s pay.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          pw.SizedBox(height: 10),
          if (d.paidDate != null)
            pw.Text(
              'Paid on ${d.paidDate}${d.paymentModeLabel == null ? '' : ' by ${d.paymentModeLabel}'}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
          pw.SizedBox(height: 18),
          pw.Text(
            'This is a computer-generated payslip.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
