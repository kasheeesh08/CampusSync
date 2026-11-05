// Seed / first-admin safeguards.
//   cd firebase && npm run test:seed      (unit checks + Local Emulator Suite integration)
//   node --test test/seed.test.mjs        (unit checks only; integration is skipped)
// "Live" refusals use a fictitious project id, so nothing here can reach a real project.
import { execFileSync, spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  NEVER_SEEDED, checkTarget, loadAnnouncementDrafts, loadPlan, splitExisting, validateAnnouncementDrafts, validatePlan,
} from '../seed_lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const SEED_DIR = join(root, '..', 'app', 'assets', 'seed');
const FAKE_LIVE = 'campussync-not-a-real-project';
const EMU = { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' };

/** Runs a script with all emulator/credential variables removed (a "live" environment). */
function runLive(script, args) {
  const env = { ...process.env };
  for (const k of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST', 'GOOGLE_APPLICATION_CREDENTIALS', 'GCLOUD_PROJECT']) delete env[k];
  return spawnSync(process.execPath, [join(root, script), ...args], { env, encoding: 'utf8' });
}

describe('target safety (no emulator needed)', () => {
  test('live writes require --confirm-live repeating the project id', () => {
    assert.throws(() => checkTarget({ projectId: FAKE_LIVE }), /without --confirm-live/);
    assert.throws(() => checkTarget({ projectId: FAKE_LIVE, confirmLive: 'other-project' }), /without --confirm-live/);
    assert.equal(checkTarget({ projectId: FAKE_LIVE, confirmLive: FAKE_LIVE }), 'live');
  });
  test('emulator mode only for local hosts, never mixed with --confirm-live', () => {
    assert.equal(checkTarget({ projectId: 'demo-x', env: EMU, needsAuth: true }), 'emulator');
    assert.throws(() => checkTarget({ projectId: 'demo-x', env: { FIRESTORE_EMULATOR_HOST: '10.1.2.3:8080' } }), /this machine/);
    assert.throws(() => checkTarget({ projectId: 'demo-x', env: { ...EMU, FIREBASE_AUTH_EMULATOR_HOST: 'example.com:9099' }, needsAuth: true }), /this machine/);
    assert.throws(() => checkTarget({ projectId: FAKE_LIVE, env: EMU, confirmLive: FAKE_LIVE }), /cannot be combined/);
    assert.throws(() => checkTarget({ projectId: 'demo-x' }), /emulator-only/);
  });
  test('seed plan contains no announcements, provenance, accounts or roles', () => {
    const plan = loadPlan(SEED_DIR);
    for (const c of NEVER_SEEDED) assert.equal(plan.collections[c], undefined, c);
    validatePlan(plan);
    assert.equal(plan.collections.calendarEvents.length, 27);
    assert.ok(plan.collections.calendarEvents.every((e) => e.status === 'published'));
  });
  test('seed data with missing/invalid status, duplicate ids or forbidden collections is rejected', () => {
    const ev = { id: 'e1', title: 'X', start: '2026-11-06', end: '2026-11-12' };
    assert.throws(() => validatePlan({ collections: { calendarEvents: [ev] } }), /calendarEvents\/e1: status/);
    assert.throws(() => validatePlan({ collections: { exams: [{ id: 'x', status: 'live' }] } }), /status/);
    assert.throws(() => validatePlan({ collections: { rooms: [{ id: 'a' }, { id: 'a' }] } }), /duplicate/);
    assert.throws(() => validatePlan({ collections: { announcements: [{ id: 'a', status: 'draft' }] } }), /not a seedable/);
  });
  test('announcement drafts are opt-in, drafts only, and carry audience keys', () => {
    const drafts = loadAnnouncementDrafts(SEED_DIR);
    assert.equal(drafts.length, 3);
    validateAnnouncementDrafts(drafts);
    assert.ok(drafts.every((a) => a.status === 'draft' && JSON.stringify(a.audienceKeys) === '["all"]' && Array.isArray(a.audience.ids)));
    assert.throws(() => validateAnnouncementDrafts([{ ...drafts[0], status: 'published' }]), /only drafts/);
    let r = runLive('seed_firestore.mjs', ['--project', FAKE_LIVE, '--dry-run']);
    assert.doesNotMatch(r.stdout, /UNPUBLISHED drafts/);
    r = runLive('seed_firestore.mjs', ['--project', FAKE_LIVE, '--dry-run', '--include-announcement-drafts']);
    assert.match(r.stdout, /announcements: 3 UNPUBLISHED drafts/);
  });
  test('existing documents are skipped, never overwritten', () => {
    const r = splitExisting([{ id: 'a' }, { id: 'b' }], new Set(['a']));
    assert.deepEqual(r.create.map((d) => d.id), ['b']);
    assert.deepEqual(r.skip.map((d) => d.id), ['a']);
  });
  test('CLI refuses live writes and removed/unsafe flags before connecting', () => {
    let r = runLive('seed_firestore.mjs', ['--project', FAKE_LIVE]);
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /without --confirm-live/);
    r = runLive('seed_firestore.mjs', ['--project', FAKE_LIVE, '--admin', 'uid', 'a@b.c']);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /bootstrap_admin\.mjs/);
    r = runLive('seed_firestore.mjs', ['--project', FAKE_LIVE, '--confirm-live', FAKE_LIVE, '--emulator-test-users']);
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /only allowed against the Local Emulator Suite/);
    r = runLive('bootstrap_admin.mjs', ['--project', FAKE_LIVE, '--uid', 'abcdefgh123']);
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /without --confirm-live/);
  });
  test('dry runs write nothing, need no credentials and list what is never seeded', () => {
    let r = runLive('seed_firestore.mjs', ['--project', FAKE_LIVE, '--dry-run']);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /nothing is written/);
    assert.match(r.stdout, /never seeded: announcements, importJobs/);
    r = runLive('bootstrap_admin.mjs', ['--project', FAKE_LIVE, '--uid', 'abcdefgh123', '--dry-run']);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /Nothing is written/);
  });
});

const onEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
describe('against the Local Emulator Suite', { skip: !onEmulator && 'emulator hosts not set (use npm run test:seed)' }, () => {
  const PROJECT = 'demo-campussync-seed';
  const node = (script, args) => spawnSync(process.execPath, [join(root, script), '--project', PROJECT, ...args], { env: process.env, encoding: 'utf8' });
  let db;
  let auth;
  const setup = async () => {
    if (db) return;
    const { initializeApp } = await import('firebase-admin/app');
    initializeApp({ projectId: PROJECT });
    db = (await import('firebase-admin/firestore')).getFirestore();
    auth = (await import('firebase-admin/auth')).getAuth();
  };

  test('re-running the seed keeps administrator edits and never adds announcements', async () => {
    await setup();
    let out = execFileSync(process.execPath, [join(root, 'seed_firestore.mjs'), '--project', PROJECT], { env: process.env, encoding: 'utf8' });
    assert.match(out, /Seed complete: [1-9]\d* created, 0 already present/);
    const room = (await db.collection('rooms').limit(1).get()).docs[0];
    await room.ref.update({ name: 'EDITED BY ADMIN' });
    const exam = (await db.collection('exams').limit(1).get()).docs[0];
    await exam.ref.update({ status: 'archived' });
    out = execFileSync(process.execPath, [join(root, 'seed_firestore.mjs'), '--project', PROJECT], { env: process.env, encoding: 'utf8' });
    assert.match(out, /Seed complete: 0 created/);
    assert.equal((await room.ref.get()).data().name, 'EDITED BY ADMIN');
    assert.equal((await exam.ref.get()).data().status, 'archived');
    assert.equal((await db.collection('announcements').get()).size, 0);
    assert.equal((await db.collection('importJobs').get()).size, 0);
    assert.equal((await db.collection('admins').get()).size, 0, 'seeding never creates administrators');
    const cal = await db.collection('calendarEvents').where('status', '==', 'published').get();
    assert.equal(cal.size, 27);
  });

  test('announcement drafts are imported unpublished, once, only with the flag', async () => {
    await setup();
    const out = execFileSync(process.execPath, [join(root, 'seed_firestore.mjs'), '--project', PROJECT, '--include-announcement-drafts'], { env: process.env, encoding: 'utf8' });
    assert.match(out, /announcements: 3 drafts created/);
    const anns = (await db.collection('announcements').get()).docs.map((d) => d.data());
    assert.equal(anns.length, 3);
    assert.ok(anns.every((a) => a.status === 'draft' && a.audienceKeys?.[0] === 'all'));
    const again = execFileSync(process.execPath, [join(root, 'seed_firestore.mjs'), '--project', PROJECT, '--include-announcement-drafts'], { env: process.env, encoding: 'utf8' });
    assert.match(again, /announcements: 0 drafts created, 3 already present/);
  });

  test('first-admin bootstrap: verified Auth account only, email from Auth, and only once', async () => {
    await setup();
    const u = await auth.createUser({ email: 'first.admin@campussync.test', password: 'Admin12345', emailVerified: false });
    let r = node('bootstrap_admin.mjs', ['--uid', u.uid]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /not verified/);
    r = node('bootstrap_admin.mjs', ['--uid', 'nosuchuser123']);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /no Firebase Authentication account/);
    await auth.updateUser(u.uid, { emailVerified: true });
    r = node('bootstrap_admin.mjs', ['--email', 'first.admin@campussync.test']); // lookup by email
    assert.equal(r.status, 0, r.stderr);
    const admin = (await db.doc(`admins/${u.uid}`).get()).data();
    assert.deepEqual([admin.email, admin.role], ['first.admin@campussync.test', 'admin']);
    const second = await auth.createUser({ email: 'second@campussync.test', password: 'Admin12345', emailVerified: true });
    r = node('bootstrap_admin.mjs', ['--uid', second.uid]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /already exists/);
    assert.equal((await db.doc(`admins/${second.uid}`).get()).exists, false);
  });
});
