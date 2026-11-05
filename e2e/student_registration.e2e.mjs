// F. Student registration and SAP ID recovery (Chrome, emulator only).
// Drives the student web app (STUDENT_URL, emulator build) and the admin
// dashboard (ADMIN_URL). Checks that nothing is written before the email is
// verified, that the profile stores the verified sign-in email, that a
// duplicate SAP ID is refused, and that an admin can release a wrongly
// claimed SAP ID so the rightful student can register.
import { launch, click, type, hasText, texts, enableSemantics, reporter, ensureSignedIn, open, sleep, shot, STUDENT_URL } from './lib.mjs';
import { followVerification, get, query } from './api.mjs';

const STUDENT = STUDENT_URL;
const r = reporter('Student registration & SAP ID recovery (Chrome)');
const stamp = Date.now().toString().slice(-5);
const SAP = `999993${stamp}`;
const squatter = { email: `test.squatter.${stamp}@campussync.test`, name: 'TEST Squatter', roll: 'B940' };
const owner = { email: `test.rightful.${stamp}@campussync.test`, name: 'TEST Rightful Owner', roll: 'B941' };
const offline = { email: `test.offline.${stamp}@campussync.test`, name: 'TEST Offline Student', roll: 'B942', sap: `700224${stamp}` };
const PASSWORD = 'Student12345';

async function signUp(page, who) {
  await page.goto(STUDENT, { waitUntil: 'networkidle0', timeout: 60000 });
  await enableSemantics(page);
  await click(page, 'Create student account');
  await type(page, 'Full name', who.name);
  await type(page, 'Email', who.email);
  await type(page, 'SAP ID', who.sap ?? SAP);
  await click(page, 'Academic group');
  await click(page, 'B.Tech Computer · Sem V · Div B', { exact: true });
  await type(page, 'Roll number', who.roll);
  await click(page, 'Lab batch');
  await click(page, 'Batch B1', { exact: true });
  await type(page, 'Password *', PASSWORD);
  await type(page, 'Confirm password', PASSWORD);
  await click(page, 'Create account', { exact: true });
  return hasText(page, 'Verify your email', { timeout: 15000 });
}

async function verifyAndSubmit(page, who) {
  await followVerification(who.email);
  await click(page, 'I have verified');
  const shown = await hasText(page, 'Complete your profile', { timeout: 15000 });
  // Nothing is retyped: the submitted values must come from the sign-up form.
  await click(page, 'Submit for approval', { exact: true });
  return shown;
}

const uidOf = async (email) => (await query('owner', 'students', [['email', email]])).docs[0]?.uid;

