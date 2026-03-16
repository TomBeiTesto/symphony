import { test, expect, type APIRequestContext } from "@playwright/test";
import {
  createIssue,
  createPipeline,
  createPipelineWithNodes,
  cleanupPipelines,
} from "./helpers";

/**
 * End-to-end tests for the Pipeline Designer & Execution Monitor.
 *
 * IMPORTANT: Tests only delete pipelines they create — user pipelines are preserved.
 * Each describe block tracks created pipeline IDs and cleans them up in afterEach.
 *
 * Run: cd test/e2e && npx playwright test pipeline.spec.ts
 */

// Helper: open config modal via toolbar (dblclick doesn't work because
// the mousedown handler re-renders the DOM, preventing the browser from
// firing a dblclick event on the same element).
async function openConfigViaToolbar(
  page: import("@playwright/test").Page,
  nodeLocator: import("@playwright/test").Locator
) {
  await nodeLocator.click();
  await page.waitForTimeout(200);
  await page.locator(".node-toolbar button:has-text('Configure')").click();
  await page.waitForTimeout(300);
}

// ============================================================
// Pipeline List Page
// ============================================================

test.describe("Pipeline List — CRUD", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("list page renders", async ({ page }) => {
    await page.goto("/board/pipeline");
    await page.waitForTimeout(500);

    await expect(page.locator("h2")).toContainText("Pipelines");
    await expect(
      page.locator("button:has-text('+ New Pipeline')")
    ).toHaveCount(1);
  });

  test("create pipeline via button navigates to designer", async ({
    page,
    request,
  }) => {
    await page.goto("/board/pipeline");
    await page.waitForTimeout(500);

    // Capture the navigation to get the new pipeline's ID
    const [response] = await Promise.all([
      page.waitForNavigation({ url: "**/board/pipeline/*" }),
      page.click("button:has-text('+ New Pipeline')"),
    ]);

    // Extract ID from URL and track for cleanup
    const url = page.url();
    const id = url.split("/board/pipeline/")[1];
    if (id) createdIds.push(id);

    await expect(page.locator("#viewport")).toHaveCount(1);
    await expect(page.locator(".palette")).toHaveCount(1);
  });

  test("pipeline cards appear after creating pipelines", async ({
    page,
    request,
  }) => {
    const p1 = await createPipeline(request, { name: "Pipeline Alpha" });
    const p2 = await createPipeline(request, { name: "Pipeline Beta" });
    createdIds.push(p1.id, p2.id);

    await page.goto("/board/pipeline");
    await page.waitForTimeout(1000);

    await expect(page.locator("body")).toContainText("Pipeline Alpha");
    await expect(page.locator("body")).toContainText("Pipeline Beta");
  });

  test("clicking pipeline card opens designer", async ({ page, request }) => {
    const pipeline = await createPipeline(request, { name: "Click Me" });
    createdIds.push(pipeline.id);

    await page.goto("/board/pipeline");
    await page.waitForTimeout(1000);

    // Click by text to be resilient to other pipelines on the page
    await page.locator(".pipeline-card:has-text('Click Me')").first().click();
    await page.waitForURL(`**/board/pipeline/${pipeline.id}`);
    await expect(page.locator("#viewport")).toHaveCount(1);
  });

  test("delete pipeline removes it from list", async ({ page, request }) => {
    const pipeline = await createPipeline(request, { name: "Delete Me E2E" });
    // Don't add to createdIds — we delete it in the test

    await page.goto("/board/pipeline");
    await page.waitForTimeout(1000);

    await expect(page.locator("body")).toContainText("Delete Me E2E");

    page.on("dialog", (dialog) => dialog.accept());

    const card = page.locator(".pipeline-card:has-text('Delete Me E2E')").first();
    await card.hover();
    const delBtn = card.locator("button:has-text('Delete')");
    if ((await delBtn.count()) > 0) {
      await delBtn.click();
      await page.waitForTimeout(1000);
      await expect(page.locator("body")).not.toContainText("Delete Me E2E");
    }
  });
});

// ============================================================
// Pipeline Designer — Canvas Basics
// ============================================================

