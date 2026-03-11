import { test, expect } from "@playwright/test";
import { join } from "path";

/**
 * Visual screenshot tests for all Symphony UI screens.
 *
 * Captures full-page screenshots for layout review and regression.
 * Run: cd test/e2e && npx playwright test screenshots.spec.ts
 *
 * Screenshots are saved to test/e2e/screenshots/
 */

const SCREENSHOTS_DIR = join(__dirname, "screenshots");

// Cleanup helper — delete all issues, projects, products to prevent seed pollution (#43)
async function cleanupAll(request: any) {
  // Delete all issues
  try {
    const snapRes = await request.get("/board/api/snapshot");
    const snap = await snapRes.json();
    if (snap.columns) {
      for (const col of snap.columns) {
        for (const issue of col.issues) {
          await request.delete(`/board/api/issues/${issue.id}`);
        }
      }
    }
  } catch {}

  // Delete all projects
  try {
    const projRes = await request.get("/board/api/projects");
    const projData = await projRes.json();
    for (const p of (projData.projects || [])) {
      await request.delete(`/board/api/projects/${p.id}`);
    }
  } catch {}

  // Delete all products
  try {
    const prodRes = await request.get("/board/api/products");
    const prodData = await prodRes.json();
    for (const p of (prodData.products || [])) {
      await request.delete(`/board/api/products/${p.id}`);
    }
  } catch {}
}

// Seed data helpers
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

  // Add features
  const features = ["Authentication", "Rate Limiting", "Monitoring", "CI/CD Integration"];
  for (const name of features) {
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
    await page.waitForTimeout(1000); // Wait for API load
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "01-board-empty.png"),
      fullPage: true,
    });
  });

  test("02 - Kanban board - with issues", async ({ page, request }) => {
    await seedIssues(request);
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "02-board-with-issues.png"),
      fullPage: true,
    });
  });

  test("03 - Kanban board - wide viewport (1920px)", async ({ page, request }) => {
    await seedIssues(request);
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "03-board-wide.png"),
      fullPage: true,
    });
  });

  test("04 - Kanban board - narrow viewport (1024px)", async ({ page, request }) => {
    await seedIssues(request);
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "04-board-narrow.png"),
      fullPage: true,
    });
  });

  test("05 - Kanban board - mobile viewport", async ({ page, request }) => {
    await seedIssues(request);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board");
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "05-board-mobile.png"),
      fullPage: true,
    });
  });

  test("06 - Create issue modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);
    await page.locator("button:has-text('New Issue')").click();
    await page.waitForTimeout(300);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "06-create-issue-modal.png"),
      fullPage: true,
    });
  });

  test("07 - Issue detail modal", async ({ page, request }) => {
    const issues = await seedIssues(request);
    await page.goto("/board");
    await page.waitForTimeout(1500);
    // Click the first card
    const firstCard = page.locator(".card").first();
    if (await firstCard.count() > 0) {
      await firstCard.click();
      await page.waitForTimeout(300);
    }
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "07-issue-detail-modal.png"),
      fullPage: true,
    });
  });

  test("08 - Projects modal", async ({ page, request }) => {
    await seedProject(request);
    await page.goto("/board");
    await page.waitForTimeout(1000);
    await page.locator("button:has-text('Projects')").click();
    await page.waitForTimeout(500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "08-projects-modal.png"),
      fullPage: true,
    });
  });

  test("09 - Template dropdown", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);
    await page.locator("button:has-text('Templates')").click();
    await page.waitForTimeout(300);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "09-template-dropdown.png"),
      fullPage: true,
    });
  });

  test("10 - Board with collapsed columns", async ({ page, request }) => {
    await seedIssues(request);
    await page.goto("/board");
    await page.waitForTimeout(1500);
    // Collapse Done and Cancelled columns by hovering and clicking collapse
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
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "10-board-collapsed-columns.png"),
      fullPage: true,
    });
  });
});

test.describe("Issue Detail Page Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("11 - Issue detail page (standalone)", async ({ page, request }) => {
    const issues = await seedIssues(request);
    if (issues.length > 0) {
      await page.goto(`/board/issues/${issues[0].id}`);
      await page.waitForTimeout(1500);
      await page.screenshot({
        path: join(SCREENSHOTS_DIR, "11-issue-detail-page.png"),
        fullPage: true,
      });
    }
  });
});

test.describe("Settings Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("12 - Settings page", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "12-settings-page.png"),
      fullPage: true,
    });
  });

  test("13 - Settings page - mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board/settings");
    await page.waitForTimeout(500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "13-settings-mobile.png"),
      fullPage: true,
    });
  });
});

test.describe("Task Lineage Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("14 - Task lineage - empty", async ({ page }) => {
    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "14-task-lineage-empty.png"),
      fullPage: true,
    });
  });

  test("15 - Task lineage - with issues", async ({ page, request }) => {
    const issues = await seedIssues(request);
    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "15-task-lineage-with-issues.png"),
      fullPage: true,
    });
  });
});

test.describe("Product Review Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("16 - Product review - empty", async ({ page }) => {
    await page.goto("/board/review");
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "16-review-empty.png"),
      fullPage: true,
    });
  });

  test("17 - Product review - with product selected", async ({ page, request }) => {
    const project = await seedProject(request);
    const product = await seedProduct(request, project.id);
    await page.goto("/board/review");
    await page.waitForTimeout(2000);
    // Wait for select to be populated, then select by value
    const select = page.locator("#product-select");
    const options = select.locator("option");
    // Select the product by value (id)
    try {
      await select.selectOption(product.id, { timeout: 5000 });
    } catch {
      // If product.id doesn't match, try by index (first non-empty option)
      const count = await options.count();
      if (count > 1) {
        await select.selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "17-review-with-product.png"),
      fullPage: true,
    });
  });
});

test.describe("Projects Page Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("20 - Projects page - empty", async ({ page }) => {
    await page.goto("/board/projects");
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "20-projects-empty.png"),
      fullPage: true,
    });
  });

  test("21 - Projects page - with projects", async ({ page, request }) => {
    await seedProject(request);
    await page.goto("/board/projects");
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "21-projects-with-data.png"),
      fullPage: true,
    });
  });

  test("22 - Projects page - new project modal", async ({ page }) => {
    await page.goto("/board/projects");
    await page.waitForTimeout(500);
    await page.click("button:has-text('New Project')");
    await page.waitForTimeout(300);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "22-projects-new-modal.png"),
      fullPage: true,
    });
  });
});

test.describe("Dashboard Screenshots", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("18 - Orchestrator dashboard", async ({ page }) => {
    await page.goto("/");
    await page.waitForTimeout(500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "18-dashboard.png"),
      fullPage: true,
    });
  });

  test("19 - Dashboard - mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/");
    await page.waitForTimeout(500);
    await page.screenshot({
      path: join(SCREENSHOTS_DIR, "19-dashboard-mobile.png"),
      fullPage: true,
    });
  });
});
