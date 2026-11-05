// Firestore security-rule tests, run against the Local Emulator Suite:
//   cd firebase && npm run test:rules
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, runTransaction, serverTimestamp, setDoc, updateDoc, where, writeBatch,
} from 'firebase/firestore';

const GROUP = 'btech-computer-2026-27-sem5-div-b';
const GROUP_C = 'btech-computer-2026-27-sem5-div-c';
const DEPT = 'dept-computer';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-campussync-rules',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env?.cleanup());

/** A valid announcement document as the app writes it (Announcement.toJson + stamp). */
const ann = (id, overrides = {}) => ({
  id, title: 'Qiskit Fall Fest', status: 'published', category: 'event', summary: null, description: null,
  startDate: null, endDate: null, registrationUrl: null, imageUrl: null, audience: { scope: 'all', ids: [] },
  audienceKeys: ['all'], source: null, updatedAt: '2026-10-21T00:00:00Z', reviewFlags: [], ...overrides,
});
const forGroup = (g) => ({ audience: { scope: 'groups', ids: [g] }, audienceKeys: [`group:${g}`] });
const exam = (groupIds, electiveOfferingIds = [], overrides = {}) => ({
  status: 'published', groupIds, electiveOfferingIds, date: '2026-11-17',
  audienceKeys: [...groupIds.map((g) => `group:${g}`), ...electiveOfferingIds.map((o) => `oe:${o}`)], ...overrides,
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/admin1'), { email: 'a@x.test', role: 'admin' });
    await setDoc(doc(db, 'admins/admin2'), { email: 'b@x.test', role: 'admin' });
    await setDoc(doc(db, 'admins/cm1'), { email: 'c@x.test', role: 'contentManager' });
    await setDoc(doc(db, 'admins/typo1'), { email: 't@x.test', role: 'Admin' }); // mistyped role (L3)
    await setDoc(doc(db, 'admins/norole1'), { email: 'n@x.test' }); // no role (L3)
    const student = { displayName: 'Test Student', avatar: 'fox', batch: 'B1', requestedGroupId: GROUP };
    await setDoc(doc(db, 'students/active1'), { ...student, uid: 'active1', sapId: '99999300001', rollNumber: 'B001', status: 'active', groupId: GROUP, oe1OfferingId: 'oe1-00' });
    await setDoc(doc(db, 'students/activeC'), { ...student, uid: 'activeC', sapId: '99999300003', rollNumber: 'C001', status: 'active', groupId: GROUP_C, requestedGroupId: GROUP_C });
    await setDoc(doc(db, 'students/pending1'), { ...student, uid: 'pending1', sapId: '99999300002', rollNumber: 'B002', status: 'pending', groupId: null });
    await setDoc(doc(db, 'sapIndex/99999300001'), { uid: 'active1' });
    await setDoc(doc(db, 'sapIndex/99999300002'), { uid: 'pending1' });
    await setDoc(doc(db, 'sapIndex/99999300003'), { uid: 'activeC' });
    await setDoc(doc(db, 'groups/' + GROUP), { label: 'Div B', type: 'division', active: true, departmentId: DEPT });
    await setDoc(doc(db, 'groups/' + GROUP_C), { label: 'Div C', type: 'division', active: true, departmentId: DEPT });
    await setDoc(doc(db, 'groups/oe1-pool'), { label: 'Open elective I', type: 'electivePool', active: true });
    await setDoc(doc(db, 'calendarEvents/pub'), { title: 'Diwali Vacation', start: '2026-11-06', end: '2026-11-12', status: 'published' });
    await setDoc(doc(db, 'calendarEvents/nostatus'), { title: 'Legacy event', start: '2026-11-06', end: '2026-11-12' });
    await setDoc(doc(db, 'rooms/CR-402'), { name: 'CR 402' });
    await setDoc(doc(db, 'timetableVersions/pub'), { groupId: GROUP, status: 'published', entries: [], effectiveFrom: '2026-07-13', version: 1 });
    await setDoc(doc(db, 'timetableVersions/draft'), { groupId: GROUP, status: 'draft', entries: [], effectiveFrom: '2026-07-13', version: 2 });
    await setDoc(doc(db, 'timetableVersions/old'), { groupId: GROUP, status: 'archived', entries: [], effectiveFrom: '2026-07-01', version: 0 });
    await setDoc(doc(db, 'exams/pub'), exam([GROUP]));
    await setDoc(doc(db, 'exams/draft'), exam([GROUP], [], { status: 'draft', date: '2026-11-18' }));
    await setDoc(doc(db, 'exams/divC'), exam([GROUP_C]));
    await setDoc(doc(db, 'exams/oe'), exam([], ['oe1-00']));
    await setDoc(doc(db, 'exams/unlinked'), exam([]));
    await setDoc(doc(db, 'announcements/draft'), ann('draft', { status: 'draft', title: 'Draft' }));
    await setDoc(doc(db, 'announcements/all'), ann('all'));
    await setDoc(doc(db, 'announcements/divB'), ann('divB', forGroup(GROUP)));
    await setDoc(doc(db, 'announcements/divC'), ann('divC', forGroup(GROUP_C)));
    await setDoc(doc(db, 'announcements/dept'), ann('dept', { audience: { scope: 'department', ids: [DEPT] }, audienceKeys: [`dept:${DEPT}`] }));
    await setDoc(doc(db, 'auditLogs/log1'), { actorUid: 'admin1', actorEmail: 'admin1@campussync.test', action: 'x' });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
// Tokens as Firebase Auth issues them: the email claim, verified or not.
const emailOf = (uid) => `${uid}@campussync.test`;
const verified = (uid) => env.authenticatedContext(uid, { email: emailOf(uid), email_verified: true }).firestore();
const unverified = (uid) => env.authenticatedContext(uid, { email: emailOf(uid), email_verified: false }).firestore();

/**
 * A staff write the way FirestoreRepository makes it: one batch with a new audit
 * record; `build(batch, db, auditId)` adds the audited writes (M4).
 */
const audited = (uid, build, auditFields = {}) => {
  const db = verified(uid);
  const b = writeBatch(db);
  const a = doc(collection(db, 'auditLogs'));
  b.set(a, { actorUid: uid, actorEmail: emailOf(uid), action: 'test', ...auditFields });
  build(b, db, a.id);
  return b.commit();
};
/** Student queries as the app sends them (FirestoreRepository.fetch): status + audience. */
const keysOf = { active1: ['all', `group:${GROUP}`, `dept:${DEPT}`, 'oe:oe1-00'], activeC: ['all', `group:${GROUP_C}`, `dept:${DEPT}`] };
const studentQuery = (uid, col, keys = keysOf[uid] ?? ['all']) =>
  getDocs(query(collection(as(uid), col), where('status', '==', 'published'), where('audienceKeys', 'array-contains-any', keys)));
const ids = (snap) => snap.docs.map((d) => d.id).sort().join(',');

/** The profile document the app writes on registration (FirestoreRepository.registerProfile). */
const profile = (uid, sapId, overrides = {}) => ({
  uid, email: emailOf(uid), displayName: 'Test Student', sapId, rollNumber: 'B050', requestedGroupId: GROUP,
  groupId: null, batch: 'B1', oe1OfferingId: null, oe2OfferingId: null, avatar: 'fox', status: 'pending',
  createdAt: serverTimestamp(), ...overrides,
});
/** The single write FirestoreRepository.releaseSapId makes for the student `uid`. */
const release = (uid, sapId, { as = 'admin1', status = 'suspended' } = {}) => audited(as, (b, db, auditId) => {
  b.update(doc(db, `students/${uid}`), { status, sapReleased: true, updatedBy: as, auditId });
  b.delete(doc(db, `sapIndex/${sapId}`));
});
/** Same transaction as the app: check the claim, then write claim + profile together. */
const register = (db, uid, sapId, overrides) => runTransaction(db, async (tx) => {
  const claim = doc(db, `sapIndex/${sapId}`);
  await tx.get(claim);
  tx.set(claim, { uid });
  tx.set(doc(db, `students/${uid}`), profile(uid, sapId, overrides));
});

describe('Allowed operations', () => {
  test('anyone can read the non-personal group catalogue (needed for registration)', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'groups/' + GROUP)));
  });
  test('active student reads published timetables and own exams via the app queries', async () => {
    const db = as('active1');
    await assertSucceeds(getDocs(query(collection(db, 'timetableVersions'), where('status', '==', 'published'))));
    await assertSucceeds(studentQuery('active1', 'exams'));
    await assertSucceeds(getDoc(doc(db, 'rooms/CR-402')));
  });
  test('verified new user registers: pending profile + SAP ID claim in one transaction', async () => {
    await assertSucceeds(register(verified('newuser'), 'newuser', '99999399999'));
  });
  test('student edits own cosmetic preferences', async () => {
    await assertSucceeds(updateDoc(doc(as('active1'), 'students/active1'), { avatar: 'owl', batch: 'B1' }));
  });
  test('admin approves a student and publishes an exam, each with an audit record', async () => {
    await assertSucceeds(audited('admin1', (b, db, auditId) =>
      b.update(doc(db, 'students/pending1'), { status: 'active', groupId: GROUP, updatedBy: 'admin1', auditId })));
    await assertSucceeds(audited('admin1', (b, db, auditId) =>
      b.set(doc(db, 'exams/new'), { ...exam([GROUP]), date: '2026-11-19', updatedBy: 'admin1', auditId })));
  });
  test('content manager publishes an announcement', async () => {
    await assertSucceeds(audited('cm1', (b, db, auditId) => b.set(doc(db, 'announcements/a1'), { ...ann('a1'), updatedBy: 'cm1', auditId })));
  });
  test('admin grants another user a role', async () => {
    await assertSucceeds(audited('admin1', (b, db, auditId) =>
      b.set(doc(db, 'admins/cm2'), { email: 'n@x.test', role: 'contentManager', updatedBy: 'admin1', auditId })));
  });
});

