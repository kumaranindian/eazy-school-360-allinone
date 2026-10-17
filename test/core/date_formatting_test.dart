import 'package:eazy_school_360/core/utils/date_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatInstant keeps the time of day', () {
    expect(formatInstant(DateTime(2026, 8, 3, 16, 5)), '3 Aug 2026, 4:05 PM');
    expect(formatInstant(DateTime(2026, 8, 3, 0, 9)), '3 Aug 2026, 12:09 AM');
  });

  test('formatInstant shows a placeholder before the server stamps it', () {
    expect(formatInstant(null), '—');
  });

  test('formatInstant converts UTC to local time', () {
    final utc = DateTime.utc(2026, 8, 3, 10, 30);
    expect(formatInstant(utc), formatInstant(utc.toLocal()));
  });
}
