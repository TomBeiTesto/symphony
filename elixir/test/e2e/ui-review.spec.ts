import { test } from "@playwright/test";
import { join } from "path";
import { cleanupAll, cleanupPipelines, cleanupSkills } from "./helpers";

/**
 * Comprehensive UI review — captures screenshots of every page and feature.
 */

const DIR = join(__dirname, "screenshots", "review");

async function shot(page: any, name: string) {
  await page.waitForTimeout(800);
  await page.screenshot({ path: join(DIR, `${name}.png`), fullPage: true });
}

// --- Seed helpers ---

async function seedFullBoard(request: any) {
  const issues = [
    { title: "Set up CI/CD pipeline", state: "Done", priority: 1, labels: ["infra", "devops"], description: "Configure GitHub Actions for automated testing and deployment." },
    { title: "Implement user authentication", state: "In Progress", priority: 2, labels: ["backend", "security"], description: "Add OAuth2 login with JWT tokens." },
    { title: "Design landing page mockups", state: "In Progress", priority: 3, labels: ["design", "frontend"] },
    { title: "Write API documentation", state: "Todo", priority: 2, labels: ["docs"] },
    { title: "Fix memory leak in worker pool", state: "Todo", priority: 1, labels: ["bug", "backend"], description: "Workers accumulate memory after 1000+ tasks. Needs profiling." },
    { title: "Add rate limiting to endpoints", state: "Backlog", priority: 3, labels: ["backend"] },
    { title: "Migrate database to PostgreSQL", state: "Backlog", priority: 2, labels: ["infra", "database"] },
    { title: "Set up monitoring dashboard", state: "Backlog", priority: 4, labels: ["infra"] },
    { title: "Refactor config module", state: "Review", priority: 3, labels: ["refactor"] },
    { title: "Update deprecated dependencies", state: "Cancelled", priority: 4, labels: ["chore"] },
    { title: "Implement search autocomplete", state: "Todo", priority: 2, labels: ["frontend", "ux"] },
    { title: "Add WebSocket support", state: "Backlog", priority: 1, labels: ["backend", "realtime"] },
  ];

  const created: any[] = [];
  for (const issue of issues) {
    const res = await request.post("/board/api/issues", { data: issue });
    created.push(await res.json());
  }
  return created;
}

async function seedProjectAndProduct(request: any) {
  const projRes = await request.post("/board/api/projects", {
    data: {
      name: "Symphony Core",
      description: "Main orchestration engine for AI agent dispatch",
      repo_url: "https://github.com/org/symphony-core",
      path: "/home/user/code/symphony-core",
    },
  });
  const project = await projRes.json();

  const prodRes = await request.post("/board/api/products", {
    data: {
      name: "Symphony Platform",
      description: "End-to-end AI orchestration platform with kanban board, pipeline designer, and knowledge base",
      project_ids: [project.id],
    },
  });
  const product = await prodRes.json();

  for (const name of ["Authentication", "Rate Limiting", "Monitoring", "CI/CD Integration"]) {
    await request.post(`/board/api/products/${product.id}/features`, {
      data: { name, description: `${name} feature across all projects` },
    });
  }

  return { project, product };
}

async function seedPipeline(request: any) {
  const pRes = await request.post("/board/api/pipelines", {
    data: { name: "Release Pipeline" },
  });
  const pipeline = await pRes.json();

  const nodes = [
    { id: "start-1", type: "start", label: "Start", position: { x: 50, y: 200 }, config: {} },
    { id: "n-1", type: "issue", label: "Build & Test", position: { x: 280, y: 120 }, config: {} },
    { id: "n-2", type: "issue", label: "Security Scan", position: { x: 280, y: 280 }, config: {} },
    { id: "n-3", type: "quality_gate", label: "QA Review", position: { x: 530, y: 200 }, config: { check_commands: "npm test\nnpm run lint" } },
    { id: "n-4", type: "integration", label: "Deploy Staging", position: { x: 780, y: 200 }, config: { integration_type: "gitlab_ci" } },
    { id: "n-5", type: "human_gate", label: "Production Sign-off", position: { x: 1030, y: 200 }, config: {} },
    { id: "n-6", type: "kb_sync", label: "Update Docs", position: { x: 1280, y: 200 }, config: {} },
    { id: "end-1", type: "end", label: "End", position: { x: 1500, y: 200 }, config: {} },
  ];
  const edges = [
    { id: "e1", source_node_id: "start-1", target_node_id: "n-1", source_port: "output" },
    { id: "e2", source_node_id: "start-1", target_node_id: "n-2", source_port: "output" },
    { id: "e3", source_node_id: "n-1", target_node_id: "n-3", source_port: "output" },
    { id: "e4", source_node_id: "n-2", target_node_id: "n-3", source_port: "output" },
    { id: "e5", source_node_id: "n-3", target_node_id: "n-4", source_port: "output" },
    { id: "e6", source_node_id: "n-4", target_node_id: "n-5", source_port: "output" },
    { id: "e7", source_node_id: "n-5", target_node_id: "n-6", source_port: "output" },
    { id: "e8", source_node_id: "n-6", target_node_id: "end-1", source_port: "output" },
  ];

  await request.patch(`/board/api/pipelines/${pipeline.id}`, {
    data: { nodes, edges },
  });

  return pipeline;
}