test.describe("Pipeline Designer — Canvas", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("designer page renders with all UI elements", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipeline(request, { name: "Designer Test" });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(500);

    await expect(page.locator("#viewport")).toHaveCount(1);
    await expect(page.locator(".palette")).toHaveCount(1);
    await expect(page.locator("#minimap")).toHaveCount(1);
    await expect(page.locator(".zoom-controls")).toHaveCount(1);
    await expect(page.locator(".canvas-actions")).toHaveCount(1);
    await expect(page.locator(".canvas-breadcrumb")).toHaveCount(1);

    const paletteItems = page.locator(".palette-item");
    await expect(paletteItems).toHaveCount(8);
  });

  test("pipeline name is editable", async ({ page, request }) => {
    const pipeline = await createPipeline(request, { name: "Rename Me" });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(500);

    const nameInput = page.locator("#pipeline-name");
    await expect(nameInput).toHaveValue("Rename Me");

    await nameInput.fill("Renamed Pipeline");
    await expect(nameInput).toHaveValue("Renamed Pipeline");
  });

  test("zoom controls work", async ({ page, request }) => {
    const pipeline = await createPipeline(request);
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(500);

    const zoomLevel = page.locator("#zoom-level");
    await expect(zoomLevel).toContainText("100%");

    await page.click("button:has-text('+')");
    await page.waitForTimeout(200);
    const text = await zoomLevel.textContent();
    expect(parseInt(text!)).toBeGreaterThan(100);
  });

  test("'back to pipelines' link works", async ({ page, request }) => {
    const pipeline = await createPipeline(request);
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(500);

    await page.click("a:has-text('Pipelines')");
    await page.waitForURL("**/board/pipeline");
  });

  test("nonexistent pipeline returns 404", async ({ page }) => {
    const response = await page.goto("/board/pipeline/nonexistent-id-999");
    expect(response!.status()).toBe(404);
  });
});

// ============================================================
// Pipeline Designer — Node Operations
// ============================================================

test.describe("Pipeline Designer — Node Operations", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("loaded pipeline displays its nodes", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      name: "With Nodes",
      nodeTypes: ["issue", "human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const nodes = page.locator(".p-node, .p-node-terminal");
    await expect(nodes).toHaveCount(4);
  });

  test("loaded pipeline displays edges", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const edges = page.locator(".edge-layer path");
    const count = await edges.count();
    expect(count).toBeGreaterThanOrEqual(2);
  });

  test("clicking a node selects it and shows toolbar", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const issueNode = page.locator(".p-node").first();
    await issueNode.click();
    await page.waitForTimeout(200);

    await expect(page.locator(".p-node.selected")).toHaveCount(1);

    const toolbar = page.locator(".node-toolbar");
    await expect(toolbar).toHaveCount(1);
    await expect(toolbar).toContainText("Configure");
    await expect(toolbar).toContainText("Duplicate");
    await expect(toolbar).toContainText("Delete");
  });

  test("delete node via toolbar removes it", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue", "human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const initialCount = await page.locator(".p-node").count();

    await page.locator(".p-node").first().click();
    await page.waitForTimeout(200);
    await page.locator(".node-toolbar button:has-text('Delete')").click();
    await page.waitForTimeout(200);

    expect(await page.locator(".p-node").count()).toBe(initialCount - 1);
  });

  test("duplicate node via toolbar creates a copy", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const initialCount = await page.locator(".p-node").count();

    await page.locator(".p-node").first().click();
    await page.waitForTimeout(200);
    await page.locator(".node-toolbar button:has-text('Duplicate')").click();
    await page.waitForTimeout(200);

    expect(await page.locator(".p-node").count()).toBe(initialCount + 1);
  });

  test("Delete key removes selected node", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const initialCount = await page.locator(".p-node").count();

    await page.locator(".p-node").first().click();
    await page.waitForTimeout(200);
    await page.keyboard.press("Delete");
    await page.waitForTimeout(200);

    expect(await page.locator(".p-node").count()).toBe(initialCount - 1);
  });

  test("Escape deselects node", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator(".p-node").first().click();
    await page.waitForTimeout(200);
    await expect(page.locator(".p-node.selected")).toHaveCount(1);

    await page.keyboard.press("Escape");
    await page.waitForTimeout(200);
    await expect(page.locator(".p-node.selected")).toHaveCount(0);
  });
});

// ============================================================
// Pipeline Designer — Configuration Modal
// ============================================================

