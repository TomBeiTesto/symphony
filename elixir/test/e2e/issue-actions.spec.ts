import { test, expect } from "@playwright/test";
import { cleanupAll, createIssue } from "./helpers";

/**
 * F9: E2E API tests for issue rerun and report endpoints.
 */

test.describe("Issue Rerun Endpoint", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("POST /api/issues/:id/rerun returns ok or 422/503 for valid issue", async ({
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Rerun test issue",
      state: "Done",
    });

    const res = await request.post(`/board/api/issues/${issue.id}/rerun`, {
      data: {},
    });

    // Rerun may succeed (200) or fail if orchestrator unavailable (503/422)
    // Either is acceptable — we just verify the endpoint responds with JSON
    expect([200, 422, 503]).toContain(res.status());
    const body = await res.json();
    expect(typeof body).toBe("object");
  });

  test("POST /api/issues/:id/rerun with hint is accepted", async ({
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Rerun hint test",
      state: "Done",
    });

    const res = await request.post(`/board/api/issues/${issue.id}/rerun`, {
      data: { hint: "Focus on the authentication module" },
    });

    // Endpoint must respond (not 404 or 500)
    expect([200, 422, 503]).toContain(res.status());
    const body = await res.json();
    expect(typeof body).toBe("object");
  });

  test("POST /api/issues/nonexistent/rerun returns non-200", async ({
    request,
  }) => {
    const res = await request.post(
      "/board/api/issues/nonexistent-issue-xyz/rerun",
      { data: {} }
    );
    // Should not be 200
    expect(res.status()).not.toBe(200);
  });
});

test.describe("Issue Report Endpoint", () => {
  test.beforeEach(async ({ request }) => {
    await cleanupAll(request);
  });

  test("GET /api/issues/:id/report returns 404 for issue with no report", async ({
    request,
  }) => {
    const issue = await createIssue(request, {
      title: "Report test issue",
      state: "Done",
    });

    const res = await request.get(`/board/api/issues/${issue.id}/report`);
    // Issue has no workspace/report — expect 404
    expect(res.status()).toBe(404);
  });

  test("GET /api/issues/nonexistent/report returns 404", async ({
    request,
  }) => {
    const res = await request.get(
      "/board/api/issues/nonexistent-issue-xyz/report"
    );
    expect(res.status()).toBe(404);
  });
});
