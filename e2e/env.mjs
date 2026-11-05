// Emulator endpoints for every E2E script. They must be given explicitly, so a
// run (which deletes data) can never hit an emulator by accident:
//   E2E_FIRESTORE_HOST=127.0.0.1:8180  E2E_AUTH_HOST=127.0.0.1:9180  E2E_PROJECT=demo-campussync-e2e
// `node run_isolated.mjs` starts a dedicated emulator and sets these for you.
// The usual shared ports (8080/9099) are refused unless E2E_ALLOW_SHARED_EMULATOR=1,
// because a run wipes that emulator's data.
const LOCAL = new Set(['127.0.0.1', 'localhost']);
const SHARED_PORTS = new Set(['8080', '9099']);

function endpoint(name) {
  const v = process.env[name];
  if (!v) throw new Error(`${name} is not set. Use "node run_isolated.mjs" or set it to a dedicated local emulator (see docs/DEPLOYMENT.md §2b).`);
  const [host, port] = v.split(':');
  if (!LOCAL.has(host) || !/^\d+$/.test(port ?? '')) throw new Error(`${name}=${v} must be 127.0.0.1:<port> or localhost:<port>.`);
  if (SHARED_PORTS.has(port) && process.env.E2E_ALLOW_SHARED_EMULATOR !== '1') {
    throw new Error(`${name}=${v} is the shared emulator port; E2E runs delete data. Use a dedicated emulator (node run_isolated.mjs).`);
  }
  return v;
}

export const FIRESTORE_HOST = endpoint('E2E_FIRESTORE_HOST');
export const AUTH_HOST = endpoint('E2E_AUTH_HOST');
export const PROJECT = process.env.E2E_PROJECT || 'demo-campussync';
if (!PROJECT.startsWith('demo-')) throw new Error(`E2E_PROJECT=${PROJECT} must start with "demo-".`);

export const AUTH = `http://${AUTH_HOST}`;
export const FS = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
/** Environment for child processes (seed script) pointing at the same emulator. */
export const emulatorEnv = { ...process.env, FIRESTORE_EMULATOR_HOST: FIRESTORE_HOST, FIREBASE_AUTH_EMULATOR_HOST: AUTH_HOST };
