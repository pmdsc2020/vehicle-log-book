/* ============================================================ screens */

let cur = null; // the open report's live pieces: { entry, els: { trips, aside, checks } }

function render() {
  const rootEl = $('#root');
  let body;
  const e = state.view === 'report' ? state.entries.get(state.openKey) : null;
  if (e) body = reportView(e);
  else {
    state.view = 'inbox';
    cur = null;
    body = inboxView();
  }
  rootEl.replaceChildren(topbar(), h('main', { class: 'wrap' }, body));
}

// ---------------------------------------------------------------- top bar

function isDark() {
  const t = document.documentElement.getAttribute('data-theme');
  if (t) return t === 'dark';
  return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
}
function toggleTheme() {
  const next = isDark() ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  lsSet('vlb.theme', next);
  render();
}

function topbar() {
  const pr = state.profile;
  return h(
    'header',
    { class: 'topbar noprint' },
    h(
      'div',
      { class: 'wrap' },
      h('button', { class: 'brand', onclick: goInbox, 'aria-label': 'All reports' }, logo(), h('span', null, h('b', null, 'Vehicle Log Reviewer'), h('small', null, 'DSC Nandurbar · desktop review'))),
      h('span', { class: 'spacer' }),
      h('button', { class: 'btn primary', onclick: pickFiles }, icon('upload'), 'Open report files'),
      h('button', { class: 'btn icon ghost', 'aria-label': isDark() ? 'Switch to light theme' : 'Switch to dark theme', title: isDark() ? 'Light theme' : 'Dark theme', onclick: toggleTheme }, icon(isDark() ? 'sun' : 'moon')),
      h(
        'button',
        { class: 'me', onclick: () => profileDialog(), 'aria-label': pr ? 'Your profile' : 'Set up your profile' },
        avatar(pr ? pr.name : '?'),
        h('span', { class: 't' }, h('strong', null, pr ? pr.name : 'Set up your profile'), h('em', null, pr ? ROLE_NAMES[pr.role] : 'Choose your role'))
      )
    )
  );
}

// ---------------------------------------------------------------- inbox

function chainDots(e) {
  const st = e.status;
  const out = [];
  for (let i = 0; i < 4; i++) {
    let cls = '';
    if (st.stage === 'returned' && i === st.returnedAt) cls = 'back';
    else if (i < st.done) cls = 'on';
    else if (i === st.done && !st.finished) cls = 'now';
    if (i > 0) out.push(h('u', { class: i < st.done ? 'on' : '' }));
    out.push(h('i', { class: cls }));
  }
  return h('span', { class: 'chain', 'aria-hidden': 'true' }, out);
}
function stagePills(e) {
  const st = e.status;
  const kind = st.stage === 'approved' ? 'ok' : st.stage === 'returned' ? 'bad' : 'info';
  const text = st.stage === 'returned' ? 'Sent back by ' + V.stepRoleLabel(st.last.step) : V.stageLabel(st);
  return h('span', { class: 'status' }, h('span', { class: 'pill ' + kind }, text), mineToSign(e) ? h('span', { class: 'pill you' }, 'Your turn') : null);
}
function checkPill(e) {
  const c = e.check;
  if (!c.ok) return h('span', { class: 'pill bad' }, icon('shieldx'), 'Checks failed');
  if (c.hasWarnings || e.aids.lines.some((l) => l.state === 'warn')) return h('span', { class: 'pill warn' }, icon('alert'), 'Notes to read');
  return h('span', { class: 'pill ok' }, icon('shield'), 'Checks passed');
}
function lastTouched(e) {
  const s = e.report.signoffs;
  return s.length ? s[s.length - 1].at : e.report.submittedAt;
}

function emptyView() {
  return h(
    'section',
    { class: 'card drop' },
    h(
      'div',
      { class: 'l' },
      h('h2', null, 'Review staff vehicle logs on a big screen'),
      h('p', { class: 'muted' }, 'Staff send their monthly report from the phone app over WhatsApp or email. Save that file, drop it here, and check every trip and odometer photo at full size before you sign.'),
      h(
        'div',
        { class: 'actions' },
        h('button', { class: 'btn primary', onclick: pickFiles }, icon('upload'), 'Open report files'),
        h('button', { class: 'btn', onclick: loadSample }, icon('file'), 'Try a sample report')
      ),
      h('p', { class: 'hint' }, 'You can also drag report files anywhere onto this page. Nothing is uploaded: the files stay in this browser on this computer.'),
      state.profile ? null : h('p', { class: 'hint' }, 'Set your name and role first (top right) so the reports waiting for you come first.')
    ),
    h(
      'div',
      { class: 'r' },
      h('h3', null, 'How a report moves'),
      h(
        'ol',
        null,
        h('li', null, h('div', null, h('b', null, 'Save the file'), h('span', null, 'Download the .vlbreport file from WhatsApp or email.'))),
        h('li', null, h('div', null, h('b', null, 'Open it here'), h('span', null, 'The seals, photo fingerprints and figures are checked on this computer.'))),
        h('li', null, h('div', null, h('b', null, 'Sign or send back'), h('span', null, 'Block Integrator checks, Accountant verifies, District Integrator approves.'))),
        h('li', null, h('div', null, h('b', null, 'Pass the file on'), h('span', null, 'Save the signed file and send it to the next person. The phone app opens it too.')))
      )
    )
  );
}

