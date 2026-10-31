/* ============================================================ actions: files, signing, photo viewer, dialogs, start-up */

// ---------------------------------------------------------------- navigation

function goInbox() {
  state.view = 'inbox';
  state.openKey = null;
  render();
  window.scrollTo(0, 0);
}
function openReport(key) {
  state.openKey = key;
  state.view = 'report';
  ui.expanded.clear();
  ui.filter = 'all';
  ui.remarks = '';
  ui.excess = false;
  ui.remarkErr = false;
  render();
  window.scrollTo(0, 0);
}

// ---------------------------------------------------------------- dialogs

/** Shows a dialog and resolves with the value of the button pressed (null when dismissed). */
function modal({ title, body, actions, wide }) {
  return new Promise((resolve) => {
    let result = null;
    const dlg = h(
      'dialog',
      { class: 'modal' + (wide ? ' wide' : ''), 'aria-label': title },
      h('div', { class: 'dh' }, h('h2', null, title)),
      h('div', { class: 'db' }, body),
      h(
        'div',
        { class: 'df' },
        actions.map((a) =>
          h(
            'button',
            {
              class: 'btn ' + (a.kind || '') + (a.grow ? ' grow' : ''),
              type: 'button',
              onclick: () => {
                if (a.check && a.check() === false) return;
                result = a.value;
                dlg.close();
              },
            },
            a.label
          )
        )
      )
    );
    dlg.addEventListener('close', () => {
      dlg.remove();
      resolve(result);
    });
    document.body.appendChild(dlg);
    dlg.showModal();
  });
}
const confirmDialog = ({ title, body, confirm, danger }) =>
  modal({ title, body, actions: [{ label: 'Cancel', value: false }, { label: confirm, kind: danger ? 'danger' : 'primary', value: true }] });

function profileDialog() {
  const cur0 = state.profile;
  const name = h('input', { class: 'input', id: 'pf-name', type: 'text', autocomplete: 'name', value: cur0 ? cur0.name : '' });
  const role = h('select', { class: 'input', id: 'pf-role' }, Object.keys(ROLE_NAMES).map((k) => h('option', { value: k, selected: cur0 ? cur0.role === k : k === 'bi' }, ROLE_NAMES[k])));
  const desig = h('input', { class: 'input', id: 'pf-desig', type: 'text', value: cur0 ? cur0.designation : '' });
  const err = h('span', { class: 'errtext', hidden: true }, 'Type your full name.');
  role.addEventListener('change', () => {
    const d = desig.value.trim();
    if (d === '' || Object.values(ROLE_NAMES).includes(d)) desig.value = ROLE_NAMES[role.value];
  });
  return modal({
    title: cur0 ? 'Your profile' : 'Who is reviewing?',
    body: h(
      'div',
      { class: 'stack' },
      h('p', null, 'Your name and role are written into every signature you add. They stay on this computer.'),
      h('div', { class: 'field' }, h('label', { for: 'pf-name' }, 'Full name'), name, err),
      h('div', { class: 'field' }, h('label', { for: 'pf-role' }, 'Your role'), role),
      h('div', { class: 'field' }, h('label', { for: 'pf-desig' }, 'Designation (optional)'), desig, h('span', { class: 'hint' }, 'Shown beside your name. Defaults to your role.'))
    ),
    actions: [
      { label: 'Cancel', value: false },
      {
        label: 'Save',
        kind: 'primary',
        value: true,
        check: () => {
          if (!name.value.trim()) {
            err.hidden = false;
            name.classList.add('err');
            name.focus();
            return false;
          }
          const r = role.value;
          saveProfile({ id: cur0 && cur0.id ? cur0.id : newUserId(r), name: name.value.trim(), designation: desig.value.trim() || ROLE_NAMES[r], role: r });
          return true;
        },
      },
    ],
  }).then((saved) => {
    if (saved) {
      if (state.tab === 'all' && Array.from(state.entries.values()).some(mineToSign)) state.tab = 'todo';
      render();
      toast('Signed in as ' + state.profile.name + ', ' + ROLE_NAMES[state.profile.role]);
    }
  });
}

// ---------------------------------------------------------------- opening files

function pickFiles() {
  $('#filein').click();
}

async function persistEntry(e) {
  await store.put('files', { key: e.key, bytes: e.bytes, savedAt: new Date().toISOString() });
}

