// D. Exams & academic calendar and E. student management / access control (Chrome).
import { launch, open, signIn, click, type, hasText, texts, shot, sleep, reporter } from './lib.mjs';
import { idToken, query, get, write, studentKeys } from './api.mjs';

const r = reporter('Exams, calendar & access-control workflow (Chrome)');
const { browser, page } = await launch();
const ADMIN = ['admin@campussync.test', 'Admin12345'];
const DIVB = 'btech-computer-2026-27-sem5-div-b';
const OS_ID = 'exam-computer-engineering-702co0c056-2026-11-25';

async function pickDate(label, mmddyyyy) {
  await click(page, label);
  await click(page, 'Switch to input');
  await type(page, 'Enter Date', mmddyyyy);
  await click(page, 'OK', { exact: true });
}
async function search(q) { await type(page, 'Search subject, code, stream', q); await sleep(500); }

try {
  await open(page, '?section=exams');
  await signIn(page, ...ADMIN);

  // ------------------------------------------------------------- exams
  const before = (await get('owner', `exams/${OS_ID}`)).doc;
  await search('Operating');
  await click(page, 'Edit', { exact: true });
  await type(page, 'Start (optional)', '9am');
  await click(page, 'Save', { exact: true });
  r.check('EX-01', 'Malformed exam time "9am" is rejected (HH:MM)', await hasText(page, 'Use HH:MM (24-hour)'));
  await type(page, 'Start (optional)', '10:00');
  await type(page, 'End (optional)', '09:00');
  await click(page, 'Save', { exact: true });
  r.check('EX-02', 'End before start is rejected', await hasText(page, 'End must be after start'));
  await type(page, 'End (optional)', '13:00');
  await click(page, 'Save', { exact: true });
  await sleep(2000);
  const after = (await get('owner', `exams/${OS_ID}`)).doc;
  const kept = ['officialCode', 'stream', 'source', 'timeSource', 'status'].every((k) => after?.[k] === before?.[k])
    && JSON.stringify(after?.groupIds) === JSON.stringify(before?.groupIds);
  r.check('EX-03', 'Edit/save keeps provenance, official code, stream, time source, status and group links', kept,
    `${after?.officialCode} · ${after?.source?.slice(-35)} · ${after?.groupIds?.length} groups`);

  // Elective-linked exam keeps its elective link on save.
  await search('5G for');
  await click(page, 'Edit', { exact: true });
  await click(page, 'Save', { exact: true });
  await sleep(2000);
  const g5 = (await get('owner', 'exams/exam-oe1-01-2026-12-02')).doc;
  r.check('EX-04', 'Editing an open-elective exam keeps its elective link and empty group list',
    JSON.stringify(g5?.electiveOfferingIds) === '["oe1-01"]' && (g5?.groupIds?.length ?? 0) === 0);
  r.check('EX-04b', 'Editing keeps the specific elective name (not the generic "Open Elective I")', g5?.subjectName === '5G for Everyone', g5?.subjectName);

  // Review-flagged record is visibly marked.
  await click(page, 'All', { exact: true });
  await search('Wireless');
  r.check('EX-05', 'Record needing review is shown with its review note (not silently verified)', await hasText(page, 'Review: Exam sheet spells'));
  await shot(page, 'a0_web_exam_review_flag');

  // Duplicate and clash handling on a new exam.
  await click(page, 'Exam', { exact: true });
  await click(page, 'Subject *');
  await click(page, 'OR · Operations Research');
  await click(page, 'B.Tech Computer · Sem V · Div B', { exact: true });
  await pickDate('Exam date *', '11/17/2026');
  await type(page, 'Start (optional)', '10:00');
  await type(page, 'End (optional)', '13:00');
  await type(page, 'Source *', 'QA TEST record – duplicate check');
  await click(page, 'Save', { exact: true });
  r.check('EX-06', 'Duplicate (same subject, date and group) is refused', await hasText(page, 'Not saved: Duplicate'));
  await shot(page, 'a1_web_exam_duplicate_refused');

  await click(page, 'Exam', { exact: true });
  await click(page, 'Subject *');
  await click(page, 'MAD · Mobile Application Development');
  await click(page, 'B.Tech Computer · Sem V · Div B', { exact: true });
  await pickDate('Exam date *', '11/17/2026');
  await type(page, 'Start (optional)', '11:00');
  await type(page, 'End (optional)', '12:00');
  await type(page, 'Source *', 'QA TEST record – clash check');
  await click(page, 'Save', { exact: true });
  r.check('EX-07', 'Overlap with another exam for the same group is refused', await hasText(page, 'Clashes with Operations Research'));

  for (const [id, src] of [['EX-06b', 'duplicate check'], ['EX-07b', 'clash check']]) {
    const n = (await query('owner', 'exams', [['source', `QA TEST record – ${src}`]])).docs.length;
    r.check(id, `Refused record (${src}) was not written to Firestore`, n === 0, `${n} saved`);
  }

  // Valid new exam starts as a draft; invisible to students until published.
  await click(page, 'Exam', { exact: true });
  await click(page, 'Subject *');
  await click(page, 'MAD · Mobile Application Development');
  await click(page, 'B.Tech Computer · Sem V · Div B', { exact: true });
  await pickDate('Exam date *', '11/30/2026');
  await type(page, 'Start (optional)', '14:00');
  await type(page, 'End (optional)', '17:00');
  await type(page, 'Source *', 'QA TEST record – NOT an official exam');
  await click(page, 'Save', { exact: true });
  await sleep(2000);
  const all = await query('owner', 'exams', [['source', 'QA TEST record – NOT an official exam']]);
  const qa = all.docs[0];
  r.check('EX-08', 'New exam saved as DRAFT', qa?.status === 'draft', qa?.status);
  const stu = await idToken('test.divb@campussync.test', 'Student12345');
  let pub = await query(stu.token, 'exams', [['status', 'published'], ['audienceKeys', await studentKeys(stu.uid)]]);
  r.check('EX-09', 'Draft exam not visible to students', !pub.docs.some((d) => d.id === qa?.id));
  await click(page, 'Drafts', { exact: true });
  await search('');
  await click(page, 'Publish', { exact: true });
  await click(page, 'Publish', { exact: true });
  await sleep(2000);
  pub = await query(stu.token, 'exams', [['status', 'published'], ['audienceKeys', await studentKeys(stu.uid)]]);
  r.check('EX-10', 'After publish the exam is visible to students', pub.docs.some((d) => d.id === qa?.id));
  await click(page, 'Visible to groups', { exact: true });
  await search('Mobile');
  await click(page, 'Withdraw', { exact: true });
  await click(page, 'Withdraw', { exact: true });
  await sleep(2000);
  pub = await query(stu.token, 'exams', [['status', 'published'], ['audienceKeys', await studentKeys(stu.uid)]]);
  const stillThere = (await get('owner', `exams/${qa?.id}`)).doc;
  r.check('EX-11', 'Withdrawn exam hidden from students but kept as a record', !pub.docs.some((d) => d.id === qa?.id) && stillThere?.status === 'archived');
  // M2: a student sees exactly the published exams for their audience; exams
  // for other streams (or with no linked group) stay hidden.
  const keys = await studentKeys(stu.uid);
  const allExams = (await query('owner', 'exams')).docs;
  const mine = allExams.filter((e) => e.status === 'published' && (e.audienceKeys ?? []).some((k) => keys.includes(k))).map((e) => e.id).sort();
  const hidden = allExams.filter((e) => e.status === 'published').length - mine.length;
  r.check('EX-12', 'Student sees exactly their audience exams; other published exams stay hidden (M2)',
    JSON.stringify(pub.docs.map((d) => d.id).sort()) === JSON.stringify(mine) && hidden > 0 && !pub.docs.some((d) => d.id === qa?.id),
    `${pub.docs.length} visible, ${hidden} hidden`);

  // ----------------------------------------------------------- calendar
  await click(page, 'Calendar', { exact: true });
  await click(page, 'Calendar event', { exact: true });
  await type(page, 'Title *', 'TEST EVENT – QA only');
  await pickDate('Start *', '11/10/2026');
  await pickDate('End *', '11/09/2026');
  await click(page, 'Save', { exact: true });
  r.check('CA-01', 'Calendar event with end before start is refused', await hasText(page, 'End date cannot be before the start date.'));
  await pickDate('End *', '11/11/2026');
  await click(page, 'Save', { exact: true });
  await sleep(2000);
  const ev = (await query('owner', 'calendarEvents', [['title', 'TEST EVENT – QA only']])).docs[0];
  r.check('CA-02', 'Valid calendar event persisted', ev?.start === '2026-11-10' && ev?.end === '2026-11-11');
  await shot(page, 'a2_web_calendar_event_saved');

  // -------------------------------------------- students & access control
  const pend = await idToken('test.pending@campussync.test', 'Student12345');
  const pendRead = await query(pend.token, 'exams', [['status', 'published'], ['audienceKeys', await studentKeys(pend.uid)]]);
  r.check('AC-01', 'Pending (unapproved) student cannot read exams', pendRead.status === 403, `HTTP ${pendRead.status}`);
  r.check('AC-02', 'Student cannot grant themselves admin', (await write(stu.token, `admins/${stu.uid}`, { email: 'x', role: 'admin', updatedBy: stu.uid })) === 403);
  r.check('AC-03', 'Student cannot approve/change their own status or group',
    (await write(pend.token, `students/${pend.uid}?updateMask.fieldPaths=status`, { status: 'active' })) === 403);
  r.check('AC-04', 'Student cannot read the audit log', (await query(stu.token, 'auditLogs')).status === 403);
  r.check('AC-05', 'Student cannot read another student profile', (await get(stu.token, `students/${pend.uid}`)).status === 403);
  r.check('AC-06', 'Student cannot publish an exam directly via the API',
    (await write(stu.token, 'exams/hack', { status: 'published', groupIds: [DIVB], date: '2026-11-20', updatedBy: stu.uid })) === 403);

  await click(page, 'Students', { contains: true });
  await sleep(1500);
  r.check('AC-07', 'Pending TEST student listed for review', await hasText(page, 'TEST Pending Student'));
  await click(page, 'Approve', { exact: true });
  await click(page, 'Approve', { exact: true });
  await sleep(2000);
  const approved = (await get('owner', `students/${pend.uid}`)).doc;
  r.check('AC-08', 'Approval sets status=active and assigns Div B', approved?.status === 'active' && approved?.groupId === DIVB);
  const nowRead = await query(pend.token, 'exams', [['status', 'published'], ['audienceKeys', await studentKeys(pend.uid)]]);
  r.check('AC-09', 'After approval the student can read published exams', nowRead.status === 200 && nowRead.docs.length > 0);

  await click(page, 'Audit log', { contains: true });
  await sleep(1500);
  const auditText = (await texts(page)).join(' ');
  r.check('AC-10', 'Audit log shows the approval and exam changes with the admin identity',
    auditText.includes('student.active') && auditText.includes('exam.save') && auditText.includes('admin@campussync.test'));
  await shot(page, 'a3_web_audit_log');

  // Content manager sees only content sections.
  await click(page, 'Sign out', { exact: true });
  await sleep(1500);
  await signIn(page, 'content@campussync.test', 'Content12345');
  const cm = (await texts(page)).join(' ');
  r.check('AC-11', 'Content manager has no Timetables/Rooms/Students/Administrators sections',
    cm.includes('Announcements') && !cm.includes('Timetables') && !cm.includes('Rooms & floors') && !cm.includes('Administrators'));
  const cmTok = await idToken('content@campussync.test', 'Content12345');
  r.check('AC-12', 'Content manager blocked from timetables by rules too (not only hidden in UI)',
    (await write(cmTok.token, 'timetableVersions/hack', { groupId: DIVB, status: 'draft', effectiveFrom: '2026-07-13', updatedBy: cmTok.uid })) === 403);
  await shot(page, 'a4_web_content_manager_view');
} catch (e) {
  r.check('EA-ERR', 'workflow completed without an automation error', false, e.message);
  await shot(page, 'zz_web_ea_error');
} finally {
  await browser.close();
}
process.exit(r.summary() ? 0 : 1);
