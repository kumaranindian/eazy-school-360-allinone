import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../school_setup/presentation/providers/school_providers.dart';
import '../../domain/fee_letterhead.dart';
import '../../domain/invoice.dart';
import '../../domain/payment.dart';
import 'fee_pdf.dart';

/// Loads the school's current address and contacts for the printed header.
/// Never throws: when the school or branch record cannot be read (a parent's
/// access, offline) the document falls back to the names stored on it.
Future<FeeLetterhead> loadLetterhead(
  WidgetRef ref, {
  required String schoolId,
  required String branchId,
  required String schoolName,
  required String branchName,
}) async {
  final repo = ref.read(schoolRepositoryProvider);
  final school = await repo.getSchool(schoolId).catchError((_) => null);
  final branch = await repo
      .getBranch(schoolId, branchId)
      .catchError((_) => null);
  return FeeLetterhead.from(
    school: school,
    branch: branch,
    fallbackSchoolName: schoolName,
    fallbackBranchName: branchName,
  );
}

/// Print / download entry points for invoices and receipts. Both always use
/// the A5 landscape sheet (office copy left, parent copy right), so the print
/// dialog is told the same format and the PDF is never rescaled.
class FeePrint {
  FeePrint._();

  static Future<Uint8List> _invoiceBytes(WidgetRef ref, Invoice i) async =>
      FeePdf.invoice(
        i,
        letterhead: await loadLetterhead(
          ref,
          schoolId: i.schoolId,
          branchId: i.branchId,
          schoolName: i.schoolName,
          branchName: i.branchName,
        ),
      );

  static Future<Uint8List> _receiptBytes(WidgetRef ref, Receipt r) async =>
      FeePdf.receipt(
        r,
        letterhead: await loadLetterhead(
          ref,
          schoolId: r.schoolId,
          branchId: r.branchId,
          schoolName: r.schoolName,
          branchName: r.branchName,
        ),
      );

  static Future<void> printInvoice(WidgetRef ref, Invoice i) async {
    final bytes = await _invoiceBytes(ref, i);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: i.invoiceNumber,
      format: FeePdf.pageFormat,
      usePrinterSettings: false,
    );
  }

  static Future<void> downloadInvoice(WidgetRef ref, Invoice i) async =>
      Printing.sharePdf(
        bytes: await _invoiceBytes(ref, i),
        filename: '${i.invoiceNumber}.pdf',
      );

  static Future<void> printReceipt(WidgetRef ref, Receipt r) async {
    final bytes = await _receiptBytes(ref, r);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: r.receiptNumber,
      format: FeePdf.pageFormat,
      usePrinterSettings: false,
    );
  }

  static Future<void> downloadReceipt(WidgetRef ref, Receipt r) async =>
      Printing.sharePdf(
        bytes: await _receiptBytes(ref, r),
        filename: '${r.receiptNumber}.pdf',
      );
}
