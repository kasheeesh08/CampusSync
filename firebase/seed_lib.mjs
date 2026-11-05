// Shared, side-effect-free logic for seed_firestore.mjs and bootstrap_admin.mjs,
// kept separate so the safety checks can be unit-tested without Firebase.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/** Collections the seed writes. Announcements and import provenance are never seeded. */
export const SEEDED = [
  'departments', 'programs', 'academicYears', 'groups', 'subjects', 'faculty', 'rooms', 'floors',
  'timetableVersions', 'electives', 'exams', 'calendarEvents',
];
export const NEVER_SEEDED = ['announcements', 'importJobs', 'admins', 'students', 'sapIndex'];
const STATUS = {
  timetableVersions: ['draft', 'published', 'archived'],
  exams: ['draft', 'published', 'archived'],
  calendarEvents: ['draft', 'published', 'archived'],
};

const LOCAL_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);
const isLocal = (hostPort) => {
  if (!hostPort) return false;
  const host = hostPort.startsWith('[') ? hostPort.slice(0, hostPort.indexOf(']') + 1) : hostPort.split(':')[0];
  return LOCAL_HOSTS.has(host);
};

/**
 * Decides where a script may write, or throws. Live writes need an explicit
 * `--confirm-live <projectId>` that repeats the project id.
 * @returns {'emulator' | 'live'}
 */
export function checkTarget({ projectId, env = {}, confirmLive = null, needsAuth = false }) {
  if (!projectId) throw new Error('--project <id> is required.');
  const fs = env.FIRESTORE_EMULATOR_HOST;
  const auth = env.FIREBASE_AUTH_EMULATOR_HOST;
  if (fs || (needsAuth && auth)) {
    if (!isLocal(fs) || (needsAuth && !isLocal(auth))) {
      throw new Error('Emulator hosts must point at this machine (127.0.0.1/localhost); refusing.');
    }
    if (confirmLive) throw new Error('--confirm-live cannot be combined with emulator hosts; refusing.');
    return 'emulator';
  }
  if (projectId.startsWith('demo-')) {
    throw new Error(`"${projectId}" is an emulator-only project id; set FIRESTORE_EMULATOR_HOST to use the emulator.`);
  }
  if (confirmLive !== projectId) {
    throw new Error(`Refusing to write to the live project "${projectId}" without --confirm-live ${projectId}.`);
  }
  return 'live';
}

/** Reads the bundled seed and returns what would be written (announcements are excluded by construction). */
export function loadPlan(seedDir) {
  const load = (f) => JSON.parse(readFileSync(join(seedDir, `${f}.json`), 'utf8'));
  const academic = load('academic');
  const campus = load('campus');
  const calendar = load('calendar');
  const collections = {
    departments: academic.departments,
    programs: academic.programs,
    academicYears: academic.academicYears,
    groups: academic.groups,
    subjects: academic.subjects.map((s) => ({ ...s, id: s.code })),
    faculty: academic.faculty,
    rooms: campus.rooms,
    floors: campus.floors,
    timetableVersions: load('timetables').versions,
    electives: load('electives').offerings,
    // audienceKeys mirrors Exam.audienceKeys in the app; the rules use it to show
    // each exam only to its groups and elective students (SECURITY_AUDIT M2).
    exams: load('exams').exams.map((e) => ({
      ...e,
      audienceKeys: [...(e.groupIds ?? []).map((g) => `group:${g}`), ...(e.electiveOfferingIds ?? []).map((o) => `oe:${o}`)],
    })),
    calendarEvents: calendar.events,
  };
  const settings = {
    ...campus.settings,
    institutionName: academic.institutions[0].name,
    calendarAudienceLabels: Object.fromEntries(Object.entries(calendar.audiences).map(([k, v]) => [k, v.label])),
  };
  return { collections, settings };
}

/** Throws on data the app or rules would mishandle: missing ids, duplicates, missing/invalid status. */
export function validatePlan({ collections }) {
  const problems = [];
  for (const name of Object.keys(collections)) {
    if (!SEEDED.includes(name)) problems.push(`${name}: not a seedable collection`);
  }
  for (const [name, docs] of Object.entries(collections)) {
    const seen = new Set();
    for (const d of docs) {
      if (typeof d.id !== 'string' || !d.id || d.id.includes('/')) problems.push(`${name}: invalid id ${JSON.stringify(d.id)}`);
      else if (seen.has(d.id)) problems.push(`${name}/${d.id}: duplicate id`);
      seen.add(d.id);
      if (name === 'exams' && (!Array.isArray(d.audienceKeys)
          || d.audienceKeys.length !== (d.groupIds ?? []).length + (d.electiveOfferingIds ?? []).length)) {
        problems.push(`exams/${d.id}: audienceKeys must list every group and elective`);
      }
      if (STATUS[name] && !STATUS[name].includes(d.status)) {
        problems.push(`${name}/${d.id}: status must be one of ${STATUS[name].join('/')} (got ${JSON.stringify(d.status)})`);
      }
    }
  }
  if (problems.length) throw new Error(`Seed data rejected:\n  ${problems.slice(0, 20).join('\n  ')}`);
}

/** Splits documents into those to create and those already present (never overwritten). */
export function splitExisting(docs, existingIds) {
  const create = [];
  const skip = [];
  for (const d of docs) (existingIds.has(d.id) ? skip : create).push(d);
  return { create, skip };
}

/**
 * The bundled announcements, for administrator review only (opt-in
 * --include-announcement-drafts). Every record must already be a draft; the
 * seed never publishes anything. audienceKeys mirrors AnnouncementAudience.keys.
 */
export function loadAnnouncementDrafts(seedDir) {
  const list = JSON.parse(readFileSync(join(seedDir, 'announcements.json'), 'utf8')).announcements;
  return list.map((a) => {
    const audience = { scope: a.audience?.scope ?? 'all', ids: a.audience?.ids ?? [] };
    const audienceKeys = audience.scope === 'all' ? ['all']
      : audience.ids.map((id) => (audience.scope === 'department' ? `dept:${id}` : `group:${id}`));
    return { ...a, audience, audienceKeys };
  });
}

/** Throws unless every record is an unpublished draft the rules would accept. */
export function validateAnnouncementDrafts(drafts) {
  const problems = [];
  for (const a of drafts) {
    if (typeof a.id !== 'string' || !a.id || a.id.includes('/')) problems.push(`announcement: invalid id ${JSON.stringify(a.id)}`);
    if (a.status !== 'draft') problems.push(`announcements/${a.id}: only drafts may be seeded (got ${JSON.stringify(a.status)})`);
    if (typeof a.title !== 'string' || !a.title || a.title.length > 140) problems.push(`announcements/${a.id}: title must be 1-140 characters`);
    if (!Array.isArray(a.audienceKeys) || a.audienceKeys.length === 0) problems.push(`announcements/${a.id}: missing audienceKeys`);
  }
  if (problems.length) throw new Error(`Announcement drafts rejected:\n  ${problems.join('\n  ')}`);
}
