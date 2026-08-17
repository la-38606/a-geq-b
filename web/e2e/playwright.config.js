// Browser tests for the A>=B web interface. Playwright builds and starts the
// real server (no mocks -- the prover behind the page is the OCaml library),
// so `npx playwright test` from this directory is all it takes.
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests',
  timeout: 30_000,
  // The prover is deterministic; a failure is a bug, not flake.
  retries: 0,
  use: {
    baseURL: 'http://127.0.0.1:8977',
    viewport: { width: 1280, height: 900 },
  },
  webServer: {
    command: 'dune exec a-geq-b-web -- --port 8977',
    cwd: '../..',
    url: 'http://127.0.0.1:8977/',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
});
