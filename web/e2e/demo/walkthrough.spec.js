// The recorded walkthrough of the A>=B web interface, cut for a README
// visitor: what the tool does inside the first fifteen seconds, then the
// architecture that makes it interesting. Roughly sixty seconds.
//
// Everything on screen is the real application doing real work: the prover
// runs, the SDP example goes through the actual numerical solver, and the
// Lean export is generated live. The only theatrics are the pauses; every
// interaction first waits for the true UI state, then lingers long enough
// for a viewer to read it.
const { test, expect } = require('@playwright/test');

// A beat for the viewer, after the awaited state change. Reading pauses only;
// never used to wait for the application.
const beat = (page, ms) => page.waitForTimeout(ms);

async function typeClaim(page, claim) {
  await page.click('#claim-input');
  await page.fill('#claim-input', '');
  await page.type('#claim-input', claim, { delay: 34 });
  await page.dispatchEvent('#claim-input', 'input');
}

async function proveAndWait(page, status) {
  await page.click('#prove-button');
  await expect(page.locator('#status-banner')).toHaveText(status, { timeout: 60_000 });
}

async function smoothScrollTo(page, selector) {
  await page.$eval(selector, (el) =>
    el.scrollIntoView({ behavior: 'smooth', block: 'center' })
  );
  await page.waitForTimeout(650); // let the smooth scroll finish
}

test('walkthrough', async ({ page }) => {
  // Establish the product: the prover with its typeset example list.
  await page.goto('/');
  await expect(page.locator('.example-row')).toHaveCount(8);
  await beat(page, 1800);

  // Pick the classic three-variable inequality and prove it.
  await page.click('.example-row:has-text("Three variables")');
  await expect(page.locator('#preview')).toBeVisible();
  await beat(page, 900);
  await proveAndWait(page, 'PROVED');
  await smoothScrollTo(page, '#cert-block');
  await beat(page, 4600); // read the typeset certificate

  // How was this proved? The route, with its trust tags.
  await page.click('#trace-toggle');
  await smoothScrollTo(page, '#trace-panel');
  await beat(page, 4600);

  // The architecture page: pipeline, then the trust boundary.
  await page.click('header nav >> text=How it works');
  await expect(page.locator('h1')).toHaveText('How A≥B works');
  await beat(page, 2600);
  await smoothScrollTo(page, '.boundary');
  await beat(page, 5200);

  // A constrained inequality: a^2 + b^2 >= 2 on the curve ab = 1.
  await page.click('header nav >> text=Prover');
  await typeClaim(page, 'a^2 + b^2 >= 2 given a*b = 1');
  await beat(page, 700);
  await proveAndWait(page, 'PROVED');
  await smoothScrollTo(page, '#cert-block');
  await beat(page, 4200); // the certificate uses the hypothesis ab - 1

  // Beyond exact search: the live numerical SDP route, reconstructed exactly.
  await page.click('#examples summary');
  await beat(page, 500);
  await page.click('.example-row:has-text("Four-variable AM-GM")');
  await beat(page, 700);
  await proveAndWait(page, 'PROVED');
  await page.click('#trace-toggle');
  await smoothScrollTo(page, '#trace-panel');
  await beat(page, 5400); // exact search misses; SDP solves; checker accepts

  // Export the machine-checkable Lean theorem.
  await typeClaim(page, 'a^2 + b^2 >= 2*a*b');
  await proveAndWait(page, 'PROVED');
  await page.click('#lean-button');
  await expect(page.locator('#lean-out')).toContainText('theorem');
  await smoothScrollTo(page, '#lean-panel');
  await beat(page, 3800);

  // End on the clean proved-certificate view (the thumbnail frame).
  await page.click('#lean-button');
  await smoothScrollTo(page, '#status-banner');
  await beat(page, 2600);
});