describe('Denied operations', () => {
  test('unauthenticated users cannot read rooms, exams or students', async () => {
    await assertFails(getDoc(doc(anon(), 'rooms/CR-402')));
    await assertFails(getDoc(doc(anon(), 'exams/pub')));
    await assertFails(getDoc(doc(anon(), 'students/active1')));
  });
  test('pending (unapproved) student cannot read timetables or exams', async () => {
    const db = as('pending1');
    await assertFails(getDoc(doc(db, 'timetableVersions/pub')));
    await assertFails(studentQuery('pending1', 'exams', ['all', `group:${GROUP}`]));
  });
  test('active student cannot read drafts, or query without the published filter', async () => {
    const db = as('active1');
    await assertFails(getDoc(doc(db, 'timetableVersions/draft')));
    await assertFails(getDoc(doc(db, 'exams/draft')));
    await assertFails(getDoc(doc(db, 'announcements/draft')));
    await assertFails(getDocs(collection(db, 'exams')));
  });
  test('student cannot approve themselves, change group, or self-register as active', async () => {
    await assertFails(updateDoc(doc(as('pending1'), 'students/pending1'), { status: 'active' }));
    await assertFails(updateDoc(doc(as('active1'), 'students/active1'), { groupId: GROUP_C }));
    await assertFails(register(verified('sneaky'), 'sneaky', '99999388888', { status: 'active', groupId: GROUP }));
  });
  test('a SAP ID already claimed by someone else cannot be registered again', async () => {
    const db = verified('thief');
    await assertFails(register(db, 'thief', '99999300001'));
    await assertFails(setDoc(doc(db, 'sapIndex/99999300001'), { uid: 'thief' }));
    await assertFails(setDoc(doc(db, 'students/thief'), profile('thief', '99999300001')));
  });
  test('student cannot read another student or list the SAP index', async () => {
    await assertFails(getDoc(doc(as('active1'), 'students/pending1')));
    await assertFails(getDocs(collection(as('active1'), 'sapIndex')));
  });
  test('student cannot grant themselves admin or write academic data, even with an audit record', async () => {
    await assertFails(audited('active1', (b, db, auditId) => b.set(doc(db, 'admins/active1'), { email: 'me@x.test', role: 'admin', updatedBy: 'active1', auditId })));
    await assertFails(audited('active1', (b, db, auditId) => b.set(doc(db, 'exams/fake'), { ...exam([GROUP]), updatedBy: 'active1', auditId })));
    await assertFails(audited('active1', (b, db, auditId) =>
      b.set(doc(db, 'timetableVersions/fake'), { groupId: GROUP, status: 'published', entries: [], effectiveFrom: '2026-07-13', updatedBy: 'active1', auditId })));
  });
  test('content manager cannot touch timetables, rooms or roles, even with an audit record', async () => {
    await assertFails(audited('cm1', (b, db, auditId) =>
      b.set(doc(db, 'timetableVersions/x'), { groupId: GROUP, status: 'draft', entries: [], effectiveFrom: '2026-07-13', updatedBy: 'cm1', auditId })));
    await assertFails(audited('cm1', (b, db, auditId) => b.set(doc(db, 'rooms/CR-999'), { name: 'X', updatedBy: 'cm1', auditId })));
    await assertFails(audited('cm1', (b, db, auditId) => b.set(doc(db, 'admins/someone'), { email: 's@x.test', role: 'admin', updatedBy: 'cm1', auditId })));
  });
  test('admin cannot change or remove their own role', async () => {
    await assertFails(audited('admin1', (b, db, auditId) =>
      b.set(doc(db, 'admins/admin1'), { email: 'a@x.test', role: 'contentManager', updatedBy: 'admin1', auditId })));
    await assertFails(deleteDoc(doc(verified('admin1'), 'admins/admin1')));
  });
  test('writes must be stamped with the real actor; invalid status values are rejected', async () => {
    await assertFails(audited('admin1', (b, db, auditId) => b.set(doc(db, 'exams/x'), { ...exam([GROUP]), updatedBy: 'someone-else', auditId })));
    await assertFails(audited('admin1', (b, db, auditId) => b.set(doc(db, 'exams/y'), { ...exam([GROUP]), status: 'live', updatedBy: 'admin1', auditId })));
  });
  test('audit log is append-only and cannot be forged', async () => {
    const db = verified('admin1');
    await assertFails(updateDoc(doc(db, 'auditLogs/log1'), { action: 'changed' }));
    await assertFails(deleteDoc(doc(db, 'auditLogs/log1')));
    await assertFails(setDoc(doc(collection(db, 'auditLogs')), { actorUid: 'cm1', actorEmail: emailOf('cm1'), action: 'forged' }));
  });
});

