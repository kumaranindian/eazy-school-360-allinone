'use strict';

// Locks a school's currency once money exists (multi-country setup).
//
// The currency is chosen by the school admin in Regional settings. After the
// first fee structure, invoice or payment is created, changing it would leave
// the school with amounts in two currencies, so the server sets
// `currencyLocked: true` on the school document and firestore.rules refuse a
// currency change from then on. Clients cannot write that flag.
//
// Idempotent and safe to run for every created document.

const SCHOOL_PATH = /^schools\/([^/]+)\//;

/** The school id a document path belongs to, or null. */
function schoolOf(path) {
  const m = SCHOOL_PATH.exec(String(path || ''));
  return m ? m[1] : null;
}

/**
 * Sets the lock if it is not set yet. A transaction, so two first documents
 * created at once write it once and a missing school is ignored.
 * Returns true when this call set it.
 */
async function lockCurrency(db, schoolId, now = () => new Date()) {
  if (!schoolId) return false;
  const ref = db.collection('schools').doc(schoolId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().currencyLocked === true) return false;
    tx.update(ref, { currencyLocked: true, currencyLockedAt: now() });
    return true;
  });
}

module.exports = { schoolOf, lockCurrency };
