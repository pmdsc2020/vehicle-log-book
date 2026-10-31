/* ============================================================ foundation: helpers, icons, storage, state */

const V = window.VLB;
const IN_ARTIFACT = !!(window.claude && typeof window.claude.use === 'function');

// ---------------------------------------------------------------- tiny DOM helper

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  if (attrs) {
    for (const k of Object.keys(attrs)) {
      const v = attrs[k];
      if (v === undefined || v === null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (k === 'value') el.value = v;
      else if (k === 'checked') el.checked = !!v;
      else if (k === 'disabled' || k === 'hidden' || k === 'open') el[k] = !!v;
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else el.setAttribute(k, v === true ? '' : String(v));
    }
  }
  add(el, kids);
  return el;
}
function add(el, kids) {
  for (const k of kids) {
    if (k === null || k === undefined || k === false) continue;
    if (Array.isArray(k)) add(el, k);
    else el.appendChild(typeof k === 'object' ? k : document.createTextNode(String(k)));
  }
  return el;
}
const $ = (sel, root) => (root || document).querySelector(sel);
const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

// ---------------------------------------------------------------- icons (stroke icons, 24 grid)

const ICONS = {
  check: 'M20 6 9 17l-5-5',
  alert: 'M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
  x: 'M18 6 6 18M6 6l12 12',
  upload: 'M12 16V4M7 9l5-5 5 5M4 20h16',
  download: 'M12 4v12M7 11l5 5 5-5M4 20h16',
  file: 'M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9zM14 3v6h6',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  left: 'M15 18l-6-6 6-6',
  right: 'M9 18l6-6-6-6',
  down: 'M6 9l6 6 6-6',
  up: 'M18 15l-6-6-6 6',
  back: 'M19 12H5M12 19l-7-7 7-7',
  flag: 'M4 22V4M4 4h13l-2 4 2 4H4',
  sun: 'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  moon: 'M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z',
  shield: 'M12 3 4 6v6c0 5 3.4 8 8 9 4.6-1 8-4 8-9V6zM9 12l2 2 4-4',
  shieldx: 'M12 3 4 6v6c0 5 3.4 8 8 9 4.6-1 8-4 8-9V6zM9.5 9.5l5 5M14.5 9.5l-5 5',
  send: 'M22 2 11 13M22 2l-7 20-4-9-9-4z',
  copy: 'M9 9h11v11H9zM5 15H4V4h11v1',
  mail: 'M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM3 7l9 6 9-6',
  chat: 'M21 12a8 8 0 0 1-11.6 7.1L3 21l1.9-5.4A8 8 0 1 1 21 12z',
  print: 'M6 9V3h12v6M6 18H4v-7h16v7h-2M7 14h10v7H7z',
  trash: 'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6',
  eye: 'M1 12s4-8 11-8 11 8 11 8-4 8-11 8S1 12 1 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  image: 'M4 4h16a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM21 16l-5-5-9 9',
  lock: 'M6 11h12a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1zM8 11V7a4 4 0 0 1 8 0v4',
  undo: 'M9 14 4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0',
  rotate: 'M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5',
  fit: 'M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5',
  actual: 'M5 5h14v14H5zM9 12h6M12 9v6',
  pin: 'M12 21s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12zM12 11.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
  clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
  link: 'M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1',
  sheet: 'M4 3h16v18H4zM4 9h16M4 15h16M10 3v18',
  info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 11v5M12 8h.01',
};
function icon(name) {
  const NS = 'http://www.w3.org/2000/svg';
  const s = document.createElementNS(NS, 'svg');
  s.setAttribute('viewBox', '0 0 24 24');
  s.setAttribute('class', 'i');
  s.setAttribute('aria-hidden', 'true');
  const p = document.createElementNS(NS, 'path');
  p.setAttribute('d', ICONS[name] || ICONS.info);
  s.appendChild(p);
  return s;
}
function logo() {
  const NS = 'http://www.w3.org/2000/svg';
  const s = document.createElementNS(NS, 'svg');
  s.setAttribute('viewBox', '0 0 48 48');
  s.setAttribute('aria-hidden', 'true');
  s.innerHTML =
    '<rect width="48" height="48" rx="11" fill="#0d6b55"/><rect x="7" y="14" width="34" height="20" rx="4" fill="#12221c"/>' +
    '<g fill="#f4f8f6"><rect x="10" y="17" width="5" height="14" rx="1.2"/><rect x="16.5" y="17" width="5" height="14" rx="1.2"/><rect x="23" y="17" width="5" height="14" rx="1.2"/><rect x="29.5" y="17" width="5" height="14" rx="1.2"/></g>' +
    '<rect x="36" y="17" width="4" height="14" rx="1.2" fill="#f2a93b"/>' +
    '<path d="M12 39h24" stroke="#f2a93b" stroke-width="2.4" stroke-linecap="round"/>';
  return s;
}

// ---------------------------------------------------------------- formatting

