'use strict';

// Email and phone checks shared by the platform callables. They mirror the
// app's `Validators.email` / `Validators.phone` (lib/core/validators) so the
// server refuses what the dialogs refuse, even from a modified client.

// Local part: RFC 5322 "atext" and single dots; domain: dot-separated labels
// of letters, digits and inner hyphens, ending in a 2+ letter TLD.
const EMAIL = /^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$/;

/** True for an address the app also accepts (RFC 5321: local part <= 64, whole <= 254). */
function isEmail(value) {
  if (typeof value !== 'string') return false;
  const e = value.trim();
  if (e.length > 254) return false;
  const at = e.lastIndexOf('@');
  if (at < 1 || at > 64) return false;
  return EMAIL.test(e);
}

const PHONE = /^\+?[0-9\-\s()]{7,20}$/;

/** True for a plausible phone number: digits, spaces, hyphens, brackets, one leading +, 7-15 digits. */
function isPhone(value) {
  if (typeof value !== 'string') return false;
  const p = value.trim();
  const digits = p.replace(/\D/g, '').length;
  return PHONE.test(p) && digits >= 7 && digits <= 15;
}

module.exports = { isEmail, isPhone };
