// node web/test/make_fixtures.js
// Signs and builds reports with the desktop code, so the phone code can be tested on them
// (test/web_fixtures_test.dart opens everything in test/fixtures/web).
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const V = require('../src/core.js');

const here = __dirname;
const phoneFiles = ['a_sent', 'a_bi', 'a_acc', 'a_approved', 'b_sent', 'b_returned', 'b_r2_sent', 'b_r2_bi'];
const read = (n) => new Uint8Array(fs.readFileSync(path.join(here, 'fixtures', n + '.vlbreport')));

const bi = { id: 'WEB-BI-01', name: 'रमेश पाटील', designation: 'Block Integrator', role: 'bi' };
const acc = { id: 'WEB-AC-01', name: 'Meena Shah', designation: 'Accountant', role: 'acc' };
const di = { id: 'WEB-DI-01', name: 'Jitendra "JR" Sonawane', designation: 'District Integrator', role: 'di' };

const out = {};

async function signed(from, steps) {
  const f = await V.decodeReportFile(read(from));
  let rep = f.report;
  for (const [who, opts] of steps) rep = await V.signReport(rep, who, opts);
  return V.encodeReportFile(rep, f.raw, f.photos);
}

(async () => {
  out.web_a_approved = await signed('a_sent', [
    [bi, { decision: 'forward', remarks: 'Trips match the diary. मीटर फोटो स्पष्ट आहेत. 👍', at: '2026-10-29T05:00:00.000Z' }],
    [acc, { decision: 'forward', remarks: 'Km × rate checked against "vouchers"\\ok\nsecond line', at: '2026-10-29T06:00:00.123Z' }],
    [di, { decision: 'approve', remarks: '', excessApproved: true, at: '2026-10-30T04:00:00.000Z' }],
  ]);
  out.web_a_approved_within = await signed('a_sent', [
    [bi, { decision: 'forward', remarks: 'ok', at: '2026-10-29T05:00:00.000Z' }],
    [acc, { decision: 'forward', remarks: 'ok', at: '2026-10-29T06:00:00.000Z' }],
    [di, { decision: 'approve', remarks: 'Only the first 500 km', excessApproved: false, at: '2026-10-30T04:00:00.000Z' }],
  ]);
  out.web_b_returned = await signed('b_sent', [[bi, { decision: 'return', remarks: 'Explain the task of 2 Oct. "More detail" please.', at: '2026-10-28T10:00:00.000Z' }]]);
  out.web_b_r2_acc = await signed('b_r2_bi', [[acc, { decision: 'forward', remarks: 'Verified', at: '2026-10-28T12:00:00.000Z' }]]);
  out.web_a_returned_by_acc = await signed('a_bi', [[acc, { decision: 'return', remarks: 'Voucher for 10 Oct missing', at: '2026-10-29T06:00:00.000Z' }]]);

  // A report built on the desktop (the sample report in the app): GPS, a note, a late entry, a cancelled trip.
  const staff = { id: 'SAMPLE-001', name: 'Sample Staff', designation: 'Field Officer', block: 'Shahada', district: 'Nandurbar', mobile: '9800000000' };
  const policy = { org: 'Development Support Centre (DSC)', office: 'Nandurbar', limitKm: 500, rate: 4, scope: 'staff', highKm: 200 };
  const photos = new Map();
  const trips = [];
  const photo = (key) => {
    const b64 = Buffer.from('sample photo ' + key + ' फोटो').toString('base64');
    photos.set(key, b64);
    return V.sha256Hex(Buffer.from(b64, 'base64'));
  };
  const mk = async (id, date, open, close, extra) => {
    const t = V.normTrip({
      id, mode: 'full', date, month: date.slice(0, 7), project: 'NABARD', vehicle: 'MH39AB1234', vtype: 'Two wheeler',
      from: 'Nandurbar', to: 'Shahada', activity: 'Village meeting', task: 'Meeting', status: 'closed', km: close - open,
      start: { km: open, photo: id + 's', photoHash: await photo(id + 's'), at: date + 'T03:30:00.000Z', gps: { lat: 21, lng: 74.25, acc: 8 } },
      end: { km: close, photo: id + 'e', photoHash: await photo(id + 'e'), at: date + 'T11:30:00.000Z' },
      loggedAt: date + 'T11:35:00.000Z', ...extra,
    });
    await V.sealTrip(t, trips, date + 'T11:36:00.000Z');
    trips.push(t);
  };
  await mk('w1', '2026-09-02', 100, 180, {});
  await mk('w2', '2026-09-09', 180, 330, { late: { reason: 'Forgot' }, notes: [{ at: '2026-09-10T00:00:00.000Z', text: 'Receipt kept' }] });
  await mk('w3', '2026-09-20', 330, 700, { prior: { by: 'DI', date: '2026-09-19', mode: 'Phone call', ref: '', none: false } });
  const built = await V.buildReport({ staff, policy, month: '2026-09', trips, photos, at: '2026-09-30T05:00:00.000Z' });
  const raw = V.reportToRaw(built);
  out.web_built_sent = await V.encodeReportFile(built, raw, photos);
  const signedBuilt = await V.signReport(built, bi, { decision: 'forward', remarks: 'ok', at: '2026-10-01T05:00:00.000Z' });
  out.web_built_bi = await V.encodeReportFile(signedBuilt, raw, photos);

  for (const dir of [path.join(here, 'fixtures'), path.join(here, '..', '..', 'test', 'fixtures', 'web')]) {
    fs.mkdirSync(dir, { recursive: true });
    for (const [name, bytes] of Object.entries(out)) fs.writeFileSync(path.join(dir, name + '.vlbreport'), bytes);
    if (dir.includes('test/fixtures/web')) for (const n of phoneFiles) fs.copyFileSync(path.join(here, 'fixtures', n + '.vlbreport'), path.join(dir, n + '.vlbreport'));
  }
  console.log(Object.keys(out).join('\n'));
})();
