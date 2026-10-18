'use strict';
// CFG-6 guard: the staff list chains up to five equality filters with
// orderBy(displayNameLower). Firestore serves that by merging one composite per
// filter field, each ending in displayNameLower - so every filter field must
// keep such an index, or combined filters fail with failed-precondition.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const idx = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'firestore.indexes.json'), 'utf8'));

test('every staff list filter has a (field, displayNameLower) composite index', () => {
  const have = new Set(
    idx.indexes
      .filter((i) => i.collectionGroup === 'staff' && i.queryScope === 'COLLECTION' && i.fields.length === 2)
      .filter((i) => i.fields[1].fieldPath === 'displayNameLower' && i.fields[1].order === 'ASCENDING')
      .map((i) => i.fields[0].fieldPath),
  );
  for (const f of ['status', 'departmentId', 'designationId', 'employmentType', 'isTeacher']) {
    assert.ok(have.has(f), `missing staff composite index (${f}, displayNameLower)`);
  }
});