// ==================== TESTS ====================

let pipelineIds: string[] = [];

test.afterAll(async ({ request }) => {
  await cleanupPipelines(request, pipelineIds);
  pipelineIds = [];
});

// --- 1. BOARD ---

test.describe("1. Kanban Board", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("01 board - empty state", async ({ page }) => {
    await page.goto("/board");
    await shot(page, "01-board-empty");
  });

  test("02 board - populated (1280px)", async ({ page, request }) => {
    await seedFullBoard(request);
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto("/board");
    await shot(page, "02-board-populated-1280");
  });

  test("03 board - wide (1920px)", async ({ page, request }) => {
    await seedFullBoard(request);
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto("/board");
    await shot(page, "03-board-wide-1920");
  });

  test("04 board - narrow (1024px)", async ({ page, request }) => {
    await seedFullBoard(request);
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.goto("/board");
    await shot(page, "04-board-narrow-1024");
  });

  test("05 board - mobile (375px)", async ({ page, request }) => {
    await seedFullBoard(request);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board");
    await shot(page, "05-board-mobile-375");
  });

  test("06 board - new issue modal", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(500);
    const btn = page.locator("button:has-text('New Issue'), button:has-text('Add'), .btn-new-issue, [onclick*='openNewIssue'], [onclick*='showCreateModal']");
    if (await btn.count() > 0) {
      await btn.first().click();
      await page.waitForTimeout(500);
    }
    await shot(page, "06-board-new-issue-modal");
  });

  test("07 board - collapsed columns", async ({ page, request }) => {
    await seedFullBoard(request);
    await page.goto("/board");
    await page.waitForTimeout(1000);
    const columns = page.locator(".column");
    const count = await columns.count();
    for (let i = count - 1; i >= count - 2 && i >= 0; i--) {
      const collapseBtn = columns.nth(i).locator(".btn-collapse");
      if (await collapseBtn.count() > 0) {
        await collapseBtn.click();
        await page.waitForTimeout(200);
      }
    }
    await shot(page, "07-board-collapsed-columns");
  });
});

// --- 2. ISSUE DETAIL ---

test.describe("2. Issue Detail", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("08 issue detail - full page", async ({ page, request }) => {
    const issues = await seedFullBoard(request);
    // Pick a rich issue (with description)
    const issue = issues.find((i: any) => i.description) || issues[0];
    await page.goto(`/board/issues/${issue.id}`);
    await shot(page, "08-issue-detail");
  });

  test("09 issue detail - editing", async ({ page, request }) => {
    const issues = await seedFullBoard(request);
    const issue = issues[0];
    await page.goto(`/board/issues/${issue.id}`);
    await page.waitForTimeout(1000);
    // Try to click edit button
    const editBtn = page.locator("button:has-text('Edit'), .btn-edit, [onclick*='toggleEdit']");
    if (await editBtn.count() > 0) {
      await editBtn.first().click();
      await page.waitForTimeout(500);
    }
    await shot(page, "09-issue-detail-editing");
  });

  test("10 issue detail - mobile", async ({ page, request }) => {
    const issues = await seedFullBoard(request);
    const issue = issues.find((i: any) => i.description) || issues[0];
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(`/board/issues/${issue.id}`);
    await shot(page, "10-issue-detail-mobile");
  });
});

// --- 3. PIPELINE DESIGNER ---

