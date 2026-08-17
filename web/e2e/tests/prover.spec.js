// Behavioural tests for the prover page. Everything runs against the real
// OCaml server; the assertions are about proof semantics (what may be called
// PROVED, what NO_CERT_FOUND must and must not claim), not about styling.
const { test, expect } = require('@playwright/test');

async function prove(page, claim) {
  await page.goto('/');
  await page.fill('#claim-input', claim);
  await page.click('#prove-button');
  await expect(page.locator('#status-banner')).not.toBeEmpty();
}

test.describe('proving', () => {
  test('a simple sum of squares is proved with its certificate', async ({ page }) => {
    await prove(page, 'a^2 + b^2 >= 2*a*b');
    await expect(page.locator('#status-banner')).toHaveText('PROVED');
    // The normalized target is shown...
    await expect(page.locator('#target')).toHaveAttribute('data-latex', /\\ge 0$/);
    // ...and the certificate is the real one: check the exact JSON the
    // checker verified, not just the pretty rendering.
    await page.click('#details-toggle');
    await expect(page.locator('#json-out')).toContainText('"poly": "a - b"');
    // The typeset block carries the LaTeX it renders in data-latex, so the
    // assertion is about the mathematics, not KaTeX markup.
    await expect(page.locator('#certificate')).toHaveAttribute(
      'data-latex',
      /\\left\(a - b\\right\)\^\{2\}/
    );
  });

  test('no certificate found is never presented as false', async ({ page }) => {
    // Motzkin's polynomial: nonnegative everywhere, provably not a sum of
    // squares. The one answer the UI must not give is "false".
    await prove(page, 'x^4*y^2 + x^2*y^4 + 1 >= 3*x^2*y^2');
    await expect(page.locator('#status-banner')).toHaveText('NO CERTIFICATE FOUND');
    await expect(page.locator('#status-note')).toContainText('not a disproof');
    await expect(page.locator('#nocert-explain')).toBeVisible();
    await expect(page.locator('#nocert-explain')).toContainText('never concludes');
    // No certificate block for an unproved claim.
    await expect(page.locator('#cert-block')).toBeHidden();
  });

  test('a constrained claim shows its assumptions and its certificate', async ({
    page,
  }) => {
    await prove(page, 'a^2 + b^2 >= 2 given a*b = 1');
    await expect(page.locator('#status-banner')).toHaveText('PROVED');
    await expect(page.locator('#assuming-block')).toBeVisible();
    await expect(page.locator('#assuming [data-latex]').first()).toHaveAttribute(
      'data-latex',
      /ab - 1 = 0/
    );
    // The certificate uses the hypothesis a*b - 1, and its domain facts are
    // restated under the identity.
    await expect(page.locator('#certificate')).toHaveAttribute('data-latex', /ab - 1/);
    await expect(page.locator('#domain-facts')).toBeVisible();
    // The reduction is explicitly relative to the domain.
    await expect(page.locator('#target-domain')).toBeVisible();
  });

  test('unparsable input is INVALID INPUT with the parser message', async ({
    page,
  }) => {
    await prove(page, 'a^2 + >= b');
    await expect(page.locator('#status-banner')).toHaveText('INVALID INPUT');
    await expect(page.locator('#status-note')).toContainText('could not parse');
    await expect(page.locator('#cert-block')).toBeHidden();
  });

  test('example rows fill the input without proving', async ({ page }) => {
    await page.goto('/');
    await page.click('.example-row:has-text("Motzkin polynomial")');
    await expect(page.locator('#claim-input')).toHaveValue(
      'x^4*y^2 + x^2*y^4 + 1 >= 3*x^2*y^2'
    );
    await expect(page.locator('#result')).toBeHidden();
  });
});

test.describe('input preview', () => {
  test('the typed claim is typeset by the backend parser', async ({ page }) => {
    await page.goto('/');
    await page.fill('#claim-input', '(a^2 + b^2)/2 >= a*b');
    await page.dispatchEvent('#claim-input', 'input');
    await expect(page.locator('#preview')).toBeVisible();
    await expect(page.locator('#preview-math')).toHaveAttribute(
      'data-latex',
      '\\frac{a^{2} + b^{2}}{2} \\ge ab'
    );
  });
});