function inboxView() {
  const all = Array.from(state.entries.values());
  if (!all.length) return emptyView();
  const todo = all.filter(mineToSign);
  const finished = all.filter((e) => e.status.finished);
  if (state.tab === 'todo' && !state.profile) state.tab = 'all';
  const shown = state.tab === 'todo' ? todo : state.tab === 'done' ? finished : all;
  shown.sort((a, b) => (a.report.month < b.report.month ? 1 : a.report.month > b.report.month ? -1 : a.report.staff.name.localeCompare(b.report.staff.name)));

  const tabBtn = (id, label, n, hot) =>
    h('button', { class: 'tab', role: 'tab', 'aria-selected': state.tab === id ? 'true' : 'false', onclick: () => { state.tab = id; render(); } }, label, h('span', { class: 'n' + (hot && n > 0 ? ' hot' : '') }, n));

  const head = h(
    'div',
    { class: 'pagehead' },
    h('div', null, h('h1', null, 'Reports'), h('p', null, plural(all.length, 'report'), ' on this computer', todo.length ? ' · ' + todo.length + ' waiting for you' : '')),
    h('span', { class: 'spacer' }),
    h('div', { class: 'tabs', role: 'tablist' }, state.profile ? tabBtn('todo', 'Waiting for me', todo.length, true) : null, tabBtn('all', 'All reports', all.length), tabBtn('done', 'Finished', finished.length))
  );

  const banner = state.profile
    ? null
    : h('div', { class: 'banner info' }, icon('user'), h('div', null, h('b', null, 'Who is reviewing? '), 'Choose your name and role to see the reports that are waiting for you and to sign them.'), h('button', { class: 'btn', onclick: () => profileDialog() }, 'Set up your profile'));

  let table;
  if (!shown.length) {
    table = h(
      'div',
      { class: 'pad', style: { textAlign: 'center' } },
      h('p', { class: 'big-n' }, state.tab === 'todo' ? 'Nothing is waiting for you' : 'No reports here yet'),
      h('p', { class: 'muted' }, state.tab === 'todo' ? 'When a report reaches the ' + ROLE_NAMES[state.profile.role] + ', it shows up here.' : 'Open a report file to add one.'),
      state.tab === 'todo' ? h('div', { class: 'actions', style: { justifyContent: 'center', marginTop: '12px' } }, h('button', { class: 'btn', onclick: () => { state.tab = 'all'; render(); } }, 'Show all reports')) : null
    );
  } else {
    table = h(
      'div',
      { class: 'tablewrap' },
      h(
        'table',
        { class: 'list' },
        h('thead', null, h('tr', null, h('th', null, 'Staff'), h('th', null, 'Month'), h('th', { class: 'num' }, 'Distance'), h('th', { class: 'num' }, 'Amount'), h('th', null, 'Progress'), h('th', null, 'Where it is'), h('th', null, 'Checks'), h('th', null, 'Last change'), h('th', { 'aria-label': 'Remove' }))),
        h('tbody', null, shown.map(inboxRow))
      )
    );
  }
  return h('div', null, banner, head, h('section', { class: 'card' }, table), h('p', { class: 'hint noprint', style: { marginTop: '12px' } }, 'Drop more files anywhere on this page. Files stay in this browser only; remove a report when you are done with it.'));
}

function inboxRow(e) {
  const p = e.report;
  const approved = e.status.stage === 'approved';
  const open = () => openReport(e.key);
  return h(
    'tr',
    { class: mineToSign(e) ? 'mine' : '', tabindex: 0, onclick: open, onkeydown: (ev) => { if (ev.key === 'Enter') open(); } },
    h('td', null, h('div', { class: 'who' }, avatar(p.staff.name), h('div', null, h('b', null, p.staff.name, isSample(e) ? h('span', { class: 'pill', style: { marginLeft: '8px' } }, 'Sample') : null), h('small', null, [p.staff.designation, p.staff.block].filter(Boolean).join(' · '))))),
    h('td', null, h('span', { class: 'big-n' }, V.fmtMonthLong(p.month)), p.revision > 1 ? h('div', null, h('span', { class: 'pill warn' }, 'Revision ' + p.revision)) : null, p.revision < newestRevision(e) ? h('div', null, h('span', { class: 'pill' }, 'Replaced')) : null),
    h('td', { class: 'num' }, h('span', { class: 'big-n' }, fmtKm(p.summary.km)), h('div', { class: 'faint' }, 'km · ' + plural(p.summary.trips, 'trip'))),
    h('td', { class: 'num' }, h('span', { class: 'big-n' }, fmtRs(approved ? V.payableAmount(p) : p.summary.amount)), h('div', { class: 'faint' }, approved ? 'approved' : p.summary.excess > 0 ? 'before excess' : 'at rate')),
    h('td', null, chainDots(e)),
    h('td', null, stagePills(e)),
    h('td', null, checkPill(e)),
    h('td', null, h('span', { class: 'muted' }, fmtShortDate(lastTouched(e)))),
    h('td', null, h('button', { class: 'qbtn', title: 'Remove from this computer', 'aria-label': 'Remove ' + p.staff.name + ' ' + V.fmtMonthLong(p.month) + ' from this computer', onclick: (ev) => { ev.stopPropagation(); removeReport(e); } }, icon('trash')))
  );
}

