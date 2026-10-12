/// CSV encoding for attendance reports, with the two things that go wrong
/// in practice handled: RFC 4180 quoting, and **spreadsheet formula
/// injection** — a name or remark such as `=HYPERLINK(...)` would run as a
/// formula when the file is opened in Excel/Sheets, so any text cell that
/// starts with `= + - @` (or a tab / carriage return) is prefixed with a
/// single quote. Numbers are written as numbers and never altered.
abstract final class AttendanceCsv {
  static const _formulaStarters = {'=', '+', '-', '@', '\t', '\r'};

  static String sanitizeText(String value) {
    if (value.isNotEmpty && _formulaStarters.contains(value[0])) {
      return "'$value";
    }
    return value;
  }

  static String cell(Object? value) {
    if (value == null) return '';
    if (value is num) return value is int ? '$value' : value.toStringAsFixed(2);
    final text = sanitizeText(value.toString());
    final needsQuotes =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    return needsQuotes ? '"${text.replaceAll('"', '""')}"' : text;
  }

  /// [header] then [rows]; `\r\n` line endings (the CSV standard).
  static String encode(List<String> header, Iterable<List<Object?>> rows) {
    final buffer = StringBuffer()
      ..write(header.map(cell).join(','))
      ..write('\r\n');
    for (final row in rows) {
      buffer
        ..write(row.map(cell).join(','))
        ..write('\r\n');
    }
    return buffer.toString();
  }
}
