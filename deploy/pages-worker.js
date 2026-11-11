/**
 * Cloudflare Pages（advanced mode）入口：构建时复制为 dist/_worker.js。
 * - /.cloud/*：同域转发到 WorkBuddy 云端（账目、成员、设置、行程）
 * - /api/budget：预算项与预算设定的云端同步，存在 Cloudflare D1（绑定名 BUDGET_DB，表结构见 deploy/budget-schema.sql）
 * - 其余路径：返回静态文件（账本在 /，行程规划在 /plan/）
 */
const UPSTREAM = "https://travel-aa-ledger-72643.app.workbuddy.host";

async function proxyCloud(request, url) {
  const target = new URL(url.pathname + url.search, UPSTREAM);
  const headers = new Headers(request.headers);
  headers.set("Origin", UPSTREAM);
  headers.delete("Referer");
  headers.delete("Cookie");
  headers.delete("Host");
  const hasBody = !["GET", "HEAD"].includes(request.method);
  const upstream = await fetch(target, {
    method: request.method,
    headers,
    body: hasBody ? request.body : undefined,
    redirect: "manual",
  });
  const response = new Response(upstream.body, upstream);
  response.headers.set("x-ledger-cloud-proxy", "1");
  response.headers.set("Cache-Control", "no-store");
  response.headers.delete("Access-Control-Allow-Origin");
  response.headers.delete("Set-Cookie");
  return response;
}

/* ---------- 预算同步 ---------- */
const BUDGET_KINDS = new Set(["item", "plan"]);
const MAX_CHANGES = 500;
const MAX_PAYLOAD = 64 * 1024;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

/* 每条记录：kind（item 预算项 / plan 预算设定）、id、trip、mt（修改时间，负数表示已删除）、payload（记录 JSON）。
 * 写入时比较修改时间：只有更新的版本（含删除）才会覆盖，旧设备传上来的旧版本不会盖掉新数据。 */
let schemaReady = false;
async function ensureSchema(db) {
  if (schemaReady) return;
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS ledger_budget (
      kind TEXT NOT NULL, id TEXT NOT NULL, trip TEXT NOT NULL DEFAULT '', mt INTEGER NOT NULL, payload TEXT,
      PRIMARY KEY (kind, id))`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_ledger_budget_trip ON ledger_budget(trip)"),
  ]);
  schemaReady = true;
}

async function handleBudget(request, env) {
  const db = env.BUDGET_DB;
  if (!db) return json({ error: "budget sync not configured" }, 503);
  await ensureSchema(db);
  if (request.method === "GET") {
    const { results } = await db.prepare("SELECT kind, id, trip, mt, payload FROM ledger_budget").all();
    return json({ rows: results || [] });
  }
  if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
  let body;
  try { body = await request.json(); } catch { return json({ error: "invalid json" }, 400); }
  const changes = Array.isArray(body?.changes) ? body.changes : null;
  if (!changes || !changes.length || changes.length > MAX_CHANGES) return json({ error: "invalid changes" }, 400);
  const stmt = db.prepare(
    `INSERT INTO ledger_budget (kind, id, trip, mt, payload) VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(kind, id) DO UPDATE SET trip = excluded.trip, mt = excluded.mt, payload = excluded.payload
     WHERE abs(excluded.mt) >= abs(ledger_budget.mt)`
  );
  const batch = [];
  for (const c of changes) {
    const kind = String(c?.kind || ""), id = String(c?.id || ""), trip = String(c?.trip || "");
    const mt = Number(c?.mt);
    const payload = c?.payload == null ? null : String(c.payload);
    if (!BUDGET_KINDS.has(kind) || !id || id.length > 80 || trip.length > 80 || !Number.isFinite(mt) || mt === 0) {
      return json({ error: "invalid change" }, 400);
    }
    if (payload && payload.length > MAX_PAYLOAD) return json({ error: "payload too large" }, 413);
    batch.push(stmt.bind(kind, id, trip, Math.trunc(mt), mt < 0 ? null : payload));
  }
  await db.batch(batch);
  return json({ ok: true, count: batch.length });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/.cloud/")) return proxyCloud(request, url);
    if (url.pathname === "/api/budget") {
      try { return await handleBudget(request, env); }
      catch (error) { return json({ error: String(error?.message || error) }, 500); }
    }
    if (url.pathname === "/plan") return Response.redirect(new URL("/plan/", url).href, 301);
    return env.ASSETS.fetch(request);
  },
};
