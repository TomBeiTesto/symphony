import { test, expect, type APIRequestContext } from "@playwright/test";
import { createIssue } from "./helpers";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";

// Create a temp vault directory for testing
let testVault: string;
const createdIssueIds: string[] = [];

test.beforeAll(async () => {
  testVault = path.join(
    os.tmpdir(),
    `kb_e2e_test_${Date.now()}_${Math.floor(Math.random() * 100000)}`
  );
  fs.mkdirSync(testVault, { recursive: true });
});

test.afterAll(async () => {
  try {
    fs.rmSync(testVault, { recursive: true, force: true });
  } catch {}
});

test.afterEach(async ({ request }) => {
  for (const id of createdIssueIds) {
    try {
      await request.delete(`/board/api/issues/${id}`);
    } catch {}
  }
  createdIssueIds.length = 0;
});

async function configureKB(request: APIRequestContext, vaultPath: string) {
  await request.patch("/board/api/settings", {
    data: {
      kb_type: "local",
      kb_vault_path: vaultPath,
      kb_subfolder: "symphony",
    },
  });
}

// ---------------------------------------------------------------------------
// Vault API Tests
// ---------------------------------------------------------------------------

test.describe("Knowledge Base — Vault API", () => {
  test("POST /api/vault/test returns ok for valid directory", async ({
    request,
  }) => {
    const res = await request.post("/board/api/vault/test", {
      data: { vault_path: testVault, kb_type: "local" },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.message).toContain("Connected");
  });

  test("POST /api/vault/test returns error for missing directory", async ({
    request,
  }) => {
    const res = await request.post("/board/api/vault/test", {
      data: { vault_path: "/nonexistent/path/xyz", kb_type: "local" },
    });
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.message).toContain("does not exist");
  });

  test("POST /api/vault/send writes issue description as note", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    const issue = await createIssue(request, {
      title: "KB Test Issue",
      state: "Done",
      description: "This is the issue body for KB testing.",
    });
    createdIssueIds.push(issue.id);

    const res = await request.post("/board/api/vault/send", {
      data: { issue_id: issue.id },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.notes_written.length).toBeGreaterThan(0);

    // Verify file on disk
    const notePath = body.notes_written[0];
    expect(fs.existsSync(notePath)).toBe(true);
    const content = fs.readFileSync(notePath, "utf-8");
    expect(content).toContain("KB Test Issue");
    expect(content).toContain("---"); // frontmatter
  });

  test("POST /api/vault/send returns 404 for nonexistent issue", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    const res = await request.post("/board/api/vault/send", {
      data: { issue_id: "nonexistent-id-xyz" },
    });
    expect(res.status()).toBe(404);
  });

  test("GET /api/vault/search returns matching notes", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    // Write a test note directly
    const dir = path.join(testVault, "symphony", "search-test");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, "searchable-note.md"),
      "---\ntags:\n  - test\n---\n# Searchable\nUnique keyword: bananaphone42.\n"
    );

    const res = await request.get(
      "/board/api/vault/search?q=bananaphone42"
    );
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.results.length).toBeGreaterThan(0);
    expect(body.results[0].title).toBe("searchable-note");
  });

  test("GET /api/vault/search returns empty for no match", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    const res = await request.get(
      "/board/api/vault/search?q=xyzzy_absolutely_nothing"
    );
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.results).toEqual([]);
  });

  test("GET /api/vault/note returns note content", async ({ request }) => {
    await configureKB(request, testVault);

    const dir = path.join(testVault, "symphony");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, "read-test.md"),
      "---\nsource: SYM-99\n---\n# Read Test\nBody content here.\n"
    );

    const res = await request.get(
      "/board/api/vault/note?path=symphony/read-test.md"
    );
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.frontmatter.source).toBe("SYM-99");
    expect(body.content).toContain("# Read Test");
  });

  test("GET /api/vault/note returns 404 for missing note", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    const res = await request.get(
      "/board/api/vault/note?path=nonexistent.md"
    );
    expect(res.status()).toBe(404);
  });

  test("GET /api/vault/note blocks path traversal", async ({ request }) => {
    await configureKB(request, testVault);

    const res = await request.get(
      "/board/api/vault/note?path=../../../etc/passwd"
    );
    expect(res.status()).toBeGreaterThanOrEqual(400);
    expect(res.status()).toBeLessThan(500);
  });
});

