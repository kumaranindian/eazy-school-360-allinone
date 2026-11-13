import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../fees/presentation/widgets/fee_pdf.dart';
import '../../domain/admission_report.dart';

/// A one-document printable summary of an [AdmissionReport]. Figures only:
/// no names, phone numbers or remarks are in the report to begin with.
abstract final class AdmissionReportPdf {
  static Future<Uint8List> build(
    AdmissionReport r, {
    required String schoolName,
    required String scopeLabel,
    required String periodLabel,
  }) async {
    String money(int v) => FeePdf.money(v, r.currency);
    pw.Widget section(
      String title,
      List<List<String>> rows, {
      List<String>? head,
    }) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 12),
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        if (rows.isEmpty)
          pw.Text('Nothing to show.')
        else
          pw.TableHelper.fromTextArray(
            headers: head,
            data: rows,
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
            cellAlignment: pw.Alignment.centerLeft,
          ),
      ],
    );
    List<List<String>> rowsOf(List<ReportRow> list) => [
      for (final x in list)
        [x.label, '${x.count}', '${x.confirmed}', '${x.ratePercent}%'],
    ];
    const head = ['', 'Enquiries', 'Admitted', 'Rate'];
    final doc = pw.Document()
      ..addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (_) => [
            pw.Text(
              '$schoolName: admission report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('$scopeLabel · $periodLabel'),
            if (r.truncated)
              pw.Text(
                'Only the most recent enquiries were counted; narrow the dates for exact figures.',
              ),
            section('Summary', [
              ['Enquiries', '${r.total}'],
              ['Admissions confirmed', '${r.confirmed}'],
              ['Conversion rate', '${r.conversionPercent}%'],
              ['Follow-ups completed', '${r.followUpCompletionPercent}%'],
              ['Fees asked', money(r.feeAmountMinor)],
              ['Fees collected (net of refunds)', money(r.feeNetPaidMinor)],
              ['Fees balance due', money(r.feeBalanceMinor)],
            ]),
            section(
              'By source',
              rowsOf(r.bySource),
              head: ['Source', ...head.skip(1)],
            ),
            section(
              'By class',
              rowsOf(r.byClass),
              head: ['Class', ...head.skip(1)],
            ),
            section(
              'By assigned staff',
              rowsOf(r.byAssignee),
              head: ['Staff', ...head.skip(1)],
            ),
            if (r.schoolWide)
              section(
                'By branch',
                rowsOf(r.byBranch),
                head: ['Branch', ...head.skip(1)],
              ),
            section('Lost enquiries', [
              ['Not interested', '${r.lostByStatus['NOT_INTERESTED'] ?? 0}'],
              ['Rejected', '${r.lostByStatus['REJECTED'] ?? 0}'],
              ['Withdrawn', '${r.lostByStatus['WITHDRAWN'] ?? 0}'],
              for (final x in r.lostReasons)
                ['Reason: ${x.reason}', '${x.count}'],
            ]),
            section(
              'Fees by category',
              [
                for (final c in r.feeCategories)
                  [
                    c.category,
                    money(c.amountMinor),
                    money(c.netPaidMinor),
                    money(c.balanceMinor),
                  ],
              ],
              head: ['Category', 'Asked', 'Collected', 'Balance'],
            ),
          ],
        ),
      );
    return doc.save();
  }
}
