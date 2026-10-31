/*
 * Vehicle Log Book reviewer: the part with no screen.
 *
 * Reads the same report file the phones send (.vlbreport), runs the same checks, signs, and writes the file
 * back. Every hash here is worked out exactly as the Flutter app does it (lib/services/report_service.dart and
 * lib/services/trip_rules.dart), including the way Dart writes numbers: a whole-number double is "4.0".
 * web/test checks this against report files made by the phone code.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.VLB = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const REPORT_FORMAT = 1;
  const FILE_EXT = 'vlbreport';
  const STEPS = ['submit', 'bi', 'acc', 'di'];
  const SAFE_NAME = /^[A-Za-z0-9_-]{1,80}$/;
  const MAX_FILE_BYTES = 120 * 1024 * 1024;
  const MAX_PHOTOS = 600;

  class ReportError extends Error {
    constructor(message) {
      super(message);
      this.name = 'ReportError';
    }
  }

  // ------------------------------------------------------------------ SHA-256

  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98,
    0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8,
    0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
    0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
    0xc67178f2,
  ]);

  /** Plain JavaScript SHA-256 of bytes, as hex. Used when the browser has no crypto.subtle. */
  function sha256Pure(data) {
    const len = data.length;
    const padded = new Uint8Array(((len + 9 + 63) >> 6) << 6);
    padded.set(data);
    padded[len] = 0x80;
    const dv = new DataView(padded.buffer);
    dv.setUint32(padded.length - 8, Math.floor((len * 8) / 4294967296));
    dv.setUint32(padded.length - 4, (len * 8) >>> 0);
    const h = new Uint32Array([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]);
    const w = new Uint32Array(64);
    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4);
      for (let i = 16; i < 64; i++) {
        const a = w[i - 15], b = w[i - 2];
        const s0 = ((a >>> 7) | (a << 25)) ^ ((a >>> 18) | (a << 14)) ^ (a >>> 3);
        const s1 = ((b >>> 17) | (b << 15)) ^ ((b >>> 19) | (b << 13)) ^ (b >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      let a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (let i = 0; i < 64; i++) {
        const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
        const ch = (e & f) ^ (~e & g);
        const t1 = (hh + S1 + ch + K[i] + w[i]) | 0;
        const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (S0 + maj) | 0;
        hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
      }
      h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
    let out = '';
    for (let i = 0; i < 8; i++) out += h[i].toString(16).padStart(8, '0');
    return out;
  }

  const hasSubtle = () =>
    typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle && globalThis.crypto.subtle.digest;

  function toHex(buf) {
    const b = new Uint8Array(buf);
    let s = '';
    for (let i = 0; i < b.length; i++) s += b[i].toString(16).padStart(2, '0');
    return s;
  }

  /** SHA-256 of a string (UTF-8) or of bytes, as lowercase hex. */
  async function sha256Hex(input) {
    const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
    if (hasSubtle()) {
      try {
        return toHex(await globalThis.crypto.subtle.digest('SHA-256', bytes));
      } catch (_) {
        /* fall through to the plain version */
      }
    }
    return sha256Pure(bytes);
  }

  // ------------------------------------------------------------------ JSON the way Dart writes it

  /** A number that Dart holds as a double. Whole values print with ".0". */
  class Dbl {
    constructor(n) {
      this.n = n;
    }
  }

  function dartDouble(n) {
    if (!Number.isFinite(n)) throw new ReportError('A number in the report is not valid.');
    if (Number.isInteger(n) && Math.abs(n) < 1e21) return String(n) + '.0';
    return String(n);
  }

  /** Same text as Dart's jsonEncode for the values used in seals. */
  function djson(v) {
    if (v === null || v === undefined) return 'null';
    if (v instanceof Dbl) return dartDouble(v.n);
    switch (typeof v) {
      case 'string':
        return JSON.stringify(v);
      case 'boolean':
        return v ? 'true' : 'false';
      case 'number':
        return Number.isInteger(v) ? String(v) : dartDouble(v);
      default:
        break;
    }
    if (Array.isArray(v)) return '[' + v.map(djson).join(',') + ']';
    const keys = Object.keys(v);
    return '{' + keys.map((k) => JSON.stringify(k) + ':' + djson(v[k])).join(',') + '}';
  }

  // ------------------------------------------------------------------ reading the file into a report

  const S = (v) => (v === null || v === undefined ? '' : String(v));
  const I = (v) => {
    if (typeof v === 'number') return Math.trunc(v);
    const n = parseInt(S(v), 10);
    return Number.isNaN(n) ? 0 : n;
  };
  const nn = (v, d) => (v === undefined || v === null ? d : v);
  const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

  function normReading(j) {
    j = isObj(j) ? j : {};
    let gps = null;
    if (j.gps !== null && j.gps !== undefined) {
      if (!isObj(j.gps) || typeof j.gps.lat !== 'number' || typeof j.gps.lng !== 'number') throw new ReportError('bad gps');
      gps = { lat: j.gps.lat, lng: j.gps.lng, acc: nn(j.gps.acc, 0) };
    }
    return {
      km: nn(j.km, 0),
      photo: nn(j.photo, null),
      photoHash: nn(j.photoHash, null),
      at: nn(j.at, ''),
      gps,
      photoTime: nn(j.photoTime, null),
      oldPhoto: nn(j.oldPhoto, false),
      prevKm: nn(j.prevKm, null),
      returnTo: nn(j.returnTo, null),
      remarks: nn(j.remarks, null),
    };
  }

  function normTrip(j) {
    if (!isObj(j)) throw new ReportError('bad trip');
    return {
      id: nn(j.id, ''),
      schema: nn(j.schema, 1),
      mode: nn(j.mode, 'start'),
      date: nn(j.date, ''),
      month: nn(j.month, ''),
      project: nn(j.project, ''),
      vehicle: nn(j.vehicle, ''),
      vtype: nn(j.vtype, ''),
      from: nn(j.from, ''),
      to: nn(j.to, ''),
      activity: nn(j.activity, ''),
      task: nn(j.task, ''),
      start: normReading(nn(j.start, {})),
      end: j.end !== null && j.end !== undefined ? normReading(j.end) : null,
      km: nn(j.km, null),
      status: nn(j.status, 'open'),
      late: nn(j.late, null),
      meterReset: nn(j.meterReset, null),
      prior: nn(j.prior, null),
      cancel: nn(j.cancel, null),
      notes: (Array.isArray(j.notes) ? j.notes : []).map((n) => ({ at: nn(isObj(n) ? n.at : '', ''), text: nn(isObj(n) ? n.text : '', '') })),
      loggedAt: nn(j.loggedAt, ''),
      chainPos: nn(j.chainPos, null),
      prevHash: nn(j.prevHash, null),
      lockedAt: nn(j.lockedAt, null),
      hash: nn(j.hash, null),
    };
  }

  function normSignoff(j) {
    if (!isObj(j)) throw new ReportError('bad signoff');
    return {
      step: S(j.step), userId: S(j.userId), name: S(j.name), designation: S(j.designation), role: S(j.role),
      at: S(j.at), decision: S(j.decision), remarks: S(j.remarks), excessApproved: j.excessApproved === true,
      prevHash: S(j.prevHash), hash: S(j.hash),
    };
  }

  function normReport(j) {
    try {
      if (!isObj(j)) throw new ReportError('This file is not a vehicle log report.');
      const id = S(j.reportId);
      if (!SAFE_NAME.test(id)) throw new ReportError('The report has a bad id.');
      const photoHashes = new Map();
      if (isObj(j.photoHashes)) {
        for (const k of Object.keys(j.photoHashes)) {
          if (!SAFE_NAME.test(k)) throw new ReportError('A photo in the report has a bad name.');
          photoHashes.set(k, S(j.photoHashes[k]));
        }
      }
      if (!isObj(j.staff) || !isObj(j.policy) || !isObj(j.summary)) throw new Error('shape');
      const rev = I(j.revision);
      const r = j.replaces;
      return {
        format: I(j.format),
        reportId: id,
        revision: rev < 1 ? 1 : rev,
        month: S(j.month),
        staff: {
          id: S(j.staff.id), name: S(j.staff.name), designation: S(j.staff.designation), block: S(j.staff.block),
          district: S(j.staff.district), mobile: S(j.staff.mobile),
        },
        policy: {
          org: S(j.policy.org), office: S(j.policy.office), limitKm: I(j.policy.limitKm),
          rate: nn(j.policy.rate, 0), scope: S(j.policy.scope) === '' ? 'staff' : S(j.policy.scope), highKm: I(j.policy.highKm),
        },
        summary: {
          trips: I(j.summary.trips), km: I(j.summary.km), within: I(j.summary.within), excess: I(j.summary.excess),
          amount: nn(j.summary.amount, 0),
        },
        submittedAt: S(j.submittedAt),
        replaces:
          r === null || r === undefined
            ? null
            : { revision: I(r.revision), step: S(r.step), name: S(r.name), role: S(r.role), remarks: S(r.remarks), at: S(r.at), hash: S(r.hash) },
        trips: j.trips.map(normTrip),
        photoHashes,
        contentHash: S(j.contentHash),
        signoffs: j.signoffs.map(normSignoff),
      };
    } catch (e) {
      if (e instanceof ReportError) throw e;
      throw new ReportError('This file is not a vehicle log report, or it is damaged.');
    }
  }

  // ------------------------------------------------------------------ labels

  const stepOfRole = (role) => (role === 'bi' || role === 'acc' || role === 'di' ? role : null);

  function stepRoleLabel(step) {
    return { bi: 'Block Integrator', acc: 'Accountant', di: 'District Integrator' }[step] || 'Field staff';
  }

  function signoffVerb(s) {
    if (s.decision === 'return') return 'Returned';
    return { bi: 'Checked', acc: 'Verified', di: 'Approved' }[s.step] || 'Sent';
  }

  function decisionsFor(step) {
    if (step === 'bi' || step === 'acc') return ['forward', 'return'];
    if (step === 'di') return ['approve', 'return'];
    return ['sent'];
  }

  // ------------------------------------------------------------------ dates and figures

  function fmtDate(ymd) {
    const p = String(ymd).split('-');
    return p.length !== 3 ? String(ymd) : p[2] + '-' + p[1] + '-' + p[0];
  }

  /** Whole number with Indian digit grouping: 1,23,456. */
  function fmtKm(n) {
    const s = String(Math.abs(Math.round(n)));
    let out;
    if (s.length <= 3) out = s;
    else {
      const head = s.slice(0, -3);
      const tail = s.slice(-3);
      let buf = '';
      for (let i = 0; i < head.length; i++) {
        if (i > 0 && (head.length - i) % 2 === 0) buf += ',';
        buf += head[i];
      }
      out = buf + ',' + tail;
    }
    return n < 0 ? '-' + out : out;
  }

  function fmtRs(n) {
    let whole = Math.floor(n);
    let paise = Math.round((n - whole) * 100);
    if (paise >= 100) {
      whole += 1;
      paise = 0;
    }
    const head = '₹' + fmtKm(whole);
    return paise === 0 ? head : head + '.' + String(paise).padStart(2, '0');
  }

  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  function fmtMonthLong(m) {
    const y = parseInt(String(m).slice(0, 4), 10);
    const mo = parseInt(String(m).slice(5, 7), 10);
    return mo >= 1 && mo <= 12 ? MONTHS[mo - 1] + ' ' + y : String(m);
  }

  function shiftMonth(month, by) {
    const y = parseInt(month.slice(0, 4), 10) || 2000;
    const m = parseInt(month.slice(5, 7), 10) || 1;
    const d = new Date(Date.UTC(y, m - 1 + by, 1));
    return String(d.getUTCFullYear()).padStart(4, '0') + '-' + String(d.getUTCMonth() + 1).padStart(2, '0');
  }

  // ------------------------------------------------------------------ seals

  const gpsKey = (g) => (g === null ? '' : [new Dbl(g.lat), new Dbl(g.lng), g.acc]);

  /** The fields a trip seal covers (coreOf in trip_rules.dart). */
  function coreOf(t) {
    const s = t.start;
    const e = t.end;
    const lateInfo = t.late;
    const reset = t.meterReset;
    const prior = t.prior;
    const cancel = t.cancel;
    return [
      t.id, t.chainPos, t.date, t.project, t.vehicle, t.from, t.to, t.activity, t.task, t.mode,
      [s.km, nn(s.photoHash, ''), s.at, gpsKey(s.gps), nn(s.photoTime, ''), nn(s.prevKm, '')],
      e === null ? '' : [e.km, nn(e.photoHash, ''), e.at, gpsKey(e.gps), nn(e.photoTime, ''), nn(e.returnTo, ''), nn(e.remarks, '')],
      t.km,
      t.status,
      lateInfo === null ? '' : nn(lateInfo.reason, ''),
      reset === null ? '' : nn(reset.reason, ''),
      prior === null ? '' : [nn(prior.by, ''), nn(prior.date, ''), nn(prior.mode, ''), nn(prior.ref, ''), prior.none === true],
      cancel === null ? '' : [nn(cancel.reason, ''), nn(cancel.at, '')],
      t.loggedAt,
      nn(t.prevHash, ''),
    ];
  }

  const hashTrip = (t) => sha256Hex(djson(coreOf(t)));

  async function sealIntact(t) {
    return t.hash !== null && t.hash === (await hashTrip(t));
  }

  /** The trip as the phone writes it with toJson, for the report fingerprint. */
  function tripForHash(t) {
    const rd = (r) =>
      r === null
        ? null
        : {
            km: r.km, photo: r.photo, photoHash: r.photoHash, at: r.at,
            gps: r.gps === null ? null : { lat: new Dbl(r.gps.lat), lng: new Dbl(r.gps.lng), acc: r.gps.acc },
            photoTime: r.photoTime, oldPhoto: r.oldPhoto, prevKm: r.prevKm, returnTo: r.returnTo, remarks: r.remarks,
          };
    return {
      id: t.id, schema: t.schema, mode: t.mode, date: t.date, month: t.month, project: t.project, vehicle: t.vehicle,
      vtype: t.vtype, from: t.from, to: t.to, activity: t.activity, task: t.task, start: rd(t.start), end: rd(t.end),
      km: t.km, status: t.status, late: t.late, meterReset: t.meterReset, prior: t.prior, cancel: t.cancel,
      notes: t.notes.map((n) => ({ at: n.at, text: n.text })), loggedAt: t.loggedAt, chainPos: t.chainPos,
      prevHash: t.prevHash, lockedAt: t.lockedAt, hash: t.hash,
    };
  }

  async function reportContentHash(p) {
    const keys = [...p.photoHashes.keys()].sort();
    const tripHashes = [];
    for (const t of p.trips) tripHashes.push(await sha256Hex(djson(tripForHash(t))));
    const r = p.replaces;
    const core = [
      'vlb-report', p.format, p.reportId, p.revision, p.month,
      [p.staff.id, p.staff.name, p.staff.designation, p.staff.block, p.staff.district, p.staff.mobile],
      [p.policy.org, p.policy.office, p.policy.limitKm, new Dbl(p.policy.rate), p.policy.scope, p.policy.highKm],
      [p.summary.trips, p.summary.km, p.summary.within, p.summary.excess, new Dbl(p.summary.amount)],
      p.submittedAt,
      r ? [r.revision, r.step, r.name, r.role, r.remarks, r.at, r.hash] : '',
      tripHashes,
      keys.map((k) => [k, p.photoHashes.get(k)]),
    ];
    return sha256Hex(djson(core));
  }

  const signoffHash = (p, s) =>
    sha256Hex(
      djson(['vlb-signoff', p.reportId, p.revision, s.step, s.userId, s.name, s.designation, s.role, s.at, s.decision, s.remarks, s.excessApproved, s.prevHash])
    );

  // ------------------------------------------------------------------ figures

  /** Totals for a month, the way the phone works them out. */
  function summarise(trips, policy) {
    const kmBy = new Map();
    const countBy = new Map();
    let km = 0;
    let n = 0;
    for (const t of trips) {
      if (t.status !== 'closed') continue;
      const k = t.km === null || t.km === undefined ? 0 : t.km;
      km += k;
      n += 1;
      kmBy.set(t.project, (kmBy.get(t.project) || 0) + k);
      countBy.set(t.project, (countBy.get(t.project) || 0) + 1);
    }
    let within = 0;
    let excess = 0;
    let gauge = 0;
    if (policy.scope === 'project') {
      for (const v of kmBy.values()) {
        within += v > policy.limitKm ? policy.limitKm : v;
        excess += v > policy.limitKm ? v - policy.limitKm : 0;
        if (v > gauge) gauge = v;
      }
    } else {
      within = km > policy.limitKm ? policy.limitKm : km;
      excess = km > policy.limitKm ? km - policy.limitKm : 0;
      gauge = km;
    }
    return { trips: n, km, within, excess, amount: within * policy.rate, gaugeKm: gauge, kmByProject: kmBy, tripsByProject: countBy };
  }

  function tripFlags(t, policy) {
    const out = [];
    if (t.late !== null) out.push('Late entry');
    if (t.meterReset !== null) out.push('Meter reset');
    if (t.prior !== null && t.prior.none === true) out.push('No prior approval');
    if (t.start.oldPhoto === true || (t.end !== null && t.end.oldPhoto === true)) out.push('Photo not fresh');
    if ((t.km || 0) > policy.highKm) out.push('High km');
    return out;
  }

  // ------------------------------------------------------------------ where the report stands

  function statusOf(p) {
    if (p.signoffs.length === 0) return { stage: 'withBi', done: 0, returnedAt: null, last: null, nextStep: 'bi', finished: false };
    const last = p.signoffs[p.signoffs.length - 1];
    const idx = STEPS.indexOf(last.step);
    if (last.decision === 'return') {
      const i = idx < 0 ? 0 : idx;
      return { stage: 'returned', done: i, returnedAt: i, last, nextStep: null, finished: true };
    }
    const table = {
      submit: ['withBi', 1, 'bi'],
      bi: ['withAcc', 2, 'acc'],
      acc: ['withDi', 3, 'di'],
      di: ['approved', 4, null],
    };
    const row = table[last.step];
    if (!row) return { stage: 'withBi', done: 0, returnedAt: null, last, nextStep: 'bi', finished: false };
    return { stage: row[0], done: row[1], returnedAt: null, last, nextStep: row[2], finished: row[0] === 'approved' };
  }

  function stageLabel(st) {
    return { withBi: 'With Block Integrator', withAcc: 'With Accountant', withDi: 'With District Integrator', approved: 'Approved', returned: 'Returned' }[st.stage];
  }

  function approvalOf(p) {
    return p.signoffs.find((s) => s.step === 'di' && s.decision === 'approve') || null;
  }

  function payableKm(p) {
    const a = approvalOf(p);
    return p.summary.within + (a && a.excessApproved ? p.summary.excess : 0);
  }

  const payableAmount = (p) => payableKm(p) * p.policy.rate;

  // ------------------------------------------------------------------ signing

  /**
   * Adds [by]'s sign-off. [by] is {id, name, designation, role}. Throws ReportError when it is not their turn.
   * Returns a new report object; the one passed in is not changed.
   */
  async function signReport(p, by, opts) {
    const st = statusOf(p);
    const step = st.nextStep;
    if (step === null) throw new ReportError('This report has already finished. Nothing more can be signed on it.');
    if (by.id === p.staff.id) throw new ReportError('You cannot sign off your own report.');
    if (stepOfRole(by.role) !== step) {
      throw new ReportError(
        'This report is waiting for the ' + stepRoleLabel(step) + '. You are signed in as ' + stepRoleLabel(by.role) + '.'
      );
    }
    if (!decisionsFor(step).includes(opts.decision)) throw new ReportError('That is not a choice at this step.');
    const note = (opts.remarks || '').trim();
    if (opts.decision === 'return' && note === '') throw new ReportError('Write why you are sending it back.');
    const s = {
      step, userId: by.id, name: by.name, designation: by.designation || '', role: by.role,
      at: opts.at || new Date().toISOString(), decision: opts.decision, remarks: note,
      excessApproved: step === 'di' && opts.decision === 'approve' && p.summary.excess > 0 && opts.excessApproved === true,
      prevHash: p.signoffs[p.signoffs.length - 1].hash, hash: '',
    };
    s.hash = await signoffHash(p, s);
    return { ...p, signoffs: [...p.signoffs, s] };
  }

  // ------------------------------------------------------------------ checking

  const tripName = (t) => fmtDate(t.date) + ' to ' + t.to;

  function someOf(items) {
    return items.length <= 3 ? items.join('; ') : items.slice(0, 3).join('; ') + '; and ' + (items.length - 3) + ' more';
  }

  /**
   * The checks every person who opens a report runs. [actualPhotos] is a Map of photo name to the SHA-256 of
   * the picture really in the file. [previous] is the same person's report for the month before, if held.
   * Returns {ok, hasWarnings, lines:[{state:'ok'|'warn'|'bad', title, detail}]}.
   */
  async function verifyReport(p, actualPhotos, previous) {
    const lines = [];
    const add = (state, title, detail) => lines.push({ state, title, detail: detail || '' });
    const done = () => ({ ok: !lines.some((l) => l.state === 'bad'), hasWarnings: lines.some((l) => l.state === 'warn'), lines });

    // 1. The file is a whole report.
    const structure = [];
    if (p.format < 1 || p.format > REPORT_FORMAT) structure.push('It was made by a newer version of the app.');
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(p.month)) structure.push('The month is not valid.');
    if (p.staff.id === '' || p.staff.name === '') structure.push('It does not say who sent it.');
    if (p.trips.length === 0) structure.push('It has no trips.');
    if (p.signoffs.length === 0 || p.signoffs[0].step !== 'submit') structure.push('It was never sent by the staff member.');
    if (structure.length) {
      add('bad', 'The report is incomplete', structure.join(' '));
      return done();
    }

    // 2. Nothing changed since it was sent.
    if ((await reportContentHash(p)) === p.contentHash) {
      add('ok', 'Report fingerprint matches', 'Nothing changed after the staff member sent it.');
    } else {
      add('bad', 'Report fingerprint does not match', 'Something in the trips, figures or photos changed after it was sent.');
    }

    // 3. Every trip still matches its seal.
    const badSeals = [];
    const wrongMonth = [];
    const stillOpen = [];
    for (const t of p.trips) {
      if (t.status === 'open') stillOpen.push(tripName(t));
      else if (!(await sealIntact(t))) badSeals.push(tripName(t));
      if (t.month !== p.month) wrongMonth.push(tripName(t));
    }
    if (stillOpen.length) add('bad', 'A trip is still open', someOf(stillOpen));
    else if (badSeals.length) add('bad', badSeals.length + ' of ' + p.trips.length + ' trips do not match their seal', someOf(badSeals));
    else {
      const cancelled = p.trips.filter((t) => t.status === 'cancelled').length;
      add(
        'ok',
        'All ' + p.trips.length + ' entries match their seals',
        cancelled > 0
          ? p.trips.length - cancelled + ' trips and ' + cancelled + ' cancelled. None was edited after it was locked.'
          : 'None was edited after it was locked.'
      );
    }
    if (wrongMonth.length) add('bad', 'Trips from another month are in this report', someOf(wrongMonth));

    // 4. The trips are linked one to the next.
    const byPos = p.trips.filter((t) => t.chainPos !== null).sort((a, b) => a.chainPos - b.chainPos);
    const unsealed = p.trips.length - byPos.length;
    const broken = [];
    const gaps = [];
    let dup = false;
    for (let i = 1; i < byPos.length; i++) {
      const a = byPos[i - 1];
      const b = byPos[i];
      if (a.chainPos === b.chainPos) dup = true;
      else if (b.chainPos === a.chainPos + 1) {
        if (b.prevHash !== a.hash) broken.push(tripName(a) + ' and ' + tripName(b));
      } else gaps.push(a.chainPos + 1 + '-' + (b.chainPos - 1));
    }
    if (unsealed > 0 || dup || broken.length) {
      add(
        'bad',
        'The chain of trips is broken',
        [
          unsealed > 0 ? unsealed + ' trips were never locked.' : '',
          dup ? 'Two trips share one place in the chain.' : '',
          broken.length ? 'Not linked: ' + someOf(broken) + '.' : '',
        ].filter(Boolean).join(' ')
      );
    } else if (gaps.length) {
      add(
        'warn',
        'Entries ' + someOf(gaps) + ' are not in this report',
        'They belong to another month, which is normal when a late entry crosses a month end. If that is not the case, ask for the full log.'
      );
    } else add('ok', 'Trips are linked in order', 'No entry is missing from the chain.');

    // 5. Odometer photos.
    let readings = 0;
    let missing = 0;
    let altered = 0;
    for (const t of p.trips) {
      for (const r of t.end ? [t.start, t.end] : [t.start]) {
        readings += 1;
        const key = r.photo || '';
        const want = r.photoHash || '';
        const listed = p.photoHashes.get(key);
        const actual = actualPhotos.get(key);
        if (key === '' || want === '' || listed === undefined || actual === undefined) missing += 1;
        else if (actual !== want || listed !== want) altered += 1;
      }
    }
    if (missing > 0 || altered > 0) {
      add(
        'bad',
        'Odometer photos: ' + (missing + altered) + ' of ' + readings + ' cannot be trusted',
        [missing > 0 ? missing + ' missing.' : '', altered > 0 ? altered + ' do not match the fingerprint taken when the trip was locked.' : ''].filter(Boolean).join(' ')
      );
    } else add('ok', 'All ' + readings + ' odometer photos are present and unchanged');

    // 6. The figures follow from the trips.
    const again = summarise(p.trips, p.policy);
    const s = p.summary;
    if (again.trips === s.trips && again.km === s.km && again.within === s.within && again.excess === s.excess && again.amount === s.amount) {
      add('ok', 'Figures match the trips', 'Km and amount were worked out again from the trips.');
    } else add('bad', 'Figures do not match the trips', 'The km or amount in the statement differ from the trips.');

    // 7. Sign-offs.
    const problems = [];
    let expectPrev = p.contentHash;
    for (let i = 0; i < p.signoffs.length; i++) {
      const so = p.signoffs[i];
      const who = signoffVerb(so) + ' by ' + so.name;
      if (i >= STEPS.length || so.step !== STEPS[i]) {
        problems.push(who + ' is out of order.');
        break;
      }
      if (so.prevHash !== expectPrev) problems.push(who + ' does not follow the one before it.');
      if ((await signoffHash(p, so)) !== so.hash) problems.push(who + ' was changed.');
      if (i === 0 && so.userId !== p.staff.id) problems.push('The first sign-off is not by the staff member.');
      if (i > 0 && so.userId === p.staff.id) problems.push(who + ' signed their own report.');
      if (!decisionsFor(so.step).includes(so.decision)) problems.push(who + ' has an invalid decision.');
      if (i < p.signoffs.length - 1 && (so.decision === 'return' || so.decision === 'approve')) problems.push('Someone signed after the report was finished.');
      expectPrev = so.hash;
    }
    if (problems.length) add('bad', 'Sign-offs do not add up', someOf(problems));
    else {
      const n = p.signoffs.length;
      add('ok', n === 1 ? 'Sent by ' + p.staff.name : n + ' sign-offs, in order and unchanged');
    }

    // 8. Continues from the month before.
    if (previous && byPos.length) {
      const earlier = previous.trips.filter((t) => t.chainPos !== null).sort((a, b) => a.chainPos - b.chainPos);
      if (earlier.length) {
        const last = earlier[earlier.length - 1];
        const first = byPos[0];
        if (first.chainPos === last.chainPos + 1 && first.prevHash === last.hash) {
          add('ok', 'Continues from the earlier month', 'The first trip follows the last one in the earlier report.');
        } else {
          add('warn', 'Does not continue from the earlier month', 'Some entries between the two reports may be missing, or the staff member changed phone.');
        }
      }
    }
    return done();
  }

  // ------------------------------------------------------------------ extra aids for a reviewer (not sealed)

  const readingOf = (t) => (t.end ? t.end.km : t.start.km);

  function tripOrder(a, b) {
    if (a.date !== b.date) return a.date < b.date ? -1 : 1;
    if (a.start.at !== b.start.at) return a.start.at < b.start.at ? -1 : 1;
    return a.start.km - b.start.km;
  }

  /**
   * Things a careful reviewer looks at that are not part of the seal: km against the meter readings, the meter
   * moving between trips, Sunday trips. Returns {lines, perTrip: Map(tripId -> [{state, text}]), unloggedKm}.
   */
  function reviewAids(p) {
    const perTrip = new Map();
    const note = (t, state, text) => {
      if (!perTrip.has(t.id)) perTrip.set(t.id, []);
      perTrip.get(t.id).push({ state, text });
    };
    const lines = [];

    const mismatch = [];
    const backwards = [];
    for (const t of p.trips) {
      if (t.status !== 'closed' || !t.end) continue;
      const diff = t.end.km - t.start.km;
      if (t.km !== diff) {
        mismatch.push(tripName(t));
        note(t, 'warn', 'Km recorded ' + t.km + ', meter readings give ' + diff + '.');
      }
      if (t.end.at && t.start.at && t.end.at < t.start.at) {
        backwards.push(tripName(t));
        note(t, 'warn', 'Closing time is before the opening time.');
      }
    }
    if (mismatch.length) lines.push({ state: 'warn', title: 'Km differs from the meter readings', detail: someOf(mismatch) });
    else lines.push({ state: 'ok', title: 'Km equals closing minus opening on every trip' });
    if (backwards.length) lines.push({ state: 'warn', title: 'Closing time is before opening time', detail: someOf(backwards) });

    // The meter, vehicle by vehicle.
    const byVehicle = new Map();
    for (const t of p.trips.filter((x) => x.status !== 'cancelled').sort(tripOrder)) {
      if (!byVehicle.has(t.vehicle)) byVehicle.set(t.vehicle, []);
      byVehicle.get(t.vehicle).push(t);
    }
    let unlogged = 0;
    const regress = [];
    const gapList = [];
    for (const list of byVehicle.values()) {
      for (let i = 1; i < list.length; i++) {
        const a = list[i - 1];
        const b = list[i];
        if (b.meterReset !== null) continue;
        const left = readingOf(a);
        if (b.start.km < left) {
          regress.push(tripName(b));
          note(b, 'warn', 'Opens at ' + fmtKm(b.start.km) + ', below the last closing ' + fmtKm(left) + ' (' + fmtDate(a.date) + ').');
        } else if (b.start.km > left) {
          const gap = b.start.km - left;
          unlogged += gap;
          gapList.push({ trip: b, gap, from: a });
          note(b, 'info', gap + ' km on the meter since the last logged trip (' + fmtDate(a.date) + ').');
        }
      }
    }
    if (regress.length) lines.push({ state: 'warn', title: 'Meter goes backwards between trips', detail: someOf(regress) });
    else lines.push({ state: 'ok', title: 'Meter only moves forward from trip to trip' });
    if (unlogged > 0) {
      lines.push({
        state: 'info',
        title: fmtKm(unlogged) + ' km on the meter between logged trips',
        detail: 'Not logged as work. ' + someOf(gapList.map((g) => fmtDate(g.trip.date) + ': ' + g.gap + ' km')),
      });
    }

    // Same day, same route, same km twice.
    const seen = new Map();
    const twice = [];
    for (const t of p.trips.filter((x) => x.status === 'closed')) {
      const k = [t.date, t.vehicle, t.from, t.to, t.km].join('|');
      if (seen.has(k)) {
        twice.push(tripName(t));
        note(t, 'warn', 'Looks like a repeat of another trip on the same day.');
      }
      seen.set(k, true);
    }
    if (twice.length) lines.push({ state: 'warn', title: 'Possible repeated trips', detail: someOf(twice) });

    // Sundays.
    const sundays = p.trips.filter((t) => t.status === 'closed' && /^\d{4}-\d{2}-\d{2}$/.test(t.date) && new Date(t.date + 'T00:00:00Z').getUTCDay() === 0);
    for (const t of sundays) note(t, 'info', 'Sunday.');
    if (sundays.length) lines.push({ state: 'info', title: sundays.length + (sundays.length === 1 ? ' trip' : ' trips') + ' on a Sunday', detail: someOf(sundays.map(tripName)) });

    return { lines, perTrip, unloggedKm: unlogged };
  }

  // ------------------------------------------------------------------ the file

  async function gunzip(bytes) {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  async function gzip(bytes) {
    const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('gzip'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  function base64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  /**
   * Opens a report file. Returns {report, photos: Map(name -> base64 text), raw}. [raw] is the file's own JSON, kept
   * so the file can be written back with one more sign-off and nothing else touched.
   */
  async function decodeReportFile(bytes) {
    if (!bytes || bytes.length === 0) throw new ReportError('The file is empty.');
    if (bytes.length > MAX_FILE_BYTES) throw new ReportError('The file is too large to be a report.');
    try {
      const raw = bytes.length > 2 && bytes[0] === 0x1f && bytes[1] === 0x8b ? await gunzip(bytes) : bytes;
      const text = new TextDecoder('utf-8', { fatal: true }).decode(raw);
      const json = JSON.parse(text);
      if (!isObj(json)) throw new ReportError('This file is not a vehicle log report.');
      const report = normReport(json);
      const photos = new Map();
      if (isObj(json.photos)) {
        const names = Object.keys(json.photos);
        if (names.length > MAX_PHOTOS) throw new ReportError('The file has too many photos.');
        for (const k of names) {
          if (!SAFE_NAME.test(k)) throw new ReportError('A photo in the file has a bad name.');
          if (typeof json.photos[k] !== 'string') throw new ReportError('This file is not a vehicle log report, or it is damaged.');
          photos.set(k, json.photos[k]);
        }
      }
      return { report, photos, raw: json };
    } catch (e) {
      if (e instanceof ReportError) throw e;
      throw new ReportError('This file is not a vehicle log report, or it is damaged.');
    }
  }

  /** SHA-256 of every photo in a file, by name. A picture that is not valid base64 is left out (so it counts as missing). */
  async function hashPhotos(photos) {
    const out = new Map();
    for (const [k, b64] of photos) {
      try {
        out.set(k, await sha256Hex(base64ToBytes(b64)));
      } catch (_) {
        /* left out */
      }
    }
    return out;
  }

  /** Everything the file shows about one report, after the checks. */
  async function openReportFile(bytes, previous) {
    const file = await decodeReportFile(bytes);
    const actual = await hashPhotos(file.photos);
    const check = await verifyReport(file.report, actual, previous);
    return { ...file, check };
  }

  /** The report as the file holds it: the file's own JSON with the sign-offs of [report] and the photos kept. */
  function reportToFileJson(report, raw, photos) {
    const out = { ...raw };
    out.signoffs = report.signoffs.map((s) => ({
      step: s.step, userId: s.userId, name: s.name, designation: s.designation, role: s.role, at: s.at,
      decision: s.decision, remarks: s.remarks, excessApproved: s.excessApproved, prevHash: s.prevHash, hash: s.hash,
    }));
    const ph = {};
    for (const [k, v] of photos) ph[k] = v;
    out.photos = ph;
    return out;
  }

  /** Packs a report and its photos into one compressed file (bytes). */
  async function encodeReportFile(report, raw, photos) {
    const text = JSON.stringify(reportToFileJson(report, raw, photos));
    return gzip(new TextEncoder().encode(text));
  }

  /** The same file as plain JSON text (no compression), for places that cannot save a .vlbreport. The phone opens it too. */
  function encodeReportJson(report, raw, photos) {
    return JSON.stringify(reportToFileJson(report, raw, photos));
  }

  function reportFileName(p) {
    const who = p.staff.name.trim().replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    return 'VehicleLog_' + p.month + '_' + (who === '' ? 'staff' : who) + '_r' + p.revision + '_s' + p.signoffs.length + '.' + FILE_EXT;
  }

  /** The message that goes with the file in WhatsApp or email. */
  function reportShareText(p) {
    const st = statusOf(p);
    const lines = ['Vehicle log, ' + fmtMonthLong(p.month) + ': ' + p.staff.name, fmtKm(p.summary.km) + ' km, ' + stageLabel(st) + '.'];
    const last = st.last;
    if (last && last.step !== 'submit') lines.push(signoffVerb(last) + ' by ' + last.name + ' (' + stepRoleLabel(last.step) + ').');
    lines.push('');
    if (st.stage === 'approved') lines.push('Approved. Open the file in Vehicle Log Book to see the sign-offs.');
    else if (st.stage === 'returned') lines.push('Sent back. Open the file in Vehicle Log Book to read the note.');
    else lines.push('Open the file in Vehicle Log Book (Review tab, Open a report file, or the desktop reviewer), check it and sign.');
    return lines.join('\n');
  }

  // ------------------------------------------------------------------ keeping several reports

  /**
   * How a file just opened relates to the copy already held: 'new', 'newer' (it carries more sign-offs),
   * 'same' (nothing new) or 'conflict' (signed differently).
   */
  function relate(have, incoming) {
    if (!have) return 'new';
    let same = have.contentHash === incoming.contentHash;
    const common = Math.min(have.signoffs.length, incoming.signoffs.length);
    for (let k = 0; k < common && same; k++) if (have.signoffs[k].hash !== incoming.signoffs[k].hash) same = false;
    if (!same) return 'conflict';
    return incoming.signoffs.length > have.signoffs.length ? 'newer' : 'same';
  }

  // ------------------------------------------------------------------ making a report (sample data, tests)

  /** Locks a trip after the last locked one in [all]. */
  async function sealTrip(t, all, nowIso) {
    let last = null;
    for (const x of all) {
      if (x.id === t.id) continue;
      if (x.chainPos !== null && (last === null || x.chainPos > (last.chainPos || 0))) last = x;
    }
    t.chainPos = (last ? last.chainPos : 0) + 1;
    t.prevHash = last ? last.hash || '' : '';
    t.lockedAt = nowIso || new Date().toISOString();
    t.hash = await hashTrip(t);
    return t;
  }

  const idPart = (id) => {
    const s = id.replace(/[^A-Za-z0-9]+/g, '');
    return s === '' ? 'staff' : s.length > 24 ? s.slice(0, 24) : s;
  };

  /** Seals trips into a report signed as sent by [staff]. [photos] is a Map of name -> base64 text. */
  async function buildReport({ staff, policy, month, trips, photos, revision = 1, replaces = null, reportId = null, at = null }) {
    const sorted = trips.map((t) => normTrip(JSON.parse(JSON.stringify(t)))).sort(tripOrder);
    const when = at || new Date().toISOString();
    const sum = summarise(sorted, policy);
    const photoHashes = new Map(await hashPhotos(photos));
    const base = {
      format: REPORT_FORMAT,
      reportId: reportId || 'R' + month + '-' + idPart(staff.id),
      revision,
      month,
      staff: { id: staff.id, name: staff.name, designation: staff.designation || '', block: staff.block || '', district: staff.district || '', mobile: staff.mobile || '' },
      policy: { org: policy.org, office: policy.office, limitKm: policy.limitKm, rate: policy.rate, scope: policy.scope, highKm: policy.highKm },
      summary: { trips: sum.trips, km: sum.km, within: sum.within, excess: sum.excess, amount: sum.amount },
      submittedAt: when,
      replaces,
      trips: sorted,
      photoHashes,
      contentHash: '',
      signoffs: [],
    };
    base.contentHash = await reportContentHash(base);
    const first = {
      step: 'submit', userId: staff.id, name: staff.name, designation: staff.designation || '', role: 'staff', at: when,
      decision: 'sent', remarks: '', excessApproved: false, prevHash: base.contentHash, hash: '',
    };
    first.hash = await signoffHash(base, first);
    base.signoffs = [first];
    return base;
  }

  /** The report as plain JSON, ready to write into a file (with the photos beside it). */
  function reportToRaw(p) {
    const rd = (r) => (r === null ? null : { ...r });
    const ph = {};
    for (const [k, v] of p.photoHashes) ph[k] = v;
    return {
      format: p.format, reportId: p.reportId, revision: p.revision, month: p.month, staff: { ...p.staff },
      policy: { ...p.policy }, summary: { ...p.summary }, submittedAt: p.submittedAt,
      replaces: p.replaces ? { ...p.replaces } : null,
      trips: p.trips.map((t) => ({ ...t, start: rd(t.start), end: rd(t.end), notes: t.notes.map((n) => ({ ...n })) })),
      photoHashes: ph, contentHash: p.contentHash, signoffs: [],
    };
  }

  return {
    REPORT_FORMAT, FILE_EXT, STEPS, SAFE_NAME, ReportError, Dbl, djson, sha256Hex, sha256Pure,
    stepOfRole, stepRoleLabel, signoffVerb, decisionsFor,
    fmtDate, fmtKm, fmtRs, fmtMonthLong, shiftMonth,
    coreOf, hashTrip, sealIntact, reportContentHash, signoffHash,
    summarise, tripFlags, statusOf, stageLabel, approvalOf, payableKm, payableAmount,
    signReport, verifyReport, reviewAids, tripOrder, readingOf,
    decodeReportFile, hashPhotos, openReportFile, encodeReportFile, encodeReportJson, reportToFileJson, reportFileName, reportShareText,
    relate, sealTrip, buildReport, reportToRaw, base64ToBytes, normReport, normTrip,
  };
});