// H1: SAP ID claims cannot be squatted in bulk, and admins can recover them.
describe('SAP ID claims (H1)', () => {
  test('an unverified account cannot claim a SAP ID or create a profile', async () => {
    await assertFails(register(unverified('fresh'), 'fresh', '99999311111'));
    await assertFails(getDoc(doc(unverified('fresh'), 'sapIndex/99999311111')));
  });
  test('a claim cannot exist without the profile of its claimant', async () => {
    await assertFails(setDoc(doc(verified('squatter'), 'sapIndex/99999311112'), { uid: 'squatter' }));
  });
  test('one registration cannot claim two SAP IDs', async () => {
    const db = verified('greedy');
    const b = writeBatch(db);
    b.set(doc(db, 'sapIndex/99999311113'), { uid: 'greedy' });
    b.set(doc(db, 'sapIndex/99999311114'), { uid: 'greedy' });
    b.set(doc(db, 'students/greedy'), profile('greedy', '99999311113'));
    await assertFails(b.commit());
  });
  test('an account that already has a profile cannot claim another SAP ID', async () => {
    await assertFails(setDoc(doc(verified('active1'), 'sapIndex/99999311115'), { uid: 'active1' }));
    await assertFails(updateDoc(doc(verified('active1'), 'students/active1'), { sapId: '99999311115' }));
  });
  test('a claim cannot be made on behalf of another account', async () => {
    const db = verified('mallory');
    const b = writeBatch(db);
    b.set(doc(db, 'sapIndex/99999311116'), { uid: 'victim' });
    b.set(doc(db, 'students/mallory'), profile('mallory', '99999311116'));
    await assertFails(b.commit());
  });
  test('claims cannot be transferred, even by an admin', async () => {
    await assertFails(setDoc(doc(verified('admin1'), 'sapIndex/99999300001'), { uid: 'admin1' }));
  });
  test('recovery: admin suspends the claimant and releases the SAP ID; the real student can then register', async () => {
    await assertSucceeds(register(verified('squatter'), 'squatter', '99999322222'));
    await assertFails(register(verified('owner'), 'owner', '99999322222'));
    await assertSucceeds(release('squatter', '99999322222'));
    await assertSucceeds(register(verified('owner'), 'owner', '99999322222'));
  });
  test('recovery is admin-only and cannot leave the claimant active', async () => {
    await assertFails(deleteDoc(doc(verified('admin1'), 'sapIndex/99999300001'))); // holder still active
    await assertFails(deleteDoc(doc(verified('cm1'), 'sapIndex/99999300002')));
    await assertFails(deleteDoc(doc(verified('pending1'), 'sapIndex/99999300002')));
    await assertFails(release('pending1', '99999300002', { as: 'cm1' }));
  });
  test('a released claimant cannot be re-activated or claim again', async () => {
    await assertSucceeds(release('pending1', '99999300002'));
    await assertFails(audited('admin1', (b, db, auditId) =>
      b.update(doc(db, 'students/pending1'), { status: 'active', groupId: GROUP, updatedBy: 'admin1', auditId })));
    await assertFails(audited('admin1', (b, db, auditId) => b.update(doc(db, 'students/pending1'), { sapReleased: false, updatedBy: 'admin1', auditId })));
    await assertFails(register(verified('pending1'), 'pending1', '99999300002'));
  });
});

