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

/** Delete specific pipelines by ID — does NOT touch user-created pipelines. */
export async function cleanupPipelines(
  request: APIRequestContext,
  ids: string[]
) {
  for (const id of ids) {
    try {
      await request.delete(`/board/api/pipelines/${id}`);
    } catch {}
  }
}

export async function createPipeline(
  request: APIRequestContext,
  data: Record<string, unknown> = {}
) {
  const res = await request.post("/board/api/pipelines", {
    data: { name: "Test Pipeline", ...data },
  });
  return await res.json();
}

export async function createPipelineWithNodes(
  request: APIRequestContext,
  opts: { name?: string; nodeTypes?: string[] } = {}
) {
  const pipeline = await createPipeline(request, {
    name: opts.name || "Test Pipeline",
  });

  // Build nodes: start + requested types + end
  const types = opts.nodeTypes || ["issue"];
  const nodes: Record<string, unknown>[] = [
    {
      id: "start-1",
      type: "start",
      label: "Start",
      position: { x: 100, y: 200 },
      issue_id: null,
      config: {},
      loop_max_retries: null,
      loop_condition: null,
    },
  ];
  const edges: Record<string, unknown>[] = [];

  let prevId = "start-1";
  types.forEach((type, i) => {
    const nodeId = `node-${i}`;
    nodes.push({
      id: nodeId,
      type,
      label: `${type} ${i + 1}`,
      position: { x: 350 + i * 250, y: 200 },
      issue_id: null,
      config: {},
      loop_max_retries: type === "loop" ? 5 : null,
      loop_condition: null,
    });
    edges.push({
      id: `edge-${i}`,
      source_node_id: prevId,
      target_node_id: nodeId,
      source_port: "output",
      label: null,
    });
    prevId = nodeId;
  });

  const endId = "end-1";
  nodes.push({
    id: endId,
    type: "end",
    label: "End",
    position: { x: 350 + types.length * 250, y: 200 },
    issue_id: null,
    config: {},
    loop_max_retries: null,
    loop_condition: null,
  });
  edges.push({
    id: `edge-end`,
    source_node_id: prevId,
    target_node_id: endId,
    source_port: "output",
    label: null,
  });

  // Save the pipeline with nodes
  const updateRes = await request.patch(
    `/board/api/pipelines/${pipeline.id}`,
    { data: { nodes, edges } }
  );
  return await updateRes.json();
}
