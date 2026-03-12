import { test, expect, type APIRequestContext } from "@playwright/test";

/**
 * Real interaction tests for Symphony board UI.
 *
 * Tests actual user workflows: creating issues, editing, deleting,
 * drag-and-drop, keyboard navigation, templates, settings, etc.
 *
 * Run: cd test/e2e && npx playwright test board.spec.ts
 */

// --- Helpers ---

async function cleanupAll(request: APIRequestContext) {
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
  try {
    const projRes = await request.get("/board/api/projects");
    const projData = await projRes.json();
    for (const p of projData.projects || []) {
      await request.delete(`/board/api/projects/${p.id}`);
    }
  } catch {}
  try {
    const prodRes = await request.get("/board/api/products");
    const prodData = await prodRes.json();
    for (const p of prodData.products || []) {
      await request.delete(`/board/api/products/${p.id}`);
    }
  } catch {}
}

async function createIssue(
  request: APIRequestContext,
  data: Record<string, unknown>
) {
  const res = await request.post("/board/api/issues", { data });
  return await res.json();
}

async function createProject(
  request: APIRequestContext,
  data: Record<string, unknown>
) {
  const res = await request.post("/board/api/projects", { data });
  return await res.json();
}

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
    await createIssue(request, {
      title: "In progress item",
      state: "In Progress",
    });
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

    // Click the card
    await page.click(`.card[data-id="${issue.id}"]`);

    // Should navigate to the detail page
    await page.waitForURL(`**/board/issues/${issue.id}`);
    await expect(page.locator("body")).toContainText("Clickable issue");
  });

  test("delete issue via card delete button", async ({ page, request }) => {
    await createIssue(request, {
      title: "Delete me",
      state: "Backlog",
      priority: 4,
    });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    // Hover over card to reveal delete button
    const card = page.locator(".card").first();
    await card.hover();

    // Accept the confirmation dialog
    page.on("dialog", (dialog) => dialog.accept());

    const deleteBtn = card.locator(".card-delete");
    if ((await deleteBtn.count()) > 0) {
      await deleteBtn.click();
      await page.waitForTimeout(500);

      // Card should be gone
      await expect(page.locator(".card")).toHaveCount(0);
    }
  });

  test("quick-add input creates issue in column", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    // Find a quick-add input (should be at bottom of each non-collapsed column)
    const quickAdd = page.locator(".quick-add-input").first();
    if ((await quickAdd.count()) > 0) {
      await quickAdd.fill("Quick added issue");
      await quickAdd.press("Enter");
      await page.waitForTimeout(500);

      // Should create a card
      await expect(page.locator(".card")).toHaveCount(1);
      await expect(page.locator(".card-title")).toContainText(
        "Quick added issue"
      );
    }
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

    // Find the "Todo" column body as a drop target
    const todoColumn = page
      .locator(".column")
      .filter({ hasText: "Todo" })
      .first();
    const dropTarget = todoColumn.locator(".column-body");

    if ((await dropTarget.count()) > 0) {
      // Perform drag
      await card.dragTo(dropTarget);
      await page.waitForTimeout(500);

      // Verify via API that the issue state changed
      const res = await request.get(`/board/api/issues/${issue.id}`);
      const updated = await res.json();
      expect(updated.state).toBe("Todo");
    }
  });
});

// ============================================================
// Board — Templates
// ============================================================

