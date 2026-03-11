import { test, expect } from "@playwright/test";

/**
 * End-to-end tests for the Symphony HTTP server.
 *
 * Prerequisites:
 *   1. Symphony server running:  mix run --no-halt  (or via CLI)
 *   2. Environment:  SYMPHONY_BASE_URL=http://127.0.0.1:4545  (default)
 *
 * Run:
 *   cd test/e2e && npm install && npx playwright install && npm test
 */

// --- Orchestrator Dashboard (GET /) ---

test.describe("Dashboard — GET /", () => {
  test("loads the dashboard page", async ({ page }) => {
    const response = await page.goto("/");
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
    expect(response!.headers()["content-type"]).toContain("text/html");
  });

  test("contains the page title", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("h1")).toContainText("Symphony");
  });

  test("displays counts section", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("body")).toContainText("Running");
    await expect(page.locator("body")).toContainText("Retrying");
  });

  test("shows auto-refresh behaviour", async ({ page }) => {
    await page.goto("/");
    const meta = page.locator('meta[http-equiv="refresh"]');
    await expect(meta).toHaveCount(1);
  });

  test("has aggregate totals section", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("body")).toContainText("Input Tokens");
    await expect(page.locator("body")).toContainText("Output Tokens");
    await expect(page.locator("body")).toContainText("Total Tokens");
    await expect(page.locator("body")).toContainText("Runtime");
  });
});

// --- Orchestrator JSON API ---

test.describe("JSON API — /api/v1", () => {
  test("GET /api/v1/state returns JSON snapshot", async ({ request }) => {
    const response = await request.get("/api/v1/state");
    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("application/json");

    const body = await response.json();
    expect(body).toHaveProperty("generated_at");
    expect(body).toHaveProperty("counts");
    expect(body.counts).toHaveProperty("running");
    expect(body.counts).toHaveProperty("retrying");
    expect(body).toHaveProperty("running");
    expect(body).toHaveProperty("retrying");
  });

  test("POST /api/v1/refresh triggers a poll", async ({ request }) => {
    const response = await request.post("/api/v1/refresh");
    expect(response.status()).toBe(202);
    const body = await response.json();
    expect(body).toHaveProperty("queued", true);
  });

  test("GET /api/v1/:identifier returns 404 for unknown issue", async ({
    request,
  }) => {
    const response = await request.get("/api/v1/NONEXISTENT-999");
    expect(response.status()).toBe(404);
  });
});

// --- Board UI (GET /board) ---

test.describe("Board — GET /board", () => {
  test("loads the board page", async ({ page }) => {
    const response = await page.goto("/board");
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
    expect(response!.headers()["content-type"]).toContain("text/html");
  });

  test("contains the board title", async ({ page }) => {
    await page.goto("/board");
    await expect(page.locator("h1")).toContainText("Symphony Board");
  });

  test("has the board container", async ({ page }) => {
    await page.goto("/board");
    await expect(page.locator("main.board")).toHaveCount(1);
  });

  test("has Task Lineage navigation link", async ({ page }) => {
    await page.goto("/board");
    const taskLineageLink = page.locator('a[href="/board/task-lineage"]');
    await expect(taskLineageLink).toHaveCount(1);
  });
});

// --- Board JSON API ---

test.describe("Board API — /board/api", () => {
  test("GET /board/api/snapshot returns board snapshot", async ({
    request,
  }) => {
    const response = await request.get("/board/api/snapshot");
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body).toHaveProperty("columns");
    expect(body).toHaveProperty("states");
    expect(body).toHaveProperty("total_issues");
    expect(body).toHaveProperty("projects");
  });

  test("GET /board/api/states returns state list", async ({ request }) => {
    const response = await request.get("/board/api/states");
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.states).toContain("Backlog");
    expect(body.states).toContain("Review");
    expect(body.states).toContain("Done");
    expect(body.states).toContain("Archived");
  });

  test("POST /board/api/issues creates an issue", async ({ request }) => {
    const response = await request.post("/board/api/issues", {
      data: { title: "E2E Test Issue", state: "Backlog" },
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.title).toBe("E2E Test Issue");
    expect(body.state).toBe("Backlog");
    expect(body.identifier).toBeTruthy();
  });

  test("GET /board/api/issues lists issues", async ({ request }) => {
    const response = await request.get("/board/api/issues");
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Array.isArray(body.issues)).toBe(true);
  });

  test("GET /board/api/templates returns templates", async ({ request }) => {
    const response = await request.get("/board/api/templates");
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Array.isArray(body.templates)).toBe(true);
    const ids = body.templates.map((t: { id: string }) => t.id);
    expect(ids).toContain("code-review");
    expect(ids).toContain("bug-report");
  });
});

