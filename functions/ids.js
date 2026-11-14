'use strict';

// Identifiers that become Firestore document ids. Firestore itself refuses a slash, '.', '..' and anything
// shaped like `__x__`; checking here turns a would-be INTERNAL error (or a surprising path) into a clean
// INVALID_ARGUMENT, and keeps hostile values out of every query and path the callables build.
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const RESERVED = /^__.*__$/;

const validId = (v) => typeof v === 'string' && ID.test(v) && !RESERVED.test(v);

/** [v] trimmed and bounded when it is a valid id, else ''. */
const idOf = (v, max = 128) => {
  const s = typeof v === 'string' ? v.trim().slice(0, max + 1) : '';
  return s.length <= max && validId(s) ? s : '';
};

/** Own-property lookup: `map['constructor']` and `map['__proto__']` must never match. */
const own = (obj, key) => (typeof key === 'string' && Object.prototype.hasOwnProperty.call(obj, key) ? obj[key] : undefined);

module.exports = { ID, validId, idOf, own };