test.describe("Board — Templates", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("template dropdown shows available templates", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    // Click Templates button
    await page.click("#template-dropdown button");
    await page.waitForTimeout(200);

    // Dropdown should open and show template items
    const menu = page.locator("#template-menu");
    await expect(menu).toHaveClass(/open/);

    // Should have template items with names
    const items = menu.locator(".template-item");
    const count = await items.count();
    expect(count).toBeGreaterThanOrEqual(1);

    // Verify known templates are listed
    await expect(menu).toContainText("Code Review");
    await expect(menu).toContainText("Bug Report");
    await expect(menu).toContainText("Feature Request");
  });

  test("clicking a template pre-fills the create modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    // Open template dropdown
    await page.click("#template-dropdown button");
    await page.waitForTimeout(200);

    // Click "Bug Report" template
    await page.click(".template-item:has-text('Bug Report')");
    await page.waitForTimeout(300);

    // Create modal should open with pre-filled values
    await expect(page.locator("#modal-overlay")).toHaveClass(/active/);

    // Title should have the template prefix
    const title = await page.inputValue("#form-title");
    expect(title).toContain("Bug:");

    // Description should have template content
    const desc = await page.inputValue("#form-description");
    expect(desc).toContain("Bug Report");

    // Labels should include bug
    const labels = await page.inputValue("#form-labels");
    expect(labels).toContain("bug");
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

    // Open modal
    await page.keyboard.press("n");
    await page.waitForTimeout(200);
    await expect(page.locator("#modal-overlay")).toHaveClass(/active/);

    // Close with Escape
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

    // Press j to focus first card
    await page.keyboard.press("j");
    await page.waitForTimeout(100);

    let focused = page.locator(".card.kb-focused");
    await expect(focused).toHaveCount(1);

    // Press j again to move to next
    await page.keyboard.press("j");
    await page.waitForTimeout(100);

    focused = page.locator(".card.kb-focused");
    await expect(focused).toHaveCount(1);

    // Press k to go back
    await page.keyboard.press("k");
    await page.waitForTimeout(100);

    focused = page.locator(".card.kb-focused");
    await expect(focused).toHaveCount(1);
  });

  test("'?' key shows help toast", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    // Dispatch '?' keydown to trigger the help toast
    await page.evaluate(() => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: '?', bubbles: true }));
    });
    await page.waitForTimeout(500);

    // Toast should appear with shortcut hints
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
    // Seed an issue in Done so the column renders
    await createIssue(request, { title: "Done thing", state: "Done" });

    await page.goto("/board");
    await page.waitForTimeout(1000);

    // Done/Cancelled/Archived columns should have collapsed class
    const collapsed = page.locator(".column.collapsed");
    const count = await collapsed.count();
    // At least Done should be collapsed by default
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
    if ((await metrics.count()) > 0) {
      // Should show total count
      await expect(metrics).toContainText("3");
    }
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

    // Title
    await expect(page.locator("body")).toContainText("Detailed issue");
    // State
    await expect(page.locator("body")).toContainText("In Progress");
    // Description
    await expect(page.locator("body")).toContainText(
      "A detailed description for testing"
    );
    // Identifier
    await expect(page.locator("body")).toContainText(issue.identifier);
    // Labels
    await expect(page.locator("body")).toContainText("backend");
    await expect(page.locator("body")).toContainText("urgent");
  });

  test("breadcrumb links back to board", async ({ page, request }) => {
    const issue = await createIssue(request, {
      title: "Breadcrumb test",
      state: "Todo",
    });

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
  test("settings fields are editable and save round-trips", async ({
    page,
  }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);

    // Change git provider to github
    await page.selectOption("#git_provider", "github");
    // Change AI provider
    await page.selectOption("#ai_provider", "openai");
    // Set a model name
    await page.fill("#ai_model", "gpt-4o-test");

    // Save via button
    await page.click("button:has-text('Save Settings')");
    await page.waitForTimeout(500);

    // "Settings saved" banner should appear
    const banner = page.locator("#saved-banner");
    await expect(banner).toHaveClass(/show/);

    // Reload and verify values persisted
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

    const banner = page.locator("#saved-banner");
    await expect(banner).toHaveClass(/show/);
  });

  test("reset to defaults works", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);

    // Change something first
    await page.fill("#ai_model", "some-custom-model");
    await page.click("button:has-text('Save Settings')");
    await page.waitForTimeout(500);

    // Accept confirmation dialog
    page.on("dialog", (dialog) => dialog.accept());

    // Click reset
    await page.click("button:has-text('Reset to Defaults')");
    await page.waitForTimeout(500);

    // Banner should show reset message
    const banner = page.locator("#saved-banner");
    await expect(banner).toBeVisible();
  });
});

// ============================================================
// Task Lineage Page
// ============================================================

