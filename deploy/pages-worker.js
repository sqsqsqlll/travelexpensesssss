/**
 * Cloudflare Pages（advanced mode）入口：构建时复制为 dist/_worker.js。
 * - /.cloud/*：同域转发到 WorkBuddy 云端，浏览器不再触发跨域（CORS）拦截，账本云同步可用
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/.cloud/")) return proxyCloud(request, url);
    if (url.pathname === "/plan") return Response.redirect(new URL("/plan/", url).href, 301);
    return env.ASSETS.fetch(request);
  },
};