const fmtKm = V.fmtKm;
const fmtRs = V.fmtRs;
const fmtDate = V.fmtDate;

function initials(name) {
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  const first = Array.from(parts[0])[0] || '?';
  const second = parts.length > 1 ? Array.from(parts[parts.length - 1])[0] : '';
  return (first + second).toUpperCase();
}
function avatar(name, cls) {
  return h('span', { class: 'av' + (cls ? ' ' + cls : ''), 'aria-hidden': 'true' }, initials(name));
}
function fmtDateTime(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return String(iso || '');
  return d.toLocaleString('en-IN', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true });
}
function fmtShortDate(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}
function fmtTime(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return d.toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit', hour12: true });
}
function weekday(ymd) {
  const d = new Date(String(ymd) + 'T00:00:00Z');
  return isNaN(d) ? '' : d.toLocaleDateString('en-IN', { weekday: 'short', timeZone: 'UTC' });
}
function plural(n, one, many) {
  return n + ' ' + (n === 1 ? one : many || one + 's');
}
/** Odometer drums: the one place the page shows its subject. */
function drums(km, size) {
  const s = String(Math.max(0, Math.round(km))).padStart(6, '0');
  return h('span', { class: 'drums' + (size ? ' ' + size : ''), role: 'img', 'aria-label': fmtKm(km) + ' km' }, Array.from(s).map((c) => h('b', { 'aria-hidden': 'true' }, c)));
}

// ---------------------------------------------------------------- storage (works with or without IndexedDB)

const mem = { files: new Map(), meta: new Map() };
let dbp = null;
function openDb() {
  if (dbp) return dbp;
  dbp = new Promise((resolve) => {
    try {
      const rq = indexedDB.open('vlb-reviewer', 1);
      rq.onupgradeneeded = () => {
        const db = rq.result;
        if (!db.objectStoreNames.contains('files')) db.createObjectStore('files', { keyPath: 'key' });
        if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta', { keyPath: 'key' });
      };
      rq.onsuccess = () => resolve(rq.result);
      rq.onerror = () => resolve(null);
      rq.onblocked = () => resolve(null);
    } catch (_) {
      resolve(null);
    }
  });
  return dbp;
}
async function dbDo(store, mode, fn) {
  const db = await openDb();
  if (!db) return undefined;
  return new Promise((resolve) => {
    try {
      const tx = db.transaction(store, mode);
      const rq = fn(tx.objectStore(store));
      tx.oncomplete = () => resolve(rq && 'result' in rq ? rq.result : undefined);
      tx.onerror = () => resolve(undefined);
      tx.onabort = () => resolve(undefined);
    } catch (_) {
      resolve(undefined);
    }
  });
}
const store = {
  async all(name) {
    const got = await dbDo(name, 'readonly', (s) => s.getAll());
    return got === undefined ? Array.from(mem[name].values()) : got;
  },
  async put(name, row) {
    mem[name].set(row.key, row);
    await dbDo(name, 'readwrite', (s) => s.put(row));
  },
  async del(name, key) {
    mem[name].delete(key);
    await dbDo(name, 'readwrite', (s) => s.delete(key));
  },
};
const lsGet = (k) => {
  try {
    return localStorage.getItem(k);
  } catch (_) {
    return memLs.get(k) || null;
  }
};
const memLs = new Map();
const lsSet = (k, v) => {
  memLs.set(k, v);
  try {
    localStorage.setItem(k, v);
  } catch (_) {
    /* kept in memory only */
  }
};

// ---------------------------------------------------------------- state

const ROLE_NAMES = { bi: 'Block Integrator', acc: 'Accountant', di: 'District Integrator' };
const ACTION = {
  bi: { title: 'Check this report', forward: 'Check and send to Accountant', done: 'Checked', next: 'the Accountant' },
  acc: { title: 'Verify this report', forward: 'Verify and send to District Integrator', done: 'Verified', next: 'the District Integrator' },
  di: { title: 'Approve this report', approve: 'Approve report', done: 'Approved', next: null },
};

const state = {
  entries: new Map(), // key -> entry
  profile: null,
  view: 'inbox',
  openKey: null,
  tab: 'todo',
  busy: false,
};
// What the screen remembers while it is open (not saved in files).
const ui = { expanded: new Set(), filter: 'all', remarks: '', excess: false, remarkErr: false, lb: null };

const keyOf = (p) => p.reportId + '~r' + p.revision;

