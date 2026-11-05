// Direct REST access to the Local Emulator Suite, used to (a) check what a
// given signed-in user can really read/write under the security rules and
// (b) verify persisted state independently of the UI.
import { AUTH, FS, PROJECT } from './env.mjs';

export async function idToken(email, password) {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const j = await r.json();
  if (!j.idToken) throw new Error(`sign-in failed for ${email}: ${JSON.stringify(j.error)}`);
  return { token: j.idToken, uid: j.localId };
}

export async function followVerification(email) {
  const codes = (await (await fetch(`${AUTH}/emulator/v1/projects/${PROJECT}/oobCodes`)).json()).oobCodes;
  const c = codes.filter((x) => x.requestType === 'VERIFY_EMAIL' && x.email === email).pop();
  if (!c) throw new Error('no verification email for ' + email);
  await fetch(c.oobLink);
}

const val = (v) => {
  const [k, x] = Object.entries(v)[0];
  if (k === 'arrayValue') return (x.values || []).map(val);
  if (k === 'mapValue') return Object.fromEntries(Object.entries(x.fields || {}).map(([a, b]) => [a, val(b)]));
  if (k === 'integerValue') return Number(x);
  return x;
};
const doc = (d) => ({ id: d.name.split('/').pop(), ...Object.fromEntries(Object.entries(d.fields || {}).map(([k, v]) => [k, val(v)])) });

/** Firestore structured query as `token` (or as the emulator owner when token is 'owner'). */
export async function query(token, collection, where = []) {
  // [field, 'value'] is an equality filter; [field, ['a', 'b']] is array-contains-any.
  const filters = where.map(([field, value]) => (Array.isArray(value)
    ? { fieldFilter: { field: { fieldPath: field }, op: 'ARRAY_CONTAINS_ANY', value: { arrayValue: { values: value.map((v) => ({ stringValue: v })) } } } }
    : { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: value } } }));
  const body = { structuredQuery: { from: [{ collectionId: collection }], ...(filters.length ? { where: filters.length === 1 ? filters[0] : { compositeFilter: { op: 'AND', filters } } } : {}) } };
  const r = await fetch(`${FS}:runQuery`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) return { status: r.status, error: (j[0] || j).error?.status || JSON.stringify(j).slice(0, 120), docs: [] };
  return { status: r.status, docs: j.filter((x) => x.document).map((x) => doc(x.document)) };
}

export async function get(token, path) {
  const r = await fetch(`${FS}/${path}`, { headers: { authorization: `Bearer ${token}` } });
  const j = await r.json();
  return { status: r.status, doc: r.ok ? doc(j) : null };
}

/** Attempts a write (PATCH = create/overwrite) and returns the HTTP status. */
export async function write(token, path, fields) {
  const toV = (v) => (typeof v === 'string' ? { stringValue: v } : Array.isArray(v) ? { arrayValue: { values: v.map(toV) } } : v === null ? { nullValue: null } : { booleanValue: v });
  const r = await fetch(`${FS}/${path}`, {
    method: 'PATCH', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, toV(v)])) }),
  });
  return r.status;
}

/**
 * The audience keys the app sends for a student (studentAudienceKeys in
 * models.dart): read via the emulator owner, exactly as stored.
 */
export async function studentKeys(uid) {
  const p = (await get('owner', `students/${uid}`)).doc ?? {};
  const g = p.groupId ? (await get('owner', `groups/${p.groupId}`)).doc : null;
  return ['all', p.groupId && `group:${p.groupId}`, g?.departmentId && `dept:${g.departmentId}`,
    p.oe1OfferingId && `oe:${p.oe1OfferingId}`, p.oe2OfferingId && p.oe2OfferingId !== p.oe1OfferingId && `oe:${p.oe2OfferingId}`].filter(Boolean);
}
