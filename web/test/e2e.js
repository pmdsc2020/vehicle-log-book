// Click-through test of the reviewer in a real browser (Chromium via Playwright).
//   python3 web/build.py && node web/test/e2e.js            (SHOTS=/some/dir to keep screenshots, OUT=/some/dir to keep signed files)
// Not part of CI: it needs Playwright and a browser. The core logic is covered by core.test.js.
'use strict';
const { chromium } = require('playwright');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const V = require('../src/core.js');

const ROOT = path.join(__dirname, '..');
const PAGE = 'file://' + path.join(ROOT, 'vehicle-log-reviewer.html');
const SHOTS = process.env.SHOTS || fs.mkdtempSync(path.join(os.tmpdir(), 'vlb-shots-'));
const OUT = process.env.OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'vlb-out-'));
fs.mkdirSync(SHOTS, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });
const fx = (n) => path.join(ROOT, 'test', 'fixtures', n + '.vlbreport');

let failed = 0;
const ok = (cond, what) => {
  console.log((cond ? 'ok   ' : 'FAIL ') + what);
  if (!cond) failed += 1;
};

async function setProfile(page, name, role) {
  await page.click('.me');
  await page.fill('#pf-name', name);
  await page.selectOption('#pf-role', role);
  await page.click('dialog.modal .btn.primary');
  await page.waitForSelector('dialog.modal', { state: 'detached' });
}

async function sign(page, { remarks, label, excess }) {
  if (remarks) await page.fill('#remarks', remarks);
  if (excess) await page.locator('.switch').click();
  await page.click('.sign .btn.primary');
  await page.waitForSelector('dialog.modal[open]');
  await page.click('dialog.modal .btn.primary, dialog.modal .btn.danger');
  await page.waitForSelector('dialog.modal', { state: 'detached' });
  await page.waitForSelector('.sendcard');
}