/** Reads one report file into the list. Returns what happened, for the summary shown afterwards. */
async function addFileBytes(bytes, fileName) {
  const file = await V.decodeReportFile(bytes);
  const actual = await V.hashPhotos(file.photos);
  const incoming = { key: keyOf(file.report), report: file.report, photos: file.photos, raw: file.raw, actual, bytes };
  const have = state.entries.get(incoming.key);
  const rel = V.relate(have ? have.report : null, incoming.report);
  await summarize(incoming);
  const res = { name: fileName, entry: incoming, key: incoming.key };
  const who = incoming.report.staff.name + ', ' + V.fmtMonthLong(incoming.report.month);
  const badLines = incoming.check.lines.filter((l) => l.state === 'bad');

  if (rel === 'same') {
    const older = have.report.signoffs.length > incoming.report.signoffs.length;
    return { ...res, kind: 'same', entry: have, message: who + ': ' + (older ? 'you already hold a later copy with more sign-offs.' : 'already on this computer.') };
  }
  if (rel === 'conflict') {
    return { ...res, kind: 'conflict', entry: have, message: who + ': this copy was signed differently from the one you hold. Your copy was kept. Ask the others which one is current.' };
  }
  if (rel === 'newer' && !incoming.check.ok) {
    return { ...res, kind: 'rejected', entry: have, message: who + ': the newer copy fails its checks, so the copy you hold was kept.', why: badLines };
  }
  if (rel === 'newer') {
    incoming.meta = have.meta;
    if (incoming.meta) incoming.meta.key = incoming.key;
    freeUrls(have);
    state.entries.set(incoming.key, incoming);
    await persistEntry(incoming);
    return { ...res, kind: 'updated', message: who + ': updated, now ' + plural(incoming.report.signoffs.length, 'sign-off') + '.' };
  }
  state.entries.set(incoming.key, incoming);
  await persistEntry(incoming);
  if (!incoming.check.ok) return { ...res, kind: 'added', bad: true, message: who + ': added, but its checks failed. It cannot be signed.', why: badLines };
  return { ...res, kind: 'added', message: who + ': added.' };
}

async function handleFiles(files) {
  const list = Array.from(files || []);
  if (!list.length) return;
  state.busy = true;
  toast('Reading ' + plural(list.length, 'file') + '…');
  const results = [];
  for (const f of list) {
    try {
      results.push(await addFileBytes(new Uint8Array(await f.arrayBuffer()), f.name));
    } catch (err) {
      results.push({ name: f.name, kind: 'rejected', message: f.name + ': ' + (err instanceof V.ReportError ? err.message : 'This file could not be read.') });
    }
  }
  await recheckAll();
  state.busy = false;
  $$('.toast').forEach((n) => n.remove());
  const changed = results.filter((r) => r.kind === 'added' || r.kind === 'updated');
  if (results.length === 1 && changed.length === 1) {
    openReport(changed[0].key);
    toast(changed[0].kind === 'updated' ? 'Updated with the new sign-offs' : changed[0].bad ? 'Opened. Its checks failed.' : 'Report opened');
    return;
  }
  if (state.view === 'report') render();
  else {
    if (state.profile && Array.from(state.entries.values()).some(mineToSign)) state.tab = 'todo';
    render();
  }
  importSummary(results, changed);
}

function importSummary(results, changed) {
  const row = (r) => {
    const kind = r.kind === 'added' || r.kind === 'updated' ? (r.bad ? 'bad' : 'ok') : r.kind === 'same' ? 'warn' : 'bad';
    return h(
      'div',
      { class: 'res ' + kind },
      icon(kind === 'ok' ? 'check' : kind === 'warn' ? 'info' : 'x'),
      h('div', null, h('b', null, r.message), r.why && r.why.length ? h('div', { class: 'why muted' }, r.why.map((l) => h('div', null, l.title + (l.detail ? ': ' + l.detail : '')))) : null)
    );
  };
  const actions = [{ label: 'Close', value: false }];
  if (changed.length === 1) actions.push({ label: 'Open it', kind: 'primary', value: true });
  modal({ title: results.length === 1 ? 'The file was not added' : 'Files opened', body: h('div', { class: 'results' }, results.map(row)), actions }).then((go) => {
    if (go && changed.length === 1) openReport(changed[0].key);
  });
}