// ---------------------------------------------------------------- one report

function reportView(e) {
  const els = {};
  els.checks = checksCard(e);
  els.trips = tripsCard(e);
  els.aside = asideCol(e);
  cur = { entry: e, els };
  const p = e.report;
  const crumbs = h(
    'div',
    { class: 'crumbs noprint' },
    h('button', { class: 'btn', onclick: goInbox }, icon('back'), 'All reports'),
    isSample(e) ? h('span', { class: 'pill' }, 'Sample report') : null,
    p.revision < newestRevision(e) ? h('span', { class: 'pill warn' }, 'A newer revision is on this computer') : null
  );
  return h(
    'div',
    null,
    crumbs,
    h(
      'div',
      { class: 'report' },
      h('div', { class: 'main' }, headerCard(e), notices(e), els.checks, h('div', { class: 'twocol' }, statementCard(e), projectsCard(e)), els.trips),
      els.aside
    )
  );
}

function ruleText(p) {
  return fmtKm(p.policy.limitKm) + ' km ' + (p.policy.scope === 'project' ? 'for each project' : 'a month') + ' at ' + fmtRs(p.policy.rate) + ' a km';
}
function fact(label, value) {
  return h('span', null, label + ' ', h('b', null, value));
}

function headerCard(e) {
  const p = e.report;
  return h(
    'section',
    { class: 'card pad' },
    h(
      'div',
      { class: 'rhead' },
      avatar(p.staff.name),
      h('div', null, h('h1', null, p.staff.name), h('p', { class: 'sub' }, [p.staff.designation, p.staff.block, p.staff.district].filter(Boolean).join(' · '))),
      h('div', { class: 'month' }, h('b', null, V.fmtMonthLong(p.month)), h('small', null, 'Revision ' + p.revision))
    ),
    h(
      'div',
      { class: 'facts' },
      fact('Sent', fmtDateTime(p.submittedAt)),
      fact('Rule', ruleText(p)),
      p.staff.mobile ? fact('Mobile', p.staff.mobile) : null,
      h('span', null, 'Report ', h('b', { class: 'mono' }, p.reportId))
    )
  );
}

function notices(e) {
  const p = e.report;
  const out = [];
  if (p.replaces) {
    const r = p.replaces;
    out.push(
      h(
        'div',
        { class: 'callout amber' },
        icon('undo'),
        h('div', null, h('b', null, 'This replaces revision ' + r.revision), h('div', { class: 'muted' }, 'Sent back by ' + r.name + ' (' + V.stepRoleLabel(r.role === 'staff' ? r.step : r.role) + ') on ' + fmtShortDate(r.at) + '.'), r.remarks ? h('q', null, r.remarks) : null)
      )
    );
  }
  const st = e.status;
  if (st.stage === 'returned') {
    out.push(
      h(
        'div',
        { class: 'callout' },
        icon('undo'),
        h('div', null, h('b', null, 'Sent back by ' + st.last.name + ' (' + V.stepRoleLabel(st.last.step) + ')'), h('div', { class: 'muted' }, fmtDateTime(st.last.at)), h('q', null, st.last.remarks))
      )
    );
  }
  return out.length ? h('div', { class: 'stack' }, out) : null;
}

function checkLine(l) {
  const ic = l.state === 'ok' ? 'check' : l.state === 'bad' ? 'x' : l.state === 'warn' ? 'alert' : 'info';
  return h('li', { class: 'cl ' + l.state }, icon(ic), h('div', null, h('b', null, l.title), l.detail ? h('span', null, l.detail) : null, l.action ? h('button', { class: 'btn sm', style: { marginTop: '6px' }, onclick: l.action.run }, l.action.label) : null));
}
function checksCard(e) {
  const c = e.check;
  const bad = c.lines.filter((l) => l.state === 'bad').length;
  const flagged = e.trips.filter((t) => V.tripFlags(t, e.report.policy).length > 0);
  const warnAid = e.aids.lines.some((l) => l.state === 'warn') || flagged.length > 0;
  let head, sub, shield, cls;
  if (bad) {
    head = 'Do not sign: ' + plural(bad, 'check') + ' failed';
    sub = 'Something in this file does not add up. Ask the staff member to send the report again.';
    shield = 'shieldx';
    cls = 'bad';
  } else if (c.hasWarnings || warnAid) {
    head = 'Checks passed, with notes to read';
    sub = 'The file is intact. Read the notes below before you sign.';
    shield = 'shield';
    cls = 'warn';
  } else {
    head = 'All checks passed';
    sub = 'Nothing changed after the staff member sent it.';
    shield = 'shield';
    cls = '';
  }
  const names = Array.from(new Set(flagged.flatMap((t) => V.tripFlags(t, e.report.policy))));
  const flagLine = flagged.length
    ? [{ state: 'warn', title: plural(flagged.length, 'trip') + ' flagged: ' + names.join(', ').toLowerCase(), detail: 'These were recorded with an exception. Look at the reason and the photos.', action: { label: 'Show these trips', run: () => { ui.filter = 'look'; refreshTrips(); cur.els.trips.scrollIntoView({ behavior: 'smooth', block: 'start' }); } } }]
    : [];
  const all = c.lines.concat(flagLine, e.aids.lines);
  const notes = all.filter((l) => l.state !== 'ok');
  const passed = all.filter((l) => l.state === 'ok');
  return h(
    'section',
    { class: 'card pad checks' },
    h('div', { class: 'banner-ok' }, h('span', { class: 'shield ' + cls }, icon(shield)), h('div', null, h('h2', null, head), h('p', { class: 'muted' }, sub))),
    notes.length ? h('ul', { class: 'clines' }, notes.map(checkLine)) : null,
    passed.length
      ? h('details', { class: 'passed', open: notes.length === 0 && false }, h('summary', null, plural(passed.length, 'check') + ' passed'), h('ul', { class: 'clines' }, passed.map(checkLine)), h('p', { class: 'hint' }, 'The seal checks run on this computer. The km, meter and repeat checks are aids for your judgement and are not part of the seal.'))
      : null
  );
}

