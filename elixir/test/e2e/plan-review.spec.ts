import { test, expect, type APIRequestContext } from "@playwright/test";
import { cleanupAll, cleanupSkills, createIssue, goToIssuesTab } from "./helpers";

/**
 * End-to-end tests for Plan Review, Follow-ups, Skills CRUD,
 * and error scenarios in the Symphony board UI.
 *
 * Run: cd test/e2e && npx playwright test plan-review.spec.ts
 */

// ============================================================
// Plan Review Flow
// ============================================================

test.describe("Plan Review Flow", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("plan status badge shows Planning on the board when plan_status is planning", async ({
    page,
    request,
  }) => {
    await createIssue(request, {
      title: "Plan test issue",
      state: "In Progress",
      plan_status: "planning",
    });

    await goToIssuesTab(page);
    await page.waitForSelector(".issue-card");

    // The Hub card should contain a plan badge with "Planning" text
    const planBadge = page.locator(".plan-badge.planning");
    await expect(planBadge).toHaveCount(1);
    await expect(planBadge).toContainText("Planning");
  });

  test("plan status badge shows Plan Ready on the board when plan_status is plan_review", async ({
    page,
    request,
  }) => {
    await createIssue(request, {
      title: "Review plan issue",
      state: "In Progress",
      plan_status: "plan_review",
      plan_text: "## Step 1\nDo the thing\n## Step 2\nVerify the thing",
    });

    await goToIssuesTab(page);
    await page.waitForSelector(".issue-card");

    const planBadge = page.locator(".plan-badge.review");
    await expect(planBadge).toHaveCount(1);
    await expect(planBadge).toContainText("Plan Ready");
  });

  test("plan review panel is visible on issue detail when plan_status is plan_review", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Detail plan review",
      state: "In Progress",
      plan_status: "plan_review",
      plan_text: "## Implementation Plan\n1. First step\n2. Second step",
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForSelector("#plan-review-panel", { state: "visible" });

    // Panel should be visible with plan content
    const planPanel = page.locator("#plan-review-panel");
    await expect(planPanel).toBeVisible();

    // Plan text should be rendered
    const planText = page.locator("#plan-text");
    await expect(planText).toContainText("Implementation Plan");

    // Plan status badge should show "Awaiting Review"
    const badge = page.locator("#plan-status-badge");
    await expect(badge).toContainText("Awaiting Review");

    // Action buttons should be visible
    const approveBtn = page.locator(
      'button:has-text("Approve & Execute")'
    );
    await expect(approveBtn).toBeVisible();

    const rejectBtn = page.locator(
      'button:has-text("Reject with Feedback")'
    );
    await expect(rejectBtn).toBeVisible();
  });

  test("plan review panel shows planning state when plan_status is planning", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Planning in progress",
      state: "In Progress",
      plan_status: "planning",
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForSelector("#plan-review-panel", { state: "visible" });

    // Badge should say "Planning"
    const badge = page.locator("#plan-status-badge");
    await expect(badge).toContainText("Planning");

    // Should show the "producing a plan" message
    const planText = page.locator("#plan-text");
    await expect(planText).toContainText("Agent is producing a plan");

    // Action buttons should NOT be visible while still planning
    const actions = page.locator("#plan-actions");
    await expect(actions).not.toBeVisible();
  });

  test("reject plan button shows feedback form", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Reject plan test",
      state: "In Progress",
      plan_status: "plan_review",
      plan_text: "## Bad Plan\nThis needs changes",
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForSelector("#plan-review-panel", { state: "visible" });

    // Click "Reject with Feedback"
    await page.click('button:has-text("Reject with Feedback")');

    // The reject form should appear
    const rejectForm = page.locator("#plan-reject-form");
    await expect(rejectForm).toBeVisible();

    // Should have a textarea for feedback
    const feedbackInput = page.locator("#plan-feedback");
    await expect(feedbackInput).toBeVisible();

    // Should have the "Re-plan with Feedback" button
    const replanBtn = page.locator(
      'button:has-text("Re-plan with Feedback")'
    );
    await expect(replanBtn).toBeVisible();

    // Cancel button should hide the form
    await page.click(
      '#plan-reject-form button:has-text("Cancel")'
    );
    await expect(rejectForm).not.toBeVisible();
  });

  test("approved plan shows approved badge without action buttons", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Approved plan issue",
      state: "In Progress",
      plan_status: "approved",
      plan_text: "## Approved Plan\nExecuting now",
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForSelector("#plan-review-panel", { state: "visible" });

    // Badge should say "Approved"
    const badge = page.locator("#plan-status-badge");
    await expect(badge).toContainText("Approved");
    await expect(badge).toHaveClass(/approved/);

    // Action buttons should be hidden for approved plans
    const actions = page.locator("#plan-actions");
    await expect(actions).not.toBeVisible();
  });

  test("plan status badge shows Executing on board when plan_status is approved", async ({
    page,
    request,
  }) => {
    await createIssue(request, {
      title: "Executing issue",
      state: "In Progress",
      plan_status: "approved",
      plan_text: "The plan",
    });

    await goToIssuesTab(page);
    await page.waitForSelector(".issue-card");

    const planBadge = page.locator(".plan-badge.approved");
    await expect(planBadge).toHaveCount(1);
    await expect(planBadge).toContainText("Executing");
  });
});

