// Shared helpers for driving the Flutter web admin dashboard in Chrome.
// Flutter renders to a canvas; with accessibility enabled it mirrors every
// button, text field and label into DOM nodes (<flt-semantics>), which these
// helpers locate by their visible text exactly as a screen reader would.
import puppeteer from 'puppeteer-core';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { AUTH_HOST, FIRESTORE_HOST } from './env.mjs';

export const BASE = process.env.ADMIN_URL || 'http://localhost:8765/';
export const STUDENT_URL = process.env.STUDENT_URL || 'http://localhost:8766/';

// Network interlock: the browser may talk only to the served web builds and the
// configured emulator. Requests to Firebase production hosts or to any other
// local port (e.g. a shared emulator a stale build was compiled for) are
// aborted and fail the suite.
const allowedLocal = new Set([new URL(BASE).host, new URL(STUDENT_URL).host, FIRESTORE_HOST, AUTH_HOST]
  .map((h) => h.replace(/^localhost:/, '127.0.0.1:')));
const PRODUCTION = [/\.googleapis\.com$/, /\.firebaseio\.com$/, /\.firebaseapp\.com$/, /\.cloudfunctions\.net$/, /\.firebasestorage\.app$/, /\.appspot\.com$/];
export const networkViolations = [];
function blocked(url) {
  const u = new URL(url);
  if (!/^https?:$/.test(u.protocol)) return false;
  if (u.hostname === 'localhost' || u.hostname === '127.0.0.1') return !allowedLocal.has(`127.0.0.1:${u.port || (u.protocol === 'https:' ? '443' : '80')}`);
  if (u.hostname === 'fonts.googleapis.com') return false;
  return PRODUCTION.some((re) => re.test(u.hostname));
}
const CHROME = process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const SHOTS = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'screenshots');
mkdirSync(SHOTS, { recursive: true });

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launch() {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    userDataDir: join(process.env.TEMP || '.', `cs-e2e-${Date.now()}`),
    defaultViewport: { width: 1440, height: 900 },
    args: ['--no-first-run', '--no-default-browser-check'],
  });
  const page = await browser.newPage();
  await page.setRequestInterception(true);
  page.on('request', (req) => {
    if (blocked(req.url())) {
      networkViolations.push(req.url().slice(0, 120));
      console.log('  [blocked request]', req.url().slice(0, 120));
      req.abort('blockedbyclient');
    } else req.continue();
  });
  page.on('pageerror', (e) => {
    const where = (e.stack || '').split('\n').slice(1, 6).join(' <- ').slice(0, 600);
    console.log('  [pageerror]', e.message, where);
  });
  return { browser, page };
}

export async function open(page, query = '') {
  await page.goto(BASE + query, { waitUntil: 'networkidle0', timeout: 60000 });
  await enableSemantics(page);
}

export async function enableSemantics(page) {
  // Flutter inserts a hidden "Enable accessibility" placeholder; activating it builds the semantics DOM.
  await page.waitForSelector('flt-semantics-placeholder, flt-semantics', { timeout: 30000 });
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) p.click();
  });
  await page.waitForSelector('flt-semantics', { timeout: 30000 });
  await sleep(500);
}

/** Visible semantics labels currently on screen (for assertions and debugging). */
export async function texts(page) {
  return page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
    .map((n) => (n.getAttribute('aria-label') || n.textContent || '').trim())
    .filter(Boolean));
}

export async function hasText(page, text, { timeout = 8000 } = {}) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if ((await texts(page)).some((t) => t.includes(text))) return true;
    await sleep(250);
  }
  return false;
}

async function centreOf(page, predicateSrc, arg, timeout) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const box = await page.evaluate((src, a) => {
      const pred = new Function('n', 'a', src);
      const nodes = [...document.querySelectorAll('flt-semantics, input, textarea')].filter((n) => pred(n, a));
      // Prefer the innermost visible match.
      const n = nodes.reverse().find((x) => { const r = x.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
      if (!n) return null;
      const r = n.getBoundingClientRect();
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    }, predicateSrc, arg);
    if (box) return box;
    await sleep(250);
  }
  throw new Error(`Element not found: ${JSON.stringify(arg)}`);
}

