'use strict';

// HW-01-OBS-01: a server-side content check of homework and announcement
// attachments. The app already refuses a file whose first bytes do not match
// its extension, but a modified client could skip that. Every upload lands
// marked contentCheck=PENDING (required by storage.rules, which keep it from
// parents and teachers); this check reads the first bytes and either marks
// the file PASSED or deletes it. It is a type check, not a virus scan.
// Mirrors lib/core/files/file_signatures.dart.

const PATHS = [
  { kind: 'HOMEWORK_FILE', re: /^schools\/[^/]+\/branches\/[^/]+\/homework\/[^/]+\/files\/[^/]+$/ },
  { kind: 'HOMEWORK_SUBMISSION', re: /^schools\/[^/]+\/branches\/[^/]+\/homework\/[^/]+\/submissions\/[^/]+\/[^/]+$/ },
  { kind: 'ANNOUNCEMENT_FILE', re: /^schools\/[^/]+\/branches\/[^/]+\/announcements\/[^/]+\/files\/[^/]+$/ },
];

const HEAD_BYTES = 4096;

/** Which checked upload [name] is, or null for any other object. */
function kindOf(name) {
  const hit = PATHS.find((p) => p.re.test(String(name || '')));
  return hit ? hit.kind : null;
}

function extOf(name) {
  const base = String(name).split('/').pop();
  const dot = base.lastIndexOf('.');
  return dot < 0 ? '' : base.slice(dot + 1).toLowerCase();
}

const starts = (b, sig) => b.length >= sig.length && sig.every((x, i) => b[i] === x);

/** Whether the leading bytes [b] (a Buffer) look like a file of type [ext]. */
function signatureMatches(ext, b) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return starts(b, [0xff, 0xd8, 0xff]);
    case 'png':
      return starts(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case 'webp':
      return b.length >= 12 && starts(b, [0x52, 0x49, 0x46, 0x46]) && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50;
    case 'pdf':
      return b.subarray(0, 1024).indexOf('%PDF') >= 0;
    case 'docx':
    case 'xlsx':
      return starts(b, [0x50, 0x4b, 0x03, 0x04]);
    case 'doc':
    case 'xls':
      return starts(b, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
    case 'txt':
      return b.length > 0 && b.subarray(0, HEAD_BYTES).indexOf(0) < 0;
    default:
      return false;
  }
}

/**
 * Checks one finalized object. [bucket] is a @google-cloud/storage Bucket (or
 * a fake with file(name).download/delete/setMetadata). Returns
 * { skipped } | { passed } | { removed, reason }.
 */
async function checkUploadedObject({ bucket, name, log = () => {} }) {
  const kind = kindOf(name);
  if (!kind) return { skipped: true };
  const file = bucket.file(name);
  const [head] = await file.download({ start: 0, end: HEAD_BYTES - 1 });
  const ext = extOf(name);
  if (!signatureMatches(ext, head)) {
    await file.delete({ ignoreNotFound: true });
    log('upload removed: contents do not match the type', { kind, ext });
    return { removed: true, reason: 'SIGNATURE_MISMATCH' };
  }
  await file.setMetadata({ metadata: { contentCheck: 'PASSED' } });
  return { passed: true };
}

module.exports = { kindOf, extOf, signatureMatches, checkUploadedObject, HEAD_BYTES };
