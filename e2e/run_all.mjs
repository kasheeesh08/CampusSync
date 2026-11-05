// Resets the emulator data, then runs every Chrome workflow suite in order.
// Normally started by `node run_isolated.mjs`, which provides a dedicated
// emulator. Requires E2E_FIRESTORE_HOST / E2E_AUTH_HOST / E2E_PROJECT (env.mjs)
// and the admin (http://localhost:8765) and student (http://localhost:8766) web
// builds compiled for that emulator (docs/DEPLOYMENT.md §2b).
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { FIRESTORE_HOST, PROJECT } from './env.mjs'; // fails fast if no dedicated emulator is configured

const here = dirname(fileURLToPath(import.meta.url));
const all = ['admin_timetable.e2e.mjs', 'admin_rooms_announcements.e2e.mjs', 'admin_exams_access.e2e.mjs', 'student_registration.e2e.mjs'];
// Optional subset, e.g. E2E_SUITES=student_registration (comma-separated name fragments).
const only = (process.env.E2E_SUITES || '').split(',').map((x) => x.trim()).filter(Boolean);
const suites = only.length ? all.filter((s) => only.some((o) => s.includes(o))) : all;
let failed = 0;
console.log(`CampusSync admin web E2E — ${new Date().toISOString()} — emulator ${FIRESTORE_HOST} (${PROJECT})`);
for (const s of suites) {
  execFileSync('node', [join(here, 'reset.mjs')], { stdio: ['ignore', 'ignore', 'inherit'] });
  console.log(`\n=== ${s} ===`);
  try {
    execFileSync('node', [join(here, s)], { stdio: 'inherit' });
  } catch {
    failed++;
  }
}
console.log(`\n${suites.length - failed}/${suites.length} suites passed`);
process.exit(failed ? 1 : 0);
