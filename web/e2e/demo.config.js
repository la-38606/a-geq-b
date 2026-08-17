// Video-recording configuration for the portfolio walkthrough
// (web/e2e/demo/walkthrough.spec.js). Kept separate from playwright.config.js
// so `npx playwright test` stays fast and video-free; run this one via
// scripts/record-demo.sh or `npm run demo`.
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './demo',
  timeout: 300_000,
  retries: 0,
  workers: 1,
  outputDir: './test-results/demo',
  use: {
    baseURL: 'http://127.0.0.1:8978',
    viewport: { width: 1440, height: 900 },
    video: { mode: 'on', size: { width: 1440, height: 900 } },
  },
  webServer: {
    command: 'dune exec a-geq-b-web -- --port 8978',
    cwd: '../..',
    url: 'http://127.0.0.1:8978/',
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
});
