// Uploads the validated reference data in app/assets/seed/*.json to Firestore.
// Create-only: documents that already exist are never overwritten, so it is
// safe to re-run and never undoes administrator edits. Announcements, import
// provenance, students and roles are never seeded. The first administrator is
// created separately with bootstrap_admin.mjs.
//
// Preview (offline, no credentials, writes nothing):
//   node seed_firestore.mjs --project <project-id> --dry-run
//
// Local Emulator Suite (never touches a real project):
//   set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 & set FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
//   node seed_firestore.mjs --project demo-campussync [--emulator-test-users]
//
// Live project (Admin SDK credentials from GOOGLE_APPLICATION_CREDENTIALS or
// `gcloud auth application-default login`; never commit key files). The project
// id must be repeated to confirm:
//   node seed_firestore.mjs --project <your-project-id> --confirm-live <your-project-id>
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
//
// --include-announcement-drafts additionally imports the bundled announcements
// as UNPUBLISHED drafts (create-only) for an administrator to review; any
// record that isn't a draft is refused.
import {
  NEVER_SEEDED, checkTarget, loadAnnouncementDrafts, loadPlan, splitExisting, validateAnnouncementDrafts, validatePlan,
} from './seed_lib.mjs';

const args = process.argv.slice(2);
const flag = (name) => args.indexOf(name);
const value = (name) => (flag(name) >= 0 ? args[flag(name) + 1] : null);
const projectId = value('--project');
const dryRun = flag('--dry-run') >= 0;
const testUsers = flag('--emulator-test-users') >= 0;
const includeDrafts = flag('--include-announcement-drafts') >= 0;

if (flag('--admin') >= 0) {
  console.error('--admin was removed. Create the first administrator with bootstrap_admin.mjs (docs/DEPLOYMENT.md).');
  process.exit(2);
}
if (!projectId) {
  console.error('Usage: node seed_firestore.mjs --project <id> [--dry-run] [--confirm-live <id>] [--emulator-test-users]');
  process.exit(2);
}

const seedDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'app', 'assets', 'seed');
const plan = loadPlan(seedDir);
validatePlan(plan);
const drafts = includeDrafts ? loadAnnouncementDrafts(seedDir) : [];
validateAnnouncementDrafts(drafts);

if (dryRun) {
  console.log(`DRY RUN for ${projectId}: nothing is written and no connection is made.`);
  for (const [name, docs] of Object.entries(plan.collections)) console.log(`  ${name}: ${docs.length} (created only if missing)`);
  console.log('  settings/campus: 1 (created only if missing)');
  if (includeDrafts) console.log(`  announcements: ${drafts.length} UNPUBLISHED drafts for admin review (created only if missing)`);
  console.log(`  never seeded: ${NEVER_SEEDED.filter((c) => !(includeDrafts && c === 'announcements')).join(', ')}`);
  process.exit(0);
}

const target = checkTarget({ projectId, env: process.env, confirmLive: value('--confirm-live'), needsAuth: testUsers });
if (testUsers && !(target === 'emulator' && process.env.FIREBASE_AUTH_EMULATOR_HOST && projectId.startsWith('demo-'))) {
  throw new Error('--emulator-test-users is only allowed against the Local Emulator Suite with a demo-* project id.');
}

const { initializeApp, applicationDefault } = await import('firebase-admin/app');
const { getFirestore, FieldValue } = await import('firebase-admin/firestore');
initializeApp(target === 'emulator' ? { projectId } : { credential: applicationDefault(), projectId });
const db = getFirestore();
console.log(`Seeding ${projectId} (${target}); existing documents are kept unchanged.`);

const now = new Date().toISOString();
const meta = { updatedBy: 'seed-script', updatedAt: now };
let batch = db.batch();
let pending = 0;
const flush = async () => {
  if (pending) await batch.commit();
  batch = db.batch();
  pending = 0;
};
// create() fails instead of overwriting if a document appeared meanwhile.
const create = async (ref, data) => {
  batch.create(ref, data);
  if (++pending >= 400) await flush();
};
const existingIds = async (name, ids) => {
  const found = new Set();
  for (let i = 0; i < ids.length; i += 300) {
    const snaps = await db.getAll(...ids.slice(i, i + 300).map((id) => db.collection(name).doc(id)));
    for (const s of snaps) if (s.exists) found.add(s.id);
  }
  return found;
};

let created = 0;
let kept = 0;
const settingsRef = db.collection('settings').doc('campus');
if ((await settingsRef.get()).exists) kept++;
else {
  await create(settingsRef, { ...plan.settings, ...meta });
  created++;
}
for (const [name, docs] of Object.entries(plan.collections)) {
  const { create: toCreate, skip } = splitExisting(docs, await existingIds(name, docs.map((d) => d.id)));
  for (const d of toCreate) await create(db.collection(name).doc(d.id), { ...d, ...meta });
  created += toCreate.length;
  kept += skip.length;
  console.log(`  ${name}: ${toCreate.length} created, ${skip.length} already present (kept)`);
}
if (drafts.length) {
  const { create: toCreate, skip } = splitExisting(drafts, await existingIds('announcements', drafts.map((d) => d.id)));
  for (const d of toCreate) await create(db.collection('announcements').doc(d.id), { ...d, ...meta });
  created += toCreate.length;
  kept += skip.length;
  console.log(`  announcements: ${toCreate.length} drafts created, ${skip.length} already present (kept); none published`);
}

if (testUsers) {
  // Test-only accounts that exist solely inside the local Auth emulator.
  const { getAuth } = await import('firebase-admin/auth');
  const auth = getAuth();
  const ensure = async (email, password) => {
    try { return (await auth.getUserByEmail(email)).uid; } catch { return (await auth.createUser({ email, password, emailVerified: true })).uid; }
  };
  const adminUid = await ensure('admin@campussync.test', 'Admin12345');
  await db.collection('admins').doc(adminUid).set({ email: 'admin@campussync.test', role: 'admin', updatedBy: 'seed-script' });
  const cmUid = await ensure('content@campussync.test', 'Content12345');
  await db.collection('admins').doc(cmUid).set({ email: 'content@campussync.test', role: 'contentManager', updatedBy: 'seed-script' });
  console.log('emulator test users: admin@campussync.test / Admin12345, content@campussync.test / Content12345');
}
if (created) {
  await create(db.collection('auditLogs').doc(), {
    actorUid: 'seed-script', actorEmail: 'seed-script', action: 'seed.import', targetPath: '*',
    summary: `Reference data import: ${created} created, ${kept} kept`, at: now, serverAt: FieldValue.serverTimestamp(),
  });
}
await flush();
console.log(`Seed complete: ${created} created, ${kept} already present and left unchanged.`);
