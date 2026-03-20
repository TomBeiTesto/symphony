import { test, expect } from "@playwright/test";

/**
 * F7: E2E API tests for backup and restore endpoints.
 */

test.describe("Backup and Restore API", () => {
  test("GET /api/backups returns 200 with backups array", async ({
    request,
  }) => {
    const res = await request.get("/board/api/backups");
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body).toHaveProperty("backups");
    expect(Array.isArray(body.backups)).toBe(true);
  });

  test("GET /api/backups response contains backup objects with expected fields", async ({
    request,
  }) => {
    const res = await request.get("/board/api/backups");
    expect(res.ok()).toBeTruthy();
    const body = await res.json();

    // If any backups exist, verify their shape
    for (const backup of body.backups) {
      expect(typeof backup.filename).toBe("string");
    }
  });

  test("POST /api/backups/restore returns 400 for missing filename", async ({
    request,
  }) => {
    const res = await request.post("/board/api/backups/restore", {
      data: {},
    });
    // Should fail because filename is missing/nil
    expect(res.status()).toBeGreaterThanOrEqual(400);
    expect(res.status()).toBeLessThan(500);
  });

  test("POST /api/backups/restore returns 400 for nonexistent backup", async ({
    request,
  }) => {
    const res = await request.post("/board/api/backups/restore", {
      data: { filename: "nonexistent_backup_xyz.json" },
    });
    expect(res.status()).toBe(400);
    const body = await res.json();
    expect(body).toHaveProperty("error");
  });
});
