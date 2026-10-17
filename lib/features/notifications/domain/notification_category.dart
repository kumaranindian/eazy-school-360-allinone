/// What a notification is about. Users may mute every category except
/// [administrative]: an administrative notice follows school policy and is
/// never silently suppressed.
enum NotificationCategory {
  announcement('ANNOUNCEMENT', 'Announcements', true),
  homework('HOMEWORK', 'Homework', true),
  results('RESULTS', 'Examination results', true),
  attendance('ATTENDANCE', 'Attendance', true),
  leave('LEAVE', 'Leave', true),
  fees('FEES', 'Fees', true),
  timetable('TIMETABLE', 'Timetable and substitutions', true),
  messages('MESSAGES', 'Messages', true),
  administrative('ADMINISTRATIVE', 'Administrative notices', false);

  final String wireValue;
  final String displayName;

  /// Whether the user may mute it.
  final bool mutable;

  const NotificationCategory(this.wireValue, this.displayName, this.mutable);

  static NotificationCategory fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v, orElse: () => administrative);

  /// The category of an event type written by the other modules. Unknown
  /// types are treated as administrative so they are never hidden.
  static NotificationCategory forType(String type) {
    if (type.startsWith('LEAVE_')) return leave;
    if (type == 'TIMETABLE_PUBLISHED' || type.startsWith('SUBSTITUTION_')) {
      return timetable;
    }
    if (type.startsWith('HOMEWORK_')) return homework;
    if (type.startsWith('ANNOUNCEMENT_') || type.startsWith('HOLIDAY_')) {
      return announcement;
    }
    if (type == 'RESULT_PUBLISHED') return results;
    if (type == 'MESSAGE_RECEIVED') return messages;
    if (type.startsWith('ATTENDANCE_')) return attendance;
    if (type.startsWith('FEE_') || type.startsWith('PAYMENT_')) return fees;
    return administrative;
  }
}
