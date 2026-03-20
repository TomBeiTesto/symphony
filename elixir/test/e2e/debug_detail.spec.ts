import { test, expect } from "@playwright/test";
import { cleanupAll, createIssue } from "./helpers";

test.describe("Issue Detail — Plan Review Panel", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("plan-review panel is visible for issue with plan_status=planning", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Plan debug",
      state: "In Progress",
      plan_status: "planning",
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForSelector("#plan-review-panel", { state: "visible" });

    const panel = page.locator("#plan-review-panel");
    await expect(panel).toBeVisible();

    // Panel should have non-trivial HTML content
    const panelHtml = await panel.innerHTML();
    expect(panelHtml.length).toBeGreaterThan(0);
  });
});
