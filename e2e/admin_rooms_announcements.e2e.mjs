// B. Room & floor management and C. announcement publishing (Chrome).
import { launch, open, signIn, ensureSignedIn, click, type, hasText, texts, shot, sleep, reporter } from './lib.mjs';
import { idToken, query, get, studentKeys } from './api.mjs';
import { FS } from './env.mjs';

const r = reporter('Rooms & announcements workflow (Chrome)');
const { browser, page } = await launch();
const ADMIN = ['admin@campussync.test', 'Admin12345'];

async function pickDate(label, mmddyyyy) {
  await click(page, label);
  await click(page, 'Switch to input');
  await type(page, 'Enter Date', mmddyyyy);
  await click(page, 'OK', { exact: true });
}

try {
  // ---------------------------------------------------------------- rooms
  await open(page, '?section=rooms');
  await signIn(page, ...ADMIN);
  await type(page, 'Search rooms', 'TR 20');
  const fl2 = (await texts(page)).join(' ');
  r.check('RM-01', 'Floor 2 source rooms present (TR 201–203)', ['TR 201', 'TR 202', 'TR 203'].every((x) => fl2.includes(x)));
  await type(page, 'Search rooms', '');

  // Duplicate room id is rejected.
  await click(page, 'New room');
  await type(page, 'Room code *', 'CR-201');
  await type(page, 'Display name *', 'Duplicate test');
  await click(page, 'Save', { exact: true });
  r.check('RM-02', 'Duplicate room id CR-201 is rejected ("Room already exists")', await hasText(page, 'Room already exists'));
  await shot(page, '96_web_room_duplicate_rejected');

  // Invalid capacity is rejected.
  await type(page, 'Room code *', 'TEST-ROOM-901');
  await type(page, 'Display name *', 'TEST Room 901 (QA record)');
  await type(page, 'Capacity (if known)', '0');
  await click(page, 'Save', { exact: true });
  r.check('RM-03', 'Capacity 0 is rejected ("Enter 1–1000")', await hasText(page, 'Enter 1–1000'));

  // Valid test room on Floor 2.
  await type(page, 'Capacity (if known)', '40');
  await click(page, 'Floor');
  await click(page, 'Floor 2', { exact: true });
  await click(page, 'Save', { exact: true });
  await sleep(2000);
  const owner = 'owner';
  let room = (await get(owner, 'rooms/TEST-ROOM-901')).doc;
  r.check('RM-04', 'Test room persisted on Floor 2 with capacity 40', room?.floorId === '2' && Number(room?.capacity) === 40, JSON.stringify({ floor: room?.floorId, cap: room?.capacity }));

  // Edit it (deactivate + restriction note) and reload.
  await type(page, 'Search rooms', 'TEST');
  await click(page, 'Edit');
  await type(page, 'Restriction note', 'QA test record – not a real room');
  await click(page, 'Active');
  await click(page, 'Save', { exact: true });
  await sleep(1500);
  await open(page, '?section=rooms');
  await ensureSignedIn(page, ...ADMIN);
  await type(page, 'Search rooms', 'TEST');
  r.check('RM-05', 'After reload the edit persisted (inactive + note shown)', await hasText(page, 'QA test record') && await hasText(page, 'inactive'));
  await shot(page, '97_web_room_edited');
  room = (await get(owner, 'rooms/TEST-ROOM-901')).doc;
  r.check('RM-06', 'Firestore record updated (active=false) and audit-stamped', room?.active === false && !!room?.updatedBy);
  const audit = await query(owner, 'auditLogs', [['targetPath', 'rooms/TEST-ROOM-901']]);
  r.check('RM-07', 'Two audit entries recorded for the room (create + edit)', audit.docs.length === 2, `${audit.docs.length} entries`);

  // Student cannot write rooms.
  const stu = await idToken('test.divb@campussync.test', 'Student12345');
  const { write } = await import('./api.mjs');
  const denied = await write(stu.token, 'rooms/TEST-ROOM-902', { name: 'hack', updatedBy: stu.uid });
  r.check('RM-08', 'Student write to rooms is rejected by rules', denied === 403, `HTTP ${denied}`);

  // -------------------------------------------------------- announcements
  await open(page, '?section=announcements');
  await ensureSignedIn(page, ...ADMIN);
  await click(page, 'New announcement');
  await click(page, 'Save draft', { exact: true });
  r.check('AN-01', 'Empty title is rejected ("Title is required.")', await hasText(page, 'Title is required.'));
  await type(page, 'Title *', 'TEST ANNOUNCEMENT – QA only, not a real college notice');
  await type(page, 'Registration link', 'not-a-link');
  await click(page, 'Save draft', { exact: true });
  r.check('AN-02', 'Malformed registration URL is rejected', await hasText(page, 'Enter a full link starting with https://'));
  await type(page, 'Registration link', 'https://example.org/qa-test');
  await pickDate('Start date', '10/30/2026');
  await pickDate('End / deadline', '10/25/2026');
  await click(page, 'Save draft', { exact: true });
  r.check('AN-03', 'End date before start date is rejected', await hasText(page, 'End date cannot be before the start date.'));
  await shot(page, '98_web_announcement_validation');
  await pickDate('End / deadline', '11/05/2026');
  await type(page, 'Short summary', 'QA test record used to verify draft/publish/withdraw.');
  await click(page, 'Save draft', { exact: true });
  await sleep(2000);
  const anns = await query('owner', 'announcements');
  const ann = anns.docs.find((d) => d.title?.startsWith('TEST ANNOUNCEMENT'));
  r.check('AN-04', 'Draft persisted with exact URL and dates', ann?.status === 'draft' && ann?.registrationUrl === 'https://example.org/qa-test' && ann?.startDate === '2026-10-30' && ann?.endDate === '2026-11-05');
  let seen = await query(stu.token, 'announcements', [['status', 'published'], ['audienceKeys', await studentKeys(stu.uid)]]);
  r.check('AN-05', 'Draft is NOT visible to students', !seen.docs.some((d) => d.id === ann?.id));
  const draftDirect = await get(stu.token, `announcements/${ann?.id}`);
  r.check('AN-06', 'Direct student read of the draft is denied', draftDirect.status === 403, `HTTP ${draftDirect.status}`);

  // Publish.
  await click(page, 'TEST ANNOUNCEMENT', { contains: true });
  await click(page, 'Publish', { exact: true });
  await click(page, 'Publish', { exact: true });
  await sleep(2000);
  seen = await query(stu.token, 'announcements', [['status', 'published'], ['audienceKeys', await studentKeys(stu.uid)]]);
  r.check('AN-07', 'Published announcement is visible to students', seen.docs.some((d) => d.id === ann?.id));
  await shot(page, '99_web_announcement_published');

  // Withdraw (archive) – deletion is intentionally disallowed by the rules.
  await click(page, 'TEST ANNOUNCEMENT', { contains: true });
  await click(page, 'Archive', { exact: true });
  await click(page, 'Archive', { exact: true });
  await sleep(2000);
  seen = await query(stu.token, 'announcements', [['status', 'published'], ['audienceKeys', await studentKeys(stu.uid)]]);
  r.check('AN-08', 'After archive students no longer see it', !seen.docs.some((d) => d.id === ann?.id));
  const { status: delStatus } = await fetch(`${FS}/announcements/${ann?.id}`,
    { method: 'DELETE', headers: { authorization: `Bearer ${(await idToken(...ADMIN)).token}` } });
  r.check('AN-09', 'Hard delete is refused even for an admin (archive keeps history)', delStatus === 403, `HTTP ${delStatus}`);
} catch (e) {
  r.check('RA-ERR', 'workflow completed without an automation error', false, e.message);
  await shot(page, 'zz_web_ra_error');
} finally {
  await browser.close();
}
process.exit(r.summary() ? 0 : 1);
