import { type APIRequestContext } from "@playwright/test";

export async function cleanupAll(request: APIRequestContext) {
  try {
    const snapRes = await request.get("/board/api/snapshot");
    const snap = await snapRes.json();
    if (snap.columns) {
      for (const col of snap.columns) {
        for (const issue of col.issues) {
          await request.delete(`/board/api/issues/${issue.id}`);
        }
      }
    }
  } catch {}
  try {
    const projRes = await request.get("/board/api/projects");
    const projData = await projRes.json();
    for (const p of projData.projects || []) {
      await request.delete(`/board/api/projects/${p.id}`);
    }
  } catch {}
  try {
    const prodRes = await request.get("/board/api/products");
    const prodData = await prodRes.json();
    for (const p of prodData.products || []) {
      await request.delete(`/board/api/products/${p.id}`);
    }
  } catch {}
}

export async function createIssue(
  request: APIRequestContext,
  data: Record<string, unknown>
) {
  const res = await request.post("/board/api/issues", { data });
  return await res.json();
}

export async function createProject(
  request: APIRequestContext,
  data: Record<string, unknown>
) {
  const res = await request.post("/board/api/projects", { data });
  return await res.json();
}