// ============================================================
// Follow-ups Flow
// ============================================================

test.describe("Follow-ups Flow", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("follow-up accept returns 404 for nonexistent issue", async ({
    request,
  }) => {
    const res = await request.post(
      "/board/api/issues/nonexistent-issue-id/follow-ups/some-fu/accept",
      {}
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("follow-up reject returns 404 for nonexistent issue", async ({
    request,
  }) => {
    const res = await request.post(
      "/board/api/issues/nonexistent-issue-id/follow-ups/some-fu/reject",
      {}
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("follow-ups panel is hidden when no follow-ups exist", async ({
    page,
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "No follow-ups issue",
      state: "In Progress",
    });

    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForSelector(".topbar");

    // The follow-ups panel should remain hidden
    const panel = page.locator("#followups-panel");
    await expect(panel).not.toBeVisible();
  });
});

// ============================================================
// Skills CRUD
// ============================================================

test.describe("Skills CRUD", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
    await cleanupSkills(request);
  });

  test("skills page loads and displays skills grid", async ({ page }) => {
    await page.goto("/board/skills");
    await page.waitForSelector(".skills-grid");

    // Page title should show "Skills Library"
    await expect(page.locator(".page-title")).toContainText("Skills Library");

    // Should have the sidebar with category filters
    await expect(page.locator("#category-filters")).toBeVisible();

    // Should have a search input
    await expect(page.locator("#search-input")).toBeVisible();

    // Should have the "New Skill" button
    await expect(
      page.locator('button:has-text("+ New Skill")')
    ).toBeVisible();
  });

  test("create a custom skill via API and verify it appears", async ({
    page,
    request,
  }) => {
    // Create a skill via API
    const createRes = await request.post("/board/api/skills", {
      data: {
        name: "e2e-test-skill",
        category: "custom",
        description: "A skill created by Playwright",
        content: "Always verify your work before marking complete.",
        tags: "e2e, test",
      },
    });
    expect(createRes.status()).toBe(201);
    const skill = await createRes.json();
    expect(skill.name).toBe("e2e-test-skill");
    expect(skill.id).toBeTruthy();

    // Verify it appears on the skills page
    await page.goto("/board/skills");
    await page.waitForSelector(".skill-card");

    await expect(page.locator(".skills-grid")).toContainText("e2e-test-skill");
  });

  test("edit custom skill content via API", async ({ request }) => {
    // Create
    const createRes = await request.post("/board/api/skills", {
      data: {
        name: "editable-skill",
        category: "custom",
        description: "Original description",
        content: "Original content",
      },
    });
    const skill = await createRes.json();

    // Edit
    const editRes = await request.patch(`/board/api/skills/${skill.id}`, {
      data: {
        description: "Updated description",
        content: "Updated content with new instructions",
      },
    });
    expect(editRes.status()).toBe(200);
    const updated = await editRes.json();
    expect(updated.description).toBe("Updated description");
    expect(updated.content).toBe("Updated content with new instructions");
  });

  test("duplicate a built-in skill via API", async ({ request }) => {
    // List skills to find a built-in one
    const listRes = await request.get("/board/api/skills");
    const listData = await listRes.json();
    const builtIn = listData.skills.find(
      (s: { built_in: boolean }) => s.built_in
    );

    if (!builtIn) {
      test.skip();
      return;
    }

    // Duplicate it
    const dupRes = await request.post(
      `/board/api/skills/${builtIn.id}/duplicate`
    );
    expect(dupRes.status()).toBe(201);
    const duplicated = await dupRes.json();
    expect(duplicated.id).not.toBe(builtIn.id);
    expect(duplicated.built_in).toBeFalsy();

    // Clean up the duplicate
    await request.delete(`/board/api/skills/${duplicated.id}`);
  });

  test("delete a custom skill via API", async ({ request }) => {
    // Create a skill
    const createRes = await request.post("/board/api/skills", {
      data: {
        name: "deletable-skill",
        category: "custom",
        content: "Will be deleted",
      },
    });
    const skill = await createRes.json();

    // Delete it
    const deleteRes = await request.delete(`/board/api/skills/${skill.id}`);
    expect(deleteRes.status()).toBe(200);
    const deleteBody = await deleteRes.json();
    expect(deleteBody.deleted).toBe(true);

    // Verify it's gone
    const getRes = await request.get(`/board/api/skills/${skill.id}`);
    expect(getRes.status()).toBe(404);
  });

  test("built-in skills cannot be deleted", async ({ request }) => {
    // List skills to find a built-in one
    const listRes = await request.get("/board/api/skills");
    const listData = await listRes.json();
    const builtIn = listData.skills.find(
      (s: { built_in: boolean }) => s.built_in
    );

    if (!builtIn) {
      test.skip();
      return;
    }

    // Try to delete it
    const deleteRes = await request.delete(`/board/api/skills/${builtIn.id}`);
    expect(deleteRes.status()).toBe(400);
    const body = await deleteRes.json();
    expect(body.error).toBe("cannot_delete_built_in");
    expect(body.message).toContain("Built-in skills cannot be deleted");
  });

  test("skills page UI: create skill via modal", async ({ page }) => {
    await page.goto("/board/skills");
    await page.waitForSelector(".skills-grid");

    // Open create modal
    await page.click('button:has-text("+ New Skill")');
    await page.waitForSelector("#skill-modal.active");

    // Modal should be visible with correct title
    await expect(page.locator("#skill-modal-title")).toContainText("New Skill");

    // Fill in the form
    await page.fill("#skill-name", "ui-created-skill");
    await page.selectOption("#skill-category", "workflow");
    await page.fill("#skill-tags", "e2e, ui-test");
    await page.fill("#skill-description", "Created via UI test");
    await page.fill("#skill-content", "Always run tests before committing.");

    // Save
    await page.click("#skill-save-btn");
    await page.waitForTimeout(500);

    // Skill should appear in the grid
    await expect(page.locator(".skills-grid")).toContainText("ui-created-skill");
  });

  test("skills page UI: search filters skills", async ({
    page,
    request,
  }) => {
    // Create two custom skills
    await request.post("/board/api/skills", {
      data: { name: "alpha-search-skill", category: "custom", content: "A" },
    });
    await request.post("/board/api/skills", {
      data: { name: "beta-search-skill", category: "custom", content: "B" },
    });

    await page.goto("/board/skills");
    await page.waitForSelector(".skill-card");

    // Search for "alpha"
    await page.fill("#search-input", "alpha");
    await page.waitForTimeout(300);

    // Only alpha skill should be visible
    await expect(page.locator(".skills-grid")).toContainText(
      "alpha-search-skill"
    );
    await expect(page.locator(".skills-grid")).not.toContainText(
      "beta-search-skill"
    );

    // Clear search
    await page.fill("#search-input", "");
    await page.waitForTimeout(300);

    // Both should be visible again
    await expect(page.locator(".skills-grid")).toContainText(
      "alpha-search-skill"
    );
    await expect(page.locator(".skills-grid")).toContainText(
      "beta-search-skill"
    );
  });

  test("skills page UI: category filter works", async ({ page, request }) => {
    // Create a custom skill in the "debugging" category
    await request.post("/board/api/skills", {
      data: {
        name: "debug-filter-skill",
        category: "debugging",
        content: "Debug instructions",
      },
    });

    await page.goto("/board/skills");
    await page.waitForSelector(".skill-card");

    // Filter by "debugging" category
    await page.click('.filter-item[data-category="debugging"]');
    await page.waitForTimeout(300);

    // The debugging skill should be visible
    await expect(page.locator(".skills-grid")).toContainText(
      "debug-filter-skill"
    );

    // Filter by "workflow" category — our debug skill should not be visible
    await page.click('.filter-item[data-category="workflow"]');
    await page.waitForTimeout(300);

    await expect(page.locator(".skills-grid")).not.toContainText(
      "debug-filter-skill"
    );

    // Go back to "all" to reset
    await page.click('.filter-item[data-category="all"]');
    await page.waitForTimeout(300);

    await expect(page.locator(".skills-grid")).toContainText(
      "debug-filter-skill"
    );
  });

  test("skills page UI: built-in skill card has no delete button", async ({
    page,
  }) => {
    await page.goto("/board/skills", { waitUntil: "networkidle" });
    await page.waitForSelector(".skill-card", { timeout: 10_000 });

    // Find a built-in skill card (should have the built-in badge)
    const builtInCard = page
      .locator(".skill-card")
      .filter({ hasText: "built-in" })
      .first();

    if ((await builtInCard.count()) > 0) {
      // Hover to reveal action buttons
      await builtInCard.hover();
      await page.waitForTimeout(200);

      // Should have a duplicate button but NOT a delete button
      const duplicateBtn = builtInCard.locator(
        'button[title="Duplicate"]'
      );
      await expect(duplicateBtn).toHaveCount(1);

      const deleteBtn = builtInCard.locator('button[title="Delete"]');
      await expect(deleteBtn).toHaveCount(0);
    }
  });
});

// ============================================================
// Error Scenarios
// ============================================================

test.describe("Error Scenarios", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("creating an issue without a title defaults to Untitled", async ({
    request,
  }) => {
    const res = await request.post("/board/api/issues", {
      data: { state: "Backlog" },
    });
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body.title).toBe("Untitled");
  });

  test("editing a non-existent issue returns 404", async ({ request }) => {
    const res = await request.patch(
      "/board/api/issues/nonexistent-id-12345",
      {
        data: { title: "Should not work" },
      }
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("deleting a non-existent issue returns 404", async ({ request }) => {
    const res = await request.delete(
      "/board/api/issues/nonexistent-id-12345"
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("navigating to a non-existent issue detail shows 404", async ({
    page,
  }) => {
    const response = await page.goto("/board/issues/nonexistent-id-999");
    expect(response!.status()).toBe(404);
    await expect(page.locator("body")).toContainText("Issue not found");
  });

  test("moving an issue without a state returns 400", async ({
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Move error test",
      state: "Backlog",
    });

    const res = await request.patch(
      `/board/api/issues/${issue.id}/move`,
      {
        data: {},
      }
    );
    expect(res.status()).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("state is required");
  });

  test("moving a non-existent issue returns 404", async ({ request }) => {
    const res = await request.patch(
      "/board/api/issues/nonexistent-id/move",
      {
        data: { state: "Done" },
      }
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("getting a non-existent skill returns 404", async ({ request }) => {
    const res = await request.get("/board/api/skills/nonexistent-skill");
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("duplicating a non-existent skill returns 404", async ({
    request,
  }) => {
    const res = await request.post(
      "/board/api/skills/nonexistent-skill/duplicate"
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });

  test("activity endpoint returns 404 for non-existent issue", async ({
    request,
  }) => {
    const res = await request.get(
      "/board/api/issues/nonexistent-id/activity"
    );
    expect(res.status()).toBe(404);
    const body = await res.json();
    expect(body.error).toBe("not_found");
  });
});
