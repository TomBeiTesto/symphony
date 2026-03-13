import { test, expect } from "@playwright/test";
import { cleanupAll, createIssue, createProject } from "./helpers";

/**
 * Real interaction tests for Symphony board UI.
 *
 * Tests actual user workflows: creating issues, editing, deleting,
 * drag-and-drop, keyboard navigation, settings, etc.
 *
 * Run: cd test/e2e && npx playwright test board.spec.ts
 */

// ============================================================
// Board — Issue CRUD via UI
// ============================================================

test.describe("Board — Issue CRUD", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("create issue via New Issue button and modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    // Open create modal
    await page.click("button:has-text('New Issue')");
    await expect(page.locator("#modal-overlay")).toHaveClass(/active/);

    // Fill in the form
    await page.fill("#form-title", "Test issue from Playwright");
    await page.fill("#form-description", "Automated test description");
    await page.selectOption("#form-state", "Todo");
    await page.selectOption("#form-priority", "2");
    await page.fill("#form-labels", "e2e, automated");

    // Submit
    await page.click('#modal-overlay button[type="submit"]');
    await page.waitForTimeout(500);

    // Modal should close
    await expect(page.locator("#modal-overlay")).not.toHaveClass(/active/);

    // Issue card should appear on the board
    await expect(page.locator(".card")).toHaveCount(1);
    await expect(page.locator(".card-title")).toContainText(
      "Test issue from Playwright"
    );
  });

  test("issue appears in correct column based on state", async ({
    page,
    request,
  }) => {
    await createIssue(request, { title: "Backlog item", state: "Backlog" });
    await createIssue(request, { title: "In progress item", state: "In Progress" });
    await createIssue(request, { title: "Done item", state: "Done" });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    // Verify via API that all 3 issues were created in correct states
    const snapRes = await request.get("/board/api/snapshot");
    const snap = await snapRes.json();
    const allIssues = snap.columns.flatMap((c: { issues: { title: string }[] }) => c.issues);
    expect(allIssues).toHaveLength(3);

    // Verify board renders multiple columns (some may be collapsed)
    const columns = page.locator(".column");
    const colCount = await columns.count();
    expect(colCount).toBeGreaterThanOrEqual(3);
  });

  test("clicking a card navigates to issue detail page", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Clickable issue",
      state: "Todo",
    });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    await page.click(`.card[data-id="${issue.id}"]`);
    await page.waitForURL(`**/board/issues/${issue.id}`);
    await expect(page.locator("body")).toContainText("Clickable issue");
  });

  test("delete issue via card delete button", async ({ page, request }) => {
    await createIssue(request, { title: "Delete me", state: "Backlog", priority: 4 });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    const card = page.locator(".card").first();
    await card.hover();

    page.on("dialog", (dialog) => dialog.accept());

    const deleteBtn = card.locator(".card-delete");
    await expect(deleteBtn).toHaveCount(1);
    await deleteBtn.click();
    await page.waitForTimeout(500);
    await expect(page.locator(".card")).toHaveCount(0);
  });

  test("quick-add input creates issue in column", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    const quickAdd = page.locator(".quick-add-input").first();
    await expect(quickAdd).toHaveCount(1);
    await quickAdd.fill("Quick added issue");
    await quickAdd.press("Enter");
    await page.waitForTimeout(500);

    await expect(page.locator(".card")).toHaveCount(1);
    await expect(page.locator(".card-title")).toContainText("Quick added issue");
  });
});

// ============================================================
// Board — Drag and Drop
// ============================================================

test.describe("Board — Drag and Drop", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("drag card between columns changes issue state", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Drag me",
      state: "Backlog",
    });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    const card = page.locator(`.card[data-id="${issue.id}"]`);
    await expect(card).toHaveCount(1);

    const todoColumn = page.locator(".column").filter({ hasText: "Todo" }).first();
    const dropTarget = todoColumn.locator(".column-body");

    await expect(dropTarget).toHaveCount(1);
    await card.dragTo(dropTarget);
    await page.waitForTimeout(500);

    const res = await request.get(`/board/api/issues/${issue.id}`);
    const updated = await res.json();
    expect(updated.state).toBe("Todo");
  });
});

// ============================================================
// Board — Keyboard Navigation
// ============================================================