// F1: a release may only delete the claim held by the student being released.
describe('SAP ID release ownership (F1)', () => {
  // State after an earlier, correct release: the squatter is suspended and
  // marked released; the rightful owner registered and now holds the SAP ID.
  const S = '99999355555';
  const staleSetup = (ownerStatus, squatterReleased = true) => env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'students/squatter'), { ...profile('squatter', S), createdAt: '2026-10-01', status: 'suspended', ...(squatterReleased ? { sapReleased: true } : {}) });
    await setDoc(doc(db, 'students/owner'), { ...profile('owner', S), createdAt: '2026-10-02', status: ownerStatus });
    await setDoc(doc(db, `sapIndex/${S}`), { uid: 'owner' });
  });
  test('REGRESSION (audit probe B): a stale squatter card cannot release the claim of the suspended rightful owner (exact probe B)', async () => {
    await staleSetup('suspended');
    await assertFails(release('squatter', S));
    // Without the update to the (already released) squatter, the delete alone is also refused.
    await assertFails(deleteDoc(doc(verified('admin1'), `sapIndex/${S}`)));
  });
  test('stale card is refused whether or not the squatter was marked before, and whatever the status of the owner', async () => {
    for (const [ownerStatus, marked] of [['suspended', false], ['pending', true], ['active', true]]) {
      await staleSetup(ownerStatus, marked);
      await assertFails(release('squatter', S));
    }
  });
  test('mismatched owner: marking student A released while deleting the claim of student B is refused', async () => {
    await assertFails(release('pending1', '99999300001')); // claim belongs to active1
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'students/active1'), { status: 'suspended' }));
    await assertFails(release('pending1', '99999300001')); // still refused when the real holder is suspended
  });
  test('missing claim: nothing can be released or marked', async () => {
    await env.withSecurityRulesDisabled((c) => deleteDoc(doc(c.firestore(), 'sapIndex/99999300002')));
    await assertFails(release('pending1', '99999300002'));
    await assertFails(audited('admin1', (b, db, auditId) =>
      b.update(doc(db, 'students/pending1'), { status: 'suspended', sapReleased: true, updatedBy: 'admin1', auditId })));
  });
  test('valid release through the same read-then-write transaction as FirestoreRepository.releaseSapId', async () => {
    const db = verified('admin1');
    await assertSucceeds(runTransaction(db, async (tx) => {
      const student = await tx.get(doc(db, 'students/pending1'));
      const claim = await tx.get(doc(db, `sapIndex/${student.data().sapId}`));
      if (claim.data().uid !== 'pending1') throw new Error('test setup: claim not held');
      const audit = doc(collection(db, 'auditLogs'));
      tx.update(student.ref, { status: 'suspended', sapReleased: true, updatedBy: 'admin1', auditId: audit.id });
      tx.delete(claim.ref);
      tx.set(audit, { actorUid: 'admin1', actorEmail: emailOf('admin1'), action: 'student.releaseSapId' });
    }));
    let after;
    await env.withSecurityRulesDisabled(async (c) => {
      after = [
        (await getDoc(doc(c.firestore(), 'students/pending1'))).data(),
        (await getDoc(doc(c.firestore(), 'sapIndex/99999300002'))).exists(),
      ];
    });
    if (after[0].status !== 'suspended' || after[0].sapReleased !== true || after[1]) throw new Error('unexpected state ' + JSON.stringify(after));
  });
  test('already released: a repeated release is refused and changes nothing', async () => {
    await assertSucceeds(release('pending1', '99999300002'));
    await assertFails(release('pending1', '99999300002'));
  });
  test('the release marker cannot be set without deleting the claim, while leaving the student active, or by the student', async () => {
    await assertFails(audited('admin1', (b, db, auditId) =>
      b.update(doc(db, 'students/pending1'), { status: 'suspended', sapReleased: true, updatedBy: 'admin1', auditId }))); // claim kept
    await assertFails(release('active1', '99999300001', { status: 'active' }));
    await assertFails(updateDoc(doc(verified('pending1'), 'students/pending1'), { sapReleased: true }));
    await assertFails(register(verified('newbie'), 'newbie', '99999366666', { sapReleased: true }));
  });
});