// --- Task Lineage (GET /board/task-lineage) ---

test.describe("Task Lineage — GET /board/task-lineage", () => {
  test("loads the task lineage page", async ({ page }) => {
    const response = await page.goto("/board/task-lineage");
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
  });

  test("contains the task lineage title", async ({ page }) => {
    await page.goto("/board/task-lineage");
    await expect(page.locator("h1")).toContainText("Task Lineage");
  });

  test("has viewport and canvas elements", async ({ page }) => {
    await page.goto("/board/task-lineage");
    await expect(page.locator("#viewport")).toHaveCount(1);
    await expect(page.locator("#canvas")).toHaveCount(1);
    await expect(page.locator("#connectors")).toHaveCount(1);
  });

  test("has project filter dropdown", async ({ page }) => {
    await page.goto("/board/task-lineage");
    await expect(page.locator("#project-filter")).toHaveCount(1);
  });

  test("has back link to board", async ({ page }) => {
    await page.goto("/board/task-lineage");
    const backLink = page.locator('a[href="/board"]');
    await expect(backLink).toHaveCount(1);
  });
});

// --- Settings (GET /board/settings) ---

test.describe("Settings — GET /board/settings", () => {
  test("loads the settings page", async ({ page }) => {
    const response = await page.goto("/board/settings");
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
  });

  test("contains settings sections", async ({ page }) => {
    await page.goto("/board/settings");
    await expect(page.locator("body")).toContainText("Git Provider");
    await expect(page.locator("body")).toContainText("AI Provider");
    await expect(page.locator("body")).toContainText("Issue Tracker");
  });
});

// --- Product Review (GET /board/review) ---

test.describe("Product Review — GET /board/review", () => {
  test("loads the product review page", async ({ page }) => {
    const response = await page.goto("/board/review");
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
    expect(response!.headers()["content-type"]).toContain("text/html");
  });

  test("contains the product review title", async ({ page }) => {
    await page.goto("/board/review");
    await expect(page.locator("h1")).toContainText("Product Review");
  });

  test("has product selector", async ({ page }) => {
    await page.goto("/board/review");
    await expect(page.locator("#product-select")).toHaveCount(1);
  });

  test("has back link to board", async ({ page }) => {
    await page.goto("/board/review");
    const backLink = page.locator('a[href="/board"]');
    await expect(backLink).toHaveCount(1);
  });
});

// --- Product Review API ---

test.describe("Product Review API — /board/api/products", () => {
  test("GET /board/api/products returns products list", async ({
    request,
  }) => {
    const response = await request.get("/board/api/products");
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body).toHaveProperty("products");
    expect(Array.isArray(body.products)).toBe(true);
  });

  test("POST /board/api/products creates a product", async ({ request }) => {
    const response = await request.post("/board/api/products", {
      data: { name: "E2E Test Product", description: "Test product" },
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.name).toBe("E2E Test Product");
    expect(body.id).toBeTruthy();
    expect(body.features).toEqual([]);
  });

  test("full product CRUD lifecycle", async ({ request }) => {
    // Create
    const createRes = await request.post("/board/api/products", {
      data: { name: "Lifecycle Product" },
    });
    expect(createRes.status()).toBe(201);
    const product = await createRes.json();

    // Read
    const getRes = await request.get(`/board/api/products/${product.id}`);
    expect(getRes.status()).toBe(200);

    // Update
    const updateRes = await request.patch(`/board/api/products/${product.id}`, {
      data: { name: "Updated Product" },
    });
    expect(updateRes.status()).toBe(200);
    const updated = await updateRes.json();
    expect(updated.name).toBe("Updated Product");

    // Delete
    const deleteRes = await request.delete(
      `/board/api/products/${product.id}`
    );
    expect(deleteRes.status()).toBe(200);

    // Verify gone
    const gone = await request.get(`/board/api/products/${product.id}`);
    expect(gone.status()).toBe(404);
  });

  test("product feature management", async ({ request }) => {
    // Create a product
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Feature Test Product" },
    });
    const product = await prodRes.json();

    // Add feature
    const featureRes = await request.post(
      `/board/api/products/${product.id}/features`,
      { data: { name: "Auth Feature", description: "API key authentication" } }
    );
    expect(featureRes.status()).toBe(201);
    const withFeature = await featureRes.json();
    expect(withFeature.features).toHaveLength(1);
    expect(withFeature.features[0].name).toBe("Auth Feature");

    // Delete feature
    const featureId = withFeature.features[0].id;
    const delRes = await request.delete(
      `/board/api/products/${product.id}/features/${featureId}`
    );
    expect(delRes.status()).toBe(200);
    const withoutFeature = await delRes.json();
    expect(withoutFeature.features).toHaveLength(0);

    // Cleanup
    await request.delete(`/board/api/products/${product.id}`);
  });
});