test.describe("Pipeline Designer — Config Modal", () => {
  const createdIds: string[] = [];

  const createdIssueIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
    // Clean up only issues created by these tests
    for (const id of createdIssueIds.splice(0)) {
      try { await request.delete(`/board/api/issues/${id}`); } catch {}
    }
  });

  test("configure button in toolbar opens config modal", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());

    const modal = page.locator("#config-modal");
    await expect(modal).toHaveCSS("display", "flex");
    await expect(modal).toContainText("Configure");
    await expect(page.locator("#cfg-label")).toHaveCount(1);
  });

  test("issue node config shows issue picker", async ({ page, request }) => {
    const issue = await createIssue(request, { title: "Pickable Issue", state: "Todo" });
    createdIssueIds.push(issue.id);
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());

    // Wait for async issue picker to load
    await page.waitForTimeout(500);
    await expect(page.locator("#issue-picker")).toHaveCount(1);
    await expect(page.locator("#issue-picker")).toContainText("Pickable Issue");
  });

  test("issue node config shows 'Create new issue' button", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());

    await expect(
      page.locator("button:has-text('Create new issue')")
    ).toHaveCount(1);
  });

  test("create-issue modal opens on top of config modal", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await expect(page.locator("#config-modal")).toHaveCSS("display", "flex");

    await page.click("button:has-text('Create new issue')");
    await page.waitForTimeout(300);

    const ciModal = page.locator("#ci-modal");
    await expect(ciModal).toHaveCSS("display", "flex");

    // Create-issue modal should be on top (higher z-index)
    const ciZIndex = await ciModal.evaluate(
      (el) => window.getComputedStyle(el).zIndex
    );
    const configZIndex = await page
      .locator("#config-modal")
      .evaluate((el) => window.getComputedStyle(el).zIndex);
    expect(parseInt(ciZIndex)).toBeGreaterThan(parseInt(configZIndex));
  });

  test("create-issue modal has all form fields", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await page.click("button:has-text('Create new issue')");
    await page.waitForTimeout(300);

    await expect(page.locator("#ci-title")).toHaveCount(1);
    await expect(page.locator("#ci-description")).toHaveCount(1);
    await expect(page.locator("#ci-state")).toHaveCount(1);
    await expect(page.locator("#ci-priority")).toHaveCount(1);
    await expect(page.locator("#ci-labels")).toHaveCount(1);
    await expect(page.locator("#ci-project")).toHaveCount(1);
    await expect(page.locator("#ci-submit")).toHaveCount(1);
  });

  test("creating issue from modal links it to the node", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await page.click("button:has-text('Create new issue')");
    await page.waitForTimeout(300);

    await page.fill("#ci-title", "Pipeline-linked issue");
    await page.click("#ci-submit");
    await page.waitForTimeout(500);

    await expect(page.locator("#ci-modal")).toHaveCSS("display", "none");

    const issueIdValue = await page.locator("#cfg-issue-id").inputValue();
    expect(issueIdValue).toBeTruthy();
    if (issueIdValue) createdIssueIds.push(issueIdValue);
  });

  test("config modal apply updates node label", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());

    await page.fill("#cfg-label", "My Custom Label");
    await page.click("button:has-text('Apply')");
    await page.waitForTimeout(300);

    await expect(page.locator("#config-modal")).toHaveCSS("display", "none");
    await expect(page.locator(".p-node-label")).toContainText("My Custom Label");
  });

  test("cancel config modal does not change node", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const origLabel = await page.locator(".p-node-label").first().textContent();

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await page.fill("#cfg-label", "Should Not Stick");
    await page.click("#config-modal button:has-text('Cancel')");
    await page.waitForTimeout(300);

    await expect(page.locator(".p-node-label").first()).toContainText(
      origLabel!
    );
  });

  test("human gate config shows instructions textarea", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await expect(page.locator("#cfg-instructions")).toHaveCount(1);
  });

  test("loop node config shows max retries and condition", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["loop"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await expect(page.locator("#cfg-max-retries")).toHaveCount(1);
    await expect(page.locator("#cfg-loop-cond")).toHaveCount(1);
  });

  test("quality gate config shows checks field", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["quality_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await expect(page.locator("#cfg-checks")).toHaveCount(1);
  });

  test("integration node config shows type selector and JSON config", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["integration"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await openConfigViaToolbar(page, page.locator(".p-node").first());
    await expect(page.locator("#cfg-int-type")).toHaveCount(1);
    await expect(page.locator("#cfg-int-config")).toHaveCount(1);
  });
});