/** Clicks the button/control whose label equals (or starts with) `label`. */
export async function click(page, label, { exact = false, contains = false, timeout = 10000 } = {}) {
  const src = `
    const t = (n.getAttribute('aria-label') || n.textContent || '').trim();
    const ok = a.exact ? t === a.label : a.contains ? t.includes(a.label) : (t === a.label || t.startsWith(a.label));
    const role = n.getAttribute('role');
    return ok && (role === 'button' || role === 'tab' || role === 'menuitem' || role === 'checkbox' || role === 'radio' || role === 'option' || n.getAttribute('flt-tappable') !== null || role === 'link');`;
  const p = await centreOf(page, src, { label, exact, contains }, timeout);
  await page.mouse.click(p.x, p.y);
  await sleep(600);
}

const remembered = new Map();

/** Types into the text field whose label/hint contains `label` (clears it first). */
export async function type(page, label, value, { timeout = 10000 } = {}) {
  const src = `
    if (!(n.tagName === 'INPUT' || n.tagName === 'TEXTAREA')) return false;
    const own = (n.getAttribute('aria-label') || '') + ' ' + (n.getAttribute('placeholder') || '');
    if (own.includes(a.label)) return true;
    // Filled fields can lose their hint; fall back to the remembered label.
    return n.dataset.csLabel === a.label;`;
  let p;
  try {
    p = await centreOf(page, src, { label }, remembered.has(label) ? 2500 : timeout);
    remembered.set(label, p);
  } catch (e) {
    // Flutter recycles input nodes after dialogs; reuse the field's last known position.
    if (!remembered.has(label)) throw e;
    p = remembered.get(label);
  }
  // Remember which label this input answered to.
  await page.evaluate((x, y, l) => {
    const el = document.elementsFromPoint(x, y).find((e) => e.tagName === 'INPUT' || e.tagName === 'TEXTAREA');
    if (el) el.dataset.csLabel = l;
  }, p.x, p.y, label);
  await page.mouse.click(p.x, p.y);
  await sleep(200);
  await page.keyboard.down('Control'); await page.keyboard.press('KeyA'); await page.keyboard.up('Control');
  await page.keyboard.press('Backspace');
  if (value) await page.keyboard.type(value, { delay: 5 });
  await sleep(400);
}

export async function shot(page, name) {
  await sleep(500);
  await page.screenshot({ path: join(SHOTS, `${name}.png`) });
  console.log(`  screenshot docs/screenshots/${name}.png`);
}

/** Minimal reporting helpers: every check is printed and counted. */
export function reporter(suite) {
  const results = [];
  return {
    check(id, desc, ok, detail = '') {
      results.push({ id, desc, ok });
      console.log(`${ok ? 'PASS' : 'FAIL'} ${id} ${desc}${detail ? ' — ' + detail : ''}`);
    },
    summary() {
      this.check('NET', 'No requests to Firebase production or to other local emulators', networkViolations.length === 0,
        networkViolations.slice(0, 3).join(' | '));
      const failed = results.filter((r) => !r.ok);
      console.log(`\n${suite}: ${results.length - failed.length}/${results.length} checks passed`);
      return failed.length === 0;
    },
  };
}

/** Signs in unless a persisted session already shows the dashboard. */
export async function ensureSignedIn(page, email, password) {
  const end = Date.now() + 15000;
  while (Date.now() < end) {
    const t = (await texts(page)).join(' ');
    if (t.includes('Sign in with an administrator account.')) return signIn(page, email, password);
    if (t.includes('CampusSync Admin') && !t.includes('Sign in with')) return;
    await sleep(300);
  }
  throw new Error('neither dashboard nor sign-in screen appeared');
}

export async function signIn(page, email, password) {
  await click(page, 'Sign in');
  await type(page, 'Email', email);
  await type(page, 'Password', password);
  await click(page, 'Sign in', { exact: true });
  await sleep(2500);
}
