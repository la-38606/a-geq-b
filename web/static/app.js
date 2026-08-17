// A>=B prover page. All mathematics happens on the server (the same OCaml
// library the CLI uses); this file renders the Proof_result JSON and never
// decides anything about a proof.

'use strict';

const $ = (id) => document.getElementById(id);

// --- presentational math rendering ---------------------------------------
// Turns the server's exact plain-text form ("a^2 - 2*a*b + b^2 >= 0") into
// display HTML: superscripts, center dots, real minus/relation glyphs, italic
// variables. Cosmetic only -- the exact strings remain available under
// "Certificate details".
function mathHTML(text) {
  const escSpan = (s) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let out = '';
  let i = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i];
    if (/[A-Za-z_]/.test(c)) {
      let j = i + 1;
      while (j < n && /[A-Za-z0-9_]/.test(text[j])) j++;
      const word = text.slice(i, j);
      out += word === 'given'
        ? '<span class="kw">given</span>'
        : '<var>' + escSpan(word) + '</var>';
      i = j;
    } else if (c === '^') {
      let j = i + 1;
      while (j < n && /[0-9]/.test(text[j])) j++;
      if (j > i + 1) {
        out += '<sup>' + text.slice(i + 1, j) + '</sup>';
        i = j;
      } else {
        out += '^';
        i++;
      }
    } else if (text.startsWith('>=', i)) {
      out += ' ≥ ';
      i += 2;
    } else if (text.startsWith('<=', i)) {
      out += ' ≤ ';
      i += 2;
    } else if (c === '*') {
      out += '·';
      i++;
    } else if (c === '-') {
      out += '−';
      i++;
    } else {
      out += escSpan(c);
      i++;
    }
  }
  return out.replace(/  +/g, ' ');
}

// --- result rendering -----------------------------------------------------

const STATUS = {
  PROVED: { cls: 'status-proved', text: 'PROVED' },
  NO_CERT_FOUND: { cls: 'status-nocert', text: 'NO CERTIFICATE FOUND' },
  INVALID_INPUT: { cls: 'status-invalid', text: 'INVALID INPUT' },
  CHECK_FAILED: { cls: 'status-rejected', text: 'CERTIFICATE REJECTED' },
};

let lastResult = null;

function statusNote(d) {
  switch (d.status) {
    case 'PROVED':
      return 'The identity below was verified with exact rational arithmetic.';
    case 'NO_CERT_FOUND':
      return 'A≥B did not find a supported certificate for this claim. ' +
             'This is not a disproof.';
    case 'INVALID_INPUT':
      return d.error || 'The input could not be read as a polynomial inequality.';
    case 'CHECK_FAILED':
      return d.error ||
             'The search proposed a certificate, but the exact checker rejected it.';
    default:
      return '';
  }
}

function certNote(d) {
  if (d.certificate.kind === 'sos') {
    return 'Each summand is a nonnegative rational multiple of a square, so the ' +
           'right-hand side is nonnegative for every real assignment. The exact ' +
           'checker verified that it equals the target, term for term.';
  }
  return 'On the domain cut out by the assumptions: every square is nonnegative, ' +
         'every multiplier of a nonnegative hypothesis is a sum of squares, and ' +
         'multiples of vanishing hypotheses are zero, so the right-hand side is ' +
         'nonnegative there. The exact checker verified the identity and that ' +
         'every scaled polynomial is a declared hypothesis.';
}

function renderTrace(steps) {
  const list = $('trace-list');
  list.replaceChildren();
  for (const s of steps) {
    const li = document.createElement('li');
    const isErr = !s.ok && (s.trusted || lastResult.status === 'INVALID_INPUT');
    li.className = s.ok ? '' : (isErr ? 'err' : 'miss');
    const mark = s.ok ? '✓' : '✕';
    const badge = s.trusted
      ? '<span class="badge badge-trusted">trusted</span>'
      : '<span class="badge badge-search">search</span>';
    const ms = s.ms == null ? '' : s.ms < 0.05 ? '&lt;0.1 ms' : s.ms.toFixed(1) + ' ms';
    li.innerHTML =
      '<span class="mark">' + mark + '</span>' +
      '<span class="step-title"></span>' +
      '<span class="step-ms">' + ms + '</span>' +
      '<span class="step-detail"></span>';
    li.querySelector('.step-title').textContent = s.title;
    li.querySelector('.step-title').insertAdjacentHTML('beforeend', badge);
    li.querySelector('.step-detail').textContent = s.detail;
    list.appendChild(li);
  }
}

function hidePanels() {
  for (const id of ['trace-panel', 'details-panel', 'lean-panel']) $(id).hidden = true;
  for (const id of ['trace-toggle', 'details-toggle', 'lean-button']) {
    $(id).setAttribute('aria-expanded', 'false');
  }
}

