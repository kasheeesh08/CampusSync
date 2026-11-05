// Creates clearly labelled TEST student accounts in the Auth/Firestore
// emulators (never a real project). Uses the emulator "owner" bypass only for
// setup; every check afterwards uses the student's own ID token.
import { AUTH, FS } from './env.mjs';

async function signUp(email, password) {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const j = await r.json();
  if (j.localId) return j.localId;
  // Already exists: sign in instead.
  const s = await (await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
  })).json();
  return s.localId;
}

async function ownerPut(path, fields) {
  const toV = (v) => (v === null ? { nullValue: null } : { stringValue: v });
  const r = await fetch(`${FS}/${path}`, {
    method: 'PATCH', headers: { 'content-type': 'application/json', authorization: 'Bearer owner' },
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, toV(v)])) }),
  });
  if (!r.ok) throw new Error(`${path}: ${r.status}`);
}

const accounts = [
  { email: 'test.divb@campussync.test', name: 'TEST Div B Student', sap: '99999399001', roll: 'B901', group: 'btech-computer-2026-27-sem5-div-b', batch: 'B1', status: 'active' },
  { email: 'test.divc@campussync.test', name: 'TEST Div C Student', sap: '99999399002', roll: 'C902', group: 'btech-computer-2026-27-sem5-div-c', batch: 'C1', status: 'active' },
  { email: 'test.pending@campussync.test', name: 'TEST Pending Student', sap: '99999399003', roll: 'B903', group: null, batch: 'B2', status: 'pending', requested: 'btech-computer-2026-27-sem5-div-b' },
];
for (const a of accounts) {
  const uid = await signUp(a.email, 'Student12345');
  // Emulator-only admin call: mark the TEST account's email as verified.
  await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:update`, {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer owner' },
    body: JSON.stringify({ localId: uid, emailVerified: true }),
  });
  await ownerPut(`students/${uid}`, {
    uid, email: a.email, displayName: a.name, sapId: a.sap, rollNumber: a.roll, status: a.status,
    groupId: a.group, requestedGroupId: a.requested ?? a.group, batch: a.batch, avatar: 'owl',
  });
  await ownerPut(`sapIndex/${a.sap}`, { uid });
  console.log(`${a.status.padEnd(7)} ${a.email} uid=${uid}`);
}
console.log('password for all: Student12345');
