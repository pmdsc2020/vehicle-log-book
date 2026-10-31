// node --test web/test
// The desktop reviewer's checks against report files made by the phone code (web/test/fixtures/*.vlbreport,
// written by test/web_vectors_test.dart), against tampering, and against signing on the desktop.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const V = require('../src/core.js');

const FIX = path.join(__dirname, 'fixtures');
const load = (name) => new Uint8Array(fs.readFileSync(path.join(FIX, name + '.vlbreport')));
const open = (name) => V.openReportFile(load(name));
const problems = (c) => c.lines.filter((l) => l.state === 'bad').map((l) => l.title + (l.detail ? ': ' + l.detail : ''));
const bad = (c, part) => c.lines.some((l) => l.state === 'bad' && l.title.includes(part));

const bi = { id: 'WEB-BI-01', name: 'रमेश पाटील', designation: 'Block Integrator', role: 'bi' };
const acc = { id: 'WEB-AC-01', name: 'Meena Shah', designation: 'Accountant', role: 'acc' };
const di = { id: 'WEB-DI-01', name: 'Jitendra Sonawane', designation: 'District Integrator', role: 'di' };

/** Changes the file's JSON and packs it again, as someone tampering with it would. */
async function tampered(name, change) {
  const f = await V.decodeReportFile(load(name));
  change(f.raw);
  const bytes = await V.gzip_for_test(JSON.stringify(f.raw));
  return V.openReportFile(bytes);
}
V.gzip_for_test = async (text) => {
  const stream = new Blob([new TextEncoder().encode(text)]).stream().pipeThrough(new CompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
};

test('SHA-256 in plain JavaScript agrees with the system one', async () => {
  for (const n of [0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 1000, 65537]) {
    const b = crypto.randomBytes(n);
    assert.equal(V.sha256Pure(b), crypto.createHash('sha256').update(b).digest('hex'), 'length ' + n);
  }
  assert.equal(await V.sha256Hex('जितेंद्र 🚗'), crypto.createHash('sha256').update('जितेंद्र 🚗').digest('hex'));
});

test('numbers and text are written the way Dart writes them', () => {
  assert.equal(V.djson([new V.Dbl(4), new V.Dbl(4.35), new V.Dbl(21), 5, null, true, 'a"b\\c\n']), '[4.0,4.35,21.0,5,null,true,"a\\"b\\\\c\\n"]');
  assert.equal(V.djson({ a: [1, { b: new V.Dbl(0.5) }], c: '' }), '{"a":[1,{"b":0.5}],"c":""}');
  assert.equal(V.djson('रमेश 🚗'), '"रमेश 🚗"');
});

for (const name of ['a_sent', 'a_bi', 'a_acc', 'a_approved', 'b_sent', 'b_returned', 'b_r2_sent', 'b_r2_bi']) {
  test('phone file ' + name + ' passes every check', async () => {
    const f = await open(name);
    assert.deepEqual(problems(f.check), []);
    assert.equal(f.check.ok, true);
  });
}

test('where each phone file stands', async () => {
  const s = async (n) => V.statusOf((await open(n)).report);
  assert.equal((await s('a_sent')).stage, 'withBi');
  assert.equal((await s('a_bi')).stage, 'withAcc');
  assert.equal((await s('a_acc')).stage, 'withDi');
  const done = await open('a_approved');
  assert.equal(V.statusOf(done.report).stage, 'approved');
  assert.equal(V.payableKm(done.report), 600);
  assert.equal(V.payableAmount(done.report), 2400);
  assert.equal((await s('b_returned')).stage, 'returned');
  const r2 = await open('b_r2_sent');
  assert.equal(r2.report.revision, 2);
  assert.equal(r2.report.replaces.revision, 1);
  assert.equal(r2.report.replaces.step, 'bi');
});

test('figures are the phone\'s, including awkward ones', async () => {
  const a = (await open('a_sent')).report;
  assert.deepEqual(a.summary, { trips: 3, km: 600, within: 500, excess: 100, amount: 2000 });
  const b = (await open('b_sent')).report;
  assert.deepEqual(b.summary, { trips: 3, km: 430, within: 390, excess: 40, amount: 390 * 4.35 });
  assert.equal(b.policy.scope, 'project');
});

test('the odd trips are read right: cancelled, late, meter reset, prior approval, notes, GPS', async () => {
  const a = (await open('a_sent')).report;
  const by = (id) => a.trips.find((t) => t.id === id);
  assert.equal(by('t3').status, 'cancelled');
  assert.equal(by('t3').end, null);
  assert.deepEqual(V.tripFlags(by('t2'), a.policy).sort(), ['Late entry', 'Photo not fresh', 'High km'].sort());
  assert.deepEqual(V.tripFlags(by('t4'), a.policy), ['Meter reset']);
  assert.equal(by('t1').start.gps.lat, 21);
  assert.equal(by('t2').notes.length, 1);
});

test('reviewer aids: meter jumps and the unlogged km', async () => {
  const a = (await open('a_sent')).report;
  const aids = V.reviewAids(a);
  assert.ok(aids.lines.length > 0);
  assert.equal(aids.lines.some((l) => l.state === 'warn' && l.title.includes('differs')), false);
});

// ---------------------------------------------------------------- tampering

test('a trip edited after it was locked is caught', async () => {
  const f = await tampered('a_approved', (j) => (j.trips[0].task = 'Something else'));
  assert.ok(bad(f.check, 'do not match their seal'));
  assert.ok(bad(f.check, 'fingerprint does not match'));
  assert.equal(f.check.ok, false);
});

test('km changed on a trip is caught', async () => {
  const f = await tampered('a_sent', (j) => (j.trips[1].km = 10));
  assert.equal(f.check.ok, false);
});

test('a note slipped into a locked trip is caught by the fingerprint', async () => {
  const f = await tampered('a_sent', (j) => j.trips[0].notes.push({ at: '2026-10-30T00:00:00.000Z', text: 'extra' }));
  assert.ok(bad(f.check, 'fingerprint does not match'));
});

test('a swapped meter photo is caught', async () => {
  const f = await tampered('a_sent', (j) => (j.photos.t1s = Buffer.from('another picture').toString('base64')));
  assert.ok(bad(f.check, 'Odometer photos'));
});

test('a photo left out is caught', async () => {
  const f = await tampered('a_sent', (j) => delete j.photos.t1e);
  assert.ok(bad(f.check, 'Odometer photos'));
});

test('a trip taken out is caught', async () => {
  const f = await tampered('a_sent', (j) => j.trips.splice(1, 1));
  assert.equal(f.check.ok, false);
});

test('rate changed is caught', async () => {
  const f = await tampered('a_sent', (j) => (j.policy.rate = 5));
  assert.equal(f.check.ok, false);
});

test('a sign-off with rewritten remarks is caught', async () => {
  const f = await tampered('a_approved', (j) => (j.signoffs[1].remarks = 'rewritten'));
  assert.ok(bad(f.check, 'Sign-offs do not add up'));
});

test('a sign-off removed from the middle is caught', async () => {
  const f = await tampered('a_approved', (j) => j.signoffs.splice(1, 1));
  assert.ok(bad(f.check, 'Sign-offs do not add up'));
});

test('a sign-off added after the report was returned is caught', async () => {
  const f = await tampered('b_returned', (j) => j.signoffs.push({ ...j.signoffs[1], step: 'acc', role: 'acc', userId: 'X-1' }));
  assert.ok(bad(f.check, 'Sign-offs do not add up'));
});

test('the staff member signing as a reviewer is caught', async () => {
  const f = await tampered('a_sent', (j) => j.signoffs.push({ ...j.signoffs[0], step: 'bi', role: 'bi' }));
  assert.ok(bad(f.check, 'Sign-offs do not add up'));
});

test('not a report', async () => {
  await assert.rejects(() => V.decodeReportFile(new Uint8Array(0)), /empty/);
  await assert.rejects(() => V.decodeReportFile(new TextEncoder().encode('hello')), /not a vehicle log report/);
  await assert.rejects(() => V.decodeReportFile(new TextEncoder().encode('[1,2]')), /not a vehicle log report/);
  const bytes = await V.gzip_for_test(JSON.stringify({ reportId: '../x', staff: {}, policy: {}, summary: {}, trips: [], signoffs: [] }));
  await assert.rejects(() => V.decodeReportFile(bytes), /bad id/);
  const bytes2 = await V.gzip_for_test(JSON.stringify({ ...(await V.decodeReportFile(load('a_sent'))).raw, photos: { '../evil': 'AAAA' } }));
  await assert.rejects(() => V.decodeReportFile(bytes2), /bad name/);
});

test('a plain text copy opens too', async () => {
  const f = await V.decodeReportFile(load('a_sent'));
  const plain = new TextEncoder().encode(JSON.stringify(f.raw));
  const g = await V.openReportFile(plain);
  assert.equal(g.check.ok, true);
});

// ---------------------------------------------------------------- signing on the desktop

test('signing goes BI, Accountant, District Integrator, and each step is accepted', async () => {
  let f = await open('a_sent');
  let rep = f.report;
  for (const [who, opts] of [
    [bi, { decision: 'forward', remarks: 'Trips match. मीटर फोटो स्पष्ट. 👍' }],
    [acc, { decision: 'forward', remarks: 'Checked "vouchers"' }],
    [di, { decision: 'approve', remarks: '', excessApproved: true }],
  ]) {
    rep = await V.signReport(rep, who, opts);
    const bytes = await V.encodeReportFile(rep, f.raw, f.photos);
    f = await V.openReportFile(bytes);
    assert.deepEqual(problems(f.check), []);
    assert.equal(f.report.signoffs.length, rep.signoffs.length);
  }
  assert.equal(V.statusOf(f.report).stage, 'approved');
  assert.equal(V.payableKm(f.report), 600);
  assert.equal(f.report.signoffs[3].excessApproved, true);
});

test('the District Integrator can leave the extra km unapproved', async () => {
  let f = await open('a_acc');
  const rep = await V.signReport(f.report, di, { decision: 'approve', remarks: 'Only within the limit', excessApproved: false });
  assert.equal(V.payableKm(rep), 500);
  assert.equal(V.payableAmount(rep), 2000);
});

test('sending back needs a reason, and ends the report', async () => {
  const f = await open('b_sent');
  await assert.rejects(() => V.signReport(f.report, bi, { decision: 'return', remarks: '  ' }), /Write why/);
  const r = await V.signReport(f.report, bi, { decision: 'return', remarks: 'Fix the task of 2 Oct' });
  assert.equal(V.statusOf(r).stage, 'returned');
  await assert.rejects(() => V.signReport(r, acc, { decision: 'forward' }), /already finished/);
});

test('the rules of signing', async () => {
  const f = await open('a_sent');
  await assert.rejects(() => V.signReport(f.report, acc, { decision: 'forward' }), /waiting for the Block Integrator/);
  await assert.rejects(() => V.signReport(f.report, { ...bi, id: f.report.staff.id }, { decision: 'forward' }), /own report/);
  await assert.rejects(() => V.signReport(f.report, { id: 'S-9', name: 'Field', role: 'staff' }, { decision: 'forward' }), /waiting for the Block Integrator/);
  await assert.rejects(() => V.signReport(f.report, bi, { decision: 'approve' }), /not a choice/);
});

test('excess km can only be approved by the District Integrator, and only when there is any', async () => {
  const b = await open('b_r2_bi');
  const accOnly = await V.signReport(b.report, acc, { decision: 'forward', excessApproved: true });
  assert.equal(accOnly.signoffs[accOnly.signoffs.length - 1].excessApproved, false);
});

test('a copy of the same report held twice is told apart', async () => {
  const a1 = (await open('a_bi')).report;
  const a2 = (await open('a_acc')).report;
  const a0 = (await open('a_sent')).report;
  assert.equal(V.relate(null, a1), 'new');
  assert.equal(V.relate(a1, a2), 'newer');
  assert.equal(V.relate(a2, a1), 'same');
  assert.equal(V.relate(a1, a1), 'same');
  assert.equal(V.relate(a0, a1), 'newer');
  const other = await V.signReport(a0, { ...bi, id: 'OTHER-BI' }, { decision: 'forward', remarks: 'different', at: '2026-10-28T08:30:00.000Z' });
  assert.equal(V.relate(a1, other), 'conflict');
});

test('continuity with the month before, when held', async () => {
  const f = await open('a_sent');
  const earlier = JSON.parse(JSON.stringify(f.report));
  const b = await V.verifyReport(f.report, await V.hashPhotos(f.photos), earlier);
  assert.equal(b.lines.some((l) => l.title === 'Does not continue from the earlier month' || l.title === 'Continues from the earlier month'), true);
});

test('file name and share text', async () => {
  const f = await open('a_bi');
  assert.equal(V.reportFileName(f.report), 'VehicleLog_2026-10_Asha-Tai-Pawar_r1_s2.vlbreport');
  assert.match(V.reportShareText(f.report), /With Accountant/);
});

test('figures print the Indian way', () => {
  assert.equal(V.fmtKm(123456), '1,23,456');
  assert.equal(V.fmtKm(585), '585');
  assert.equal(V.fmtRs(2340), '₹2,340');
  assert.equal(V.fmtRs(1696.5), '₹1,696.50');
  assert.equal(V.fmtMonthLong('2026-10'), 'October 2026');
  assert.equal(V.shiftMonth('2026-01', -1), '2025-12');
});