function renderResult(d) {
  lastResult = d;
  $('result').hidden = false;
  hidePanels();

  const st = STATUS[d.status] || STATUS.CHECK_FAILED;
  const banner = $('status-banner');
  banner.className = 'status ' + st.cls;
  banner.textContent = st.text;
  $('status-note').textContent = statusNote(d);
  $('nocert-explain').hidden = d.status !== 'NO_CERT_FOUND';

  const warnings = $('warnings');
  warnings.replaceChildren();
  for (const w of d.vacuous || []) {
    const p = document.createElement('p');
    p.className = 'warning';
    p.textContent = 'Warning: ' + w;
    warnings.appendChild(p);
  }

  $('claim-block').hidden = false;
  $('claim-echo').innerHTML = mathHTML(d.claim);

  const hyps = d.hypotheses || [];
  $('assuming-block').hidden = hyps.length === 0;
  if (hyps.length > 0) {
    $('assuming').innerHTML = hyps.map((h) => mathHTML(h.text)).join('<br>');
  }

  $('target-block').hidden = !d.target;
  if (d.target) {
    $('target').innerHTML =
      mathHTML(d.target.text + ' >= 0') +
      (hyps.length > 0 ? ' <span class="domain-note">(on the domain above)</span>' : '');
  }

  const proved = d.status === 'PROVED' && d.certificate;
  $('cert-block').hidden = !proved;
  if (proved) {
    $('certificate').innerHTML =
      '<div>' + mathHTML(d.target.text) + '</div>' +
      '<div class="cert-rhs">= ' + mathHTML(d.certificate.text) + '</div>';
    $('cert-note').textContent = certNote(d);
  }

  $('actions').hidden = false;
  $('trace-toggle').hidden = !(d.trace && d.trace.length > 0);
  $('details-toggle').hidden = !proved;
  // The emitted Lean proof handles unconstrained sum-of-squares certificates.
  $('lean-button').hidden =
    !(proved && d.certificate.kind === 'sos' && hyps.length === 0);

  if (d.trace && d.trace.length > 0) renderTrace(d.trace);
  if (proved) {
    $('latex-out').textContent = d.target.latex + ' = ' + d.certificate.latex;
    $('json-out').textContent = JSON.stringify(d.certificate.file, null, 2);
  }
}

function renderServerError(msg) {
  lastResult = null;
  $('result').hidden = false;
  hidePanels();
  const banner = $('status-banner');
  banner.className = 'status status-invalid';
  banner.textContent = 'REQUEST FAILED';
  $('status-note').textContent = msg;
  $('nocert-explain').hidden = true;
  $('warnings').replaceChildren();
  for (const id of ['claim-block', 'assuming-block', 'target-block', 'cert-block',
                    'actions']) {
    $(id).hidden = true;
  }
}

// --- server calls ---------------------------------------------------------

async function prove(claim) {
  const button = $('prove-button');
  button.disabled = true;
  button.textContent = 'Proving…';
  try {
    const res = await fetch('/api/prove', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ claim }),
    });
    const data = await res.json();
    if (!res.ok) {
      renderServerError(data.error || 'request failed (HTTP ' + res.status + ')');
    } else {
      renderResult(data);
    }
  } catch {
    renderServerError('Could not reach the local server. Is a-geq-b-web still running?');
  } finally {
    button.disabled = false;
    button.textContent = 'Prove';
  }
}

async function exportLean() {
  if (!lastResult) return;
  const panel = $('lean-panel');
  try {
    const res = await fetch('/api/lean', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ claim: lastResult.claim }),
    });
    const data = await res.json();
    if (data.lean) {
      $('lean-out').textContent = data.lean;
      $('lean-note').textContent =
        'Generated from the verified certificate; the sum-of-squares identity is ' +
        'closed by `ring` and nonnegativity by `positivity`. Lean was not run ' +
        'here. Compile this file (with Mathlib) to have Lean’s kernel check ' +
        'the theorem.';
    } else {
      $('lean-out').textContent = '-- ' + (data.error || 'export failed');
      $('lean-note').textContent = '';
    }
    panel.hidden = false;
    $('lean-button').setAttribute('aria-expanded', 'true');
  } catch {
    renderServerError('Could not reach the local server. Is a-geq-b-web still running?');
  }
}

// --- examples -------------------------------------------------------------

async function loadExamples() {
  try {
    const res = await fetch('/examples.json');
    if (!res.ok) return;
    const data = await res.json();
    const chips = $('example-chips');
    for (const ex of data.examples) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'chip';
      b.textContent = ex.label;
      b.title = ex.claim + (ex.note ? ' (' + ex.note + ')' : '');
      b.addEventListener('click', () => {
        $('claim-input').value = ex.claim;
        $('claim-input').focus();
      });
      chips.appendChild(b);
    }
    $('examples').hidden = false;
  } catch {
    /* examples are a convenience; the prover works without them */
  }
}

// --- wiring ---------------------------------------------------------------

function togglePanel(buttonId, panelId) {
  const button = $(buttonId);
  const panel = $(panelId);
  button.addEventListener('click', () => {
    const open = panel.hidden;
    panel.hidden = !open;
    button.setAttribute('aria-expanded', String(open));
  });
}

$('prove-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const claim = $('claim-input').value.trim();
  if (claim !== '') prove(claim);
});

togglePanel('trace-toggle', 'trace-panel');
togglePanel('details-toggle', 'details-panel');
$('lean-button').addEventListener('click', () => {
  if ($('lean-panel').hidden) exportLean();
  else {
    $('lean-panel').hidden = true;
    $('lean-button').setAttribute('aria-expanded', 'false');
  }
});

for (const copy of document.querySelectorAll('button.copy')) {
  copy.addEventListener('click', async () => {
    const text = $(copy.dataset.copy).textContent;
    try {
      await navigator.clipboard.writeText(text);
      copy.textContent = 'Copied';
      setTimeout(() => (copy.textContent = 'Copy'), 1200);
    } catch {
      /* clipboard unavailable (e.g. non-secure context); leave the text visible */
    }
  });
}

loadExamples();
