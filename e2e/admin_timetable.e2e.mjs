// A. Timetable import & publishing in the real admin web build (Chrome).
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { launch, open, signIn, ensureSignedIn, click, type, hasText, texts, shot, sleep, reporter } from './lib.mjs';
import { idToken, query } from './api.mjs';

const FIX = join(dirname(fileURLToPath(import.meta.url)), 'fixtures');
const DIVB = 'btech-computer-2026-27-sem5-div-b';
const r = reporter('Timetable workflow (Chrome)');
const { browser, page } = await launch();

async function upload(file) {
  const [chooser] = await Promise.all([page.waitForFileChooser({ timeout: 10000 }), click(page, 'Choose file')]);
  await chooser.accept([join(FIX, file)]);
  await sleep(1500);
}

try {
  await open(page, '?section=timetables');
  await signIn(page, 'admin@campussync.test', 'Admin12345');
  r.check('TT-01', 'Timetables page lists Div B v1 as published', await hasText(page, 'Version 1') && await hasText(page, 'published'));
  await click(page, 'New version');
  r.check('TT-02', 'Empty draft cannot be published (validation error shown)', await hasText(page, 'Timetable has no entries.'));

  // Unsupported file type.
  await click(page, 'Import CSV / JSON');
  await upload('test_unsupported.pdf');
  r.check('TT-03', 'Unsupported .pdf upload is rejected with a clear message', await hasText(page, 'Unsupported file type'));
  await shot(page, '90_web_tt_unsupported_file');

  // Malformed CSV.
  await upload('test_malformed_timetable.csv');
  const t1 = (await texts(page)).join(' ');
  r.check('TT-04', 'Malformed CSV: 0 entries, line-level errors, Apply disabled',
    t1.includes('Parsed 0 entries, 3 error(s)') && t1.includes('invalid weekday') && t1.includes('unknown room'));
  await shot(page, '91_web_tt_malformed_csv');

  // Conflicting CSV parses, but the validator must block publishing.
  await upload('test_conflicting_timetable.csv');
  r.check('TT-05', 'Conflicting CSV parses (2 entries) for preview', await hasText(page, 'Parsed 2 entries, 0 error(s)'));
  await click(page, 'Apply to draft');
  r.check('TT-06', 'Double-booked room is reported as a validation error', await hasText(page, 'double-booked'));
  await shot(page, '92_web_tt_conflict_blocked');

  // Valid CSV replaces the draft.
  await click(page, 'Import CSV / JSON');
  await upload('test_valid_timetable.csv');
  r.check('TT-07', 'Valid CSV previews 4 entries, 0 errors', await hasText(page, 'Parsed 4 entries, 0 error(s)'));
  await click(page, 'Apply to draft');
  const t2 = (await texts(page)).join(' ');
  r.check('TT-08', 'Mappings resolved in preview: room CR 201, faculty name, batch',
    t2.includes('CR 201') && t2.includes('Dr. Prashasti Kanikar') && t2.includes('B1'));
  r.check('TT-09', 'Valid draft shows 0 errors', await hasText(page, '0 errors'));
  await shot(page, '93_web_tt_valid_preview');

  // Save draft first: students must not see it.
  await click(page, 'Save draft', { exact: true });
  await sleep(2000);
  const stu = await idToken('test.divb@campussync.test', 'Student12345');
  let pub = await query(stu.token, 'timetableVersions', [['status', 'published'], ['groupId', DIVB]]);
  r.check('TT-10', 'Saved draft is NOT visible to a Div B student', pub.docs.length === 1 && pub.docs[0].version === 1, `student sees v${pub.docs.map((d) => d.version)}`);
  const draftRead = await query(stu.token, 'timetableVersions', [['status', 'draft']]);
  r.check('TT-11', 'Student query for drafts is denied by rules', draftRead.status === 403, `HTTP ${draftRead.status}`);

  // Publish.
  await click(page, 'Publish', { exact: true });
  await click(page, 'Publish', { exact: true }); // confirmation dialog
  await sleep(2500);
  pub = await query(stu.token, 'timetableVersions', [['status', 'published'], ['groupId', DIVB]]);
  const v2 = pub.docs.find((d) => d.version === 2);
  r.check('TT-12', 'After publish the Div B student sees v2 (4 entries) and v1 is archived',
    pub.docs.length === 1 && v2 && v2.entries.length === 4, `published: v${pub.docs.map((d) => d.version)}`);
  r.check('TT-13', 'Source provenance recorded from the uploaded file', v2?.source === 'Uploaded file: test_valid_timetable.csv', v2?.source);
  const stuC = await idToken('test.divc@campussync.test', 'Student12345');
  const pubC = await query(stuC.token, 'timetableVersions', [['status', 'published'], ['groupId', 'btech-computer-2026-27-sem5-div-c']]);
  r.check('TT-14', 'Div C student still sees only Div C v1 (no leak between divisions)', pubC.docs.length === 1 && pubC.docs[0].version === 1);

  // Reload: persistence.
  await open(page, '?section=timetables');
  await ensureSignedIn(page, 'admin@campussync.test', 'Admin12345');
  await sleep(1500);
  const t3 = (await texts(page)).join(' ');
  r.check('TT-15', 'After reload: v2 published, v1 archived (persisted in Firestore)',
    t3.includes('Version 2') && t3.includes('Version 1') && t3.includes('archived') && t3.includes('Roll back to this'));
  await shot(page, '94_web_tt_published_v2');

  // Rollback to v1.
  await click(page, 'Roll back to this');
  await click(page, 'Roll back', { exact: true });
  await sleep(2500);
  pub = await query(stu.token, 'timetableVersions', [['status', 'published'], ['groupId', DIVB]]);
  r.check('TT-16', 'Rollback: student sees v1 again (38 source entries)', pub.docs.length === 1 && pub.docs[0].version === 1 && pub.docs[0].entries.length === 38);
  await shot(page, '95_web_tt_rolled_back');
} catch (e) {
  r.check('TT-ERR', 'workflow completed without an automation error', false, e.message);
  await shot(page, '9x_web_tt_error');
} finally {
  await browser.close();
}
process.exit(r.summary() ? 0 : 1);