async function removeReport(e) {
  const p = e.report;
  const ok = await confirmDialog({
    title: 'Remove this report?',
    body: h('p', null, p.staff.name + ', ' + V.fmtMonthLong(p.month) + ' will be removed from this computer only. Nobody else is affected. Save a copy first if you still need it.'),
    confirm: 'Remove',
    danger: true,
  });
  if (!ok) return;
  freeUrls(e);
  state.entries.delete(e.key);
  await store.del('files', e.key);
  await store.del('meta', e.key);
  await recheckAll();
  if (state.openKey === e.key) goInbox();
  else render();
  toast('Removed');
}

// ---------------------------------------------------------------- ticks and queries

function setChecked(e, id, v) {
  const m = metaOf(e);
  if (v) m.checked[id] = true;
  else delete m.checked[id];
  saveMetaSoon(e);
  updateProgress(e);
  if (ui.filter === 'open' && !ui.lb) refreshTrips();
}
function markAll(e, v) {
  const m = metaOf(e);
  for (const t of e.trips) {
    if (t.status === 'cancelled') continue;
    if (v) m.checked[t.id] = true;
    else delete m.checked[t.id];
  }
  saveMetaSoon(e);
  refreshTrips();
  updateProgress(e);
}
function setQuery(e, id, v) {
  const m = metaOf(e);
  if (v) m.queried[id] = true;
  else delete m.queried[id];
  saveMetaSoon(e);
  if (ui.lb) lbPanel();
  else {
    refreshTrips();
    refreshAside();
  }
}
function queriedTrips(e) {
  const m = metaOf(e);
  return e.trips.filter((t) => m.queried[t.id]);
}
function addQueriesToRemarks(e) {
  const lines = queriedTrips(e).map((t) => '- ' + fmtDate(t.date) + ', ' + t.from + ' to ' + t.to + ': ');
  if (!lines.length) return;
  ui.remarks = (ui.remarks.trim() ? ui.remarks.trim() + '\n' : '') + 'Please explain these trips:\n' + lines.join('\n');
  refreshAside();
  const r = $('#remarks');
  if (r) {
    r.focus();
    r.setSelectionRange(r.value.length, r.value.length);
  }
}

// ---------------------------------------------------------------- signing

async function startSign(e, decision) {
  const pr = state.profile;
  if (!pr) return profileDialog();
  const p = e.report;
  const step = e.status.nextStep;
  const act = ACTION[step];
  const note = ui.remarks.trim();
  if (decision === 'return' && !note) {
    ui.remarkErr = true;
    refreshAside();
    const r = $('#remarks');
    if (r) r.focus();
    return;
  }
  const label = decision === 'return' ? 'Send back to staff' : act[decision];
  const withExcess = step === 'di' && decision === 'approve' && p.summary.excess > 0 && ui.excess;
  const got = checkedCount(e);
  const total = tripsToCheck(e);
  const lines = [h('div', null, h('b', null, p.staff.name), ' · ' + V.fmtMonthLong(p.month) + ' · ' + fmtKm(p.summary.km) + ' km')];
  if (decision === 'return') lines.push(h('p', null, 'The report goes back to ' + p.staff.name + '. They will need to correct it and send a new revision.'));
  else if (step === 'di') {
    const km = p.summary.within + (withExcess ? p.summary.excess : 0);
    lines.push(h('p', null, 'Payable: ', h('b', null, fmtKm(km) + ' km, ' + fmtRs(km * p.policy.rate)), p.summary.excess > 0 ? (withExcess ? ' (includes ' + fmtKm(p.summary.excess) + ' km above the limit)' : ' (the ' + fmtKm(p.summary.excess) + ' km above the limit is not approved)') : ''));
  } else lines.push(h('p', null, 'It goes on to ' + act.next + '.'));
  if (decision !== 'return' && got < total) lines.push(h('div', { class: 'callout amber' }, icon('alert'), h('div', null, h('b', null, 'You have ticked ' + got + ' of ' + total + ' trips.'), h('div', { class: 'muted' }, 'Your signature says you checked the whole report.'))));
  if (note) lines.push(h('div', { class: 'note' }, note, h('small', null, 'Your remarks')));
  lines.push(h('p', { class: 'hint' }, 'This is added to the file as your signature, with your name and the time. It cannot be removed.'));
  const ok = await confirmDialog({ title: label + '?', body: h('div', { class: 'stack' }, lines), confirm: label, danger: decision === 'return' });
  if (!ok) return;
  try {
    const signed = await V.signReport(p, { id: pr.id, name: pr.name, designation: pr.designation, role: pr.role }, { decision, remarks: note, excessApproved: withExcess });
    const bytes = await V.encodeReportFile(signed, e.raw, e.photos);
    e.report = signed;
    e.bytes = bytes;
    await persistEntry(e);
    await summarize(e);
    ui.remarks = '';
    ui.excess = false;
    ui.remarkErr = false;
    render();
    if (!e.check.ok) toast('Signed, but the file no longer passes its checks. Please report this.');
    else toast(decision === 'return' ? 'Sent back. Save the file and send it to the staff member.' : 'Signed. Save the file and send it on.');
    const card = $('.sendcard');
    if (card) card.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  } catch (err) {
    toast(err && err.message ? err.message : 'The report could not be signed.');
  }
}

