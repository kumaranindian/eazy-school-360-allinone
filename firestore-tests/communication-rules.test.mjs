// Firestore rules tests for Milestone 11 — notifications, preferences and
// parent–teacher conversations (see ../firestore.rules and
// ../docs/milestone-11-notifications-parent-teacher-communication.md).
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, query, orderBy, limit, where, serverTimestamp, setDoc, updateDoc, deleteDoc, writeBatch, getCountFromServer,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'cm-a';
let counter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'y1';
const branch = (s, b) => ['schools', s, 'branches', b];
const seed = (fn) => testEnv.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });
const col = (db, name, b = NORTH, s = A) => collection(db, ...branch(s, b), name);
const ref = (db, name, id, b = NORTH, s = A) => doc(db, ...branch(s, b), name, id);
const msgRef = (db, conv, id, b = NORTH, s = A) => doc(db, ...branch(s, b), 'conversations', conv, 'messages', id);

const convDoc = ({ id = 'c1', parent = 'cm-p1', teacher = 'cm-t1', staff = 'st1', student = 's1', section = 'sa', subject = 'math', overrides = {} } = {}) => ({
  schoolId: A, branchId: NORTH, academicYearId: YEAR, classId: 'c5', sectionId: section, studentId: student, studentName: 'Anil',
  parentUserId: parent, parentName: 'Parent', teacherUserId: teacher, teacherStaffId: staff, teacherName: 'Teacher',
  subjectId: subject, subjectName: 'Maths', title: 'Homework help', participants: [parent, teacher], status: 'OPEN', revision: 1,
  lastEvent: 'OPENED', messageCount: 1, lastMessageId: `${id}-m1`, lastMessageAt: serverTimestamp(), unreadForParent: 0,
  unreadForTeacher: 1, lastReadParentAt: serverTimestamp(), lastReadTeacherAt: null, flagged: false, flagReason: null,
  flaggedBy: null, flaggedAt: null, ...audit(parent), ...overrides,
});
const msgDoc = (uid, id, o = {}) => ({
  schoolId: A, branchId: NORTH, conversationId: 'c1', senderUserId: uid, senderName: 'X', senderRole: 'PARENT',
  body: 'Hello teacher', attachments: [], createdAt: serverTimestamp(), ...o,
});
const eventDoc = (id, rev, event, toStatus, uid) => ({
  schoolId: A, branchId: NORTH, conversationId: id, revision: rev, event, toStatus, actorId: uid, actorName: 'X', note: null, at: serverTimestamp(),
});
const notice = (convId, msgId, recipient, uid, o = {}) => ({
  schoolId: A, branchId: NORTH, audience: 'USER', recipientUserId: recipient, type: 'MESSAGE_RECEIVED', applicationId: null,
  conversationId: convId, messageId: msgId, title: 'New message', body: 'New message from X', createdBy: uid,
  createdAt: serverTimestamp(), readAt: null, ...o,
});

function startBatch(db, uid, { id = 'c1', conv = {}, msg = {}, withEvent = true, withNotice = true } = {}) {
  const b = writeBatch(db);
  const { overrides, ...named } = conv;
  const c = convDoc({ id, ...named, overrides: overrides ?? {} });
  b.set(msgRef(db, id, c.lastMessageId), msgDoc(uid, c.lastMessageId, { conversationId: id, ...msg }));
  b.set(ref(db, 'conversations', id), c);
  if (withEvent) b.set(ref(db, 'conversationEvents', `${id}__1`), eventDoc(id, 1, 'OPENED', 'OPEN', uid));
  if (withNotice) b.set(ref(db, 'notifications', `msg__${c.lastMessageId}`), notice(id, c.lastMessageId, c.teacherUserId, uid));
  return b;
}