async function saveSigned(page, name) {
  const [dl] = await Promise.all([page.waitForEvent('download'), page.click('.sendcard .btn.primary')]);
  const file = path.join(OUT, name);
  await dl.saveAs(file);
  return file;
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, colorScheme: 'light', acceptDownloads: true });
  const page = await ctx.newPage();
  const errs = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errs.push(m.text());
  });
  page.on('pageerror', (e) => errs.push('PAGEERROR ' + e.message));

  await page.goto(PAGE);
  await page.waitForSelector('.drop');
  ok(await page.locator('text=Review staff vehicle logs on a big screen').count() === 1, 'empty state shows');

  // ---- the sample report
  await page.click('text=Try a sample report');
  await page.waitForSelector('.report');
  ok((await page.locator('.checks h2').innerText()).toLowerCase().includes('checks passed'), 'sample report passes its checks');
  ok((await page.locator('.checks h2').innerText()).includes('notes'), 'sample report has notes to read (meter gap, late entry)');
  await page.waitForFunction(() => Array.from(document.images).every((i) => i.complete && i.naturalWidth > 0));
  await page.screenshot({ path: SHOTS + '/10-sample-top.png' });
  await page.screenshot({ path: SHOTS + '/11-sample-full.png', fullPage: true });

  // ---- someone with no matching role cannot sign
  ok((await page.locator('.sign h2').innerText()).startsWith('With the Block Integrator'), 'with no profile, the panel says who it waits for');

  // ---- trip detail and the photo viewer
  await page.locator('tr.row').nth(1).click();
  await page.waitForSelector('tr.detail');
  await page.screenshot({ path: SHOTS + '/12-trip-detail.png' });
  await page.locator('tr.detail .thumb').first().click();
  await page.waitForSelector('dialog.lb[open] .stage img');
  await page.waitForFunction(() => document.querySelector('#lightbox img').naturalWidth > 0);
  await page.waitForTimeout(150);
  await page.screenshot({ path: SHOTS + '/13-lightbox.png' });
  const t0 = await page.locator('#lightbox img').evaluate((i) => i.style.transform);
  await page.keyboard.press('+');
  await page.keyboard.press('+');
  const t1 = await page.locator('#lightbox img').evaluate((i) => i.style.transform);
  ok(t0 !== t1, 'zoom keys change the picture transform');
  await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(150);
  ok((await page.locator('#lbpanel .big').first().innerText()).includes('photo 4 of'), 'right arrow goes to the next photo');
  await page.keyboard.press('r');
  ok((await page.locator('#lightbox img').evaluate((i) => i.style.transform)).includes('rotate(90deg)'), 'R rotates');
  await page.locator('#lbpanel .switch').click();
  await page.keyboard.press('Escape');
  await page.waitForSelector('dialog.lb', { state: 'hidden' });
  ok((await page.locator('.prog .js-prog-text').innerText()).startsWith('1 of'), 'ticking a trip in the viewer shows in the trip list');

  // ---- Block Integrator signs
  await setProfile(page, 'रमेश पाटील', 'bi');
  ok(await page.locator('.sign h2:has-text("Check this report")').count() === 1, 'BI sees the check panel');
  await page.click('text=Tick all');
  await page.click('.sign .btn.danger');
  ok(await page.locator('#remarkErr:not([hidden])').count() === 1, 'sending back without a reason is refused');
  await page.locator('tr.row .qbtn').nth(2).click();
  await page.click('text=/Add 1 queried trip to remarks/');
  ok((await page.inputValue('#remarks')).includes('Please explain'), 'queried trips can be added to the remarks');
  await page.fill('#remarks', 'Trips match the diary. मीटर फोटो स्पष्ट आहेत.');
  await page.locator('tr.row .qbtn').nth(2).click();
  await page.click('.sign .btn.primary');
  await page.waitForSelector('dialog.modal[open]');
  await page.screenshot({ path: SHOTS + '/14-confirm.png' });
  await page.click('dialog.modal .btn.primary');
  await page.waitForSelector('.sendcard');
  ok((await page.locator('.steps .step.now b').innerText()) === 'Verified', 'after BI the report moves to the Accountant');
  const biFile = await saveSigned(page, 'signed_by_bi.vlbreport');
  await page.screenshot({ path: SHOTS + '/15-after-bi.png', fullPage: true });

  // ---- Accountant, then District Integrator (with the excess approved)
  await setProfile(page, 'Meena Shah', 'acc');
  await sign(page, { remarks: 'Vouchers checked' });
  const accFile = await saveSigned(page, 'signed_by_acc.vlbreport');
  await setProfile(page, 'Jitendra Sonawane', 'di');
  ok(await page.locator('.switch').count() === 1, 'DI sees the excess switch');
  await sign(page, { remarks: '', excess: true });
  ok((await page.locator('.sign h2').innerText()) === 'Approved', 'the report ends approved');
  const diFile = await saveSigned(page, 'approved_by_di.vlbreport');
  await page.screenshot({ path: SHOTS + '/16-approved.png', fullPage: true });

  // ---- what the browser wrote is a report the core accepts, with the right figures
  const fin = await V.openReportFile(new Uint8Array(fs.readFileSync(diFile)));
  ok(fin.check.ok, 'the approved file passes every check');
  ok(V.statusOf(fin.report).stage === 'approved', 'it is approved');
  ok(fin.report.signoffs.map((s) => s.step).join() === 'submit,bi,acc,di', 'four sign-offs in order');
  ok(V.payableKm(fin.report) === fin.report.summary.km, 'excess approved: all km payable');
  ok(fin.report.signoffs[1].remarks.includes('मीटर'), 'Devanagari remarks survive');
  ok(fin.report.signoffs.slice(1).map((x) => x.designation).join() === 'Block Integrator,Accountant,District Integrator', 'each signer carries the designation of their role');
  const mid = await V.openReportFile(new Uint8Array(fs.readFileSync(biFile)));
  ok(mid.check.ok && V.statusOf(mid.report).stage === 'withAcc', 'the file saved after BI is with the Accountant');
  const acc = await V.openReportFile(new Uint8Array(fs.readFileSync(accFile)));
  ok(acc.check.ok && V.statusOf(acc.report).stage === 'withDi', 'the file saved after the Accountant is with the DI');

  // ---- opening files, tampering, older copies
  await page.click('text=All reports');
  await page.setInputFiles('#filein', [biFile]);
  await page.waitForSelector('dialog.modal[open]');
  ok((await page.locator('dialog.modal .res').first().innerText()).includes('later copy'), 'an older copy is not allowed to replace a later one');
  await page.click('dialog.modal .btn');
  const bytes = new Uint8Array(fs.readFileSync(fx('a_sent')));
  const f = await V.decodeReportFile(bytes);
  f.raw.trips[0].km = 999;
  const tampered = path.join(OUT, 'tampered.vlbreport');
  fs.writeFileSync(tampered, Buffer.from(JSON.stringify(f.raw)));
  await page.setInputFiles('#filein', [tampered]);
  await page.waitForSelector('.report');
  ok((await page.locator('.checks h2').innerText()).startsWith('Do not sign'), 'a changed file is marked Do not sign');
  await setProfile(page, 'रमेश पाटील', 'bi');
  ok(await page.locator('.sign .btn.primary[disabled]').count() === 1, 'forwarding a failed report is blocked');
  await page.screenshot({ path: SHOTS + '/17-tampered.png' });
  fs.writeFileSync(path.join(OUT, 'junk.vlbreport'), 'hello');
  await page.setInputFiles('#filein', [path.join(OUT, 'junk.vlbreport')]);
  await page.waitForSelector('dialog.modal[open]');
  ok((await page.locator('dialog.modal').innerText()).includes('not a vehicle log report'), 'a file that is not a report is turned away kindly');
  await page.click('dialog.modal .btn');

  // ---- it keeps the reports after a reload
  await page.reload();
  await page.click('.tab:has-text("All reports")');
  await page.waitForSelector('table.list');
  ok((await page.locator('table.list tbody tr').count()) === 2, 'both reports are still there after a reload');

  // ---- dark theme and a narrow window
  await page.click('.topbar .btn.icon');
  await page.screenshot({ path: SHOTS + '/18-dark-inbox.png' });
  await page.locator('table.list tbody tr').first().click();
  await page.waitForSelector('.report');
  await page.screenshot({ path: SHOTS + '/19-dark-report.png', fullPage: true });
  await page.setViewportSize({ width: 400, height: 860 });
  await page.waitForTimeout(200);
  await page.screenshot({ path: SHOTS + '/20-phone-report.png', fullPage: true });
  const wide = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  ok(!wide, 'no sideways scroll at phone width');
  await page.click('text=All reports');
  await page.screenshot({ path: SHOTS + '/21-phone-inbox.png' });

  ok(errs.length === 0, 'no console errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
  await browser.close();
  console.log('\nscreenshots:', SHOTS, '\nfiles:', OUT);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