test.describe('proof trace', () => {
  test('the trace shows the exact route with the trust tags', async ({ page }) => {
    await prove(page, 'a^2 + b^2 >= 2*a*b');
    await page.click('#trace-toggle');
    const steps = page.locator('#trace-list li');
    await expect(steps).toHaveCount(4); // parse, normalize, exact search, check
    await expect(steps.nth(0)).toContainText('Parse');
    await expect(steps.nth(0).locator('.tag-trusted')).toBeVisible();
    await expect(steps.nth(2)).toContainText('Exact search');
    await expect(steps.nth(2).locator('.tag-search')).toBeVisible();
    // The final stage is always the trusted check -- the only gate to PROVED.
    await expect(steps.nth(3)).toContainText('Exact check');
    await expect(steps.nth(3).locator('.tag-trusted')).toBeVisible();
  });

  test('the trace of a failed search records the miss honestly', async ({ page }) => {
    await prove(page, 'x^4*y^2 + x^2*y^4 + 1 >= 3*x^2*y^2');
    await page.click('#trace-toggle');
    const search = page.locator('#trace-list li', { hasText: 'Exact search' });
    await expect(search).toContainText('no certificate');
    // No trusted-check step may appear when nothing was checked. (Match on
    // step titles: a step *detail* legitimately mentions the exact checker.)
    await expect(
      page.locator('#trace-list .step-title', { hasText: 'Exact check' })
    ).toHaveCount(0);
  });
});

test.describe('lean export', () => {
  test('generates a theorem and says Lean was not run', async ({ page }) => {
    await prove(page, 'a^2 + b^2 >= 2*a*b');
    await page.click('#lean-button');
    await expect(page.locator('#lean-out')).toContainText('theorem');
    await expect(page.locator('#lean-out')).toContainText('positivity');
    // Honesty requirement: the page must not imply a kernel check happened.
    await expect(page.locator('#lean-note')).toContainText('Lean was not run');
  });

  test('is not offered for constrained proofs', async ({ page }) => {
    await prove(page, 'a^2 + b^2 >= 2 given a*b = 1');
    await expect(page.locator('#status-banner')).toHaveText('PROVED');
    await expect(page.locator('#lean-button')).toBeHidden();
  });
});

test.describe('api', () => {
  test('malformed requests are 400s, not proofs', async ({ request }) => {
    const bad = await request.post('/api/prove', { data: 'not json at all' });
    expect(bad.status()).toBe(400);
    const noClaim = await request.post('/api/prove', { data: { x: 1 } });
    expect(noClaim.status()).toBe(400);
  });

  test('SDP route metadata matches what actually happened', async ({ request }) => {
    // Four-variable AM-GM needs the numerical route. With the sdp/ virtualenv
    // present this proves via numerical_sdp; without it the trace must say the
    // solver was unavailable. Either way the metadata may not lie.
    const res = await request.post('/api/prove', {
      data: { claim: 'a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d' },
    });
    expect(res.ok()).toBeTruthy();
    const d = await res.json();
    const titles = d.trace.map((s) => s.title);
    expect(titles).toContain('Exact search');
    expect(titles).toContain('Numerical SDP');
    if (d.status === 'PROVED') {
      expect(d.search).toBe('numerical_sdp');
      expect(titles).toContain('Rational reconstruction');
      const last = d.trace[d.trace.length - 1];
      expect(last.title).toBe('Exact check');
      expect(last.trusted).toBe(true);
      expect(last.ok).toBe(true);
    } else {
      expect(d.status).toBe('NO_CERT_FOUND');
      const sdp = d.trace.find((s) => s.title === 'Numerical SDP');
      expect(sdp.ok).toBe(false);
      expect(d.certificate).toBeNull();
    }
  });

  test('a vacuous domain is proved but carries the warning', async ({ request }) => {
    const res = await request.post('/api/prove', {
      data: { claim: 'a^2 >= 1 given a = 2, a = 3' },
    });
    const d = await res.json();
    expect(d.status).toBe('PROVED');
    expect(d.vacuous.length).toBeGreaterThan(0);
    expect(d.vacuous[0]).toContain('vacuously');
  });
});

test.describe('how it works', () => {
  test('the architecture page tells the whole story', async ({ page }) => {
    await page.goto('/how-it-works');
    await expect(page.locator('h1')).toHaveText('How A≥B works');
    // The two zones of the trust boundary.
    await expect(page.locator('.zone-search')).toContainText('numerical SDP');
    await expect(page.locator('.zone-trusted')).toContainText('certificate checker');
    // The code map expands and shows the real modules, checker highlighted.
    await page.click('details.impl summary');
    await expect(page.locator('table.modules tr.trusted-row')).toContainText('Checker');
    await expect(page.locator('table.modules')).toContainText('Proof_result');
  });
});
