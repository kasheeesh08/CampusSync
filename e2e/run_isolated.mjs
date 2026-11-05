// Runs the Chrome E2E suites against a DEDICATED, temporary Firebase Emulator
// Suite, so no shared emulator is ever reset or written:
//   node run_isolated.mjs
// Defaults: Firestore 127.0.0.1:8180, Auth 127.0.0.1:9180, project demo-campussync-e2e
// (override with E2E_FIRESTORE_PORT / E2E_AUTH_PORT / E2E_PROJECT). Refuses to start
// if a port is already in use. The web builds served on 8765/8766 must be compiled
// with the same ports and project (docs/DEPLOYMENT.md §2b); the network interlock in
// lib.mjs fails the run if they talk to anything else.
import { execSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createConnection } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const firebaseDir = join(here, '..', 'firebase');
const fsPort = Number(process.env.E2E_FIRESTORE_PORT || 8180);
const authPort = Number(process.env.E2E_AUTH_PORT || 9180);
const hubPort = fsPort + 230;
const loggingPort = fsPort + 330;
const project = process.env.E2E_PROJECT || 'demo-campussync-e2e';
if (!project.startsWith('demo-')) throw new Error('E2E_PROJECT must start with "demo-".');
if ([fsPort, authPort].some((p) => p === 8080 || p === 9099)) throw new Error('Choose ports other than the shared 8080/9099.');

const inUse = (port) => new Promise((resolve) => {
  const s = createConnection({ host: '127.0.0.1', port }, () => { s.destroy(); resolve(true); });
  s.on('error', () => resolve(false));
});
for (const p of [fsPort, authPort, hubPort, loggingPort]) {
  if (await inUse(p)) throw new Error(`Port ${p} is already in use; refusing to start (nothing was touched). Pick other ports.`);
}
for (const url of [process.env.ADMIN_URL || 'http://localhost:8765/', process.env.STUDENT_URL || 'http://localhost:8766/']) {
  const ok = await fetch(url).then((r) => r.ok, () => false);
  if (!ok) throw new Error(`${url} is not being served (see docs/DEPLOYMENT.md §2b).`);
}

const dir = mkdtempSync(join(tmpdir(), 'campussync-e2e-'));
const config = join(dir, 'firebase.json');
writeFileSync(config, JSON.stringify({
  firestore: { rules: join(firebaseDir, 'firestore.rules').replace(/\\/g, '/') },
  emulators: {
    firestore: { host: '127.0.0.1', port: fsPort },
    auth: { host: '127.0.0.1', port: authPort },
    hub: { host: '127.0.0.1', port: hubPort },
    logging: { host: '127.0.0.1', port: loggingPort },
    ui: { enabled: false },
    singleProjectMode: true,
  },
}));
console.log(`Dedicated emulator: Firestore 127.0.0.1:${fsPort}, Auth 127.0.0.1:${authPort}, project ${project}`);

// Call the project-local CLI directly (no shell), so the exec command stays one argument.
const firebaseCli = join(firebaseDir, 'node_modules', 'firebase-tools', 'lib', 'bin', 'firebase.js');
const r = spawnSync(process.execPath, [firebaseCli, 'emulators:exec', '--config', config, '--only', 'firestore,auth',
  '--project', project, 'node run_all.mjs'], {
  cwd: here,
  stdio: 'inherit',
  env: { ...process.env, E2E_FIRESTORE_HOST: `127.0.0.1:${fsPort}`, E2E_AUTH_HOST: `127.0.0.1:${authPort}`, E2E_PROJECT: project },
});

// On Windows the Firestore JVM can outlive emulators:exec. The port was free
// before we started, so a process still listening on it is ours.
if (process.platform === 'win32') {
  try {
    execSync(`powershell -NoProfile -Command "$c = Get-NetTCPConnection -LocalPort ${fsPort} -State Listen -ErrorAction SilentlyContinue; `
      + `if ($c) { $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $c[0].OwningProcess); `
      + `if ($p.CommandLine -like '*cloud-firestore-emulator*' -and $p.CommandLine -like '*--port ${fsPort}*') { Stop-Process -Id $p.ProcessId -Force } }"`, { stdio: 'ignore' });
  } catch { /* nothing left over */ }
}
rmSync(dir, { recursive: true, force: true });
process.exit(r.status ?? 1);