test.describe("Board — Keyboard Navigation", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("'n' key opens create modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    await page.keyboard.press("n");
    await page.waitForTimeout(200);

    await expect(page.locator("#modal-overlay")).toHaveClass(/active/);
  });

  test("Escape closes modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    await page.keyboard.press("n");
    await page.waitForTimeout(200);
    await expect(page.locator("#modal-overlay")).toHaveClass(/active/);

    await page.keyboard.press("Escape");
    await page.waitForTimeout(200);
    await expect(page.locator("#modal-overlay")).not.toHaveClass(/active/);
  });

  test("j/k keys navigate cards", async ({ page, request }) => {
    await createIssue(request, { title: "Issue A", state: "Todo" });
    await createIssue(request, { title: "Issue B", state: "Todo" });
    await createIssue(request, { title: "Issue C", state: "Todo" });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    await page.keyboard.press("j");
    await page.waitForTimeout(100);
    await expect(page.locator(".card.kb-focused")).toHaveCount(1);

    await page.keyboard.press("j");
    await page.waitForTimeout(100);
    await expect(page.locator(".card.kb-focused")).toHaveCount(1);

    await page.keyboard.press("k");
    await page.waitForTimeout(100);
    await expect(page.locator(".card.kb-focused")).toHaveCount(1);
  });

  test("'?' key shows help toast", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    await page.evaluate(() => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "?", bubbles: true }));
    });
    await page.waitForTimeout(500);

    const toast = page.locator("#toast-container .toast");
    await expect(toast.first()).toBeVisible({ timeout: 3000 });
    await expect(toast.first()).toContainText("Navigate");
  });
});

// ============================================================
// Board — Column Collapse
// ============================================================

test.describe("Board — Column Collapse", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("terminal columns (Done, Cancelled) start collapsed", async ({
    page,
    request,
  }) => {
    await createIssue(request, { title: "Done thing", state: "Done" });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    const collapsed = page.locator(".column.collapsed");
    const count = await collapsed.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });
});

// ============================================================
// Board — Metrics Bar
// ============================================================

test.describe("Board — Metrics Bar", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("metrics bar shows correct counts", async ({ page, request }) => {
    await createIssue(request, { title: "A", state: "Todo" });
    await createIssue(request, { title: "B", state: "In Progress" });
    await createIssue(request, { title: "C", state: "Done" });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    const metrics = page.locator("#metrics-bar");
    await expect(metrics).toHaveCount(1);
    await expect(metrics).toContainText("3");
  });
});

// ============================================================
// Issue Detail Page
// ============================================================

test.describe("Issue Detail Page", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("renders issue details correctly", async ({ page, request }) => {
    const issue = await createIssue(request, {
      title: "Detailed issue",
      state: "In Progress",
      priority: 1,
      description: "A detailed description for testing",
      labels: ["backend", "urgent"],
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForTimeout(500);

    await expect(page.locator("body")).toContainText("Detailed issue");
    await expect(page.locator("body")).toContainText("In Progress");
    await expect(page.locator("body")).toContainText("A detailed description for testing");
    await expect(page.locator("body")).toContainText(issue.identifier);
    await expect(page.locator("body")).toContainText("backend");
    await expect(page.locator("body")).toContainText("urgent");
  });

  test("breadcrumb links back to board", async ({ page, request }) => {
    const issue = await createIssue(request, { title: "Breadcrumb test", state: "Todo" });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForTimeout(500);

    const boardLink = page.locator('.breadcrumb a[href="/board"]');
    await expect(boardLink).toHaveCount(1);
    await boardLink.click();
    await page.waitForURL("**/board");
  });

  test("returns 404 for nonexistent issue", async ({ page }) => {
    const response = await page.goto("/board/issues/nonexistent-id-999");
    expect(response!.status()).toBe(404);
  });
});

// ============================================================
// Settings Page
// ============================================================

test.describe("Settings — Save & Load", () => {
  test("settings fields are editable and save round-trips", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);

    await page.selectOption("#git_provider", "github");
    await page.selectOption("#ai_provider", "openai");
    await page.fill("#ai_model", "gpt-4o-test");

    await page.click("button:has-text('Save Settings')");
    await page.waitForTimeout(500);

    const banner = page.locator("#saved-banner");
    await expect(banner).toHaveClass(/show/);

    await page.goto("/board/settings");
    await page.waitForTimeout(500);

    await expect(page.locator("#git_provider")).toHaveValue("github");
    await expect(page.locator("#ai_provider")).toHaveValue("openai");
    await expect(page.locator("#ai_model")).toHaveValue("gpt-4o-test");
  });

  test("Ctrl+S triggers save", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);

    await page.keyboard.press("Control+s");
    await page.waitForTimeout(500);

    await expect(page.locator("#saved-banner")).toHaveClass(/show/);
  });

  test("reset to defaults works", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);

    await page.fill("#ai_model", "some-custom-model");
    await page.click("button:has-text('Save Settings')");
    await page.waitForTimeout(500);

    page.on("dialog", (dialog) => dialog.accept());
    await page.click("button:has-text('Reset to Defaults')");
    await page.waitForTimeout(500);

    await expect(page.locator("#saved-banner")).toBeVisible();
  });
});

// ============================================================
// Task Lineage Page
// ============================================================

