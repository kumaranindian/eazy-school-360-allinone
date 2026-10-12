'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { categoryFor, allowsPush } = require('./categories');

test('categoryFor mirrors the app', () => {
  assert.strictEqual(categoryFor('LEAVE_APPROVED'), 'LEAVE');
  assert.strictEqual(categoryFor('HOMEWORK_PUBLISHED'), 'HOMEWORK');
  assert.strictEqual(categoryFor('SUBSTITUTION_ASSIGNED'), 'TIMETABLE');
  assert.strictEqual(categoryFor('RESULT_PUBLISHED'), 'RESULTS');
  assert.strictEqual(categoryFor('SOMETHING_NEW'), 'ADMINISTRATIVE');
});

test('allowsPush honours the switch and muted categories, never muting administrative', () => {
  assert.strictEqual(allowsPush(null, 'HOMEWORK'), true);
  assert.strictEqual(allowsPush({ pushEnabled: false }, 'ADMINISTRATIVE'), false);
  assert.strictEqual(allowsPush({ mutedCategories: ['HOMEWORK'] }, 'HOMEWORK'), false);
  assert.strictEqual(allowsPush({ mutedCategories: ['ADMINISTRATIVE'] }, 'ADMINISTRATIVE'), true);
  assert.strictEqual(allowsPush({ mutedCategories: ['HOMEWORK'] }, 'FEES'), true);
});
