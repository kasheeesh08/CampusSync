// Creates the FIRST administrator, separately from data seeding. Further
// admins and content managers are granted from the admin dashboard.
//
// Safeguards: the account must already exist in Firebase Authentication with a
// verified email; the stored email is read from Authentication (not typed);
// it refuses if any admin or content manager already exists; and a live
// project must be confirmed by repeating its id.
//
//   node bootstrap_admin.mjs --project <id> --uid <uid> --dry-run        (offline preview)
//   node bootstrap_admin.mjs --project <your-project-id> --uid <uid> --confirm-live <your-project-id>
//
// Credentials for a live project: GOOGLE_APPLICATION_CREDENTIALS (key file kept
// outside the repo) or `gcloud auth application-default login`.
// No credentials? Use the Firebase Console instead (docs/DEPLOYMENT.md §3).
import { checkTarget } from './seed_lib.mjs';

const args = process.argv.slice(2);
const flag = (name) => args.indexOf(name);
const value = (name) => (flag(name) >= 0 ? args[flag(name) + 1] : null);
const projectId = value('--project');
const uidArg = value('--uid');
const emailArg = value('--email'); // alternative to --uid: looks the account up in Authentication

const validUid = !!uidArg && /^[A-Za-z0-9]{6,128}$/.test(uidArg);
const validEmail = !!emailArg && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailArg);
if (!projectId || validUid === validEmail) {
  console.error('Usage: node bootstrap_admin.mjs --project <id> (--uid <Firebase Auth UID> | --email <verified sign-in email>) [--dry-run] [--confirm-live <id>]');
  process.exit(2);
}
const who = uidArg ?? emailArg;
if (flag('--dry-run') >= 0) {
  console.log(`DRY RUN: would make ${who} the first admin of ${projectId} if that account exists with a verified email`);
  console.log('and no admin or content manager exists yet. Nothing is written and no connection is made.');
  process.exit(0);
}

const target = checkTarget({ projectId, env: process.env, confirmLive: value('--confirm-live'), needsAuth: true });
const { initializeApp, applicationDefault } = await import('firebase-admin/app');
const { getAuth } = await import('firebase-admin/auth');
const { getFirestore, FieldValue } = await import('firebase-admin/firestore');
initializeApp(target === 'emulator' ? { projectId } : { credential: applicationDefault(), projectId });
const db = getFirestore();

const fail = (msg) => {
  console.error(`Refused: ${msg}`);
  process.exit(1);
};
let user;
try {
  user = uidArg ? await getAuth().getUser(uidArg) : await getAuth().getUserByEmail(emailArg);
} catch {
  fail(`no Firebase Authentication account for ${who}. Register or add the user first.`);
}
if (!user.email || !user.emailVerified) fail('the account email is not verified. Verify it first.');
if (user.disabled) fail('the account is disabled.');
const uid = user.uid;

const adminRef = db.collection('admins').doc(uid);
await db.runTransaction(async (tx) => {
  const existing = await tx.get(db.collection('admins').limit(1));
  if (!existing.empty) fail('an administrator already exists. Grant further roles from the admin dashboard.');
  tx.create(adminRef, { email: user.email, role: 'admin', updatedBy: 'bootstrap-admin' });
  tx.create(db.collection('auditLogs').doc(), {
    actorUid: 'bootstrap-admin', actorEmail: 'bootstrap-admin', action: 'admin.bootstrap', targetPath: `admins/${uid}`,
    summary: user.email, at: new Date().toISOString(), serverAt: FieldValue.serverTimestamp(),
  });
});
console.log(`First administrator created for ${user.email} (${target}).`);
