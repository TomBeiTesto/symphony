import { test, expect } from "@playwright/test";
import { cleanupAll } from "./helpers";

/**
 * F6: E2E API tests for AI-powered product analysis endpoints.
 * Each endpoint creates a queued issue and returns {issue, message}.
 */

let productId: string;

test.describe("Product AI Analysis Endpoints", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);

    // Seed a product
    const res = await request.post("/board/api/products", {
      data: { name: "AI Test Product", description: "For E2E AI testing" },
    });
    expect(res.status()).toBe(201);
    const product = await res.json();
    productId = product.id;
  });

  test("POST /api/products/:id/analyze-gaps creates an issue and returns 201", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/analyze-gaps`
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty("issue");
    expect(body).toHaveProperty("message");
    expect(body.issue.id).toBeTruthy();
  });

  test("POST /api/products/:id/create-gap-issues creates issues from gaps and returns 201", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/create-gap-issues`,
      {
        data: {
          gaps: [
            {
              feature_name: "Rate Limiting",
              reason: "Not yet implemented",
            },
          ],
        },
      }
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty("created");
    expect(Array.isArray(body.created)).toBe(true);
    expect(body.created.length).toBe(1);
  });

  test("POST /api/products/:id/create-gap-issues with empty gaps returns 201 with empty list", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/create-gap-issues`,
      { data: { gaps: [] } }
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body.created).toEqual([]);
  });

  test("POST /api/products/:id/generate-features creates an issue and returns 201", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/generate-features`,
      { data: { prompt: "Identify all authentication-related features" } }
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty("issue");
    expect(body).toHaveProperty("message");
    expect(body.issue.id).toBeTruthy();
  });

  test("POST /api/products/:id/generate-features without prompt returns 400", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/generate-features`,
      { data: {} }
    );
    expect(res.status()).toBe(400);
  });

  test("POST /api/products/:id/analyze-existing-features creates an issue and returns 201", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/analyze-existing-features`
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty("issue");
    expect(body).toHaveProperty("message");
    expect(body.issue.id).toBeTruthy();
  });

  test("POST /api/products/:id/code-review creates an issue and returns 201", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/code-review`,
      { data: {} }
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty("issue");
    expect(body).toHaveProperty("message");
    expect(body.issue.id).toBeTruthy();
  });

  test("POST /api/products/:id/generate-definition creates an issue and returns 201", async ({
    request,
  }) => {
    const res = await request.post(
      `/board/api/products/${productId}/generate-definition`,
      { data: {} }
    );
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body).toHaveProperty("issue");
    expect(body).toHaveProperty("message");
    expect(body.issue.id).toBeTruthy();
  });

  test("AI endpoints return 404 for nonexistent product", async ({
    request,
  }) => {
    const endpoints = [
      "analyze-gaps",
      "generate-features",
      "analyze-existing-features",
      "code-review",
      "generate-definition",
    ];

    for (const endpoint of endpoints) {
      const res = await request.post(
        `/board/api/products/nonexistent-product-id/${endpoint}`,
        { data: { prompt: "test" } }
      );
      expect(res.status()).toBe(404);
    }
  });
});