function statementCard(e) {
  const p = e.report;
  const s = p.summary;
  const st = e.status;
  const row = (label, value, cls) => h('div', { class: 'lr' + (cls ? ' ' + cls : '') }, h('span', null, label), h('span', { class: 'd' }), h('b', null, value));
  const approved = st.stage === 'approved';
  return h(
    'section',
    { class: 'card pad' },
    h('div', { class: 'sec' }, h('h2', null, 'Statement')),
    h(
      'div',
      { class: 'ledger' },
      row('Trips counted', String(s.trips)),
      row('Total distance', fmtKm(s.km) + ' km'),
      row('Within the limit', fmtKm(s.within) + ' km'),
      row('Above the limit', fmtKm(s.excess) + ' km', s.excess > 0 ? 'over' : ''),
      row('Rate', fmtRs(p.policy.rate) + ' a km'),
      row('Amount for km within limit', fmtRs(s.amount), 'strong'),
      approved ? row('Approved for payment', fmtKm(V.payableKm(p)) + ' km · ' + fmtRs(V.payableAmount(p)), 'strong') : null
    ),
    s.excess > 0 && !approved ? h('p', { class: 'hint', style: { marginTop: '10px' } }, fmtKm(s.excess) + ' km is above the limit. Only the District Integrator can approve it (' + fmtRs(s.excess * p.policy.rate) + ' more).') : null,
    approved && s.excess > 0 ? h('p', { class: 'hint', style: { marginTop: '10px' } }, V.approvalOf(p).excessApproved ? 'The District Integrator approved the km above the limit.' : 'The District Integrator did not approve the km above the limit.') : null
  );
}

function projectsCard(e) {
  const p = e.report;
  const kms = Array.from(e.sum.kmByProject.entries()).sort((a, b) => b[1] - a[1]);
  const top = kms.length ? kms[0][1] : 0;
  const base = p.policy.scope === 'project' ? Math.max(top, p.policy.limitKm) : e.sum.km || 1;
  return h(
    'section',
    { class: 'card pad' },
    h('div', { class: 'sec' }, h('h2', null, 'By project'), h('span', { class: 'faint' }, p.policy.scope === 'project' ? 'Limit ' + fmtKm(p.policy.limitKm) + ' km each' : 'Share of the month')),
    h(
      'div',
      { class: 'bars' },
      kms.map(([name, km]) => {
        const over = p.policy.scope === 'project' && km > p.policy.limitKm;
        return h(
          'div',
          { class: 'bar' },
          h('div', { class: 't' }, h('span', null, name || '(no project)'), h('span', null, fmtKm(km) + ' km')),
          h('div', { class: 'rail' }, h('i', { style: { width: Math.max(2, Math.round((km / base) * 100)) + '%' } })),
          h('small', null, plural(e.sum.tripsByProject.get(name) || 0, 'trip'), over ? ' · ' + fmtKm(km - p.policy.limitKm) + ' km over the limit' : '')
        );
      })
    )
  );
}

// ---------------------------------------------------------------- trips

function tripNeedsLook(e, t) {
  return V.tripFlags(t, e.report.policy).length > 0 || (e.aids.perTrip.get(t.id) || []).some((a) => a.state === 'warn') || !!metaOf(e).queried[t.id] || t.status === 'cancelled';
}

