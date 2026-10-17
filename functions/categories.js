'use strict';

// Mirrors lib/features/notifications/domain/notification_category.dart.
// Keep the two in step: the app decides what it shows with the Dart version,
// this decides what is pushed.
function categoryFor(type) {
  const t = type || '';
  if (t.startsWith('LEAVE_')) return 'LEAVE';
  if (t === 'TIMETABLE_PUBLISHED' || t.startsWith('SUBSTITUTION_')) return 'TIMETABLE';
  if (t.startsWith('HOMEWORK_')) return 'HOMEWORK';
  if (t.startsWith('ANNOUNCEMENT_') || t.startsWith('HOLIDAY_')) return 'ANNOUNCEMENT';
  if (t === 'RESULT_PUBLISHED') return 'RESULTS';
  if (t === 'MESSAGE_RECEIVED') return 'MESSAGES';
  if (t.startsWith('ATTENDANCE_')) return 'ATTENDANCE';
  if (t.startsWith('FEE_') || t.startsWith('PAYMENT_')) return 'FEES';
  return 'ADMINISTRATIVE';
}

// Whether a user's stored preferences allow pushing [category]. Push defaults
// to on; administrative notices can never be muted.
function allowsPush(prefs, category) {
  if (!prefs) return true;
  if (prefs.pushEnabled === false) return false;
  if (category === 'ADMINISTRATIVE') return true;
  const muted = Array.isArray(prefs.mutedCategories) ? prefs.mutedCategories : [];
  return !muted.includes(category);
}

module.exports = { categoryFor, allowsPush };