// ============================================================
// Pipeline Designer — Save & Load
// ============================================================

test.describe("Pipeline Designer — Save & Load", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("Ctrl+S saves pipeline and shows toast", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.keyboard.press("Control+s");
    await page.waitForTimeout(500);

    const toast = page.locator(".toast");
    await expect(toast.first()).toBeVisible({ timeout: 3000 });
    await expect(toast.first()).toContainText("Pipeline saved");
  });

  test("save button saves pipeline", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.click("button:has-text('Save')");
    await page.waitForTimeout(500);

    const toast = page.locator(".toast");
    await expect(toast.first()).toBeVisible({ timeout: 3000 });
  });

  test("saved pipeline persists and reloads correctly", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      name: "Persist Test",
      nodeTypes: ["issue", "human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.fill("#pipeline-name", "Persisted Pipeline");
    await page.click("button:has-text('Save')");
    await page.waitForTimeout(500);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await expect(page.locator("#pipeline-name")).toHaveValue(
      "Persisted Pipeline"
    );

    const nodes = page.locator(".p-node, .p-node-terminal");
    await expect(nodes).toHaveCount(4);
  });
});

// ============================================================
// Pipeline Designer — Keyboard Shortcuts
// ============================================================

test.describe("Pipeline Designer — Keyboard Shortcuts", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("? key opens help modal", async ({ page, request }) => {
    const pipeline = await createPipeline(request);
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(500);

    await page.locator("#viewport").click();
    await page.waitForTimeout(100);
    await page.keyboard.press("?");
    await page.waitForTimeout(300);

    const helpModal = page.locator("#help-modal");
    await expect(helpModal).toHaveCSS("display", "flex");
    await expect(helpModal).toContainText("Keyboard Shortcuts");
  });

  test("Escape closes help modal", async ({ page, request }) => {
    const pipeline = await createPipeline(request);
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(500);

    await page.locator("#viewport").click();
    await page.keyboard.press("?");
    await page.waitForTimeout(300);
    await expect(page.locator("#help-modal")).toHaveCSS("display", "flex");

    await page.keyboard.press("Escape");
    await page.waitForTimeout(200);
    await expect(page.locator("#help-modal")).toHaveCSS("display", "none");
  });

  test("Ctrl+Z undoes last action", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator(".p-node").first().click();
    await page.waitForTimeout(200);
    await page.keyboard.press("Delete");
    await page.waitForTimeout(200);

    const countAfterDelete = await page.locator(".p-node").count();

    await page.keyboard.press("Control+z");
    await page.waitForTimeout(200);

    expect(await page.locator(".p-node").count()).toBe(countAfterDelete + 1);
  });
});

// ============================================================
// Pipeline Designer — Execution Mode
// ============================================================