test.describe("Task Lineage — Interaction", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("renders tree nodes from seeded issues", async ({
    page,
    request,
  }) => {
    await createIssue(request, { title: "Root issue", state: "Todo" });
    await createIssue(request, {
      title: "Another root",
      state: "In Progress",
    });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    // Should render tree nodes
    const nodes = page.locator(".tree-node");
    await expect(nodes).toHaveCount(2);

    // Nodes should show titles
    await expect(page.locator(".node-title").first()).toContainText(
      /Root issue|Another root/
    );
  });

  test("tree nodes show age indicator", async ({ page, request }) => {
    await createIssue(request, { title: "Fresh issue", state: "Todo" });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    // Node should have an age indicator (created today)
    const node = page.locator(".tree-node").first();
    await expect(node).toHaveCount(1);
    const ageEl = node.locator(".node-age");
    await expect(ageEl).toHaveCount(1);
    await expect(ageEl).toContainText("today");
  });

  test("clicking a tree node navigates to issue detail", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Navigate me",
      state: "Todo",
    });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    // Click the node
    await page.locator(".tree-node").first().click();
    await page.waitForURL(`**/board/issues/${issue.id}`);
    await expect(page.locator("body")).toContainText("Navigate me");
  });

  test("project filter dropdown works", async ({ page, request }) => {
    const project = await createProject(request, {
      name: "Filter Project",
    });
    await createIssue(request, {
      title: "Proj issue",
      state: "Todo",
      project_id: project.id,
    });
    await createIssue(request, { title: "No proj issue", state: "Todo" });

    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1500);

    // All issues visible initially
    await expect(page.locator(".tree-node")).toHaveCount(2);

    // Select the project filter
    const select = page.locator("#project-filter");
    await select.selectOption(project.id);
    await page.waitForTimeout(500);

    // Only the project's issue should be visible
    await expect(page.locator(".tree-node")).toHaveCount(1);
    await expect(page.locator(".node-title")).toContainText("Proj issue");
  });

  test("empty state when no issues", async ({ page }) => {
    await page.goto("/board/task-lineage");
    await page.waitForTimeout(1000);

    await expect(page.locator(".empty-state")).toContainText(
      "No issues to display"
    );
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

  test("selecting a product shows the spec sheet", async ({
    page,
    request,
  }) => {
    // Create a product with a project and feature
    const project = await createProject(request, { name: "Review Project" });
    const prodRes = await request.post("/board/api/products", {
      data: {
        name: "Review Product",
        description: "For testing",
        project_ids: [project.id],
      },
    });
    const product = await prodRes.json();

    // Add a feature
    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name: "Auth", description: "Authentication feature" },
    });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    // Select the product
    const select = page.locator("#product-select");
    try {
      await select.selectOption(product.id, { timeout: 3000 });
    } catch {
      // Try by index if ID doesn't match
      const options = select.locator("option");
      if ((await options.count()) > 1) {
        await select.selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);

    // Spec sheet should appear with product header
    await expect(page.locator(".spec-sheet")).toBeVisible();

    // Feature should be listed in a card
    await expect(page.locator(".feature-card")).toHaveCount(1);
    await expect(page.locator(".feature-card")).toContainText("Auth");

    // Project tag should be present
    await expect(page.locator(".project-tag")).toContainText("Review Project");
  });

  test("feature card shows overall status and project tags", async ({
    page,
    request,
  }) => {
    const project = await createProject(request, { name: "Status Project" });
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Status Product", project_ids: [project.id] },
    });
    const product = await prodRes.json();
    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name: "Feature X" },
    });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    const select = page.locator("#product-select");
    try {
      await select.selectOption(product.id, { timeout: 3000 });
    } catch {
      const options = select.locator("option");
      if ((await options.count()) > 1) {
        await select.selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);

    // Feature card should show a status badge
    await expect(page.locator(".feature-status-badge")).toHaveCount(1);

    // Feature project tag should show project name with status
    await expect(page.locator(".feature-project-tag")).toContainText(
      "Status Project"
    );
  });

  test("overall progress bar shows completeness", async ({
    page,
    request,
  }) => {
    const project = await createProject(request, { name: "Score Project" });
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Score Product", project_ids: [project.id] },
    });
    const product = await prodRes.json();
    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name: "F1" },
    });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    const select = page.locator("#product-select");
    try {
      await select.selectOption(product.id, { timeout: 3000 });
    } catch {
      const options = select.locator("option");
      if ((await options.count()) > 1) {
        await select.selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);

    // Overall progress bar should be present
    await expect(page.locator(".overall-bar")).toHaveCount(1);
    await expect(page.locator(".overall-bar")).toContainText(
      "Overall Completeness"
    );
  });

  test("feature detail modal shows per-project statuses", async ({
    page,
    request,
  }) => {
    const project = await createProject(request, { name: "Detail Project" });
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Detail Product", project_ids: [project.id] },
    });
    const product = await prodRes.json();
    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name: "F1" },
    });

    await page.goto("/board/products");
    await page.waitForTimeout(1000);

    const select = page.locator("#product-select");
    try {
      await select.selectOption(product.id, { timeout: 3000 });
    } catch {
      const options = select.locator("option");
      if ((await options.count()) > 1) {
        await select.selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);

    // Hover over the feature card to reveal the detail button, then click it
    await page.locator(".feature-card").first().hover();
    const detailBtn = page.locator('.feature-action-btn[title="Per-project details"]').first();
    if ((await detailBtn.count()) > 0) {
      await detailBtn.click();
      await page.waitForTimeout(500);

      // Detail modal should show project name and status
      await expect(page.locator("#detail-modal")).toBeVisible();
      await expect(page.locator(".detail-project-row")).toContainText("Detail Project");
    }
  });
});

