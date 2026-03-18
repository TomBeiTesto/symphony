import { test, expect } from "@playwright/test";

/**
 * End-to-end smoke tests for the Symphony HTTP server.
 * Covers page loads, API contracts, and basic structure.
 *
 * Run: cd test/e2e && npx playwright test dashboard.spec.ts
 */

// --- Orchestrator Dashboard (GET /) ---

test.describe("Dashboard — GET /", () => {
  test("loads and shows Symphony title", async ({ page }) => {
    const response = await page.goto("/");
    expect(response!.status()).toBe(200);
    expect(response!.headers()["content-type"]).toContain("text/html");
    await expect(page.locator("h1")).toContainText("Symphony");
  });

  test("displays running/retrying counts and token totals", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("body")).toContainText("Running");
    await expect(page.locator("body")).toContainText("Retrying");
    await expect(page.locator("body")).toContainText("Input Tokens");
    await expect(page.locator("body")).toContainText("Output Tokens");
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
    expect(body.counts).toHaveProperty("running");
    expect(body.counts).toHaveProperty("retrying");
    expect(body).toHaveProperty("running");
    expect(body).toHaveProperty("retrying");
  });

  test("POST /api/v1/refresh triggers a poll", async ({ request }) => {
    const response = await request.post("/api/v1/refresh");
    expect(response.status()).toBe(202);
    expect(await response.json()).toHaveProperty("queued", true);
  });

  test("GET /api/v1/:identifier returns 404 for unknown issue", async ({ request }) => {
    const response = await request.get("/api/v1/NONEXISTENT-999");
    expect(response.status()).toBe(404);
  });
});

// --- Product API ---

test.describe("Product API — /board/api/products", () => {
  test("GET /board/api/products returns products list", async ({ request }) => {
    const response = await request.get("/board/api/products");
    expect(response.status()).toBe(200);
    expect(Array.isArray((await response.json()).products)).toBe(true);
  });

  test("full product CRUD lifecycle", async ({ request }) => {
    const createRes = await request.post("/board/api/products", {
      data: { name: "Lifecycle Product" },
    });
    expect(createRes.status()).toBe(201);
    const product = await createRes.json();

    expect((await request.get(`/board/api/products/${product.id}`)).status()).toBe(200);

    const updateRes = await request.patch(`/board/api/products/${product.id}`, {
      data: { name: "Updated Product" },
    });
    expect(updateRes.status()).toBe(200);
    expect((await updateRes.json()).name).toBe("Updated Product");

    expect((await request.delete(`/board/api/products/${product.id}`)).status()).toBe(200);
    expect((await request.get(`/board/api/products/${product.id}`)).status()).toBe(404);
  });

  test("product feature add and delete", async ({ request }) => {
    const prodRes = await request.post("/board/api/products", {
      data: { name: "Feature Test Product" },
    });
    const product = await prodRes.json();

    const featureRes = await request.post(`/board/api/products/${product.id}/features`, {
      data: { name: "Auth Feature", description: "API key authentication" },
    });
    expect(featureRes.status()).toBe(201);
    const withFeature = await featureRes.json();
    expect(withFeature.features).toHaveLength(1);
    expect(withFeature.features[0].name).toBe("Auth Feature");

    const featureId = withFeature.features[0].id;
    const delRes = await request.delete(`/board/api/products/${product.id}/features/${featureId}`);
    expect(delRes.status()).toBe(200);
    expect((await delRes.json()).features).toHaveLength(0);

    await request.delete(`/board/api/products/${product.id}`);
  });
});