function tripsCard(e) {
  const m = metaOf(e);
  const filter = ui.filter;
  const list = e.trips.filter((t) => (filter === 'look' ? tripNeedsLook(e, t) : filter === 'open' ? t.status !== 'cancelled' && !m.checked[t.id] : true));
  const total = tripsToCheck(e);
  const seg = (id, label) => h('button', { 'aria-pressed': filter === id ? 'true' : 'false', onclick: () => { ui.filter = id; refreshTrips(); } }, label);
  const allDone = checkedCount(e) === total;
  return h(
    'section',
    { class: 'card' },
    h(
      'div',
      { class: 'tbar' },
      h('h2', null, 'Trips'),
      h('div', { class: 'seg', role: 'group', 'aria-label': 'Filter trips' }, seg('all', 'All ' + e.trips.length), seg('look', 'Needs a look'), seg('open', 'Not checked')),
      h('div', { class: 'prog noprint' }, h('span', { class: 'js-prog-text' }, checkedCount(e) + ' of ' + total + ' checked'), h('span', { class: 'rail' }, h('i', { class: 'js-prog-rail', style: { width: (total ? Math.round((checkedCount(e) / total) * 100) : 0) + '%' } })), h('button', { class: 'btn sm', onclick: () => { markAll(e, !allDone); } }, allDone ? 'Clear ticks' : 'Tick all'))
    ),
    h(
      'div',
      { class: 'tablewrap' },
      h(
        'table',
        { class: 'trips' },
        h('thead', null, h('tr', null, h('th', { class: 'noprint' }, h('span', { class: 'sr' }, 'Checked')), h('th', null, 'Date'), h('th', null, 'Route'), h('th', null, 'Work'), h('th', null, 'Meter'), h('th', { class: 'num', style: { textAlign: 'right' } }, 'Km'), h('th', { class: 'noprint' }, 'Photos'), h('th', { class: 'noprint' }, h('span', { class: 'sr' }, 'Query')))),
        h('tbody', null, list.length ? list.map((t) => tripRows(e, t)) : h('tr', null, h('td', { colspan: 8, class: 'faint', style: { textAlign: 'center', padding: '28px' } }, filter === 'look' ? 'No trip needs a second look.' : 'Every trip is ticked.')))
      )
    )
  );
}

function thumb(e, t, which, big) {
  const r = which === 'start' ? t.start : t.end;
  if (!r) return h('span', { class: 'thumb none' }, '—');
  const url = photoUrl(e, r.photo);
  const bad = photoState(e, r) !== 'ok';
  const label = which === 'start' ? 'Opening' : 'Closing';
  return h(
    'button',
    { class: 'thumb' + (big ? ' lg' : ''), title: label + ' photo. Click to enlarge.', 'aria-label': label + ' odometer photo, ' + fmtDate(t.date) + ', ' + fmtKm(r.km) + ' km. Open large.', onclick: (ev) => { ev.stopPropagation(); openLightbox(e, t.id, which); } },
    url && !bad ? h('img', { src: url, alt: '', loading: 'lazy', onerror: (ev) => ev.target.replaceWith(h('span', { class: 'nopic' }, 'Not a picture')) }) : h('span', { class: 'nopic' }, bad ? 'Photo does not match' : 'No photo'),
    h('span', null, label)
  );
}

function tripRows(e, t) {
  const m = metaOf(e);
  const open = ui.expanded.has(t.id);
  const gone = t.status === 'cancelled';
  const flags = V.tripFlags(t, e.report.policy);
  const aids = e.aids.perTrip.get(t.id) || [];
  const q = m.queried[t.id];
  const toggle = () => {
    if (ui.expanded.has(t.id)) ui.expanded.delete(t.id);
    else ui.expanded.add(t.id);
    refreshTrips();
  };
  const main = h(
    'tr',
    { class: 'row' + (open ? ' open' : '') + (gone ? ' gone' : '') + (q ? ' q' : ''), tabindex: 0, 'aria-expanded': open ? 'true' : 'false', onclick: toggle, onkeydown: (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); toggle(); } } },
    h('td', { class: 'noprint' }, gone ? h('span', { class: 'faint' }, '—') : h('input', { type: 'checkbox', class: 'ck', checked: !!m.checked[t.id], 'aria-label': 'Checked: ' + fmtDate(t.date) + ' ' + t.from + ' to ' + t.to, onclick: (ev) => ev.stopPropagation(), onchange: (ev) => setChecked(e, t.id, ev.target.checked) })),
    h('td', { class: 'date' }, h('b', null, fmtDate(t.date)), h('small', null, weekday(t.date))),
    h(
      'td',
      { class: 'rt' },
      h('b', null, t.from + ' → ' + t.to),
      h('small', null, t.project + ' · ' + t.vehicle),
      h('div', { class: 'flags', style: { marginTop: '4px' } }, gone ? h('span', { class: 'pill' }, 'Cancelled') : null, flags.map((f) => h('span', { class: 'pill warn' }, f)), q ? h('span', { class: 'pill bad' }, 'Query raised') : null),
      aids.filter((a) => a.state === 'warn').slice(0, 1).map((a) => h('span', { class: 'aid warn' }, a.text))
    ),
    h('td', { class: 'wk' }, h('b', null, t.activity), h('small', null, t.task)),
    h('td', { class: 'rd' }, t.end ? fmtKm(t.start.km) + ' → ' + fmtKm(t.end.km) : fmtKm(t.start.km)),
    h('td', { class: 'km' }, t.km === null ? '—' : fmtKm(t.km), h('small', null, 'km')),
    h('td', { class: 'noprint' }, h('div', { class: 'ths' }, thumb(e, t, 'start'), t.end ? thumb(e, t, 'end') : null)),
    h('td', { class: 'noprint' }, h('button', { class: 'qbtn', 'aria-pressed': q ? 'true' : 'false', title: q ? 'Remove the query' : 'Raise a query on this trip', 'aria-label': 'Raise a query on ' + fmtDate(t.date) + ' ' + t.from + ' to ' + t.to, onclick: (ev) => { ev.stopPropagation(); setQuery(e, t.id, !q); } }, icon('flag')))
  );
  if (!open) return [main];
  return [main, h('tr', { class: 'detail' }, h('td', { colspan: 8 }, tripDetail(e, t)))];
}