// H2: profiles contain only allowed, validated fields and the verified sign-in email.
describe('Student identity fields (H2)', () => {
  test('the stored email must be the verified sign-in email', async () => {
    await assertFails(register(verified('spoof'), 'spoof', '99999333331', { email: 'principal@college.example' }));
  });
  test('unknown fields, a foreign uid, or missing fields are rejected', async () => {
    await assertFails(register(verified('x1'), 'x1', '99999333332', { role: 'admin' }));
    await assertFails(register(verified('x2'), 'x2', '99999333333', { uid: 'someone-else' }));
    const db = verified('x3');
    const { requestedGroupId, ...missing } = profile('x3', '99999333334');
    const b = writeBatch(db);
    b.set(doc(db, 'sapIndex/99999333334'), { uid: 'x3' });
    b.set(doc(db, 'students/x3'), missing);
    await assertFails(b.commit());
  });
  test('malformed values are rejected', async () => {
    const bad = [
      { displayName: 'x'.repeat(51) }, { displayName: 'R2-D2' }, { displayName: 'A' },
      { rollNumber: 'b050' }, { rollNumber: 'B05' },
      { requestedGroupId: 'no-such-group' }, { requestedGroupId: 'oe1-pool' },
      { batch: 'B1-very-long-batch' }, { batch: { not: 'a string' } }, { avatar: 'Fox!' },
      { createdAt: '2026-01-01T00:00:00Z' },
    ];
    for (const [i, o] of bad.entries()) {
      await assertFails(register(verified(`bad${i}`), `bad${i}`, `700223444${String(i).padStart(2, '0')}`, o));
    }
    await assertFails(register(verified('bad-sap'), 'bad-sap', '7002A344499'));
  });
  test('self-edits must stay valid', async () => {
    const db = verified('active1');
    await assertSucceeds(updateDoc(doc(db, 'students/active1'), { displayName: "Priya D'Souza", avatar: 'owl', batch: 'B2' }));
    await assertFails(updateDoc(doc(db, 'students/active1'), { displayName: 'y'.repeat(5000) }));
    await assertFails(updateDoc(doc(db, 'students/active1'), { batch: { not: 'a string' } }));
    await assertFails(updateDoc(doc(db, 'students/active1'), { email: 'other@x.test' }));
  });
});