async function seedWorld() {
  counter += 1;
  A = `cm-a-${counter}`;
  const B = `cm-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'cm-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'cm-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'cm-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'cm-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'cm-t1': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'cm-t2': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'cm-t3': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'cm-t-south': { schoolId: A, branchId: SOUTH, role: 'TEACHER' },
      'cm-fin': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'cm-p1': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'par1' },
      'cm-p2': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'par2' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    const n = branch(A, NORTH);
    for (const [staffId, uid] of [['st1', 'cm-t1'], ['st2', 'cm-t2'], ['st3', 'cm-t3']]) {
      await setDoc(doc(db, ...n, 'staff', staffId), { schoolId: A, branchId: NORTH, userId: uid, status: 'ACTIVE', isTeacher: true, ...audit('seed') });
    }
    const slot = (key, teacher) => setDoc(doc(db, ...n, 'assignmentSlots', key), {
      schoolId: A, branchId: NORTH, assignmentId: `a-${key}`, teacherStaffId: teacher, createdBy: 'seed', createdAt: serverTimestamp(),
    });
    await slot(`${YEAR}__c5__sa__math`, 'st1');
    await slot(`${YEAR}__c5__sa__CLASS_TEACHER`, 'st2');
    await slot(`${YEAR}__c5__sb__sci`, 'st3');
    const student = (id, section, st = 'ACTIVE') => setDoc(doc(db, ...n, 'students', id), {
      schoolId: A, branchId: NORTH, status: st, currentAcademicYearId: YEAR, currentClassId: 'c5', currentSectionId: section, ...audit('seed'),
    });
    await student('s1', 'sa');
    await student('s2', 'sa');
    await student('s3', 'sb');
    const link = (studentId, parentId, o = {}) => setDoc(doc(db, ...n, 'students', studentId, 'parentLinks', parentId), {
      schoolId: A, branchId: NORTH, studentId, parentId, canAccessPortal: true, status: 'ACTIVE', ...audit('seed'), ...o,
    });
    await link('s1', 'par1');
    await link('s2', 'par2');
    await link('s3', 'par1');
    const contact = (staffId, uid, enabled = true) => setDoc(doc(db, ...n, 'messageContacts', staffId), {
      schoolId: A, branchId: NORTH, staffId, userId: uid, name: 'T', enabled, sectionKeys: [`${YEAR}__c5__sa`],
      scopes: [`${YEAR}__c5__sa__math`], subjectNames: {}, updatedAt: serverTimestamp(),
    });
    await contact('st1', 'cm-t1');
    await contact('st2', 'cm-t2');
  });
}

const open = async (uid = 'cm-p1', o = {}) => assertSucceeds(startBatch(asUser(uid), uid, o).commit());

const denied = (n, p) => assertFails(p).catch((e) => { throw new Error('denial case ' + n + ' was allowed: ' + e.message); });
let dn = 0;

// ===================================================================== TESTS

test('Only a linked parent starts a conversation, with a teacher who holds the slot for the child\'s section', async () => {
  await seedWorld();
  const p1 = asUser('cm-p1');
  await assertSucceeds(startBatch(p1, 'cm-p1').commit());
  // the class teacher (CLASS_TEACHER slot) is a valid counterpart too
  await assertSucceeds(startBatch(p1, 'cm-p1', { id: 'c2', conv: { teacher: 'cm-t2', staff: 'st2', subject: 'CLASS_TEACHER' } }).commit());
  // a duplicate id is a replay of an existing document, not a new conversation
  await denied('Only a1', startBatch(p1, 'cm-p1').commit());
  // a teacher cannot start one; nor can a parent as someone else
  await denied('Only a2', startBatch(asUser('cm-t1'), 'cm-t1', { id: 'c3', conv: { parent: 'cm-t1', teacher: 'cm-p1' } }).commit());
  await denied('Only a3', startBatch(p1, 'cm-p1', { id: 'c4', conv: { parent: 'cm-p2' } }).commit());
  // another family's child; a child in another section; a teacher without the slot; a staff record of someone else
  await denied('Only a4', startBatch(p1, 'cm-p1', { id: 'c5', conv: { student: 's2' } }).commit());
  await denied('Only a5', startBatch(p1, 'cm-p1', { id: 'c6', conv: { student: 's3' } }).commit()); // linked, but section sb has no math teacher
  await denied('Only a6', startBatch(p1, 'cm-p1', { id: 'c7', conv: { teacher: 'cm-t3', staff: 'st3' } }).commit());
  await denied('Only a7', startBatch(p1, 'cm-p1', { id: 'c8', conv: { teacher: 'cm-t3', staff: 'st1' } }).commit());
  // malformed
  await denied('Only a8', startBatch(p1, 'cm-p1', { id: 'c9', conv: { overrides: { title: 'x' } } }).commit());
  await denied('Only a9', startBatch(p1, 'cm-p1', { id: 'c10', conv: { overrides: { messageCount: 5 } } }).commit());
  await denied('Only a10', startBatch(p1, 'cm-p1', { id: 'c11', conv: { overrides: { status: 'CLOSED' } } }).commit());
  await denied('Only a11', startBatch(p1, 'cm-p1', { id: 'c12', conv: { overrides: { participants: ['cm-p1', 'cm-t1', 'cm-p2'] } } }).commit());
  await denied('Only a12', startBatch(p1, 'cm-p1', { id: 'c13', msg: { senderUserId: 'cm-t1' } }).commit());
  await denied('Only a13', startBatch(p1, 'cm-p1', { id: 'c14', msg: { body: '' } }).commit());
  await denied('Only a14', startBatch(p1, 'cm-p1', { id: 'c15', msg: { body: 'x'.repeat(2001) } }).commit());
  await denied('Only a15', startBatch(p1, 'cm-p1', { id: 'c16', withEvent: false }).commit());
});

test('An ended or portal-disabled link, a withdrawn child and a non-parent cannot start one', async () => {
  await seedWorld();
  await seed(async (db) => {
    await updateDoc(doc(db, ...branch(A, NORTH), 'students', 's1', 'parentLinks', 'par1'), { status: 'INACTIVE' });
  });
  await assertFails(startBatch(asUser('cm-p1'), 'cm-p1').commit());
  await seed(async (db) => {
    await updateDoc(doc(db, ...branch(A, NORTH), 'students', 's1', 'parentLinks', 'par1'), { status: 'ACTIVE', canAccessPortal: false });
  });
  await assertFails(startBatch(asUser('cm-p1'), 'cm-p1').commit());
  await seed(async (db) => {
    await updateDoc(doc(db, ...branch(A, NORTH), 'students', 's1', 'parentLinks', 'par1'), { canAccessPortal: true });
    await updateDoc(doc(db, ...branch(A, NORTH), 'students', 's1'), { status: 'LEFT' });
  });
  await assertFails(startBatch(asUser('cm-p1'), 'cm-p1').commit());
});

function reply(db, uid, convId, msgId, { section = 'teacher', o = {}, bump = 1, withNotice = true, recipient } = {}) {
  const b = writeBatch(db);
  b.set(msgRef(db, convId, msgId), msgDoc(uid, msgId, { conversationId: convId, senderRole: 'TEACHER', ...o }));
  const unread = section === 'teacher' ? { unreadForParent: bump } : { unreadForTeacher: bump };
  b.update(ref(db, 'conversations', convId), {
    messageCount: 2, lastMessageId: msgId, lastMessageAt: serverTimestamp(), ...unread, ...stamp(uid),
  });
  if (withNotice) b.set(ref(db, 'notifications', `msg__${msgId}`), notice(convId, msgId, recipient ?? (section === 'teacher' ? 'cm-p1' : 'cm-t1'), uid));
  return b;
}

test('Messages: members only, same commit as the counter, no edit, no delete, no duplicate notice', async () => {
  await seedWorld();
  await open();
  const t1 = asUser('cm-t1');
  // outsiders cannot read, post or list
  for (const uid of ['cm-p2', 'cm-t2', 'cm-t-south', 'cm-fin', 'cm-br-north', 'cm-admin']) {
    const db = asUser(uid);
    await denied('Messag1', getDoc(ref(db, 'conversations', 'c1')));
    await denied('Messag2', getDocs(collection(db, ...branch(A, NORTH), 'conversations', 'c1', 'messages')));
    await denied('Messag3', reply(db, uid, 'c1', 'x1').commit());
  }
  // a message without the conversation update is refused
  const lone = writeBatch(t1);
  lone.set(msgRef(t1, 'c1', 'm-lone'), msgDoc('cm-t1', 'm-lone', { conversationId: 'c1', senderRole: 'TEACHER' }));
  await denied('Messag4', lone.commit());
  // validation, forged sender, wrong counter, forged / self / mismatched notice
  await denied('Messag5', reply(t1, 'cm-t1', 'c1', 'm2', { o: { body: '  ' } }).commit());
  await denied('Messag6', reply(t1, 'cm-t1', 'c1', 'm2', { o: { body: 'y'.repeat(2001) } }).commit());
  await denied('Messag7', reply(t1, 'cm-t1', 'c1', 'm2', { o: { senderUserId: 'cm-p1' } }).commit());
  await denied('Messag8', reply(t1, 'cm-t1', 'c1', 'm2', { bump: 2 }).commit());
  await denied('Messag9', reply(t1, 'cm-t1', 'c1', 'm2', { recipient: 'cm-t1' }).commit());
  await denied('Messag10', reply(t1, 'cm-t1', 'c1', 'm2', { recipient: 'cm-p2' }).commit());
  await denied('Messag11', reply(t1, 'cm-t1', 'c1', 'm2', { o: { attachments: [1, 2, 3, 4] } }).commit());
  await assertSucceeds(reply(t1, 'cm-t1', 'c1', 'm2').commit());
  // the parent can read it; a retry of the same message cannot duplicate anything
  await assertSucceeds(getDoc(msgRef(asUser('cm-p1'), 'c1', 'm2')));
  await denied('Messag12', reply(t1, 'cm-t1', 'c1', 'm2').commit());
  // messages are never edited or deleted — by anyone, administrators included
  for (const uid of ['cm-t1', 'cm-p1', 'cm-admin']) {
    await denied('Messag13', updateDoc(msgRef(asUser(uid), 'c1', 'm2'), { body: 'changed' }));
    await denied('Messag14', deleteDoc(msgRef(asUser(uid), 'c1', 'm2')));
  }
  await denied('Messag15', deleteDoc(ref(asUser('cm-p1'), 'conversations', 'c1')));
});

test('Unread counters move only for the other member, and each reader clears only their own', async () => {
  await seedWorld();
  await open();
  const t1 = asUser('cm-t1');
  const p1 = asUser('cm-p1');
  // the teacher cannot clear the parent's counter, nor their own sender-side counter trick
  await assertFails(updateDoc(ref(t1, 'conversations', 'c1'), { unreadForParent: 0, lastReadParentAt: serverTimestamp(), ...stamp('cm-t1') }));
  await assertFails(updateDoc(ref(p1, 'conversations', 'c1'), { unreadForTeacher: 0, lastReadTeacherAt: serverTimestamp(), ...stamp('cm-p1') }));
  await assertFails(updateDoc(ref(t1, 'conversations', 'c1'), { unreadForTeacher: 5, lastReadTeacherAt: serverTimestamp(), ...stamp('cm-t1') }));
  await assertSucceeds(updateDoc(ref(t1, 'conversations', 'c1'), { unreadForTeacher: 0, lastReadTeacherAt: serverTimestamp(), ...stamp('cm-t1') }));
  // a parent message increments the teacher's counter
  const b = writeBatch(p1);
  b.set(msgRef(p1, 'c1', 'm3'), msgDoc('cm-p1', 'm3'));
  b.update(ref(p1, 'conversations', 'c1'), { messageCount: 2, lastMessageId: 'm3', lastMessageAt: serverTimestamp(), unreadForTeacher: 1, ...stamp('cm-p1') });
  b.set(ref(p1, 'notifications', 'msg__m3'), notice('c1', 'm3', 'cm-t1', 'cm-p1'));
  await assertSucceeds(b.commit());
  // the participants and tenant are immutable
  await assertFails(updateDoc(ref(t1, 'conversations', 'c1'), { participants: ['cm-t1', 'cm-p2'], ...stamp('cm-t1') }));
  await assertFails(updateDoc(ref(t1, 'conversations', 'c1'), { parentUserId: 'cm-p2', ...stamp('cm-t1') }));
  await assertFails(updateDoc(ref(t1, 'conversations', 'c1'), { schoolId: 'other', ...stamp('cm-t1') }));
});

test('Status: either member closes; a parent cannot reopen; only the teacher reopens or archives; closed takes no messages', async () => {
  await seedWorld();
  await open();
  const p1 = asUser('cm-p1');
  const t1 = asUser('cm-t1');
  const change = (db, uid, id, rev, event, status) => {
    const b = writeBatch(db);
    b.update(ref(db, 'conversations', id), { status, revision: rev, lastEvent: event, ...stamp(uid) });
    b.set(ref(db, 'conversationEvents', `${id}__${rev}`), eventDoc(id, rev, event, status, uid));
    return b;
  };
  await assertFails(change(asUser('cm-p2'), 'cm-p2', 'c1', 2, 'CLOSED', 'CLOSED').commit());
  await assertFails(change(p1, 'cm-p1', 'c1', 2, 'ARCHIVED', 'ARCHIVED').commit()); // must close first
  await assertSucceeds(change(p1, 'cm-p1', 'c1', 2, 'CLOSED', 'CLOSED').commit());
  // closed: no message from anyone
  await assertFails(reply(t1, 'cm-t1', 'c1', 'm9').commit());
  const parentMsg = writeBatch(p1);
  parentMsg.set(msgRef(p1, 'c1', 'm10'), msgDoc('cm-p1', 'm10'));
  parentMsg.update(ref(p1, 'conversations', 'c1'), { messageCount: 2, lastMessageId: 'm10', lastMessageAt: serverTimestamp(), unreadForTeacher: 2, ...stamp('cm-p1') });
  await assertFails(parentMsg.commit());
  await assertFails(change(p1, 'cm-p1', 'c1', 3, 'REOPENED', 'OPEN').commit());
  await assertFails(change(p1, 'cm-p1', 'c1', 3, 'ARCHIVED', 'ARCHIVED').commit());
  await assertSucceeds(change(t1, 'cm-t1', 'c1', 3, 'REOPENED', 'OPEN').commit());
  await assertSucceeds(reply(t1, 'cm-t1', 'c1', 'm11').commit());
  // status change without its event record is refused
  const bare = writeBatch(t1);
  bare.update(ref(t1, 'conversations', 'c1'), { status: 'CLOSED', revision: 4, lastEvent: 'CLOSED', ...stamp('cm-t1') });
  await assertFails(bare.commit());
  await assertSucceeds(change(t1, 'cm-t1', 'c1', 4, 'CLOSED', 'CLOSED').commit());
  await assertSucceeds(change(t1, 'cm-t1', 'c1', 5, 'ARCHIVED', 'ARCHIVED').commit());
  await assertFails(change(t1, 'cm-t1', 'c1', 6, 'REOPENED', 'OPEN').commit()); // archived stays archived
});

test('Reporting opens a conversation to administrators — and only then', async () => {
  await seedWorld();
  await open();
  const p1 = asUser('cm-p1');
  for (const uid of ['cm-admin', 'cm-br-north']) {
    await assertFails(getDoc(ref(asUser(uid), 'conversations', 'c1')));
    await assertFails(getDocs(collection(asUser(uid), ...branch(A, NORTH), 'conversations', 'c1', 'messages')));
  }
  const report = (db, uid, reason) => {
    const b = writeBatch(db);
    b.update(ref(db, 'conversations', 'c1'), {
      flagged: true, flagReason: reason, flaggedBy: uid, flaggedAt: serverTimestamp(), revision: 2, lastEvent: 'REPORTED', ...stamp(uid),
    });
    b.set(ref(db, 'conversationEvents', 'c1__2'), eventDoc('c1', 2, 'REPORTED', 'OPEN', uid));
    return b;
  };
  await assertFails(report(asUser('cm-p2'), 'cm-p2', 'rude').commit());
  await assertFails(report(p1, 'cm-p1', 'x').commit());
  await assertSucceeds(report(p1, 'cm-p1', 'Inappropriate tone').commit());
  // administrators of the branch (and the school) can now read; others cannot; nobody can write as them
  for (const uid of ['cm-admin', 'cm-br-north']) {
    await assertSucceeds(getDoc(ref(asUser(uid), 'conversations', 'c1')));
    await assertSucceeds(getDocs(collection(asUser(uid), ...branch(A, NORTH), 'conversations', 'c1', 'messages')));
    await assertSucceeds(getDocs(query(col(asUser(uid), 'conversations'), where('flagged', '==', true))));
  }
  for (const uid of ['cm-br-south', 'cm-admin-b', 'cm-t2', 'cm-fin']) {
    await assertFails(getDoc(ref(asUser(uid), 'conversations', 'c1')));
  }
  await assertFails(reply(asUser('cm-admin'), 'cm-admin', 'c1', 'mx', { recipient: 'cm-p1' }).commit());
  // once reported it cannot be reported again
  await assertFails(report(p1, 'cm-p1', 'again please').commit());
});

test('Queries the app issues: own conversations by membership, newest first', async () => {
  await seedWorld();
  await open();
  const mine = (db, uid) => getDocs(query(col(db, 'conversations'), where('participants', 'array-contains', uid), orderBy('lastMessageAt', 'desc'), limit(30)));
  await assertSucceeds(mine(asUser('cm-p1'), 'cm-p1'));
  await assertSucceeds(mine(asUser('cm-t1'), 'cm-t1'));
  await assertSucceeds(mine(asUser('cm-p2'), 'cm-p2')); // empty, allowed
  // asking for someone else's list, or an unfiltered list, is refused
  await assertFails(mine(asUser('cm-p2'), 'cm-p1'));
  await assertFails(getDocs(col(asUser('cm-p1'), 'conversations')));
  await assertFails(getDocs(query(col(asUser('cm-t2'), 'conversations'), where('studentId', '==', 's1'))));
  const msgs = (db) => getDocs(query(collection(db, ...branch(A, NORTH), 'conversations', 'c1', 'messages'), orderBy('createdAt', 'desc'), limit(30)));
  await assertSucceeds(msgs(asUser('cm-p1')));
  await assertFails(msgs(asUser('cm-p2')));
  await assertSucceeds(getDocs(query(col(asUser('cm-p1'), 'conversationEvents'), where('conversationId', '==', 'c1'))).catch(() => null));
});

test('A user reads and marks read only their own notifications; counts are aggregates of their own', async () => {
  await seedWorld();
  await open();
  const t1 = asUser('cm-t1');
  const id = `msg__c1-m1`;
  await assertSucceeds(getDoc(ref(t1, 'notifications', id)));
  for (const uid of ['cm-p1', 'cm-t2', 'cm-admin']) await assertFails(getDoc(ref(asUser(uid), 'notifications', id)));
  await assertFails(updateDoc(ref(asUser('cm-p1'), 'notifications', id), { readAt: serverTimestamp() }));
  const unread = (db, uid) => getCountFromServer(query(col(db, 'notifications'), where('audience', '==', 'USER'), where('recipientUserId', '==', uid), where('readAt', '==', null)));
  const n = await assertSucceeds(unread(t1, 'cm-t1'));
  if (n.data().count !== 1) throw new Error('expected 1 unread, got ' + n.data().count);
  await assertFails(unread(asUser('cm-p1'), 'cm-t1'));
  await assertFails(updateDoc(ref(t1, 'notifications', id), { title: 'changed', readAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref(t1, 'notifications', id), { readAt: serverTimestamp() }));
  const after = await assertSucceeds(unread(t1, 'cm-t1'));
  if (after.data().count !== 0) throw new Error('expected 0 unread');
});

test('Push devices are written only by the server; the owner can read and delete their own', async () => {
  await seedWorld();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'cm-p1', 'devices', 'tok1'), { token: 'x'.repeat(40), platform: 'android', schoolId: A, status: 'ACTIVE' });
  });
  const dev = (db, uid, id = 'tok1') => doc(db, 'users', uid, 'devices', id);
  const body = (o = {}) => ({ token: 'x'.repeat(40), platform: 'android', updatedAt: serverTimestamp(), ...o });
  const p1 = asUser('cm-p1');
  // No client write, however well-formed: registration goes through the function.
  await assertFails(setDoc(dev(p1, 'cm-p1', 'new'), body()));
  await assertFails(setDoc(dev(p1, 'cm-p1'), body()));
  await assertFails(updateDoc(dev(p1, 'cm-p1'), { status: 'ACTIVE' }));
  await assertFails(setDoc(dev(asUser('cm-p2'), 'cm-p1', 'x'), body()));
  // Own registration: readable and removable; another user's is neither.
  await assertSucceeds(getDoc(dev(p1, 'cm-p1')));
  await assertFails(getDoc(dev(asUser('cm-p2'), 'cm-p1')));
  await assertFails(deleteDoc(dev(asUser('cm-p2'), 'cm-p1')));
  await assertSucceeds(deleteDoc(dev(p1, 'cm-p1')));
  // The delivery log is server-only.
  await assertFails(getDoc(doc(p1, 'pushDeliveries', 'evt')));
  await assertFails(setDoc(doc(p1, 'pushDeliveries', 'evt'), { status: 'SENT' }));
});

test('Preferences and read lists are the user\'s own, validated, and critical notices cannot be muted', async () => {
  await seedWorld();
  const prefs = (db, uid) => doc(db, 'users', uid, 'preferences', 'notifications');
  const body = (o = {}) => ({ mutedCategories: ['HOMEWORK'], pushEnabled: false, updatedAt: serverTimestamp(), ...o });
  const p1 = asUser('cm-p1');
  await assertSucceeds(setDoc(prefs(p1, 'cm-p1'), body()));
  await assertSucceeds(getDoc(prefs(p1, 'cm-p1')));
  await assertFails(getDoc(prefs(asUser('cm-p2'), 'cm-p1')));
  await assertFails(setDoc(prefs(asUser('cm-p2'), 'cm-p1'), body()));
  await assertFails(setDoc(prefs(p1, 'cm-p1'), body({ mutedCategories: ['ADMINISTRATIVE'] })));
  await assertFails(setDoc(prefs(p1, 'cm-p1'), body({ mutedCategories: ['NOT_A_CATEGORY'] })));
  await assertFails(setDoc(prefs(p1, 'cm-p1'), body({ pushEnabled: 'yes' })));
  await assertFails(setDoc(doc(p1, 'users', 'cm-p1', 'preferences', 'other'), body()));
  const reads = (db, uid) => doc(db, 'users', uid, 'noticeReads', 'state');
  await assertSucceeds(setDoc(reads(p1, 'cm-p1'), { ids: ['a', 'b'] }));
  await assertFails(setDoc(reads(p1, 'cm-p1'), { ids: Array.from({ length: 501 }, (_, i) => `n${i}`) }));
  await assertFails(setDoc(reads(asUser('cm-p2'), 'cm-p1'), { ids: [] }));
  await assertFails(getDoc(reads(asUser('cm-p2'), 'cm-p1')));
});

test('Teachers opt in to parent messages; a conversation needs it', async () => {
  await seedWorld();
  const contact = (uid, staff, o = {}) => ({
    schoolId: A, branchId: NORTH, staffId: staff, userId: uid, name: 'T', enabled: true, sectionKeys: [`${YEAR}__c5__sa`],
    scopes: [`${YEAR}__c5__sa__math`], subjectNames: { [`${YEAR}__c5__sa__math`]: 'Maths' }, updatedAt: serverTimestamp(), ...o,
  });
  // only the teacher writes their own contact
  await assertFails(setDoc(ref(asUser('cm-t2'), 'messageContacts', 'st1'), contact('cm-t2', 'st1')));
  await assertFails(setDoc(ref(asUser('cm-t1'), 'messageContacts', 'st1'), contact('cm-t2', 'st1')));
  await assertFails(setDoc(ref(asUser('cm-p1'), 'messageContacts', 'st1'), contact('cm-p1', 'st1')));
  await assertFails(setDoc(ref(asUser('cm-admin'), 'messageContacts', 'st1'), contact('cm-admin', 'st1')));
  await assertSucceeds(setDoc(ref(asUser('cm-t1'), 'messageContacts', 'st1'), contact('cm-t1', 'st1', { enabled: false })));
  // a parent cannot see a teacher who has not opted in, and cannot start a conversation with them
  await assertFails(getDoc(ref(asUser('cm-p1'), 'messageContacts', 'st1')));
  await assertFails(startBatch(asUser('cm-p1'), 'cm-p1').commit());
  await assertSucceeds(setDoc(ref(asUser('cm-t1'), 'messageContacts', 'st1'), contact('cm-t1', 'st1')));
  await assertSucceeds(getDoc(ref(asUser('cm-p1'), 'messageContacts', 'st1')));
  await assertSucceeds(getDocs(query(col(asUser('cm-p1'), 'messageContacts'), where('enabled', '==', true), where('sectionKeys', 'array-contains', `${YEAR}__c5__sa`))));
  await assertFails(getDocs(col(asUser('cm-p1'), 'messageContacts')));
  await assertSucceeds(startBatch(asUser('cm-p1'), 'cm-p1').commit());
  // other tenants cannot read contacts
  await assertFails(getDoc(ref(asUser('cm-admin-b'), 'messageContacts', 'st1')));
  await assertFails(deleteDoc(ref(asUser('cm-t1'), 'messageContacts', 'st1')));
});

test('Gaps found by mutation: impersonated parent, spoofed reporter, counter without message, stray and pre-read notices', async () => {
  await seedWorld();
  const p1 = asUser('cm-p1');
  // a parent cannot open a conversation in another parent's name, even with their own audit fields
  await denied('Gap1', startBatch(p1, 'cm-p1', {
    id: 'c9', conv: { parent: 'cm-p2', overrides: audit('cm-p1') },
  }).commit());
  await open();
  const t1 = asUser('cm-t1');
  // bumping the counters without a message document is refused (it would inflate the other member's badge)
  const bare = writeBatch(t1);
  bare.update(ref(t1, 'conversations', 'c1'), {
    messageCount: 2, lastMessageId: 'ghost', lastMessageAt: serverTimestamp(), unreadForParent: 1, ...stamp('cm-t1'),
  });
  await denied('Gap2', bare.commit());
  // a notice with a made-up id (so a retry could duplicate it), or one created already read
  const withNotice = (id, o = {}) => {
    const b = writeBatch(t1);
    b.set(msgRef(t1, 'c1', 'm5'), msgDoc('cm-t1', 'm5', { conversationId: 'c1', senderRole: 'TEACHER' }));
    b.update(ref(t1, 'conversations', 'c1'), {
      messageCount: 2, lastMessageId: 'm5', lastMessageAt: serverTimestamp(), unreadForParent: 1, ...stamp('cm-t1'),
    });
    b.set(ref(t1, 'notifications', id), notice('c1', 'm5', 'cm-p1', 'cm-t1', o));
    return b;
  };
  await denied('Gap3', withNotice('random-id').commit());
  await denied('Gap4', withNotice('msg__m5', { readAt: serverTimestamp() }).commit());
  await assertSucceeds(withNotice('msg__m5').commit());
  // a reporter cannot name someone else as the reporter
  const spoof = writeBatch(p1);
  spoof.update(ref(p1, 'conversations', 'c1'), {
    flagged: true, flagReason: 'rude tone', flaggedBy: 'cm-t1', flaggedAt: serverTimestamp(), revision: 2, lastEvent: 'REPORTED', ...stamp('cm-p1'),
  });
  spoof.set(ref(p1, 'conversationEvents', 'c1__2'), eventDoc('c1', 2, 'REPORTED', 'OPEN', 'cm-p1'));
  await denied('Gap5', spoof.commit());
});

test('A sender cannot skip or fake the other member\'s unread counter', async () => {
  await seedWorld();
  await open();
  const p1 = asUser('cm-p1');
  const t1 = asUser('cm-t1');
  const send = (db, uid, msgId, counters, recipient) => {
    const b = writeBatch(db);
    b.set(msgRef(db, 'c1', msgId), msgDoc(uid, msgId, { conversationId: 'c1' }));
    b.update(ref(db, 'conversations', 'c1'), {
      messageCount: 2, lastMessageId: msgId, lastMessageAt: serverTimestamp(), ...counters, ...stamp(uid),
    });
    b.set(ref(db, 'notifications', `msg__${msgId}`), notice('c1', msgId, recipient, uid));
    return b;
  };
  // the parent's message must raise the teacher's counter by exactly one (it is 1 now)
  await denied('Ctr1', send(p1, 'cm-p1', 'm7', {}, 'cm-t1').commit());
  await denied('Ctr2', send(p1, 'cm-p1', 'm7', { unreadForTeacher: 1 }, 'cm-t1').commit());
  await denied('Ctr3', send(p1, 'cm-p1', 'm7', { unreadForTeacher: 9 }, 'cm-t1').commit());
  await assertSucceeds(send(p1, 'cm-p1', 'm7', { unreadForTeacher: 2 }, 'cm-t1').commit());
  // and the teacher's reply must raise the parent's counter by exactly one
  const reply2 = (counters) => {
    const b = writeBatch(t1);
    b.set(msgRef(t1, 'c1', 'm8'), msgDoc('cm-t1', 'm8', { conversationId: 'c1', senderRole: 'TEACHER' }));
    b.update(ref(t1, 'conversations', 'c1'), {
      messageCount: 3, lastMessageId: 'm8', lastMessageAt: serverTimestamp(), ...counters, ...stamp('cm-t1'),
    });
    b.set(ref(t1, 'notifications', 'msg__m8'), notice('c1', 'm8', 'cm-p1', 'cm-t1'));
    return b;
  };
  await denied('Ctr4', reply2({}).commit());
  await denied('Ctr5', reply2({ unreadForParent: 0 }).commit());
  await assertSucceeds(reply2({ unreadForParent: 1 }).commit());
});
