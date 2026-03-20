import { test, expect } from "@playwright/test";

/**
 * F8: E2E API tests for skill-groups CRUD endpoints.
 */

const createdGroupIds: string[] = [];

test.afterEach(async ({ request }) => {
  for (const id of createdGroupIds) {
    try {
      await request.delete(`/board/api/skill-groups/${id}`);
    } catch {}
  }
  createdGroupIds.length = 0;
});

test.describe("Skill Groups CRUD", () => {
  test("GET /api/skill-groups returns 200 with skill_groups array", async ({
    request,
  }) => {
    const res = await request.get("/board/api/skill-groups");
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body).toHaveProperty("skill_groups");
    expect(Array.isArray(body.skill_groups)).toBe(true);
  });

  test("POST /api/skill-groups creates a skill group and returns 201", async ({
    request,
  }) => {
    const res = await request.post("/board/api/skill-groups", {
      data: {
        name: "e2e-test-group",
        description: "Group created by Playwright E2E test",
      },
    });
    expect(res.status()).toBe(201);
    const group = await res.json();
    expect(group.id).toBeTruthy();
    expect(group.name).toBe("e2e-test-group");
    createdGroupIds.push(group.id);
  });

  test("GET /api/skill-groups/:id returns the group", async ({ request }) => {
    // Create
    const createRes = await request.post("/board/api/skill-groups", {
      data: { name: "get-test-group" },
    });
    const group = await createRes.json();
    createdGroupIds.push(group.id);

    // Get by ID
    const res = await request.get(`/board/api/skill-groups/${group.id}`);
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.id).toBe(group.id);
    expect(body.name).toBe("get-test-group");
  });

  test("GET /api/skill-groups/:id returns 404 for nonexistent group", async ({
    request,
  }) => {
    const res = await request.get(
      "/board/api/skill-groups/nonexistent-group-id"
    );
    expect(res.status()).toBe(404);
  });

  test("PATCH /api/skill-groups/:id updates the group", async ({ request }) => {
    // Create
    const createRes = await request.post("/board/api/skill-groups", {
      data: { name: "patch-test-group", description: "Original" },
    });
    const group = await createRes.json();
    createdGroupIds.push(group.id);

    // Update
    const patchRes = await request.patch(
      `/board/api/skill-groups/${group.id}`,
      { data: { description: "Updated description" } }
    );
    expect(patchRes.ok()).toBeTruthy();
    const updated = await patchRes.json();
    expect(updated.description).toBe("Updated description");
  });

  test("DELETE /api/skill-groups/:id deletes the group", async ({
    request,
  }) => {
    // Create
    const createRes = await request.post("/board/api/skill-groups", {
      data: { name: "delete-test-group" },
    });
    const group = await createRes.json();

    // Delete
    const deleteRes = await request.delete(
      `/board/api/skill-groups/${group.id}`
    );
    expect(deleteRes.ok()).toBeTruthy();
    const body = await deleteRes.json();
    expect(body.deleted).toBe(true);

    // Verify gone
    const getRes = await request.get(`/board/api/skill-groups/${group.id}`);
    expect(getRes.status()).toBe(404);
  });

  test("created group appears in the list", async ({ request }) => {
    const createRes = await request.post("/board/api/skill-groups", {
      data: { name: "list-check-group" },
    });
    const group = await createRes.json();
    createdGroupIds.push(group.id);

    const listRes = await request.get("/board/api/skill-groups");
    const body = await listRes.json();
    const found = body.skill_groups.find(
      (g: { id: string }) => g.id === group.id
    );
    expect(found).toBeTruthy();
    expect(found.name).toBe("list-check-group");
  });
});