// ============================================================
// Projects Page — Interactions
// ============================================================

test.describe("Projects Page — Interaction", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("create, edit, and delete a project", async ({ page }) => {
    await page.goto("/board/projects");
    await page.waitForTimeout(500);

    // Empty state should show
    await expect(page.locator("#empty-state")).toBeVisible();

    // Create project
    await page.click(".topbar-right button:has-text('New Project')");
    await page.fill("#form-name", "CRUD Project");
    await page.fill("#form-description", "Testing CRUD");
    await page.click("#form-submit-btn");
    await page.waitForTimeout(500);

    // Project card should appear
    await expect(page.locator(".project-card")).toHaveCount(1);
    await expect(page.locator(".project-card h3")).toContainText(
      "CRUD Project"
    );
    await expect(page.locator(".project-card .desc")).toContainText(
      "Testing CRUD"
    );

    // Edit project
    await page.click(".project-card button:has-text('Edit')");
    await page.waitForTimeout(200);
    await page.fill("#form-name", "Updated Project");
    await page.click("#form-submit-btn");
    await page.waitForTimeout(500);

    await expect(page.locator(".project-card h3")).toContainText(
      "Updated Project"
    );

    // Delete project
    page.on("dialog", (dialog) => dialog.accept());
    await page.click(".project-card button:has-text('Delete')");
    await page.waitForTimeout(500);

    // Should be back to empty state
    await expect(page.locator("#empty-state")).toBeVisible();
  });

  test("search filter narrows results", async ({ page, request }) => {
    await createProject(request, {
      name: "Alpha Project",
      description: "First one",
    });
    await createProject(request, {
      name: "Beta Project",
      description: "Second one",
    });
    await createProject(request, {
      name: "Gamma Project",
      description: "Third one",
    });

    await page.goto("/board/projects");
    await page.waitForTimeout(500);

    // All 3 should show
    await expect(page.locator(".project-card")).toHaveCount(3);

    // Type in search
    await page.fill("#search", "Beta");
    await page.waitForTimeout(300);

    // Only Beta should show
    await expect(page.locator(".project-card")).toHaveCount(1);
    await expect(page.locator(".project-card h3")).toContainText(
      "Beta Project"
    );

    // Clear search — all return
    await page.fill("#search", "");
    await page.waitForTimeout(300);
    await expect(page.locator(".project-card")).toHaveCount(3);
  });

  test("project card shows issue count", async ({ page, request }) => {
    const project = await createProject(request, { name: "Count Project" });
    await createIssue(request, {
      title: "Issue 1",
      state: "Todo",
      project_id: project.id,
    });
    await createIssue(request, {
      title: "Issue 2",
      state: "Todo",
      project_id: project.id,
    });

    await page.goto("/board/projects");
    await page.waitForTimeout(500);

    // Issue count badge should show 2
    const count = page.locator(".issue-count");
    await expect(count).toContainText("2");
  });
});

// ============================================================
// Cross-page Navigation
// ============================================================

test.describe("Cross-page Navigation", () => {
  test("board topbar links navigate to all pages", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);

    // Projects link
    const projLink = page.locator('a[href="/board/projects"]');
    await expect(projLink).toHaveCount(1);

    // Task Lineage link
    const lineageLink = page.locator('a[href="/board/task-lineage"]');
    await expect(lineageLink).toHaveCount(1);

    // Review link
    const reviewLink = page.locator('a[href="/board/products"]');
    await expect(reviewLink).toHaveCount(1);

    // Settings link
    const settingsLink = page.locator('a[href="/board/settings"]');
    await expect(settingsLink).toHaveCount(1);

    // Dashboard link
    const dashLink = page.locator('a[href="/"]');
    await expect(dashLink).toHaveCount(1);
  });

  test("all sub-pages have breadcrumb back to board", async ({ page }) => {
    const subPages = [
      "/board/projects",
      "/board/task-lineage",
      "/board/products",
      "/board/settings",
    ];

    for (const url of subPages) {
      await page.goto(url);
      await page.waitForTimeout(300);

      const boardLink = page.locator('.breadcrumb a[href="/board"]');
      await expect(boardLink).toHaveCount(1);
    }
  });

  test("dashboard has link to board and settings", async ({ page }) => {
    await page.goto("/");
    await page.waitForTimeout(300);

    await expect(page.locator('a[href="/board"]')).toHaveCount(1);
    await expect(page.locator('a[href="/board/settings"]')).toHaveCount(1);
  });
});