function kv(label, value) {
  if (value === null || value === undefined || value === '') return null;
  return h('div', null, h('span', { class: 'k' }, label), h('span', { class: 'v' }, value));
}

function readingCard(e, t, which) {
  const r = which === 'start' ? t.start : t.end;
  const label = which === 'start' ? 'Opening reading' : 'Closing reading';
  if (!r) return h('div', null, h('span', { class: 'k' }, label), h('span', { class: 'faint' }, 'Not taken'));
  const ps = photoState(e, r);
  return h(
    'div',
    null,
    h('span', { class: 'k' }, label),
    drums(r.km, 'lg'),
    thumb(e, t, which, true),
    h('small', null, 'Logged ', fmtDateTime(r.at)),
    r.photoTime ? h('small', null, 'Photo taken ', fmtDateTime(r.photoTime)) : null,
    r.oldPhoto ? h('small', { style: { color: 'var(--warn)', fontWeight: 600 } }, 'Photo was not fresh') : null,
    r.gps ? h('small', null, icon('pin'), ' ', r.gps.lat.toFixed(5) + ', ' + r.gps.lng.toFixed(5) + (r.gps.acc ? ' (±' + Math.round(r.gps.acc) + ' m) ' : ' '), h('a', { href: 'https://www.openstreetmap.org/?mlat=' + r.gps.lat + '&mlon=' + r.gps.lng + '#map=16/' + r.gps.lat + '/' + r.gps.lng, target: '_blank', rel: 'noopener', onclick: (ev) => ev.stopPropagation() }, 'map')) : h('small', null, 'No location recorded'),
    r.prevKm !== null && r.prevKm !== undefined ? h('small', null, 'Last closing before this: ' + fmtKm(r.prevKm)) : null,
    r.returnTo ? h('small', null, 'Returned to ' + r.returnTo) : null,
    r.remarks ? h('small', null, 'Remarks: ' + r.remarks) : null,
    h('small', { style: { color: ps === 'ok' ? 'var(--ok)' : 'var(--bad)', fontWeight: 600 } }, ps === 'ok' ? 'Photo matches its fingerprint' : ps === 'missing' ? 'Photo is missing' : 'Photo does not match its fingerprint')
  );
}

function tripDetail(e, t) {
  const aids = e.aids.perTrip.get(t.id) || [];
  return h(
    'div',
    { class: 'dgrid' },
    h(
      'div',
      { class: 'kv' },
      kv('Project', t.project),
      kv('Vehicle', t.vehicle + (t.vtype ? ' (' + t.vtype + ')' : '')),
      kv('Activity', t.activity),
      kv('Task', t.task),
      kv('Logged', fmtDateTime(t.loggedAt)),
      kv('Locked', t.lockedAt ? fmtDateTime(t.lockedAt) + (t.chainPos !== null ? ' · entry no. ' + t.chainPos : '') : null),
      kv('Seal', t.hash ? t.hash.slice(0, 16) + '…' : null),
      t.late ? kv('Late entry', t.late.reason || 'No reason given') : null,
      t.meterReset ? kv('Meter reset', t.meterReset.reason || 'No reason given') : null,
      t.prior ? kv('Prior approval', t.prior.none ? 'None taken' : [t.prior.by, t.prior.date, t.prior.mode, t.prior.ref].filter(Boolean).join(', ')) : null,
      t.cancel ? kv('Cancelled', (t.cancel.reason || '') + (t.cancel.at ? ' (' + fmtDateTime(t.cancel.at) + ')' : '')) : null,
      t.notes.length ? h('div', null, h('span', { class: 'k' }, 'Notes'), h('span', { class: 'v' }, t.notes.map((n) => h('div', { class: 'note' }, n.text, h('small', null, fmtDateTime(n.at)))))) : null,
      aids.length ? h('div', null, h('span', { class: 'k' }, 'Look at'), h('span', { class: 'v' }, aids.map((a) => h('span', { class: 'aid ' + a.state }, a.text)))) : null
    ),
    h('div', { class: 'rdg' }, readingCard(e, t, 'start'), readingCard(e, t, 'end'))
  );
}

// ---------------------------------------------------------------- the sign-off column

function asideCol(e) {
  return h('aside', { class: 'aside noprint', 'aria-label': 'Sign-off' }, stepsCard(e), signCard(e), sendCard(e), signoffsCard(e), fileCard(e));
}

function stepsCard(e) {
  const st = e.status;
  const labels = [['Sent', 'Staff'], ['Checked', 'Block Int.'], ['Verified', 'Accountant'], ['Approved', 'District Int.']];
  const steps = labels.map(([a, b], i) => {
    let cls = '';
    if (st.stage === 'returned' && i === st.returnedAt) cls = 'back';
    else if (i < st.done) cls = 'done';
    else if (i === st.done && !st.finished) cls = 'now';
    return h('div', { class: 'step ' + cls }, h('span', { class: 'dot' }, cls === 'done' ? icon('check') : cls === 'back' ? icon('x') : null), h('b', null, a), h('small', null, b));
  });
  return h('section', { class: 'card pad' }, h('div', { class: 'steps' }, steps), h('p', { class: 'muted', style: { textAlign: 'center', marginTop: '12px', fontWeight: 600 } }, V.stageLabel(st)));
}