// --- Projects Page (GET /board/projects) ---

test.describe("Projects — GET /board/projects", () => {
  test("loads the projects page", async ({ page }) => {
    const response = await page.goto("/board/projects");
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
    expect(response!.headers()["content-type"]).toContain("text/html");
  });

  test("contains the projects title", async ({ page }) => {
    await page.goto("/board/projects");
    await expect(page.locator("h1")).toContainText("Projects");
  });

  test("has search input and action buttons", async ({ page }) => {
    await page.goto("/board/projects");
    await expect(page.locator("#search")).toHaveCount(1);
    // "New Project" button in the topbar
    await expect(page.locator(".topbar-right button:has-text('New Project')")).toHaveCount(1);
    // "Import" button in the topbar
    await expect(page.locator(".topbar-right button:has-text('Import')")).toHaveCount(1);
  });

  test("has back link to board", async ({ page }) => {
    await page.goto("/board/projects");
    const backLink = page.locator('a[href="/board"]');
    await expect(backLink).toHaveCount(1);
  });

  test("shows empty state or project grid", async ({ page }) => {
    await page.goto("/board/projects");
    await page.waitForTimeout(500);
    // Either the empty state or the project grid should be present
    const emptyVisible = await page.locator("#empty-state").isVisible();
    const gridHasCards = await page.locator(".project-card").count();
    expect(emptyVisible || gridHasCards > 0).toBe(true);
  });

  test("can create a project via modal", async ({ page, request }) => {
    // Clean up first
    const projRes = await request.get("/board/api/projects");
    const projData = await projRes.json();
    for (const p of (projData.projects || [])) {
      await request.delete(`/board/api/projects/${p.id}`);
    }

    await page.goto("/board/projects");
    await page.waitForTimeout(500);
    await page.click(".topbar-right button:has-text('New Project')");
    await page.fill("#form-name", "E2E Test Project");
    await page.fill("#form-description", "Created by Playwright");
    await page.click("#form-submit-btn");
    await page.waitForTimeout(500);
    // Project should appear in the grid
    await expect(page.locator(".project-card")).toHaveCount(1);
    await expect(page.locator(".project-card h3")).toContainText("E2E Test Project");

    // Cleanup
    const projRes2 = await request.get("/board/api/projects");
    const projData2 = await projRes2.json();
    for (const p of (projData2.projects || [])) {
      await request.delete(`/board/api/projects/${p.id}`);
    }
  });
});

// --- Accessibility & Responsiveness ---

test.describe("Accessibility & Responsiveness", () => {
  test("dashboard has a valid document structure", async ({ page }) => {
    await page.goto("/");
    const h1Count = await page.locator("h1").count();
    expect(h1Count).toBeGreaterThanOrEqual(1);
  });

  test("dashboard is responsive on mobile viewport", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/");
    const h1 = page.locator("h1");
    await expect(h1).toBeVisible();
  });

  test("board is responsive on mobile viewport", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board");
    const h1 = page.locator("h1");
    await expect(h1).toBeVisible();
  });
});
