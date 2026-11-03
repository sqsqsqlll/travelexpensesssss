/**
 * Cloudflare Worker：把 travel.sqsqsq.online/.cloud/* 转发到 WorkBuddy 云端。
 * 浏览器只和本站同域通信，不再触发跨域（CORS）拦截。
 *
 * 路由（Workers Routes）：travel.sqsqsq.online/.cloud/*
 * 其余路径不经过本 Worker，仍由 OSS 返回网页。
 */
const UPSTREAM = "https://travel-aa-ledger-72643.app.workbuddy.host";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/.cloud/")) return fetch(request);

    const target = new URL(url.pathname + url.search, UPSTREAM);
    const headers = new Headers(request.headers);
    // 以 WorkBuddy 自己的来源身份请求，避免上游按 Origin 拒绝
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
    // 同域访问不需要这些跨域头，去掉以免干扰
    response.headers.delete("Access-Control-Allow-Origin");
    response.headers.delete("Set-Cookie");
    return response;
  },
};