function signoffsCard(e) {
  const p = e.report;
  return h(
    'section',
    { class: 'card pad' },
    h('div', { class: 'sec' }, h('h2', null, 'Sign-offs')),
    h(
      'ol',
      { class: 'tl' },
      p.signoffs.map((s) => {
        const back = s.decision === 'return';
        return h(
          'li',
          null,
          h('span', { class: 'c' + (back ? ' back' : '') }, icon(back ? 'undo' : 'check')),
          h(
            'div',
            null,
            h('b', null, (s.step === 'submit' ? 'Sent' : V.signoffVerb(s)) + ' by ' + s.name),
            h('small', null, [s.designation || V.stepRoleLabel(s.step), fmtDateTime(s.at)].join(' · ')),
            s.excessApproved ? h('small', { style: { color: 'var(--ok)', fontWeight: 600 } }, 'Km above the limit approved') : null,
            s.remarks ? h('div', { class: 'rem' }, s.remarks) : null
          )
        );
      })
    )
  );
}

function signCard(e) {
  const st = e.status;
  const pr = state.profile;
  const p = e.report;
  if (st.stage === 'approved') {
    return h('section', { class: 'card pad sign' }, h('h2', null, 'Approved'), h('p', { class: 'role' }, 'Nothing more to sign. Payable: ' + fmtKm(V.payableKm(p)) + ' km, ' + fmtRs(V.payableAmount(p)) + '.'));
  }
  if (st.stage === 'returned') {
    return h('section', { class: 'card pad sign' }, h('h2', null, 'Sent back to staff'), h('p', { class: 'role' }, 'The staff member corrects the trips and sends a new revision. Open that file here when it arrives.'));
  }
  const waiting = V.stepRoleLabel(st.nextStep);
  if (!pr) {
    return h('section', { class: 'card pad sign' }, h('h2', null, 'With the ' + waiting), h('p', { class: 'role' }, 'Set your name and role to sign reports.'), h('button', { class: 'btn primary big', onclick: () => profileDialog() }, 'Set up your profile'));
  }
  if (pr.id === p.staff.id || pr.role !== st.nextStep) {
    return h(
      'section',
      { class: 'card pad sign' },
      h('h2', null, 'With the ' + waiting),
      h('p', { class: 'role' }, 'You are signed in as ' + ROLE_NAMES[pr.role] + '. This step belongs to the ' + waiting + '. Read the report as much as you like, but only that role can sign it.'),
      h('button', { class: 'btn', onclick: () => profileDialog() }, 'Change my role')
    );
  }
  // It is my turn.
  const step = st.nextStep;
  const act = ACTION[step];
  const total = tripsToCheck(e);
  const got = checkedCount(e);
  const failed = !e.check.ok;
  const dec = step === 'di' ? 'approve' : 'forward';
  const remarks = h('textarea', { class: 'input' + (ui.remarkErr ? ' err' : ''), id: 'remarks', rows: 4, placeholder: 'Anything the next person should know. Required if you send it back.', oninput: (ev) => { ui.remarks = ev.target.value; ui.remarkErr = false; ev.target.classList.remove('err'); const er = $('#remarkErr'); if (er) er.hidden = true; } });
  remarks.value = ui.remarks;
  const excess = p.summary.excess;
  return h(
    'section',
    { class: 'card pad sign' },
    h('h2', null, act.title),
    h('p', { class: 'role' }, 'Signing as ' + pr.name + ', ' + ROLE_NAMES[pr.role]),
    h('div', { class: 'meter' }, h('div', { class: 'row' }, h('span', { class: 'js-prog-text' }, got + ' of ' + total + ' trips checked'), got === total ? icon('check') : null), h('div', { class: 'rail' }, h('i', { class: 'js-prog-rail', style: { width: (total ? Math.round((got / total) * 100) : 0) + '%' } })), h('span', { class: 'hint' }, 'Tick each trip as you check it. Your signature covers the whole report.')),
    failed ? h('div', { class: 'callout', style: { marginBottom: '12px' } }, icon('shieldx'), h('div', null, h('b', null, 'This report failed its checks'), h('div', { class: 'muted' }, 'You cannot forward it. Send it back so the staff member can send it again.'))) : null,
    h('div', { class: 'field' }, h('label', { for: 'remarks' }, 'Remarks'), remarks, h('span', { class: 'errtext', id: 'remarkErr', hidden: !ui.remarkErr }, 'Write why you are sending it back.'), queriedTrips(e).length ? h('button', { class: 'btn sm', type: 'button', onclick: () => addQueriesToRemarks(e) }, icon('flag'), 'Add ' + plural(queriedTrips(e).length, 'queried trip') + ' to remarks') : null),
    step === 'di' && excess > 0
      ? h(
          'label',
          { class: 'switch' },
          h('div', null, h('b', null, 'Approve the ' + fmtKm(excess) + ' km above the limit'), h('span', null, ui.excess ? fmtKm(p.summary.within + excess) + ' km, ' + fmtRs((p.summary.within + excess) * p.policy.rate) + ' will be payable.' : 'Off: only ' + fmtKm(p.summary.within) + ' km, ' + fmtRs(p.summary.amount) + ', is payable.')),
          h('input', { type: 'checkbox', checked: ui.excess, onchange: (ev) => { ui.excess = ev.target.checked; refreshAside(); } }),
          h('span', { class: 'tr' })
        )
      : null,
    h(
      'div',
      { class: 'stack', style: { marginTop: '12px' } },
      h('button', { class: 'btn primary big', disabled: failed, onclick: () => startSign(e, dec) }, icon('check'), act[dec]),
      h('button', { class: 'btn big danger', onclick: () => startSign(e, 'return') }, icon('undo'), 'Send back to staff')
    ),
    h('p', { class: 'sealnote' }, 'Your name and the time are added to the file. A signature cannot be removed afterwards.')
  );
}

