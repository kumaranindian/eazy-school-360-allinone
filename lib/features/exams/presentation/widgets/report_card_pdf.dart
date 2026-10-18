import '../../../../core/regional/school_time.dart';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/result_calculator.dart';
import '../../domain/result_summary.dart';

/// Everything a report card prints (ASCII only: the built-in PDF fonts have
/// no glyphs beyond Latin-1, the same constraint as the fee receipts), taken from the **stored, finalised**
/// result — names, marks, grades, remarks, the attendance snapshot and the
/// scheme it was calculated under — never recomputed from live data, so a
/// published report card is historically consistent.
class ReportCardData {
  final String schoolName;
  final String branchName;
  final String academicYearName;
  final String className;
  final String sectionName;
  final ResultSummary summary;
  final DateTime? publishedAt;
  final bool provisional;

  const ReportCardData({
    required this.schoolName,
    required this.branchName,
    required this.academicYearName,
    required this.className,
    required this.sectionName,
    required this.summary,
    this.publishedAt,
    this.provisional = false,
  });
}

abstract final class ReportCardPdf {
  static String _num(double? v, {int decimals = 2}) {
    if (v == null) return '-';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(decimals).replaceFirst(RegExp(r'0+$'), '');
  }

  static String outcomeLabel(SubjectOutcome o) => switch (o) {
    SubjectOutcome.passed => 'Pass',
    SubjectOutcome.failed => 'Fail',
    SubjectOutcome.absent => 'Absent',
    SubjectOutcome.exempted => 'Exempted',
    SubjectOutcome.pending => 'Pending',
  };

  static Future<Uint8List> build(ReportCardData d) async {
    final r = d.summary.result;
    final doc = pw.Document(title: 'Report card - ${r.studentName}');
    final published = d.publishedAt == null
        ? '-'
        : SchoolTime.formatInstant(d.publishedAt!);

    pw.Widget kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              k,
              style: const pw.TextStyle(color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(child: pw.Text(v)),
        ],
      ),
    );

    pw.Widget cell(String t, {bool bold = false, pw.Alignment? align}) =>
        pw.Container(
          alignment: align ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            t,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    final lines = r.lines;
    final hasComponents = lines.any((l) => l.theory != null);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  d.schoolName,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (d.branchName.isNotEmpty) pw.Text(d.branchName),
                pw.SizedBox(height: 6),
                pw.Text(
                  'REPORT CARD - ${d.summary.examName}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (d.provisional)
                  pw.Text(
                    'PROVISIONAL - not a published result',
                    style: pw.TextStyle(
                      color: PdfColors.red,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          pw.Divider(),
          kv('Student', r.studentName),
          kv('Admission no.', r.admissionNumber ?? '-'),
          kv('Class / section', '${d.className} - ${d.sectionName}'),
          if (r.rollNumber != null) kv('Roll number', r.rollNumber!),
          kv('Academic year', d.academicYearName),
          kv('Published', published),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              if (hasComponents) 1: const pw.FlexColumnWidth(1.2),
              if (hasComponents) 2: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell('Subject', bold: true),
                  if (hasComponents) cell('Theory', bold: true),
                  if (hasComponents) cell('Practical', bold: true),
                  cell('Max', bold: true),
                  cell('Obtained', bold: true),
                  cell('%', bold: true),
                  cell('Grade', bold: true),
                  cell('Result', bold: true),
                ],
              ),
              for (final l in lines)
                pw.TableRow(
                  children: [
                    cell(l.subjectName),
                    if (hasComponents) cell(_num(l.theory)),
                    if (hasComponents) cell(_num(l.practical)),
                    cell(_num(l.maxMarks)),
                    cell(
                      l.outcome == SubjectOutcome.absent ||
                              l.outcome == SubjectOutcome.exempted
                          ? outcomeLabel(l.outcome)
                          : _num(l.obtained),
                    ),
                    cell(_num(l.percent)),
                    cell(l.grade ?? '-'),
                    cell(outcomeLabel(l.outcome)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 10),
          kv(
            'Total',
            r.totalMax == 0
                ? '-'
                : '${_num(r.totalObtained)} / ${_num(r.totalMax)}',
          ),
          kv(
            'Percentage',
            r.overallPercentage == null ? '-' : '${_num(r.overallPercentage)}%',
          ),
          kv('Overall grade', r.overallGrade ?? '-'),
          if (r.gpa != null) kv('GPA', _num(r.gpa)),
          kv('Result', r.result.displayName),
          if (r.rank != null) kv('Rank', '${r.rank} of ${r.classSize}'),
          if (d.summary.attendance != null)
            kv(
              'Attendance',
              d.summary.attendance!.percentage == null
                  ? 'No attendance recorded'
                  : '${_num(d.summary.attendance!.percentage, decimals: 1)}% '
                        '(${_num(d.summary.attendance!.attendedDays)} of '
                        '${d.summary.attendance!.markedDays} marked days)',
            ),
          pw.SizedBox(height: 10),
          if (d.summary.teacherRemark.isNotEmpty)
            kv('Class teacher', d.summary.teacherRemark),
          if (d.summary.principalRemark.isNotEmpty)
            kv('Principal', d.summary.principalRemark),
          pw.SizedBox(height: 36),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Container(width: 140, height: 0.5, color: PdfColors.black),
                  pw.Text(
                    'Class teacher',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 140, height: 0.5, color: PdfColors.black),
                  pw.Text('Principal', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 140, height: 0.5, color: PdfColors.black),
                  pw.Text(
                    'Parent / guardian',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Grades follow "${d.summary.schemeSnapshot['name'] ?? 'the school scheme'}" '
            '(version ${d.summary.version} of this result).',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