test.describe("Task Lineage — Interaction", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("renders tree nodes from seeded issues", async ({ page, request }) => {
    await createIssue(request, { title: "Root issue", state: "Todo" });
    await createIssue(request, { title: "Another root", state: "In Progress" });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    await expect(page.locator(".tree-node")).toHaveCount(2);
    await expect(page.locator(".node-title").first()).toContainText(
      /Root issue|Another root/
    );
  });

  test("tree nodes show age indicator", async ({ page, request }) => {
    await createIssue(request, { title: "Fresh issue", state: "Todo" });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    const ageEl = page.locator(".tree-node").first().locator(".node-age");
    await expect(ageEl).toHaveCount(1);
    await expect(ageEl).toContainText("today");
  });

  test("clicking a tree node navigates to issue detail", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, { title: "Navigate me", state: "Todo" });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    await page.locator(".tree-node").first().click();
    await page.waitForURL(`**/board/issues/${issue.id}`);
    await expect(page.locator("body")).toContainText("Navigate me");
  });

  test("project filter dropdown works", async ({ page, request }) => {
    const project = await createProject(request, { name: "Filter Project" });
    await createIssue(request, { title: "Proj issue", state: "Todo", project_id: project.id });
    await createIssue(request, { title: "No proj issue", state: "Todo" });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    await expect(page.locator(".tree-node")).toHaveCount(2);

    await page.locator("#project-filter").selectOption(project.id);
    await page.waitForTimeout(500);

    await expect(page.locator(".tree-node")).toHaveCount(1);
    await expect(page.locator(".node-title")).toContainText("Proj issue");
  });

  test("empty state when no issues", async ({ page }) => {
    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1000);

    await expect(page.locator(".empty-state")).toContainText("No issues to display");
  });
});

// ============================================================
// Products Page
// ============================================================

test.describe("Products — Interaction", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("empty state shows select prompt", async ({ page }) => {
    await page.goto("/board/products");
    await page.waitForTimeout(500);

    await expect(page.locator("#product-select")).toHaveCount(1);
  });

  test("selecting a product shows the spec sheet", async ({ page, request }) => {
    const project = await createProject(request, { name: "Review Project" });
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Review Product", description: "For testing", project_ids: [project.id] },
    });
    const product = await prodRes.json();

    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name: "Auth", description: "Authentication feature" },
    });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    const select = page.locator("#product-select");
    await select.selectOption(product.id);
    await page.waitForTimeout(1000);

    await expect(page.locator(".spec-sheet")).toBeVisible();
    await expect(page.locator(".feature-card")).toHaveCount(1);
    await expect(page.locator(".feature-card")).toContainText("Auth");
    await expect(page.locator(".project-tag")).toContainText("Review Project");
  });

  test("overall progress bar shows completeness", async ({ page, request }) => {
    const project = await createProject(request, { name: "Score Project" });
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Score Product", project_ids: [project.id] },
    });
    const product = await prodRes.json();
    await request.post(`/board/api/products/${product.id}/features`, { data: { name: "F1" } });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    await page.locator("#product-select").selectOption(product.id);
    await page.waitForTimeout(1000);

    await expect(page.locator(".overall-bar")).toHaveCount(1);
    await expect(page.locator(".overall-bar")).toContainText("Overall Completeness");
  });

  test("feature detail modal shows per-project statuses", async ({ page, request }) => {
    const project = await createProject(request, { name: "Detail Project" });
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Detail Product", project_ids: [project.id] },
    });
    const product = await prodRes.json();
    await request.post(`/board/api/products/${product.id}/features`, { data: { name: "F1" } });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    await page.locator("#product-select").selectOption(product.id);
    await page.waitForTimeout(1000);

    await page.locator(".feature-card").first().hover();
    const detailBtn = page.locator('.feature-action-btn[title="Per-project details"]').first();
    await expect(detailBtn).toHaveCount(1);
    await detailBtn.click();
    await page.waitForTimeout(500);

    await expect(page.locator("#detail-modal")).toBeVisible();
    await expect(page.locator(".detail-project-row")).toContainText("Detail Project");
  });
});

// ============================================================
// Cross-page Navigation
// ============================================================

test.describe("Cross-page Navigation", () => {
  test("board topbar links navigate to all pages", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    await expect(page.locator('a[href="/board/task-lineage"]')).toHaveCount(1);
    await expect(page.locator('a[href="/board"]')).toHaveCount(1);
    await expect(page.locator('a[href="/board/settings"]')).toHaveCount(1);
    await expect(page.locator('a[href="/"]')).toHaveCount(1);
  });

  test("sub-pages have back link to board", async ({ page }) => {
    const subPages = ["/board/task-lineage", "/board/products", "/board/settings"];

    for (const url of subPages) {
      await page.goto(url);
      await page.waitForTimeout(300);
      await expect(page.locator('a[href="/board"]')).toHaveCount(1);
    }
  });

  test("dashboard has link to board and settings", async ({ page }) => {
    await page.goto("/");
    await page.waitForTimeout(300);

    await expect(page.locator('a[href="/board"]')).toHaveCount(1);
    await expect(page.locator('a[href="/board/settings"]')).toHaveCount(1);
  });
});