function lastSignedByMe(e) {
  const s = e.report.signoffs;
  return !!state.profile && s.length > 1 && s[s.length - 1].userId === state.profile.id;
}

function sendCard(e) {
  if (!lastSignedByMe(e)) return null;
  const p = e.report;
  const st = e.status;
  let who;
  if (st.stage === 'returned') who = 'the staff member, ' + p.staff.name;
  else if (st.stage === 'approved') who = 'the staff member, ' + p.staff.name + ', and keep a copy for the accounts';
  else who = 'the ' + V.stepRoleLabel(st.nextStep);
  const msg = h('textarea', { class: 'input msgbox', id: 'sharemsg', rows: 5, readonly: true });
  msg.value = V.reportShareText(p);
  const name = outName(e);
  return h(
    'section',
    { class: 'card pad sendcard' },
    h('h2', null, icon('check'), 'Signed. Now pass it on'),
    h('p', { class: 'muted', style: { margin: '6px 0 12px' } }, 'Save the file and send it to ' + who + '. Attach it in WhatsApp or email.'),
    h('div', { class: 'stack' }, h('button', { class: 'btn primary big', onclick: () => saveReport(e) }, icon('download'), 'Save the signed file'), h('span', { class: 'hint' }, name), msg),
    h(
      'div',
      { class: 'links', style: { marginTop: '10px' } },
      h('button', { class: 'btn sm', onclick: () => copyText(msg.value, msg) }, icon('copy'), 'Copy message'),
      h('a', { class: 'btn sm', href: 'https://web.whatsapp.com/send?text=' + encodeURIComponent(msg.value), target: '_blank', rel: 'noopener' }, icon('chat'), 'WhatsApp Web'),
      h('a', { class: 'btn sm', href: 'mailto:?subject=' + encodeURIComponent('Vehicle log ' + V.fmtMonthLong(p.month) + ': ' + p.staff.name) + '&body=' + encodeURIComponent(msg.value) }, icon('mail'), 'Email')
    )
  );
}

function outName(e) {
  const n = V.reportFileName(e.report);
  return IN_ARTIFACT ? n.replace(/\.vlbreport$/, '.json') : n;
}

function fileCard(e) {
  return h(
    'section',
    { class: 'card pad' },
    h('div', { class: 'sec' }, h('h2', null, 'This file')),
    h(
      'div',
      { class: 'stack' },
      lastSignedByMe(e) ? null : h('button', { class: 'btn', onclick: () => saveReport(e) }, icon('download'), 'Save a copy'),
      h('button', { class: 'btn', onclick: () => exportCsv(e) }, icon('sheet'), 'Export trips as CSV'),
      IN_ARTIFACT ? null : h('button', { class: 'btn', onclick: () => window.print() }, icon('print'), 'Print this report'),
      h('button', { class: 'btn danger', onclick: () => removeReport(e) }, icon('trash'), 'Remove from this computer')
    ),
    IN_ARTIFACT ? h('p', { class: 'hint', style: { marginTop: '10px' } }, 'Saved as a .json file here. The phone app opens it like a .vlbreport file.') : null
  );
}

// ---------------------------------------------------------------- partial redraws (keep typing and scroll)

function refreshTrips() {
  if (!cur) return;
  const n = tripsCard(cur.entry);
  cur.els.trips.replaceWith(n);
  cur.els.trips = n;
}
function refreshAside() {
  if (!cur) return;
  const keep = $('#remarks') ? $('#remarks').selectionStart : null;
  const n = asideCol(cur.entry);
  cur.els.aside.replaceWith(n);
  cur.els.aside = n;
  if (keep !== null && $('#remarks')) $('#remarks').focus();
}
function updateProgress(e) {
  const total = tripsToCheck(e);
  const got = checkedCount(e);
  $$('.js-prog-text').forEach((n) => (n.textContent = got + ' of ' + total + ' checked'));
  $$('.meter .js-prog-text').forEach((n) => (n.textContent = got + ' of ' + total + ' trips checked'));
  $$('.js-prog-rail').forEach((n) => (n.style.width = (total ? Math.round((got / total) * 100) : 0) + '%'));
}