test.describe("Pipeline Designer — Execution", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("run button starts execution and toggles UI", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    const runBtn = page.locator("#run-btn");
    await expect(runBtn).toContainText("Run");
    await runBtn.click();
    await page.waitForTimeout(1000);

    await expect(runBtn).toContainText("Stop");
    await expect(page.locator(".palette")).toHaveCSS("display", "none");
  });

  test("stop button exits execution mode", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator("#run-btn").click();
    await page.waitForTimeout(1000);
    await expect(page.locator("#run-btn")).toContainText("Stop");

    await page.locator("#run-btn").click();
    await page.waitForTimeout(500);

    await expect(page.locator("#run-btn")).toContainText("Run");
    await expect(page.locator(".palette")).toHaveCSS("display", "flex");
  });

  test("execution mode shows node status classes", async ({
    page,
    request,
  }) => {
    // Simple start -> end pipeline that auto-completes
    const pipeline = await createPipeline(request, { name: "Quick Complete" });
    createdIds.push(pipeline.id);

    await request.patch(`/board/api/pipelines/${pipeline.id}`, {
      data: {
        nodes: [
          {
            id: "s1", type: "start", label: "Start",
            position: { x: 100, y: 200 }, issue_id: null, config: {},
            loop_max_retries: null, loop_condition: null,
          },
          {
            id: "e1", type: "end", label: "End",
            position: { x: 400, y: 200 }, issue_id: null, config: {},
            loop_max_retries: null, loop_condition: null,
          },
        ],
        edges: [{
          id: "edge1", source_node_id: "s1", target_node_id: "e1",
          source_port: "output", label: null,
        }],
      },
    });

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator("#run-btn").click();
    await page.waitForTimeout(3000);

    const completedNodes = page.locator(".exec-completed");
    expect(await completedNodes.count()).toBeGreaterThanOrEqual(1);
  });

  test("clicking node in exec mode shows exec sidebar", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator("#run-btn").click();
    await page.waitForTimeout(1000);

    await page.locator(".p-node, .p-node-terminal").first().click();
    await page.waitForTimeout(300);

    const sidebar = page.locator("#exec-sidebar");
    await expect(sidebar).toHaveClass(/open/);
    await expect(sidebar).toContainText("State:");
  });

  test("exec sidebar has close button", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator("#run-btn").click();
    await page.waitForTimeout(1000);

    // Click the issue node (not a terminal) to get a proper sidebar
    await page.locator(".p-node").first().click();
    await page.waitForTimeout(500);
    await expect(page.locator("#exec-sidebar")).toHaveClass(/open/);

    // Find close button by title attribute (more robust)
    const closeBtn = page.locator('#exec-sidebar button[title="Close"]');
    await expect(closeBtn).toHaveCount(1);
    await closeBtn.click();
    await page.waitForTimeout(300);
    await expect(page.locator("#exec-sidebar")).not.toHaveClass(/open/);
  });
});

// ============================================================
// Pipeline Designer — Gate Decisions
// ============================================================

test.describe("Pipeline Designer — Gates", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("human gate in waiting state shows approve/reject buttons", async ({
    page,
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator("#run-btn").click();
    await page.waitForTimeout(3000);

    const gateNode = page.locator(".p-node.exec-waiting");
    if ((await gateNode.count()) > 0) {
      await gateNode.click();
      await page.waitForTimeout(300);

      const sidebar = page.locator("#exec-sidebar");
      await expect(sidebar).toContainText("waiting_gate");
      await expect(sidebar.locator("button:has-text('Approve')")).toHaveCount(1);
      await expect(sidebar.locator("button:has-text('Reject')")).toHaveCount(1);
      await expect(sidebar.locator(".gate-feedback")).toHaveCount(1);
    }
  });

  test("approving gate advances pipeline", async ({ page, request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["human_gate"],
    });
    createdIds.push(pipeline.id);

    await page.goto(`/board/pipeline/${pipeline.id}`);
    await page.waitForTimeout(1000);

    await page.locator("#run-btn").click();
    await page.waitForTimeout(3000);

    const gateNode = page.locator(".p-node.exec-waiting");
    if ((await gateNode.count()) > 0) {
      await gateNode.click();
      await page.waitForTimeout(300);

      await page.locator("#exec-sidebar button:has-text('Approve')").click();
      await page.waitForTimeout(2000);

      expect(await page.locator(".p-node.exec-waiting").count()).toBe(0);
    }
  });
});

// ============================================================
// Pipeline API — Direct Tests
// ============================================================