function loadProfile() {
  try {
    const j = JSON.parse(lsGet('vlb.reviewer.profile') || 'null');
    if (j && typeof j.id === 'string' && typeof j.name === 'string' && ['bi', 'acc', 'di'].includes(j.role)) return j;
  } catch (_) {
    /* none */
  }
  return null;
}
function saveProfile(p) {
  state.profile = p;
  lsSet('vlb.reviewer.profile', JSON.stringify(p));
}
function newUserId(role) {
  const a = new Uint8Array(6);
  (window.crypto || { getRandomValues: (x) => x.forEach((_, i) => (x[i] = Math.floor(Math.random() * 256))) }).getRandomValues(a);
  return 'WEB-' + role.toUpperCase() + '-' + Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** The same person's report for the month before, if this computer holds one. */
function findPrevious(report) {
  let best = null;
  const want = V.shiftMonth(report.month, -1);
  for (const e of state.entries.values()) {
    const r = e.report;
    if (r.staff.id === report.staff.id && r.month === want && (!best || r.revision > best.revision)) best = r;
  }
  return best;
}

/** Works out everything the screens show about one report. */
async function summarize(entry) {
  const p = entry.report;
  entry.status = V.statusOf(p);
  entry.check = await V.verifyReport(p, entry.actual, findPrevious(p));
  entry.aids = V.reviewAids(p);
  entry.sum = V.summarise(p.trips, p.policy);
  entry.tripById = new Map(p.trips.map((t) => [t.id, t]));
  entry.trips = p.trips.slice().sort(V.tripOrder);
  return entry;
}
async function recheckAll() {
  for (const e of state.entries.values()) await summarize(e);
}

function mineToSign(entry) {
  const pr = state.profile;
  if (!pr || !entry.status) return false;
  return entry.status.nextStep === pr.role && pr.id !== entry.report.staff.id && entry.report.revision >= newestRevision(entry);
}
function isSample(entry) {
  return /^SAMPLE-/.test(entry.report.staff.id);
}
function newestRevision(entry) {
  let top = entry.report.revision;
  for (const e of state.entries.values()) if (e.report.reportId === entry.report.reportId && e.report.revision > top) top = e.report.revision;
  return top;
}

// ---------------------------------------------------------------- photos

const sniff = (bytes) => (bytes[0] === 0xff && bytes[1] === 0xd8 ? 'image/jpeg' : bytes[0] === 0x89 && bytes[1] === 0x50 ? 'image/png' : bytes[0] === 0x52 && bytes[1] === 0x49 ? 'image/webp' : 'image/jpeg');
function photoUrl(entry, name) {
  if (!name) return null;
  if (!entry.urls) entry.urls = new Map();
  if (entry.urls.has(name)) return entry.urls.get(name);
  const b64 = entry.photos.get(name);
  if (!b64) return null;
  try {
    const bytes = V.base64ToBytes(b64);
    const url = URL.createObjectURL(new Blob([bytes], { type: sniff(bytes) }));
    entry.urls.set(name, url);
    return url;
  } catch (_) {
    return null;
  }
}
function freeUrls(entry) {
  if (entry.urls) for (const u of entry.urls.values()) URL.revokeObjectURL(u);
  entry.urls = null;
}
/** 'ok' when the picture in the file is the one the trip was locked with. */
function photoState(entry, r) {
  const key = r.photo || '';
  const a = entry.actual.get(key);
  if (!a) return 'missing';
  return a === r.photoHash && entry.report.photoHashes.get(key) === r.photoHash ? 'ok' : 'altered';
}

// ---------------------------------------------------------------- review marks kept per report (ticks, queries)

function metaOf(entry) {
  if (!entry.meta) entry.meta = { key: entry.key, checked: {}, queried: {}, remarks: '' };
  return entry.meta;
}
let metaTimer = null;
function saveMetaSoon(entry) {
  clearTimeout(metaTimer);
  metaTimer = setTimeout(() => store.put('meta', metaOf(entry)), 250);
}
function checkedCount(entry) {
  const m = metaOf(entry);
  return entry.trips.filter((t) => t.status !== 'cancelled' && m.checked[t.id]).length;
}
function tripsToCheck(entry) {
  return entry.trips.filter((t) => t.status !== 'cancelled').length;
}

// ---------------------------------------------------------------- toast

let toastTimer = null;
function toast(text) {
  $$('.toast').forEach((n) => n.remove());
  const t = h('div', { class: 'toast', role: 'status' }, text);
  document.body.appendChild(t);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.remove(), 3800);
}

// ---------------------------------------------------------------- saving files and text

function download(name, data, mime) {
  const blob = data instanceof Blob ? data : new Blob([data], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = h('a', { href: url, download: name });
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}
/** Saves a file: with a browser download, or through the viewer's save prompt inside Claude. */
async function saveFile(name, data, mime) {
  if (IN_ARTIFACT) {
    try {
      const dl = await window.claude.use('downloads');
      if (!dl) {
        toast('Saving files is not available in this view. Open the standalone page to save.');
        return false;
      }
      await dl.save({ filename: name, data });
      return true;
    } catch (e) {
      if (e && e.code === 'declined') return false;
      toast('The file could not be saved here.');
      return false;
    }
  }
  download(name, data, mime);
  return true;
}
async function copyText(text, field) {
  try {
    await navigator.clipboard.writeText(text);
    toast('Copied');
  } catch (_) {
    if (field) {
      field.focus();
      field.select();
    }
    toast('Press Ctrl+C to copy the selected text');
  }
}
