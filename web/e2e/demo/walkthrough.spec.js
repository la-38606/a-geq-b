// The recorded walkthrough of the A>=B web interface (roughly 80 seconds).
//
// Everything on screen is the real application doing real work: the prover
// runs, the SDP example goes through the actual numerical solver, and the
// Lean export is generated live. The only theatrics are the pauses -- every
// interaction first waits for the true UI state, then lingers long enough
// for a viewer to read it.
//
// Story: prove a classic inequality -> read the certificate -> open the
// proof path (trust tags) -> tour "How A>=B works" -> a constrained proof ->
// the SDP-routed proof with its trace -> Lean export -> end on the proved
// certificate.
const { test, expect } = require('@playwright/test');

// A beat for the viewer, after the awaited state change. Reading pauses only;
// never used to wait for the application.
const beat = (page, ms) => page.waitForTimeout(ms);

async function typeClaim(page, claim) {
  await page.click('#claim-input');
  await page.fill('#claim-input', '');
  await page.type('#claim-input', claim, { delay: 38 });
}

async function proveAndWait(page, status) {
  await page.click('#prove-button');
  await expect(page.locator('#status-banner')).toHaveText(status, { timeout: 60_000 });
}

async function smoothScrollTo(page, selector) {
  await page.$eval(selector, (el) =>
    el.scrollIntoView({ behavior: 'smooth', block: 'center' })
  );
  await page.waitForTimeout(700); // let the smooth scroll finish
}

test('walkthrough', async ({ page }) => {
  // Scene 1 -- the prover page.
  await page.goto('/');
  await expect(page.locator('#examples')).toBeVisible();
  await beat(page, 2600);

  // Scene 2 -- type the classic three-variable inequality and prove it.
  await typeClaim(page, 'a^2 + b^2 + c^2 >= a*b + b*c + c*a');
  await beat(page, 600);
  await proveAndWait(page, 'PROVED');
  await smoothScrollTo(page, '#cert-block');
  await beat(page, 4200); // read the certificate identity

  // Scene 3 -- how was this proved? The route, with its trust tags.
  await page.click('#trace-toggle');
  await smoothScrollTo(page, '#trace-panel');
  await beat(page, 5000);

  // Scene 4 -- the architecture page: pipeline, trust boundary, SDP branch.
  await page.click('header nav >> text=How it works');
  await expect(page.locator('h1')).toHaveText('How A≥B works');
  await beat(page, 2600);
  await smoothScrollTo(page, '.boundary');
  await beat(page, 4600);
  await smoothScrollTo(page, '.flow');
  await beat(page, 3200);
  await smoothScrollTo(page, '.langs');
  await beat(page, 3000); // OCaml exact, Python numerical, Lean formal

  // Scene 5 -- a constrained inequality: a^2 + b^2 >= 2 on the curve ab = 1.
  await page.click('header nav >> text=Prover');
  await beat(page, 800);
  await typeClaim(page, 'a^2 + b^2 >= 2 given a*b = 1');
  await beat(page, 600);
  await proveAndWait(page, 'PROVED');
  await smoothScrollTo(page, '#cert-block');
  await beat(page, 4400); // certificate uses the hypothesis ab - 1

  // Scene 6 -- a target the exact search cannot close: the numerical SDP
  // route, live, with exact reconstruction in the trace.
  await page.click('.chip:has-text("Four-variable AM–GM")');
  await beat(page, 700);
  await proveAndWait(page, 'PROVED');
  await smoothScrollTo(page, '#cert-block');
  await beat(page, 3000);
  await page.click('#trace-toggle');
  await smoothScrollTo(page, '#trace-panel');
  await beat(page, 5600); // exact search misses; SDP solves; checker accepts

  // Scene 7 -- export the machine-checkable Lean theorem.
  await typeClaim(page, 'a^2 + b^2 >= 2*a*b');
  await proveAndWait(page, 'PROVED');
  await page.click('#lean-button');
  await expect(page.locator('#lean-out')).toContainText('theorem');
  await smoothScrollTo(page, '#lean-panel');
  await beat(page, 4400);

  // Scene 8 -- end on the proved certificate.
  await smoothScrollTo(page, '#status-banner');
  await beat(page, 3000);
});