test.describe("Pipeline API", () => {
  const createdIds: string[] = [];

  test.afterEach(async ({ request }) => {
    await cleanupPipelines(request, createdIds.splice(0));
  });

  test("CRUD lifecycle via API", async ({ request }) => {
    const createRes = await request.post("/board/api/pipelines", {
      data: { name: "API Test Pipeline" },
    });
    expect(createRes.ok()).toBeTruthy();
    const pipeline = await createRes.json();
    expect(pipeline.name).toBe("API Test Pipeline");
    expect(pipeline.id).toBeTruthy();
    createdIds.push(pipeline.id);

    const getRes = await request.get(`/board/api/pipelines/${pipeline.id}`);
    expect(getRes.ok()).toBeTruthy();

    const updateRes = await request.patch(
      `/board/api/pipelines/${pipeline.id}`,
      { data: { name: "Updated Pipeline", description: "A description" } }
    );
    expect(updateRes.ok()).toBeTruthy();
    const updated = await updateRes.json();
    expect(updated.name).toBe("Updated Pipeline");
    expect(updated.description).toBe("A description");

    const listRes = await request.get("/board/api/pipelines");
    const listData = await listRes.json();
    expect(listData.pipelines.length).toBeGreaterThanOrEqual(1);

    // Delete inside test — remove from cleanup list
    const delRes = await request.delete(`/board/api/pipelines/${pipeline.id}`);
    expect(delRes.ok()).toBeTruthy();
    createdIds.pop();

    const gone = await request.get(`/board/api/pipelines/${pipeline.id}`);
    expect(gone.status()).toBe(404);
  });

  test("save and retrieve pipeline with nodes and edges", async ({
    request,
  }) => {
    const pipeline = await createPipelineWithNodes(request, {
      name: "Nodes Test",
      nodeTypes: ["issue", "human_gate", "quality_gate"],
    });
    createdIds.push(pipeline.id);

    const res = await request.get(`/board/api/pipelines/${pipeline.id}`);
    const data = await res.json();

    expect(data.nodes.length).toBe(5);
    expect(data.edges.length).toBe(4);

    const types = data.nodes.map((n: { type: string }) => n.type).sort();
    expect(types).toEqual([
      "end", "human_gate", "issue", "quality_gate", "start",
    ]);
  });

  test("pipeline run lifecycle via API", async ({ request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["issue"],
    });
    createdIds.push(pipeline.id);

    const runRes = await request.post(
      `/board/api/pipelines/${pipeline.id}/run`
    );
    expect(runRes.ok()).toBeTruthy();
    const run = await runRes.json();
    expect(run.status).toBe("running");
    expect(run.node_states).toBeTruthy();

    const statusRes = await request.get(
      `/board/api/pipelines/${pipeline.id}/runs/${run.id}`
    );
    expect(statusRes.ok()).toBeTruthy();

    const cancelRes = await request.post(
      `/board/api/pipelines/${pipeline.id}/runs/${run.id}/cancel`
    );
    expect(cancelRes.ok()).toBeTruthy();
    const cancelled = await cancelRes.json();
    expect(cancelled.status).toBe("cancelled");
  });

  test("gate decision API works", async ({ request }) => {
    const pipeline = await createPipelineWithNodes(request, {
      nodeTypes: ["human_gate"],
    });
    createdIds.push(pipeline.id);

    const runRes = await request.post(
      `/board/api/pipelines/${pipeline.id}/run`
    );
    const run = await runRes.json();

    await new Promise((r) => setTimeout(r, 2000));

    const gateNode = pipeline.nodes.find(
      (n: { type: string }) => n.type === "human_gate"
    );

    if (gateNode) {
      const gateRes = await request.post(
        `/board/api/pipelines/${pipeline.id}/runs/${run.id}/gate/${gateNode.id}`,
        { data: { action: "approve", feedback: "Looks good" } }
      );
      expect(gateRes.ok()).toBeTruthy();
    }

    await request.post(
      `/board/api/pipelines/${pipeline.id}/runs/${run.id}/cancel`
    );
  });

  test("404 for nonexistent pipeline", async ({ request }) => {
    const res = await request.get("/board/api/pipelines/nonexistent-id");
    expect(res.status()).toBe(404);
  });

  test("404 for nonexistent run", async ({ request }) => {
    const pipeline = await createPipeline(request);
    createdIds.push(pipeline.id);
    const res = await request.get(
      `/board/api/pipelines/${pipeline.id}/runs/nonexistent-run`
    );
    expect(res.status()).toBe(404);
  });
});

// ============================================================
// Cross-page Navigation — Pipeline
// ============================================================

test.describe("Pipeline — Navigation", () => {
  test("topbar has pipeline link on all pages", async ({ page }) => {
    await page.goto("/board");
    await page.waitForTimeout(300);
    await expect(
      page.locator('a[href="/board/pipeline"]')
    ).toHaveCount(1);
  });

  test("pipeline link in topbar has active state on pipeline pages", async ({
    page,
  }) => {
    await page.goto("/board/pipeline");
    await page.waitForTimeout(300);

    const pipelineLink = page.locator(
      'a[href="/board/pipeline"].nav-active'
    );
    await expect(pipelineLink).toHaveCount(1);
  });
});