// H3: publication status is explicit; events without one are never shown to students.
describe('Calendar publication status (H3)', () => {
  test('students see published events through the status-filtered query, never ones without a status', async () => {
    const snap = await getDocs(query(collection(as('active1'), 'calendarEvents'), where('status', '==', 'published')));
    if (snap.docs.map((d) => d.id).join() !== 'pub') throw new Error('unexpected events: ' + snap.docs.map((d) => d.id));
    await assertFails(getDoc(doc(as('active1'), 'calendarEvents/nostatus')));
  });
  test('staff cannot save an event with a missing or invalid status', async () => {
    const ev = { title: 'X', start: '2026-12-01', end: '2026-12-01', updatedBy: 'cm1' };
    await assertFails(audited('cm1', (b, db, auditId) => b.set(doc(db, 'calendarEvents/a'), { ...ev, auditId })));
    await assertFails(audited('cm1', (b, db, auditId) => b.set(doc(db, 'calendarEvents/b'), { ...ev, status: 'live', auditId })));
    await assertSucceeds(audited('cm1', (b, db, auditId) => b.set(doc(db, 'calendarEvents/c'), { ...ev, status: 'draft', auditId })));
  });
});

// M2: group-targeted announcements and exams are readable only by their audience.
describe('Audience enforcement (M2)', () => {
  test('a student sees exactly the announcements for everyone, their group and their department', async () => {
    const snap = await assertSucceeds(studentQuery('active1', 'announcements'));
    if (ids(snap) !== 'all,dept,divB') throw new Error('unexpected: ' + ids(snap));
    const c = await assertSucceeds(studentQuery('activeC', 'announcements'));
    if (ids(c) !== 'all,dept,divC') throw new Error('unexpected for Div C: ' + ids(c));
  });
  test('a student cannot read another group by id, by asking for its key, or without an audience filter', async () => {
    await assertFails(getDoc(doc(as('active1'), 'announcements/divC')));
    await assertSucceeds(getDoc(doc(as('active1'), 'announcements/divB')));
    await assertFails(studentQuery('active1', 'announcements', ['all', `group:${GROUP_C}`]));
    await assertFails(getDocs(query(collection(as('active1'), 'announcements'), where('status', '==', 'published'))));
  });
  test('exams: own group and chosen elective only; unlinked and other-group exams stay hidden', async () => {
    const snap = await assertSucceeds(studentQuery('active1', 'exams'));
    if (ids(snap) !== 'oe,pub') throw new Error('unexpected: ' + ids(snap));
    for (const id of ['divC', 'unlinked']) await assertFails(getDoc(doc(as('active1'), `exams/${id}`)));
    await assertFails(getDoc(doc(as('activeC'), 'exams/oe')), 'Div C student did not choose that elective');
  });
  test('staff still read everything, without an audience filter', async () => {
    await assertSucceeds(getDocs(collection(as('cm1'), 'announcements')));
    await assertSucceeds(getDocs(collection(as('cm1'), 'exams')));
  });
  test('audienceKeys must agree with the audience fields', async () => {
    const save = (id, data) => audited('cm1', (b, db, auditId) => b.set(doc(db, `announcements/${id}`), { ...ann(id), ...data, updatedBy: 'cm1', auditId }));
    await assertFails(save('k1', { audience: { scope: 'groups', ids: [GROUP] }, audienceKeys: ['all'] }));
    await assertFails(save('k2', { audienceKeys: [`group:${GROUP}`] })); // scope all
    await assertFails(save('k3', { audience: { scope: 'groups', ids: [GROUP] }, audienceKeys: [] }));
    await assertSucceeds(save('k4', forGroup(GROUP)));
    const saveExam = (data) => audited('cm1', (b, db, auditId) => b.set(doc(db, 'exams/e1'), { ...exam([GROUP]), ...data, updatedBy: 'cm1', auditId }));
    await assertFails(saveExam({ audienceKeys: [] }));
    await assertFails(saveExam({ audienceKeys: ['all'] }));
    await assertSucceeds(saveExam({}));
  });
});