const a = await launch();
const b = await launch();
const c = await launch();
try {
  // 1. Account creation writes nothing until the email is verified.
  r.check('RG-01', 'Sign-up shows the verify-email step', await signUp(a.page, squatter));
  r.check('RG-02', 'No profile or SAP ID claim before verification',
    (await query('owner', 'students', [['email', squatter.email]])).docs.length === 0 && (await get('owner', `sapIndex/${SAP}`)).status === 404);

  // 2. After verification the prefilled form submits with the verified email.
  r.check('RG-03', 'After "I have verified" the "Complete your profile" form appears', await verifyAndSubmit(a.page, squatter));
  r.check('RG-04', 'Pending-approval screen shown', await hasText(a.page, 'Waiting for approval', { timeout: 15000 }));
  const sqUid = await uidOf(squatter.email);
  const prof = sqUid && (await get('owner', `students/${sqUid}`)).doc;
  const claim = (await get('owner', `sapIndex/${SAP}`)).doc;
  r.check('RG-05', 'Profile stores the verified sign-in email, pending, with the SAP claim',
    prof?.email === squatter.email && prof?.status === 'pending' && claim?.uid === sqUid, JSON.stringify({ email: prof?.email, status: prof?.status }));
  r.check('RG-05b', 'Submitted values were prefilled from sign-up (nothing retyped)',
    prof?.sapId === SAP && prof?.displayName === squatter.name && prof?.rollNumber === squatter.roll && prof?.batch === 'B1');

  // 3. A second account cannot take the same SAP ID.
  await signUp(b.page, owner);
  await verifyAndSubmit(b.page, owner);
  const refused = (await hasText(b.page, 'This SAP ID is already registered', { timeout: 10000 }))
    && !(await texts(b.page)).some((t) => t.includes('permission-denied')); // no raw rules error shown
  if (!refused) console.log('  visible:', JSON.stringify((await texts(b.page)).slice(0, 15)));
  r.check('RG-06', 'Duplicate SAP ID refused with a clear message', refused);
  r.check('RG-07', 'No profile written for the refused account', !(await uidOf(owner.email)));
  await shot(b.page, 'f0_registration_duplicate_sap');

  // 4. Admin releases the wrongly claimed SAP ID.
  // Emulator web builds keep sessions in memory: navigate once, then sign in.
  await open(a.page, '?section=students');
  await ensureSignedIn(a.page, 'admin@campussync.test', 'Admin12345');
  await type(a.page, 'Search name, SAP ID, roll, email', SAP);
  r.check('RG-08', 'Approval card marks verified vs self-declared details',
    (await hasText(a.page, `Sign-in email (verified): ${squatter.email}`)) && (await hasText(a.page, 'Self-declared, unverified')));
  await shot(a.page, 'f1_admin_identity_labels');
  await click(a.page, 'Release SAP ID', { exact: true });
  await click(a.page, 'Suspend and release', { exact: true });
  await sleep(1500);
  const after = (await get('owner', `students/${sqUid}`)).doc;
  const audit = (await query('owner', 'auditLogs', [['action', 'student.releaseSapId']])).docs;
  r.check('RG-09', 'Release suspends the claimant, frees the SAP ID and is audited',
    after?.status === 'suspended' && (await get('owner', `sapIndex/${SAP}`)).status === 404 && audit.length === 1);

  // 5. The rightful student can now register the SAP ID.
  await click(b.page, 'Submit for approval', { exact: true });
  r.check('RG-10', 'Rightful student registers after the release', await hasText(b.page, 'Waiting for approval', { timeout: 15000 }));
  const ownerUid = await uidOf(owner.email);
  r.check('RG-11', 'SAP ID now claimed by the rightful account', ownerUid && (await get('owner', `sapIndex/${SAP}`)).doc?.uid === ownerUid);

  // 6. Network failure: a clear message, nothing saved, and a retry works.
  await signUp(c.page, offline);
  await followVerification(offline.email);
  await click(c.page, 'I have verified');
  await hasText(c.page, 'Complete your profile', { timeout: 15000 });
  await sleep(2000); // let the post-verification refresh settle before cutting the network
  await c.page.setOfflineMode(true);
  await click(c.page, 'Submit for approval', { exact: true });
  // Offline, the first step to fail may be the token refresh (Auth layer) or the
  // claim check (Firestore layer); both must report a network problem.
  // The message is a short-lived snackbar, so sample often.
  let seen = null;
  const t0 = Date.now();
  while (!seen && Date.now() - t0 < 30000) {
    const t = await texts(c.page);
    seen = t.find((x) => x.includes('Could not reach the server') || x.includes('No internet connection') || x.includes('already registered'));
    if (!seen) await sleep(100);
  }
  console.log('  offline message:', JSON.stringify(seen));
  r.check('RG-12', 'Offline submit shows a network message (not "already registered")',
    !!seen && !seen.includes('already registered'), seen ?? 'no message');
  await c.page.setOfflineMode(false);
  r.check('RG-13', 'Nothing was saved while offline', !(await uidOf(offline.email)) && (await get('owner', `sapIndex/${offline.sap}`)).status === 404);
  await sleep(3000);
  await click(c.page, 'Submit for approval', { exact: true });
  r.check('RG-14', 'Retry after reconnecting succeeds', await hasText(c.page, 'Waiting for approval', { timeout: 20000 }));
} catch (e) {
  r.check('RG-ERR', 'Suite completed without errors', false, e.message);
} finally {
  await a.browser.close();
  await b.browser.close();
  await c.browser.close();
}
process.exit(r.summary() ? 0 : 1);
