// Prints semantics labels and inputs for an admin section (debugging aid).
//   node probe.mjs <section> [button-to-click ...]
import { launch, open, texts, signIn, click, sleep } from './lib.mjs';

const [section = 'overview', ...clicks] = process.argv.slice(2);
const { browser, page } = await launch();
try {
  await open(page, `?section=${section}`);
  await signIn(page, 'admin@campussync.test', 'Admin12345');
  for (const c of clicks) await click(page, c);
  await sleep(1000);
  console.log('TEXTS:', JSON.stringify((await texts(page)).map((t) => t.replace(/\n/g, ' | ').slice(0, 90))));
  console.log('INPUTS:', JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('input,textarea')].map((n) => n.getAttribute('aria-label')))));
  console.log('ROLES:', JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('flt-semantics[role]')].map((n) => `${n.getAttribute('role')}:${(n.getAttribute('aria-label') || n.textContent || '').trim().slice(0, 30)}`).slice(0, 60))));
} finally {
  await browser.close();
}