// M3: announcements contain only known, bounded fields.
describe('Announcement validation (M3)', () => {
  const save = (id, data) => audited('cm1', (b, db, auditId) => b.set(doc(db, `announcements/${id}`), { ...ann(id), ...data, updatedBy: 'cm1', auditId }));
  test('a complete, valid announcement is accepted', async () => {
    await assertSucceeds(save('ok', {
      summary: 's'.repeat(200), description: 'd'.repeat(5000), registrationUrl: 'https://example.org/register',
      imageUrl: 'https://example.org/i.png', startDate: '2026-10-30', endDate: '2026-11-05', source: 'Dept notice',
    }));
  });
  test('unsafe or oversized values are rejected', async () => {
    const bad = [
      { registrationUrl: 'javascript:alert(1)' }, { imageUrl: 'ftp://example.org/i.png' }, { registrationUrl: 'https://a b.org' },
      { registrationUrl: 'https://example.org/' + 'a'.repeat(2040) },
      { description: 'd'.repeat(5001) }, { summary: 's'.repeat(201) }, { source: 'x'.repeat(301) },
      { category: 'spam' }, { startDate: '30/10/2026' }, { title: '' }, { title: 't'.repeat(141) },
      { extra: 'field' }, { audience: { scope: 'everyone', ids: [] } }, { reviewFlags: 'not a list' },
    ];
    for (const [i, o] of bad.entries()) await assertFails(save(`bad${i}`, o));
  });
  test('the stored id must match the document id (no writes to a different document)', async () => {
    await assertFails(save('x', { id: 'y' }));
  });
});

