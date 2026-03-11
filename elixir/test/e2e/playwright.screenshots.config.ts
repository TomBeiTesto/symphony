import { defineConfig } from "@playwright/test";

/**
 * Config for screenshot capture only.
 * Run: npm run test:screenshots
 */
export default defineConfig({
  testDir: ".",
  testMatch: "screenshots.spec.ts",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  workers: 1,
  reporter: "list",
  use: {
    baseURL: process.env.SYMPHONY_BASE_URL ?? "http://127.0.0.1:4545",
    screenshot: "off",
  },
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
});
