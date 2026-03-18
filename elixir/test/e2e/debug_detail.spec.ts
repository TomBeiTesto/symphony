import { test, expect } from "@playwright/test";
import { cleanupAll, createIssue } from "./helpers";

test("debug issue detail JS errors", async ({ page, request }) => {
  await cleanupAll(request);
  const errors: string[] = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', err => errors.push('PAGE ERROR: ' + err.message));
  
  const issue = await createIssue(request, {
    title: "Plan debug",
    state: "In Progress",
    plan_status: "planning",
  });
  
  await page.goto(`/board/issues/${issue.id}`);
  await page.waitForTimeout(3000);
  
  console.log('JS errors:', errors.length ? errors.join('\n') : 'none');
  
  const panelDisplay = await page.locator("#plan-review-panel").evaluate(el => getComputedStyle(el).display);
  console.log('Plan panel display:', panelDisplay);
  
  const panelHtml = await page.locator("#plan-review-panel").innerHTML();
  console.log('Plan panel HTML length:', panelHtml.length);
});