test.describe("3. Pipeline Designer", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("11 pipelines - list empty", async ({ page }) => {
    await page.goto("/board/pipeline");
    await shot(page, "11-pipelines-list-empty");
  });

  test("12 pipelines - list with pipeline", async ({ page, request }) => {
    const p = await seedPipeline(request);
    pipelineIds.push(p.id);
    await page.goto("/board/pipeline");
    await shot(page, "12-pipelines-list-populated");
  });

  test("13 pipeline - designer canvas", async ({ page, request }) => {
    const p = await seedPipeline(request);
    pipelineIds.push(p.id);
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto(`/board/pipeline/${p.id}`);
    await page.waitForTimeout(1500);
    await shot(page, "13-pipeline-designer-canvas");
  });

  test("14 pipeline - designer node config panel", async ({ page, request }) => {
    const p = await seedPipeline(request);
    pipelineIds.push(p.id);
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto(`/board/pipeline/${p.id}`);
    await page.waitForTimeout(1500);
    // Click on a node to open config
    const node = page.locator(".pipeline-node, [data-node-id]").first();
    if (await node.count() > 0) {
      await node.click();
      await page.waitForTimeout(500);
    }
    await shot(page, "14-pipeline-designer-node-config");
  });

  test("15 pipeline - designer mobile", async ({ page, request }) => {
    const p = await seedPipeline(request);
    pipelineIds.push(p.id);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(`/board/pipeline/${p.id}`);
    await page.waitForTimeout(1500);
    await shot(page, "15-pipeline-designer-mobile");
  });
});

// --- 4. SETTINGS ---

test.describe("4. Settings", () => {
  test("16 settings - full page", async ({ page }) => {
    await page.goto("/board/settings");
    await shot(page, "16-settings-full");
  });

  test("17 settings - scrolled to KB section", async ({ page }) => {
    await page.goto("/board/settings");
    await page.waitForTimeout(500);
    // Scroll to KB section
    const kbSection = page.locator("text=Knowledge Base, text=KB Type, #kb_type").first();
    if (await kbSection.count() > 0) {
      await kbSection.scrollIntoViewIfNeeded();
      await page.waitForTimeout(300);
    }
    await shot(page, "17-settings-kb-section");
  });

  test("18 settings - mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board/settings");
    await shot(page, "18-settings-mobile");
  });
});

// --- 5. PRODUCT HUB ---

test.describe("5. Product Hub", () => {
  test.beforeEach(async ({ request }) => { await cleanupAll(request); });

  test("19 product hub - empty", async ({ page }) => {
    await page.goto("/board/products");
    await shot(page, "19-product-hub-empty");
  });

  test("20 product hub - with product selected", async ({ page, request }) => {
    const { product } = await seedProjectAndProduct(request);
    await page.goto("/board/products");
    await page.waitForTimeout(1500);
    // Select the product
    try {
      await page.locator("#product-select").selectOption(product.id, { timeout: 3000 });
    } catch {
      const opts = page.locator("#product-select option");
      if (await opts.count() > 1) {
        await page.locator("#product-select").selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);
    await shot(page, "20-product-hub-selected");
  });

  test("21 product hub - features tab", async ({ page, request }) => {
    const { product } = await seedProjectAndProduct(request);
    await page.goto("/board/products");
    await page.waitForTimeout(1500);
    try {
      await page.locator("#product-select").selectOption(product.id, { timeout: 3000 });
    } catch {
      const opts = page.locator("#product-select option");
      if (await opts.count() > 1) {
        await page.locator("#product-select").selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);
    // Click features tab
    const featTab = page.locator("[data-tab='features'], button:has-text('Features'), .tab:has-text('Features')");
    if (await featTab.count() > 0) {
      await featTab.first().click();
      await page.waitForTimeout(500);
    }
    await shot(page, "21-product-hub-features");
  });

  test("22 product hub - KB tab", async ({ page, request }) => {
    const { product } = await seedProjectAndProduct(request);
    await page.goto("/board/products");
    await page.waitForTimeout(1500);
    try {
      await page.locator("#product-select").selectOption(product.id, { timeout: 3000 });
    } catch {
      const opts = page.locator("#product-select option");
      if (await opts.count() > 1) {
        await page.locator("#product-select").selectOption({ index: 1 });
      }
    }
    await page.waitForTimeout(1000);
    // Click KB tab
    const kbTab = page.locator("[data-tab='kb'], button:has-text('Knowledge'), .tab:has-text('KB')");
    if (await kbTab.count() > 0) {
      await kbTab.first().click();
      await page.waitForTimeout(500);
    }
    await shot(page, "22-product-hub-kb-tab");
  });

  test("23 product hub - mobile", async ({ page, request }) => {
    const { product } = await seedProjectAndProduct(request);
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board/products");
    await page.waitForTimeout(1500);
    try {
      await page.locator("#product-select").selectOption(product.id, { timeout: 3000 });
    } catch {
      const opts = page.locator("#product-select option");
      if (await opts.count() > 1) {
        await page.locator("#product-select").selectOption({ index: 1 });
      }
    }
    await shot(page, "23-product-hub-mobile");
  });
});

// --- 6. SKILLS ---

test.describe("6. Skills", () => {
  test("24 skills - page", async ({ page }) => {
    await page.goto("/board/skills");
    await shot(page, "24-skills-page");
  });

  test("25 skills - mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/board/skills");
    await shot(page, "25-skills-mobile");
  });
});