// M4: staff writes must create their audit record in the same commit, with the real actor.
describe('Audit enforcement (M4)', () => {
  test('a content write without an audit record is rejected', async () => {
    await assertFails(setDoc(doc(verified('cm1'), 'announcements/n1'), { ...ann('n1'), updatedBy: 'cm1' }));
    await assertFails(setDoc(doc(verified('cm1'), 'announcements/n2'), { ...ann('n2'), updatedBy: 'cm1', auditId: 'missingAudit123' }));
  });
  test('an existing (older) audit record cannot be reused', async () => {
    await assertFails(setDoc(doc(verified('admin1'), 'announcements/n3'), { ...ann('n3'), updatedBy: 'admin1', auditId: 'log1' }));
  });
  test('the audit record must name the real actor and their real email', async () => {
    const write = (fields) => audited('cm1', (b, db, auditId) => b.set(doc(db, 'announcements/n4'), { ...ann('n4'), updatedBy: 'cm1', auditId }), fields);
    await assertFails(write({ actorEmail: 'admin@campussync.test' }));
    await assertFails(write({ actorUid: 'admin1' }));
    await assertSucceeds(write({}));
  });
  test('student approval and role changes need an audit record too', async () => {
    await assertFails(updateDoc(doc(verified('admin1'), 'students/pending1'), { status: 'active', groupId: GROUP, updatedBy: 'admin1' }));
    await assertFails(setDoc(doc(verified('admin1'), 'admins/cm3'), { email: 'x@x.test', role: 'contentManager', updatedBy: 'admin1' }));
  });
});

// L1: published and archived timetable versions are frozen.
describe('Timetable version immutability (L1)', () => {
  const upd = (id, data) => audited('admin1', (b, db, auditId) => b.update(doc(db, `timetableVersions/${id}`), { ...data, updatedBy: 'admin1', auditId }));
  test('the content of a published or archived version cannot change', async () => {
    await assertFails(upd('pub', { entries: [{ x: 1 }] }));
    await assertFails(upd('old', { effectiveFrom: '2026-08-01' }));
    await assertFails(upd('pub', { status: 'archived', entries: [{ x: 1 }] }));
  });
  test('a published version cannot go back to draft (which would make it editable)', async () => {
    await assertFails(upd('pub', { status: 'draft' }));
  });
  test('publish, archive and roll back move only the status', async () => {
    await assertSucceeds(upd('pub', { status: 'archived', updatedAt: '2026-10-21T00:00:00Z' }));
    await assertSucceeds(upd('old', { status: 'published', publishedBy: 'admin1@campussync.test', publishedAt: '2026-10-21T00:00:00Z' }));
  });
  test('drafts stay fully editable', async () => {
    await assertSucceeds(upd('draft', { entries: [{ x: 1 }], effectiveFrom: '2026-07-20' }));
    await assertSucceeds(upd('draft', { status: 'published' }));
  });
});

// L2: removing administrators can never leave the project without one.
describe('Administrator removal (L2)', () => {
  test('an admin cannot remove or demote themselves', async () => {
    await assertFails(deleteDoc(doc(verified('admin1'), 'admins/admin1')));
    await assertFails(audited('admin1', (b, db, auditId) => b.set(doc(db, 'admins/admin1'), { email: 'a@x.test', role: 'contentManager', updatedBy: 'admin1', auditId })));
  });
  test('after one admin removes another, the removed one can no longer remove the remover', async () => {
    await assertSucceeds(deleteDoc(doc(verified('admin1'), 'admins/admin2')));
    await assertFails(deleteDoc(doc(verified('admin2'), 'admins/admin1')));
  });
  test('after a demotion, the demoted admin can no longer demote or remove the other', async () => {
    await assertSucceeds(audited('admin1', (b, db, auditId) => b.set(doc(db, 'admins/admin2'), { email: 'b@x.test', role: 'contentManager', updatedBy: 'admin1', auditId })));
    await assertFails(audited('admin2', (b, db, auditId) => b.set(doc(db, 'admins/admin1'), { email: 'a@x.test', role: 'contentManager', updatedBy: 'admin2', auditId })));
    await assertFails(deleteDoc(doc(verified('admin2'), 'admins/admin1')));
  });
});

// L3: only recognised roles grant staff access.
describe('Admin role values (L3)', () => {
  test('a mistyped or missing role grants no staff access', async () => {
    for (const uid of ['typo1', 'norole1']) {
      await assertFails(getDoc(doc(verified(uid), 'rooms/CR-402')));
      await assertFails(getDoc(doc(verified(uid), 'announcements/draft')));
      await assertFails(getDocs(collection(verified(uid), 'auditLogs')));
      await assertFails(audited(uid, (b, db, auditId) => b.set(doc(db, `announcements/${uid}`), { ...ann(uid), updatedBy: uid, auditId })));
      await assertFails(getDocs(collection(verified(uid), 'students')));
    }
  });
  test('recognised roles keep their access', async () => {
    await assertSucceeds(getDoc(doc(verified('cm1'), 'announcements/draft')));
    await assertSucceeds(getDocs(collection(verified('admin1'), 'students')));
  });
});
