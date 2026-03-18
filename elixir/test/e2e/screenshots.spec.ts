import { test, expect } from "@playwright/test";
import { join } from "path";
import { cleanupAll } from "./helpers";

/**
 * Visual screenshot tests for all Symphony UI screens.
 *
 * Captures full-page screenshots for layout review and regression.
 * Run: cd test/e2e && npx playwright test screenshots.spec.ts
 *
 * Screenshots are saved to test/e2e/screenshots/
 */

const SCREENSHOTS_DIR = join(__dirname, "screenshots");

async function seedIssues(request: any) {
  const issues = [
    { title: "Set up CI/CD pipeline", state: "Done", priority: 1, labels: ["infra", "devops"] },
    { title: "Implement user authentication", state: "In Progress", priority: 2, labels: ["backend", "security"] },
    { title: "Design landing page mockups", state: "In Progress", priority: 3, labels: ["design", "frontend"] },
    { title: "Write API documentation", state: "Todo", priority: 2, labels: ["docs"] },
    { title: "Fix memory leak in worker pool", state: "Todo", priority: 1, labels: ["bug", "backend"] },
    { title: "Add rate limiting to endpoints", state: "Backlog", priority: 3, labels: ["backend"] },
    { title: "Migrate database to PostgreSQL", state: "Backlog", priority: 2, labels: ["infra", "database"] },
    { title: "Set up monitoring dashboard", state: "Backlog", priority: 4, labels: ["infra"] },
    { title: "Refactor config module", state: "Review", priority: 3, labels: ["refactor"] },
    { title: "Update deprecated dependencies", state: "Cancelled", priority: 4, labels: ["chore"] },
  ];

  const created: any[] = [];
  for (const issue of issues) {
    const res = await request.post("/board/api/issues", { data: issue });
    created.push(await res.json());
  }
  return created;
}

async function seedProject(request: any) {
  const res = await request.post("/board/api/projects", {
    data: {
      name: "Symphony Core",
      description: "Main orchestration engine for AI agent dispatch",
      repo_url: "https://github.com/org/symphony-core",
      path: "/home/user/code/symphony-core",
    },
  });
  return await res.json();
}

async function seedProduct(request: any, projectId: string) {
  const res = await request.post("/board/api/products", {
    data: {
      name: "Symphony Platform",
      description: "End-to-end AI orchestration platform",
      project_ids: [projectId],
    },
  });
  const product = await res.json();

  for (const name of ["Authentication", "Rate Limiting", "Monitoring", "CI/CD Integration"]) {
    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name, description: `${name} across all projects` },
    });
  }
  return product;
}

// --- Screenshot Tests ---

test.describe("Board Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("01 - Kanban board - empty state", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(1000);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "01-board-empty.png"), fullPage: true });
  });

  test("02 - Kanban board - with issues", async ({ page, request }) => {
    await seedIssues(request);
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "02-board-with-issues.png"), fullPage: true });
  });

  test("03 - Kanban board - wide viewport (1920px)", async ({ page, request }) => {
    await seedIssues(request);
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "03-board-wide.png"), fullPage: true });
  });

  test("04 - Kanban board - narrow viewport (1024px)", async ({ page, request }) => {
    await seedIssues(request);
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "04-board-narrow.png"), fullPage: true });
  });

  test("05 - Kanban board - mobile viewport", async ({ page, request }) => {
    await seedIssues(request);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "05-board-mobile.png"), fullPage: true });
  });

  test("06 - Create issue modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);
    await page.locator("button:has-text('New Issue')").click();
    await page.waitForTimeout(300);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "06-create-issue-modal.png"), fullPage: true });
  });

  test("07 - Issue detail page", async ({ page, request }) => {
    const issues = await seedIssues(request);
    await page.goto(`/board/issues/${issues[0].id}`);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "07-issue-detail-page.png"), fullPage: true });
  });

  test("08 - Board with collapsed columns", async ({ page, request }) => {
    await seedIssues(request);
    await page.goto("/board");
    await page.waitForTimeout(1500);
    const columns = page.locator(".column");
    const count = await columns.count();
    for (let i = count - 1; i >= count - 3 && i >= 0; i--) {
      const header = columns.nth(i).locator(".column-header");
      await header.hover();
      const collapseBtn = columns.nth(i).locator(".btn-collapse");
      if (await collapseBtn.count() > 0) {
        await collapseBtn.click();
        await page.waitForTimeout(200);
      }
    }
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "08-board-collapsed-columns.png"), fullPage: true });
  });
});

test.describe("Settings Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("10 - Settings page", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "10-settings-page.png"), fullPage: true });
  });

  test("11 - Settings page - mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board/settings");
    await page.waitForTimeout(500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "11-settings-mobile.png"), fullPage: true });
  });
});

test.describe("Product Hub Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("14 - Product hub - empty", async ({ page }) => {
    await page.goto("/board/products");
    await page.waitForTimeout(1000);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "14-hub-empty.png"), fullPage: true });
  });

  test("15 - Product hub - with product selected", async ({ page, request }) => {
    const project = await seedProject(request);
    const product = await seedProduct(request, project.id);
    await page.goto("/board/products");
    await page.waitForTimeout(2000);
    try {
      await page.locator("#product-select").selectOption(product.id, { timeout: 5000 });
    } catch {
      const options = page.locator("#product-select option");
      if (await options.count() > 1) {
        await page.locator("#product-select").selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1500);
    await page.screenshot({ path: join(SCREENSHOTS_DIR, "15-hub-with-product.png"), fullPage: true });
  });
});