// ---------------------------------------------------------------- saving

async function saveReport(e) {
  const name = outName(e);
  try {
    const data = IN_ARTIFACT ? V.encodeReportJson(e.report, e.raw, e.photos) : await V.encodeReportFile(e.report, e.raw, e.photos);
    const ok = await saveFile(name, data, 'application/octet-stream');
    if (ok) toast(IN_ARTIFACT ? 'Saved' : 'Saved ' + name + ' to your Downloads');
  } catch (_) {
    toast('The file could not be saved.');
  }
}

function csvCell(v) {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
async function exportCsv(e) {
  const p = e.report;
  const head = ['Date', 'Day', 'Project', 'Vehicle', 'From', 'To', 'Activity', 'Task', 'Opening km', 'Closing km', 'Km', 'Status', 'Flags'];
  const rows = e.trips.map((t) => [t.date, weekday(t.date), t.project, t.vehicle, t.from, t.to, t.activity, t.task, t.start.km, t.end ? t.end.km : '', t.km === null ? '' : t.km, t.status, V.tripFlags(t, p.policy).join('; ')]);
  const text = '﻿' + [head].concat(rows).map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';
  const who = p.staff.name.trim().replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'staff';
  const ok = await saveFile('VehicleLog_' + p.month + '_' + who + '_trips.csv', text, 'text/csv');
  if (ok) toast('Trips saved as CSV');
}

// ---------------------------------------------------------------- the photo viewer

function lbEl() {
  let d = $('#lightbox');
  if (d) return d;
  d = h('dialog', { class: 'lb', id: 'lightbox', 'aria-label': 'Odometer photo' });
  document.body.appendChild(d);
  d.addEventListener('close', () => {
    const had = ui.lb;
    ui.lb = null;
    d.replaceChildren();
    if (had && cur) {
      refreshTrips();
      updateProgress(cur.entry);
    }
  });
  d.addEventListener('keydown', lbKey);
  return d;
}

function openLightbox(e, tripId, which) {
  const list = [];
  for (const t of e.trips) {
    if (t.start && t.start.photo) list.push({ t, which: 'start' });
    if (t.end && t.end.photo) list.push({ t, which: 'end' });
  }
  let i = list.findIndex((x) => x.t.id === tripId && x.which === which);
  if (i < 0) i = 0;
  if (!list.length) return;
  const d = lbEl();
  ui.lb = { e, list, i, s: 1, fit: 1, tx: 0, ty: 0, rot: 0, iw: 0, ih: 0 };
  const msg = h('div', { class: 'lbmsg', hidden: true }, 'This photo cannot be shown');
  const img = h('img', { alt: 'Odometer photo', draggable: 'false' });
  img.addEventListener('error', () => {
    if (img.getAttribute('src')) msg.hidden = false;
  });
  const stage = h(
    'div',
    { class: 'stage', id: 'lbstage' },
    img,
    msg,
    h('button', { class: 'nav p', 'aria-label': 'Previous photo', onclick: () => lbGo(-1) }, icon('left')),
    h('button', { class: 'nav n', 'aria-label': 'Next photo', onclick: () => lbGo(1) }, icon('right')),
    h(
      'div',
      { class: 'tools' },
      h('button', { class: 'btn icon', 'aria-label': 'Zoom out', title: 'Zoom out (-)', onclick: () => lbZoom(1 / 1.35) }, icon('minus')),
      h('button', { class: 'btn icon', 'aria-label': 'Zoom in', title: 'Zoom in (+)', onclick: () => lbZoom(1.35) }, icon('plus')),
      h('button', { class: 'btn icon', 'aria-label': 'Fit to window', title: 'Fit (0)', onclick: lbFit }, icon('fit')),
      h('button', { class: 'btn icon', 'aria-label': 'Actual size', title: 'Actual size (1)', onclick: lbActual }, icon('actual')),
      h('button', { class: 'btn icon', 'aria-label': 'Rotate', title: 'Rotate (R)', onclick: lbRotate }, icon('rotate')),
      h('button', { class: 'btn icon', 'aria-label': 'Close', title: 'Close (Esc)', onclick: () => d.close() }, icon('x'))
    )
  );
  d.replaceChildren(h('div', { class: 'lbx' }, stage, h('div', { class: 'lbp', id: 'lbpanel' })));
  ui.lb.img = img;
  ui.lb.stage = stage;
  img.addEventListener('load', () => {
    msg.hidden = true;
    ui.lb.iw = img.naturalWidth;
    ui.lb.ih = img.naturalHeight;
    img.style.width = img.naturalWidth + 'px';
    img.style.height = img.naturalHeight + 'px';
    img.style.marginLeft = -img.naturalWidth / 2 + 'px';
    img.style.marginTop = -img.naturalHeight / 2 + 'px';
    lbFit();
  });
  stage.addEventListener(
    'wheel',
    (ev) => {
      ev.preventDefault();
      lbZoomAt(ev.clientX, ev.clientY, ui.lb.s * Math.exp(-ev.deltaY * 0.0016));
    },
    { passive: false }
  );
  let drag = null;
  stage.addEventListener('pointerdown', (ev) => {
    if (ev.target.closest('button')) return;
    drag = { x: ev.clientX, y: ev.clientY, tx: ui.lb.tx, ty: ui.lb.ty };
    stage.setPointerCapture(ev.pointerId);
    stage.classList.add('drag');
  });
  stage.addEventListener('pointermove', (ev) => {
    if (!drag || !ui.lb) return;
    ui.lb.tx = drag.tx + ev.clientX - drag.x;
    ui.lb.ty = drag.ty + ev.clientY - drag.y;
    lbPaint();
  });
  const end = () => {
    drag = null;
    stage.classList.remove('drag');
  };
  stage.addEventListener('pointerup', end);
  stage.addEventListener('pointercancel', end);
  stage.addEventListener('dblclick', (ev) => {
    if (ev.target.closest('button')) return;
    const L = ui.lb;
    if (Math.abs(L.s - L.fit) < 0.01) lbZoomAt(ev.clientX, ev.clientY, 1 < L.fit ? L.fit * 2.5 : 1);
    else lbFit();
  });
  d.showModal();
  lbShow();
}

function lbShow() {
  const L = ui.lb;
  const cur0 = L.list[L.i];
  const url = photoUrl(L.e, (cur0.which === 'start' ? cur0.t.start : cur0.t.end).photo);
  const r = cur0.which === 'start' ? cur0.t.start : cur0.t.end;
  L.rot = 0;
  const msg = $('.lbmsg');
  if (msg) msg.hidden = true;
  if (url && photoState(L.e, r) === 'ok') L.img.src = url;
  else {
    L.img.removeAttribute('src');
    L.img.style.width = L.img.style.height = '0';
    if (msg) {
      msg.textContent = photoState(L.e, r) === 'missing' ? 'The photo is missing from the file' : 'This photo does not match its fingerprint';
      msg.hidden = false;
    }
  }
  lbPanel();
}
function lbGo(d) {
  const L = ui.lb;
  L.i = (L.i + d + L.list.length) % L.list.length;
  lbShow();
}
function lbFitScale() {
  const L = ui.lb;
  const sw = L.stage.clientWidth;
  const sh = L.stage.clientHeight;
  const sideways = L.rot % 180 !== 0;
  const w = sideways ? L.ih : L.iw;
  const hh = sideways ? L.iw : L.ih;
  if (!w || !hh) return 1;
  return Math.min(sw / w, sh / hh) * 0.96;
}
function lbFit() {
  const L = ui.lb;
  if (!L) return;
  L.fit = lbFitScale();
  L.s = L.fit;
  L.tx = 0;
  L.ty = 0;
  lbPaint();
}
function lbActual() {
  const L = ui.lb;
  L.s = 1;
  L.tx = 0;
  L.ty = 0;
  lbPaint();
}
function lbRotate() {
  const L = ui.lb;
  L.rot = (L.rot + 90) % 360;
  lbFit();
}
function lbZoomAt(cx, cy, ns) {
  const L = ui.lb;
  const lo = Math.min(L.fit, 1) * 0.5;
  ns = Math.max(lo, Math.min(10, ns));
  const rect = L.stage.getBoundingClientRect();
  const dx = cx - (rect.left + rect.width / 2) - L.tx;
  const dy = cy - (rect.top + rect.height / 2) - L.ty;
  L.tx = cx - (rect.left + rect.width / 2) - (dx * ns) / L.s;
  L.ty = cy - (rect.top + rect.height / 2) - (dy * ns) / L.s;
  L.s = ns;
  lbPaint();
}
function lbZoom(f) {
  const L = ui.lb;
  const rect = L.stage.getBoundingClientRect();
  lbZoomAt(rect.left + rect.width / 2, rect.top + rect.height / 2, L.s * f);
}
function lbPaint() {
  const L = ui.lb;
  if (!L) return;
  L.img.style.transform = 'translate(' + L.tx + 'px,' + L.ty + 'px) rotate(' + L.rot + 'deg) scale(' + L.s + ')';
  const z = $('#lbzoom');
  if (z) z.textContent = Math.round(L.s * 100) + '%';
}
function lbKey(ev) {
  const L = ui.lb;
  if (!L) return;
  if (ev.target.closest('input, textarea')) return;
  const k = ev.key;
  if (k === 'ArrowRight') lbGo(1);
  else if (k === 'ArrowLeft') lbGo(-1);
  else if (k === '+' || k === '=') lbZoom(1.35);
  else if (k === '-') lbZoom(1 / 1.35);
  else if (k === '0') lbFit();
  else if (k === '1') lbActual();
  else if (k === 'r' || k === 'R') lbRotate();
  else return;
  ev.preventDefault();
}

function lbPanel() {
  const L = ui.lb;
  if (!L) return;
  const { t, which } = L.list[L.i];
  const e = L.e;
  const r = which === 'start' ? t.start : t.end;
  const m = metaOf(e);
  const ps = photoState(e, r);
  const aids = e.aids.perTrip.get(t.id) || [];
  const flags = V.tripFlags(t, e.report.policy);
  const items = [];
  items.push(h('li', { class: ps === 'ok' ? '' : 'w' }, icon(ps === 'ok' ? 'check' : 'alert'), ps === 'ok' ? 'Photo matches the fingerprint taken when the trip was locked.' : ps === 'missing' ? 'The photo is missing from the file.' : 'The photo does not match its fingerprint. Do not rely on it.'));
  if (r.photoTime) items.push(h('li', null, icon('clock'), 'Photo taken ' + fmtDateTime(r.photoTime)));
  items.push(h('li', null, icon('clock'), 'Reading logged ' + fmtDateTime(r.at)));
  if (r.oldPhoto) items.push(h('li', { class: 'w' }, icon('alert'), 'The photo was not fresh when it was added.'));
  if (r.gps) items.push(h('li', null, icon('pin'), r.gps.lat.toFixed(5) + ', ' + r.gps.lng.toFixed(5) + (r.gps.acc ? ' (±' + Math.round(r.gps.acc) + ' m)' : '')));
  flags.forEach((f) => items.push(h('li', { class: 'w' }, icon('flag'), f)));
  aids.forEach((a) => items.push(h('li', { class: a.state === 'warn' ? 'w' : '' }, icon(a.state === 'warn' ? 'alert' : 'info'), a.text)));
  const total = L.list.length;
  const panel = $('#lbpanel');
  panel.replaceChildren();
  add(panel, [
    h('div', null, h('div', { class: 'big' }, fmtDate(t.date) + ' · ' + weekday(t.date) + ' · photo ' + (L.i + 1) + ' of ' + total), h('h2', null, t.from + ' → ' + t.to), h('div', { class: 'muted' }, t.project + ' · ' + t.vehicle)),
    h('div', null, h('div', { class: 'big', style: { marginBottom: '6px' } }, (which === 'start' ? 'Opening' : 'Closing') + ' reading'), drums(r.km, 'lg'), t.km !== null ? h('div', { class: 'muted', style: { marginTop: '8px' } }, which === 'end' ? 'Trip distance ' + fmtKm(t.km) + ' km (' + fmtKm(t.start.km) + ' → ' + fmtKm(t.end.km) + ')' : 'Trip distance ' + fmtKm(t.km) + ' km') : null),
    m.queried[t.id] ? h('div', { class: 'q' }, 'Query raised on this trip') : null,
    h('ul', null, items),
    t.status === 'cancelled' ? null : h('label', { class: 'switch', style: { margin: 0 } }, h('div', null, h('b', null, 'Reading matches the photo'), h('span', null, 'Tick this trip as checked')), h('input', { type: 'checkbox', checked: !!m.checked[t.id], onchange: (ev) => setChecked(e, t.id, ev.target.checked) }), h('span', { class: 'tr' })),
    h('div', { class: 'actions' }, h('button', { class: 'btn', onclick: () => setQuery(e, t.id, !m.queried[t.id]) }, icon('flag'), m.queried[t.id] ? 'Remove query' : 'Raise a query'), h('button', { class: 'btn', onclick: () => lbGo(1) }, 'Next photo', icon('right'))),
    h('p', { class: 'hint' }, 'Zoom ', h('b', { id: 'lbzoom' }, ''), '. Scroll to zoom, drag to move, double-click to jump in. ', h('span', { class: 'kbd' }, '←'), ' ', h('span', { class: 'kbd' }, '→'), ' photos, ', h('span', { class: 'kbd' }, 'R'), ' rotate, ', h('span', { class: 'kbd' }, 'Esc'), ' close.')
  ]);
  lbPaint();
}

// ---------------------------------------------------------------- a sample report to try the screens on

function drawOdometer(km, label) {
  const c = document.createElement('canvas');
  c.width = 960;
  c.height = 640;
  const g = c.getContext('2d');
  const bg = g.createLinearGradient(0, 0, 960, 640);
  bg.addColorStop(0, '#2b3a33');
  bg.addColorStop(1, '#101815');
  g.fillStyle = bg;
  g.fillRect(0, 0, 960, 640);
  g.fillStyle = '#0b100e';
  g.beginPath();
  g.roundRect(110, 200, 740, 240, 28);
  g.fill();
  g.strokeStyle = '#4b5d54';
  g.lineWidth = 6;
  g.stroke();
  const digits = String(km).padStart(6, '0');
  for (let i = 0; i < 6; i++) {
    const x = 150 + i * 112;
    g.fillStyle = i === 5 ? '#c99524' : '#e8efe9';
    g.beginPath();
    g.roundRect(x, 232, 96, 176, 10);
    g.fill();
    g.fillStyle = i === 5 ? '#1a1100' : '#101815';
    g.font = '700 150px "Barlow Semi Condensed", Arial, sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(digits[i], x + 48, 322);
  }
  g.fillStyle = '#8da398';
  g.font = '600 34px "Barlow Semi Condensed", Arial, sans-serif';
  g.textAlign = 'left';
  g.fillText('KM', 150, 480);
  g.textAlign = 'right';
  g.fillText('SAMPLE PHOTO · ' + label, 810, 560);
  return c.toDataURL('image/jpeg', 0.8).split(',')[1];
}

async function loadSample() {
  const now = new Date();
  const month = V.shiftMonth(now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0'), -1);
  const staff = { id: 'SAMPLE-001', name: 'Sample Staff', designation: 'Field Officer', block: 'Shahada', district: 'Nandurbar', mobile: '9800000000' };
  const policy = { org: 'Development Support Centre (DSC)', office: 'Nandurbar', limitKm: 500, rate: 4, scope: 'staff', highKm: 200 };
  const photos = new Map();
  const trips = [];
  const photo = async (key, km, label) => {
    const b64 = drawOdometer(km, label);
    photos.set(key, b64);
    return V.sha256Hex(V.base64ToBytes(b64));
  };
  const mk = async (id, day, project, to, activity, task, open, close, extra) => {
    const date = month + '-' + String(day).padStart(2, '0');
    const cancelled = close === null;
    const t = V.normTrip({
      id, mode: 'full', date, month, project, vehicle: 'MH39AB1234', vtype: 'Two wheeler', from: 'Nandurbar', to, activity, task,
      status: cancelled ? 'cancelled' : 'closed', km: cancelled ? null : close - open,
      start: { km: open, photo: id + 's', photoHash: await photo(id + 's', open, 'opening'), at: date + 'T03:30:00.000Z', photoTime: date + 'T03:29:30.000Z', gps: extra && extra.gps ? { lat: 21.3667, lng: 74.2417, acc: 9 } : null },
      end: cancelled ? null : { km: close, photo: id + 'e', photoHash: await photo(id + 'e', close, 'closing'), at: date + 'T11:30:00.000Z', photoTime: date + 'T11:29:40.000Z' },
      loggedAt: date + 'T11:35:00.000Z',
      late: extra && extra.late ? { reason: extra.late } : null,
      prior: extra && extra.prior ? { by: 'District Integrator', date: month + '-01', mode: 'Phone call', ref: '', none: false } : null,
      cancel: cancelled ? { reason: 'Meeting postponed because of rain', at: date + 'T05:00:00.000Z' } : null,
      notes: extra && extra.note ? [{ at: date + 'T12:00:00.000Z', text: extra.note }] : [],
    });
    await V.sealTrip(t, trips, date + 'T11:36:00.000Z');
    trips.push(t);
  };
  await mk('s1', 3, 'NABARD', 'Shahada', 'Village meeting', 'Farmer group meeting', 100, 172, {});
  await mk('s2', 6, 'Project SAHAS', 'Taloda', 'Monitoring visit', 'School health check', 172, 290, { late: 'Phone was switched off in the field', gps: true });
  await mk('s3', 10, 'NABARD', 'Akkalkuwa', 'Training', 'Seed treatment demonstration', 290, 433, { prior: true, gps: true });
  await mk('s4', 13, 'NABARD', 'Navapur', 'Village meeting', 'Called off', 433, null, {});
  await mk('s5', 17, 'Project SAHAS', 'Dhadgaon', 'Monitoring visit', 'Anganwadi review', 433, 560, { note: 'Receipt for the ferry kept with the diary' });
  await mk('s6', 24, 'NABARD', 'Shahada', 'Review meeting', 'Quarterly review with the block team', 560, 775, {});
  const built = await V.buildReport({ staff, policy, month, trips, photos, at: V.shiftMonth(month, 1) + '-01T05:00:00.000Z' });
  const raw = V.reportToRaw(built);
  const bytes = await V.encodeReportFile(built, raw, photos);
  const res = await addFileBytes(bytes, 'sample');
  await recheckAll();
  if (res.kind === 'same') toast('The sample report is already here');
  else toast('Sample report added. Sign it to practise, then remove it.');
  openReport(res.key);
}

// ---------------------------------------------------------------- drag and drop, start-up

function hasFiles(ev) {
  return !!(ev.dataTransfer && Array.from(ev.dataTransfer.types || []).includes('Files'));
}
let dragDepth = 0;
function veil(on) {
  let v = $('#veil');
  if (on && !v) {
    document.body.appendChild(h('div', { class: 'veil', id: 'veil' }, h('div', null, 'Drop report files to open them', h('small', null, 'They are read on this computer and are not uploaded'))));
  } else if (!on && v) v.remove();
}

async function boot() {
  const th = lsGet('vlb.theme');
  if (th === 'light' || th === 'dark') document.documentElement.setAttribute('data-theme', th);
  state.profile = loadProfile();
  $('#filein').addEventListener('change', async (ev) => {
    const files = Array.from(ev.target.files || []);
    ev.target.value = '';
    await handleFiles(files);
  });
  window.addEventListener('dragenter', (ev) => {
    if (!hasFiles(ev)) return;
    dragDepth += 1;
    veil(true);
  });
  window.addEventListener('dragover', (ev) => {
    if (hasFiles(ev)) ev.preventDefault();
  });
  window.addEventListener('dragleave', (ev) => {
    if (!hasFiles(ev)) return;
    dragDepth = Math.max(0, dragDepth - 1);
    if (!dragDepth) veil(false);
  });
  window.addEventListener('drop', (ev) => {
    if (!hasFiles(ev)) return;
    ev.preventDefault();
    dragDepth = 0;
    veil(false);
    handleFiles(ev.dataTransfer.files);
  });
  render();
  try {
    const rows = await store.all('files');
    const metas = new Map((await store.all('meta')).map((m) => [m.key, m]));
    for (const row of rows) {
      try {
        const file = await V.decodeReportFile(row.bytes);
        const entry = { key: row.key, report: file.report, photos: file.photos, raw: file.raw, actual: await V.hashPhotos(file.photos), bytes: row.bytes, meta: metas.get(row.key) };
        state.entries.set(entry.key, entry);
      } catch (_) {
        /* a damaged row is skipped */
      }
    }
    await recheckAll();
  } catch (_) {
    /* start empty */
  }
  if (state.profile && Array.from(state.entries.values()).some(mineToSign)) state.tab = 'todo';
  else if (!state.profile) state.tab = 'all';
  render();
}

window.__vlb = { state, ui, V, handleFiles, addFileBytes, loadSample, openReport };
boot();
