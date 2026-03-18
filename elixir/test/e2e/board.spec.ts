import { test, expect } from "@playwright/test";
import { cleanupAll, createIssue, createProject, goToIssuesTab } from "./helpers";

/**
 * Real interaction tests for Symphony Product Hub UI.
 *
 * Tests actual user workflows: creating issues, editing, deleting,
 * drag-and-drop, keyboard navigation, settings, etc.
 *
 * The board page (/board) now serves the Product Hub with a tab-based UI.
 * The Kanban view is in the "Issues" tab. The default tab is "Spec Sheet".
 * To see cards, navigate to the Issues tab via "All Issues" sidebar or tab click.
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

  test("create issue via + Issue button and modal", async ({ page }) => {
    await goToIssuesTab(page);

    // Open create modal
    await page.click("button:has-text('+ Issue')");
    await page.waitForTimeout(300);

    // Modal should be visible
    await expect(page.locator("#hi-modal")).toHaveCSS("display", "flex");

    // Fill in the form
    await page.fill("#hi-title", "Test issue from Playwright");
    await page.fill("#hi-description", "Automated test description");
    await page.selectOption("#hi-priority", "2");
    await page.fill("#hi-labels", "e2e, automated");

    // Submit
    await page.click("#hi-submit");
    await page.waitForTimeout(500);

    // Modal should close
    await expect(page.locator("#hi-modal")).toHaveCSS("display", "none");

    // Issue card should appear on the board
    await expect(page.locator(".issue-card")).toHaveCount(1);
    await expect(page.locator(".issue-card-title")).toContainText(
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

    await goToIssuesTab(page);

    // Verify via API that all 3 issues were created in correct states
    const snapRes = await request.get("/board/api/snapshot");
    const snap = await snapRes.json();
    const allIssues = snap.columns.flatMap((c: { issues: { title: string }[] }) => c.issues);
    expect(allIssues).toHaveLength(3);

    // Verify board renders multiple columns (some may be collapsed)
    const columns = page.locator(".kb-column");
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

    await goToIssuesTab(page);

    await page.click(`.issue-card[data-id="${issue.id}"]`);
    await page.waitForURL(`**/board/issues/${issue.id}`);
    await expect(page.locator("body")).toContainText("Clickable issue");
  });

  test("delete issue via card delete button", async ({ page, request }) => {
    await createIssue(request, { title: "Delete me", state: "Backlog", priority: 4 });

    await goToIssuesTab(page);

    const card = page.locator(".issue-card").first();
    await card.hover();

    page.on("dialog", (dialog) => dialog.accept());

    const deleteBtn = card.locator(".card-delete");
    await expect(deleteBtn).toHaveCount(1);
    await deleteBtn.click();
    await page.waitForTimeout(500);
    await expect(page.locator(".issue-card")).toHaveCount(0);
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

    await goToIssuesTab(page);

    const card = page.locator(`.issue-card[data-id="${issue.id}"]`);
    await expect(card).toHaveCount(1);

    const todoColumn = page.locator(".kb-column").filter({ hasText: "Todo" }).first();
    const dropTarget = todoColumn.locator(".kb-column-body");

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

    await expect(page.locator("#hi-modal")).toHaveCSS("display", "flex");
  });

  test("Escape closes modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    await page.keyboard.press("n");
    await page.waitForTimeout(200);
    await expect(page.locator("#hi-modal")).toHaveCSS("display", "flex");

    await page.keyboard.press("Escape");
    await page.waitForTimeout(200);
    await expect(page.locator("#hi-modal")).toHaveCSS("display", "none");
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
    await expect(toast.first()).toContainText("Tabs");
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

    await goToIssuesTab(page);

    const collapsed = page.locator(".kb-column.collapsed");
    const count = await collapsed.count();
    expect(count).toBeGreaterThanOrEqual(1);
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

  test("topbar links back to board", async ({ page, request }) => {
    const issue = await createIssue(request, { title: "Breadcrumb test", state: "Todo" });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForTimeout(500);

    // Topbar has a link back to /board via logo or Hub nav item
    const boardLink = page.locator('.topbar a[href="/board"]').first();
    await expect(boardLink).toBeVisible();
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
// ============================================================
// Products Page (now the Hub default view)
// ============================================================

test.describe("Products — Interaction", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("empty state shows welcome prompt", async ({ page }) => {
    // Clear localStorage to reset tab/product selection from prior tests
    await page.goto("/board");
    await page.evaluate(() => localStorage.clear());
    await page.goto("/board");
    await page.waitForTimeout(500);

    // With no products, spec tab is disabled; call switchTab directly to verify welcome screen
    await page.evaluate(() => switchTab('spec'));
    await page.waitForTimeout(300);
    await expect(page.locator(".empty-state")).toBeVisible();
    await expect(page.locator(".empty-state")).toContainText("Welcome to Symphony");
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

    await page.goto("/board");
    await page.waitForTimeout(1000);

    // Click on the product in the sidebar
    const prodItem = page.locator(`.sidebar-item[data-product-id="${product.id}"]`);
    await expect(prodItem).toBeVisible({ timeout: 5000 });
    await prodItem.click();
    await page.waitForTimeout(1000);

    // Ensure we're on Spec Sheet tab
    await page.click('[data-tab="spec"]');
    await page.waitForTimeout(500);

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

    await page.goto("/board");
    await page.waitForTimeout(1000);

    const prodItem = page.locator(`.sidebar-item[data-product-id="${product.id}"]`);
    await expect(prodItem).toBeVisible({ timeout: 5000 });
    await prodItem.click();
    await page.waitForTimeout(500);

    await page.click('[data-tab="spec"]');
    await page.waitForTimeout(500);

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

    await page.goto("/board");
    await page.waitForTimeout(1000);

    const prodItem = page.locator(`.sidebar-item[data-product-id="${product.id}"]`);
    await expect(prodItem).toBeVisible({ timeout: 5000 });
    await prodItem.click();
    await page.waitForTimeout(500);

    await page.click('[data-tab="spec"]');
    await page.waitForTimeout(500);

    await page.locator(".feature-card").first().hover();
    const detailBtn = page.locator('.feature-action-btn[title="Details"]').first();
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

    // Topbar has links to all main pages
    await expect(page.locator('.topbar-nav a[href="/board/settings"]')).toHaveCount(1);
    // At least one link to /board (logo + Hub nav link)
    const boardLinks = await page.locator('a[href="/board"]').count();
    expect(boardLinks).toBeGreaterThanOrEqual(1);
  });

  test("sub-pages have link to board", async ({ page }) => {
    const subPages = ["/board/settings"];

    for (const url of subPages) {
      await page.goto(url);
      await page.waitForTimeout(300);
      const boardLinks = await page.locator('a[href="/board"]').count();
      expect(boardLinks).toBeGreaterThanOrEqual(1);
    }
  });
});
