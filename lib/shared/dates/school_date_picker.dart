import 'package:flutter/material.dart';

import '../../core/regional/school_time.dart';

/// The English locale whose short date reads in the same order as the
/// school's date format (Regional settings), so the date picker's typed
/// input expects, say, dd/MM/yyyy rather than the US MM/dd/yyyy
/// (SET-01-DEF-02). The rest of the app keeps its own locale.
Locale pickerLocaleFor(String dateFormat) {
  final f = dateFormat.toLowerCase();
  final d = f.indexOf('d');
  final m = f.indexOf('m');
  final y = f.indexOf('y');
  if (y >= 0 && y < d && y < m) return const Locale('en', 'CA'); // y-MM-dd
  if (m >= 0 && d >= 0 && m < d) return const Locale('en', 'US'); // MM/dd/y
  return const Locale('en', 'GB'); // dd/MM/y
}

/// [showDatePicker] in the school's date order. Use this everywhere instead
/// of calling [showDatePicker] directly.
Future<DateTime?> showSchoolDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
}) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: firstDate,
  lastDate: lastDate,
  helpText: helpText,
  initialEntryMode: initialEntryMode,
  locale: pickerLocaleFor(SchoolTime.dateFormat),
);