// ---------------------------------------------------------------------------
// Settings — KB Configuration
// ---------------------------------------------------------------------------

test.describe("Knowledge Base — Settings", () => {
  test("Settings page has Knowledge Base section", async ({ page }) => {
    await page.goto("/board/settings");
    await expect(page.locator("text=Knowledge Base")).toBeVisible();
    await expect(page.locator("#kb_type")).toBeVisible();
    await expect(page.locator("#kb_vault_path")).toBeVisible();
    await expect(page.locator("#kb_subfolder")).toBeVisible();
  });

  test("Test Connection button works for valid path", async ({
    page,
    request,
  }) => {
    await configureKB(request, testVault);
    await page.goto("/board/settings");

    // Wait for settings to load
    await page.waitForTimeout(500);

    // Fill vault path and click test
    await page.fill("#kb_vault_path", testVault);
    await page.click("#kb-test-btn");

    // Wait for result
    await expect(page.locator("#kb-test-result")).toContainText("Connected", {
      timeout: 5000,
    });
  });
});

// ---------------------------------------------------------------------------
// Issue Detail — Send to KB
// ---------------------------------------------------------------------------

test.describe("Knowledge Base — Issue Detail", () => {
  test("Send to KB button appears and works with confirmation", async ({
    page,
    request,
  }) => {
    await configureKB(request, testVault);

    // Create an issue
    const issue = await createIssue(request, {
      title: "KB Detail Test",
      state: "Done",
      description: "Description for KB detail test.",
    });
    createdIssueIds.push(issue.id);

    // Navigate to issue detail
    await page.goto(`/board/issues/${issue.id}`);

    // Wait for KB check to run
    await page.waitForTimeout(1000);

    // Send to KB button should be visible
    const btn = page.locator("#send-to-kb-btn");
    await expect(btn).toBeVisible({ timeout: 5000 });

    // Accept the confirmation dialog
    page.once("dialog", (dialog) => dialog.accept());

    // Click it
    await btn.click();

    // Button should change to "Sent to KB" after success
    await expect(btn).toContainText("Sent", { timeout: 5000 });
  });
});

// ---------------------------------------------------------------------------
// Vault API — Delete Note
// ---------------------------------------------------------------------------

test.describe("Knowledge Base — Delete Note", () => {
  test("DELETE /api/vault/note deletes a note", async ({ request }) => {
    await configureKB(request, testVault);

    // Write a test note
    const dir = path.join(testVault, "symphony", "delete-test");
    fs.mkdirSync(dir, { recursive: true });
    const notePath = path.join(dir, "to-delete.md");
    fs.writeFileSync(notePath, "# Delete me\n");

    const res = await request.delete("/board/api/vault/note", {
      data: { path: "symphony/delete-test/to-delete.md" },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(fs.existsSync(notePath)).toBe(false);
  });

  test("DELETE /api/vault/note returns 404 for missing note", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    const res = await request.delete("/board/api/vault/note", {
      data: { path: "nonexistent-note.md" },
    });
    expect(res.status()).toBe(404);
  });

  test("DELETE /api/vault/note blocks path traversal", async ({
    request,
  }) => {
    await configureKB(request, testVault);

    const res = await request.delete("/board/api/vault/note", {
      data: { path: "../../../etc/passwd" },
    });
    expect(res.status()).toBeGreaterThanOrEqual(400);
    expect(res.status()).toBeLessThan(500);
  });
});

// ---------------------------------------------------------------------------
// Product Hub — KB Tab
// ---------------------------------------------------------------------------

test.describe("Knowledge Base — Hub KB Tab", () => {
  test("KB tab is visible in the Product Hub", async ({ page }) => {
    await page.goto("/board");
    await expect(page.locator('[data-tab="kb"]')).toBeVisible();
  });

  test("KB tab shows search bar and results area", async ({
    page,
    request,
  }) => {
    await configureKB(request, testVault);

    // Write a test note
    const dir = path.join(testVault, "symphony", "hub-test");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, "hub-note.md"),
      "---\ntags:\n  - test\n---\n# Hub Note\nContent for hub test.\n"
    );

    await page.goto("/board");
    await page.click('[data-tab="kb"]');

    // Search bar should be visible
    await expect(page.locator("#kb-search-input")).toBeVisible({
      timeout: 5000,
    });

    // Results area should exist
    await expect(page.locator("#kb-results")).toBeVisible();
  });
});
