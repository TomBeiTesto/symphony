import { test, expect } from "@playwright/test";

/**
 * E2E tests for the /board/guide page (GuideUI).
 */

test.describe("Guide Page", () => {
  test("GET /board/guide returns 200", async ({ page }) => {
    const response = await page.goto("/board/guide");
    expect(response!.status()).toBe(200);
  });

  test("guide page renders guide-specific content", async ({ page }) => {
    await page.goto("/board/guide");

    // Title includes "Symphony Guide"
    await expect(page).toHaveTitle(/Symphony Guide/i);

    // Guide sidebar is present
    await expect(page.locator("#guide-sidebar")).toBeVisible();

    // Search input is present
    await expect(page.locator("#guide-search")).toBeVisible();

    // Canvas is present
    await expect(page.locator("#guide-canvas")).toBeVisible();
  });

  test("guide page has topbar with back-to-board navigation", async ({
    page,
  }) => {
    await page.goto("/board/guide");

    // The topbar should be visible
    await expect(page.locator(".topbar")).toBeVisible();

    // There should be a link back to /board
    const boardLink = page.locator('a[href="/board"], a[href*="/board"]').first();
    await expect(boardLink).toBeVisible();
  });
});
