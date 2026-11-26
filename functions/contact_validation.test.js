'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { isEmail, isPhone } = require('./contact_validation');

// Same cases as test/core/validators_test.dart: the server and the app agree.
test('isEmail accepts real addresses', () => {
  for (const e of ['user@example.com', 'first.last@school.co.in', "o'brien+fees@example.org", 'a_b-c@sub-domain.example.com', `${'a'.repeat(64)}@example.com`]) {
    assert.equal(isEmail(e), true, e);
  }
});

test('isEmail refuses markup, bad dots, bad domains and long local parts', () => {
  for (const e of ['<script>alert(1)</script>@x.com', '<script>@x.com', 'a b@example.com', '.lead@example.com', 'trail.@example.com',
    'dou..ble@example.com', 'user@-bad.com', 'user@example', 'user@example.c', 'user@@example.com', `${'a'.repeat(65)}@example.com`, '', null, 7]) {
    assert.equal(isEmail(e), false, String(e));
  }
});

test('isPhone accepts usual formats and refuses letters and odd lengths', () => {
  for (const p of ['+91 98765 43210', '044-2345 6789', '(04) 123 4567', '9876543210']) assert.equal(isPhone(p), true, p);
  for (const p of ['abcde', '98765abc10', '12345', '1234567890123456', '98+765 43210', '', null]) assert.equal(isPhone(p), false, String(p));
});
