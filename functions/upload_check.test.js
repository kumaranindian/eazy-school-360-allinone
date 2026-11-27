'use strict';
const test = require('node:test');
const assert = require('node:assert');
const u = require('./upload_check');

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);
const EXE = Buffer.from('MZ\x90\x00\x03\x00', 'latin1');

function fakeBucket(bytes) {
  const calls = { deleted: [], metadata: [] };
  return {
    calls,
    file: (name) => ({
      download: async ({ start, end }) => [bytes.subarray(start, end + 1)],
      delete: async () => calls.deleted.push(name),
      setMetadata: async (m) => calls.metadata.push([name, m]),
    }),
  };
}

const HW = 'schools/s1/branches/b1/homework/h1/files/k1_worksheet.png';

test('only homework and announcement uploads are checked', () => {
  assert.equal(u.kindOf(HW), 'HOMEWORK_FILE');
  assert.equal(u.kindOf('schools/s1/branches/b1/homework/h1/submissions/st1/a.pdf'), 'HOMEWORK_SUBMISSION');
  assert.equal(u.kindOf('schools/s1/branches/b1/announcements/a1/files/att_x.pdf'), 'ANNOUNCEMENT_FILE');
  assert.equal(u.kindOf('schools/s1/branches/b1/students/st1/photo.png'), null);
});

test('signatures: each allowed type, and a renamed executable is refused', () => {
  assert.ok(u.signatureMatches('png', PNG));
  assert.ok(u.signatureMatches('jpg', Buffer.from([0xff, 0xd8, 0xff, 0xe0])));
  assert.ok(u.signatureMatches('pdf', Buffer.from('\n%PDF-1.7')));
  assert.ok(u.signatureMatches('docx', Buffer.from([0x50, 0x4b, 0x03, 0x04, 1])));
  assert.ok(u.signatureMatches('txt', Buffer.from('Read chapter 4')));
  assert.equal(u.signatureMatches('png', EXE), false);
  assert.equal(u.signatureMatches('pdf', EXE), false);
  assert.equal(u.signatureMatches('txt', Buffer.from([0x41, 0x00, 0x42])), false, 'binary is not text');
  assert.equal(u.signatureMatches('exe', EXE), false, 'unknown types never pass');
});

test('a matching file is marked PASSED and kept', async () => {
  const bucket = fakeBucket(PNG);
  assert.deepEqual(await u.checkUploadedObject({ bucket, name: HW }), { passed: true });
  assert.deepEqual(bucket.calls.metadata, [[HW, { metadata: { contentCheck: 'PASSED' } }]]);
  assert.deepEqual(bucket.calls.deleted, []);
});

test('a file whose contents do not match its type is deleted, never marked', async () => {
  const bucket = fakeBucket(EXE);
  const r = await u.checkUploadedObject({ bucket, name: HW });
  assert.equal(r.removed, true);
  assert.deepEqual(bucket.calls.deleted, [HW]);
  assert.deepEqual(bucket.calls.metadata, []);
});

test('other objects are left alone', async () => {
  const bucket = fakeBucket(EXE);
  assert.deepEqual(await u.checkUploadedObject({ bucket, name: 'schools/s1/branches/b1/students/st1/photo.png' }), { skipped: true });
  assert.deepEqual(bucket.calls.deleted, []);
});
