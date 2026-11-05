// Resets a dedicated Firestore EMULATOR to the validated seed + test accounts.
// DELETES every document in that emulator. The target comes from env.mjs, which
// accepts only explicitly configured local hosts and refuses the shared ports.
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FIRESTORE_HOST, PROJECT, emulatorEnv } from './env.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const r = await fetch(`http://${FIRESTORE_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
if (!r.ok) throw new Error('emulator not reachable: ' + r.status);
execFileSync('node', [join(here, '..', 'firebase', 'seed_firestore.mjs'), '--project', PROJECT, '--emulator-test-users'], { env: emulatorEnv, stdio: 'inherit' });
execFileSync('node', [join(here, 'setup_accounts.mjs')], { env: emulatorEnv, stdio: 'inherit' });
