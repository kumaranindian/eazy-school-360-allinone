import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../fees/presentation/widgets/fee_print.dart' show loadLetterhead;
import '../../domain/payslip_document.dart';
import 'payslip_pdf.dart';

/// Print and download entry points for a payslip. The letterhead is the
/// school's current address and contacts when they can be read, otherwise the
/// names stored on the payslip (printing never fails because of it).
class PayslipPrint {
  PayslipPrint._();

  static Future<void> print(
    WidgetRef ref,
    PayslipDocument d, {
    required String schoolId,
    required String branchId,
  }) async {
    final bytes = await PayslipPdf.build(
      d,
      letterhead: await loadLetterhead(
        ref,
        schoolId: schoolId,
        branchId: branchId,
        schoolName: d.schoolName,
        branchName: d.branchName,
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: d.fileName,
      format: PayslipPdf.pageFormat,
      usePrinterSettings: false,
    );
  }

  static Future<void> download(
    WidgetRef ref,
    PayslipDocument d, {
    required String schoolId,
    required String branchId,
  }) async => Printing.sharePdf(
    bytes: await PayslipPdf.build(
      d,
      letterhead: await loadLetterhead(
        ref,
        schoolId: schoolId,
        branchId: branchId,
        schoolName: d.schoolName,
        branchName: d.branchName,
      ),
    ),
    filename: d.fileName,
  );
}
