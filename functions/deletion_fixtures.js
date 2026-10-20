'use strict';

// Shared by the in-memory and emulator tests of the deletion processor.

const S = 'schools/s1';
const B1 = `${S}/branches/b1`;
const B2 = `${S}/branches/b2`;

const FILES = [
  `${B1}/parents/par1/photo.jpg`,
  `${B1}/staff/st1/photo.jpg`,
  `${B1}/staff/st1/documents/d1/contract.pdf`,
  `${B1}/leaveDocs/teacher/l1/note.pdf`,
  `${B1}/leaveDocs/other/l2/x.pdf`,
  `${B1}/conversations/c1/files/f.png`,
  `${B1}/conversations/c1/files/g.png`,
  `${B1}/students/stu1/photo.jpg`,
];

function fakeStorage(paths = FILES) {
  const files = new Set(paths);
  return {
    files,
    deletePrefix: async (prefix) => {
      let n = 0;
      for (const f of [...files]) if (f.startsWith(prefix)) (files.delete(f), n++);
      return n;
    },
    list: async (prefix) => [...files].filter((f) => f.startsWith(prefix)),
    deleteFile: async (f) => void files.delete(f),
  };
}

const seed = () => ({
  'users/parent': { schoolId: 's1', branchId: 'b1', role: 'PARENT', status: 'ACTIVE', name: 'Pat Parent', email: 'p@x.com', phone: '+911', linkedParentId: 'par1', login: { enabled: true } },
  'users/teacher': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE', name: 'Tia Teacher', email: 't@x.com', login: { enabled: true } },
  'users/other': { schoolId: 's1', branchId: 'b1', role: 'PARENT', status: 'ACTIVE', name: 'Olly Other', email: 'o@x.com', linkedParentId: 'par2' },
  'users/adminA': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE', name: 'Admin A', email: 'a@x.com' },
  'users/adminB': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE', name: 'Admin B', email: 'b@x.com' },
  'users/solo': { schoolId: 's9', role: 'SCHOOL_ADMIN', status: 'ACTIVE', name: 'Solo', email: 's@x.com' },
  'users/reviewer': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', name: 'Reviewer' },
  'users/parent/devices/d1': { token: 't1' },
  'users/parent/devices/d2': { token: 't2' },
  'users/parent/preferences/notifications': { push: true },
  'users/parent/noticeReads/state': { lastRead: 1 },
  'users/other/devices/d9': { token: 'keep-me' },
  [`${S}`]: { name: 'School' },
  [B1]: { name: 'Main' },
  [B2]: { name: 'Annex' },
  [`${B1}/parents/par1`]: { firstName: 'Pat', lastName: 'Parent', displayName: 'Pat Parent', phone: '+911', email: 'p@x.com', photoUrl: 'u', occupation: 'x', addressLine1: 'a', city: 'c', linkedUserId: 'parent' },
  [`${B1}/parents/par2`]: { firstName: 'Olly', lastName: 'Other', phone: '+912', email: 'o@x.com', linkedUserId: 'other' },
  [`${B1}/parentAccess/par1`]: { classKeys: ['c'] },
  [`${B1}/parentAccess/par2`]: { classKeys: ['c'] },
  [`${B1}/students/stu1`]: { firstName: 'Kid', lastName: 'Student', dateOfBirth: '2015', createdBy: 'teacher', updatedBy: 'adminA' },
  [`${B1}/students/stu1/parentLinks/par1`]: { parentId: 'par1', createdBy: 'parent', updatedBy: 'parent' },
  [`${B1}/homework/hw1`]: { title: 'HW', createdBy: 'teacher', createdByName: 'Tia Teacher', publishedBy: 'teacher' },
  [`${B2}/homework/hw2`]: { title: 'HW2', createdBy: 'teacher', updatedBy: 'teacher' },
  [`${B1}/homework/hw3`]: { title: 'HW3', createdBy: 'adminA' },
  [`${B1}/leaveApplications/l1`]: { applicantUserId: 'teacher', applicantName: 'Tia Teacher', reason: 'surgery', startDateKey: '2026-10-01', attachments: [{ path: `${B1}/leaveDocs/teacher/l1/note.pdf`, name: 'note.pdf' }], decidedBy: 'adminA', decidedByName: 'Admin A', status: 'APPROVED' },
  [`${B1}/leaveApplications/l2`]: { applicantUserId: 'other', applicantName: 'Olly Other', reason: 'fever', attachments: [{ path: `${B1}/leaveDocs/other/l2/x.pdf`, name: 'x.pdf' }], decidedBy: 'teacher', decidedByName: 'Tia Teacher', status: 'APPROVED' },
  [`${B1}/staff/st1`]: { userId: 'teacher', firstName: 'Tia', lastName: 'Teacher', phone: '+913', email: 't@x.com', employeeCode: 'E1', joiningDate: '2020', departmentId: 'd1', photoUrl: 'p', bloodGroup: 'O+', alternatePhone: '9', address: 'addr', city: 'c', state: 's', country: 'IN', postalCode: '1' },
  [`${B1}/teacherAccess/teacher`]: { classKeys: ['c'] },
  [`${B1}/teacherAccess/other`]: { classKeys: ['c'] },
  [`${B1}/payments/p1`]: { collectedBy: 'teacher', collectorName: 'Tia Teacher', studentName: 'Kid Student', createdBy: 'teacher', amountMinor: 5000 },
  [`${B1}/invoices/i1`]: { createdBy: 'teacher', updatedBy: 'teacher', total: 5000 },
  [`${B1}/financialAuditLogs/f1`]: { actorId: 'teacher', actorName: 'Tia Teacher' },
  [`${B1}/conversations/c1`]: { participants: ['parent', 'teacher'], parentUserId: 'parent', parentName: 'Pat Parent', teacherUserId: 'teacher', teacherName: 'Tia Teacher', title: 'Maths' },
  [`${B1}/conversations/c1/messages/m1`]: { senderUserId: 'parent', senderName: 'Pat Parent', body: 'hello', attachments: [{ path: `${B1}/conversations/c1/files/f.png` }] },
  [`${B1}/conversations/c1/messages/m2`]: { senderUserId: 'teacher', senderName: 'Tia Teacher', body: 'hi back', attachments: [{ path: `${B1}/conversations/c1/files/g.png` }] },
  [`${B1}/studentAttendance/a1`]: { status: 'PRESENT', createdBy: 'teacher' },
  [`${B1}/studentAttendance/a1/history/h1`]: { changedBy: 'teacher', changedByName: 'Tia Teacher' },
  [`${B1}/notifications/n1`]: { audience: 'USER', recipientUserId: 'parent', title: 'mine' },
  [`${B1}/notifications/n2`]: { audience: 'USER', recipientUserId: 'other', title: 'not mine' },
  [`${B1}/notifications/n3`]: { audience: 'SCHOOL', title: 'broadcast' },
  [`${S}/authAudit/e1`]: { actorId: 'adminA', type: 'X' },
  [`${S}/authAudit/e2`]: { actorId: 'teacher', type: 'Y' },
});

const authUsers = () => ({ 'p@x.com': 'parent', 't@x.com': 'teacher', 'o@x.com': 'other', 'a@x.com': 'adminA', 's@x.com': 'solo' });


module.exports = { S, B1, B2, FILES, fakeStorage, seed, authUsers };
