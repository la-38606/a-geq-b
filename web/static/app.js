// A>=B prover page. All mathematics happens on the server (the same OCaml
// library the CLI uses); this file renders the Proof_result JSON and never
// decides anything about a proof. Typesetting is KaTeX over the LaTeX strings
// the core emits (see math.js); the exact plain-text forms stay available
// under "Certificate details".

'use strict';

const $ = (id) => document.getElementById(id);

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
    return 'The right-hand side is a sum of squares with nonnegative rational ' +
           'coefficients; the exact checker verified that it equals the target.';
  }
  return 'On the stated domain every term on the right is nonnegative or zero; ' +
         'the exact checker verified the identity and that each scaled ' +
         'polynomial is a declared assumption.';
}

// The certificate as one display equation, target = sum of terms. Long
// identities break into an aligned block, one summand per row, so nothing
// overflows or shrinks.
function certificateLatex(d) {
  const target = d.target.latex;
  const terms = d.certificate.latex_terms;
  const oneLine = target + ' = ' + terms.join(' + ');
  if (oneLine.length <= 120 || terms.length === 1) return oneLine;
  return '\\begin{aligned}' +
    target + ' ={}& ' + terms[0] +
    terms.slice(1).map((t) => ' \\\\ &+ ' + t).join('') +
    '\\end{aligned}';
}

function renderTrace(d) {
  const body = $('trace-list').querySelector('tbody');
  body.replaceChildren();
  for (const s of d.trace) {
    const row = document.createElement('tr');
    if (!s.ok) row.className = 'miss';
    const tag = s.trusted
      ? '<span class="tag tag-trusted">trusted</span>'
      : '<span class="tag tag-search">search</span>';
    const ms = s.ms == null ? '' : s.ms < 0.05 ? '&lt;0.1 ms' : s.ms.toFixed(1) + ' ms';
    row.innerHTML =
      '<td class="step-title"></td>' +
      '<td class="step-detail"></td>' +
      '<td class="step-ms">' + ms + '</td>';
    row.querySelector('.step-title').textContent = s.title;
    row.querySelector('.step-title').insertAdjacentHTML('beforeend', tag);
    const detail = row.querySelector('.step-detail');
    // Typeset the two stages whose content is mathematics; the rest is prose.
    if (s.title === 'Normalize' && s.ok && d.target) {
      tex(detail, d.target.latex + ' \\ge 0');
    } else if (s.title === 'Side conditions' && s.ok && d.hypotheses.length > 0) {
      tex(detail, d.hypotheses.map((h) => h.latex).join(',\\quad '));
    } else {
      detail.textContent = s.detail;
    }
    body.appendChild(row);
  }
  $('sdp-note').hidden =
    !d.trace.some((s) => s.title === 'Numerical SDP' && s.ok);
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
  // Let the result take the page: fold the example list away (it reopens on
  // demand) and drop the input preview, which the Claim block now repeats.
  // Cancel any debounced or in-flight preview so a fast proof is not followed
  // by the preview popping back in.
  clearTimeout(previewTimer);
  previewSeq++;
  $('examples').open = false;
  $('preview').hidden = true;

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

  $('claim-block').hidden = !d.claim_latex;
  if (d.claim_latex) tex($('claim-echo'), d.claim_latex, true);

  const hyps = d.hypotheses || [];
  $('assuming-block').hidden = hyps.length === 0;
  if (hyps.length > 0) {
    const box = $('assuming');
    box.replaceChildren();
    for (const h of hyps) {
      const line = document.createElement('div');
      tex(line, h.latex);
      box.appendChild(line);
    }
  }

  $('target-block').hidden = !d.target;
  if (d.target) {
    tex($('target'), d.target.latex + ' \\ge 0');
    $('target-domain').hidden = hyps.length === 0;
  }

  const proved = d.status === 'PROVED' && d.certificate;
  $('cert-block').hidden = !proved;
  if (proved) {
    tex($('certificate'), certificateLatex(d), true);
    $('cert-note').textContent = certNote(d);
    const constrained = d.certificate.kind === 'positivstellensatz';
    $('domain-facts').hidden = !constrained;
    if (constrained) {
      tex($('domain-facts-math'), hyps.map((h) => h.latex).join(',\\qquad '));
    }
  }

  $('actions').hidden = false;
  $('trace-toggle').hidden = !(d.trace && d.trace.length > 0);
  $('details-toggle').hidden = !proved;
  // The emitted Lean proof handles unconstrained sum-of-squares certificates.
  $('lean-button').hidden =
    !(proved && d.certificate.kind === 'sos' && hyps.length === 0);

  if (d.trace && d.trace.length > 0) renderTrace(d);
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

// --- live preview ---------------------------------------------------------
// Parsed by the backend (the only parser there is); rendered when it answers.
// A claim that does not parse yet simply shows no preview.

let previewTimer = null;
let previewSeq = 0;

async function updatePreview() {
  const claim = $('claim-input').value.trim();
  if (claim === '') {
    $('preview').hidden = true;
    return;
  }
  const seq = ++previewSeq;
  try {
    const res = await fetch('/api/preview', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ claim }),
    });
    const d = await res.json();
    if (seq !== previewSeq) return; // a newer keystroke superseded this reply
    if (d.latex) {
      tex($('preview-math'), d.latex, true);
      $('preview').hidden = false;
    } else {
      $('preview').hidden = true;
    }
  } catch {
    $('preview').hidden = true;
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
// A compact list: name on the left, the typeset claim on the right. The LaTeX
// comes from /api/preview so it is exactly what the parser sees.

async function loadExamples() {
  try {
    const res = await fetch('/examples.json');
    if (!res.ok) return;
    const data = await res.json();
    const list = $('example-list');
    for (const ex of data.examples) {
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'example-row';
      row.title = ex.note || '';
      const name = document.createElement('span');
      name.className = 'example-name';
      name.textContent = ex.label;
      const math = document.createElement('span');
      math.className = 'example-claim';
      math.textContent = ex.claim; // fallback until the preview answers
      row.append(name, math);
      row.addEventListener('click', () => {
        $('claim-input').value = ex.claim;
        updatePreview();
        $('claim-input').focus();
      });
      list.appendChild(row);
      fetch('/api/preview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ claim: ex.claim }),
      })
        .then((r) => r.json())
        .then((d) => { if (d.latex) tex(math, d.latex); })
        .catch(() => {});
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

$('claim-input').addEventListener('input', () => {
  clearTimeout(previewTimer);
  previewTimer = setTimeout(updatePreview, 250);
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
