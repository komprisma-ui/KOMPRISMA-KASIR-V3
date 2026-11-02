const CACHE_NAME = "kasira-offline-shell-v1";
const CORE_ASSETS = ["/", "/index.html", "/manifest.webmanifest", "/kasira-icon.svg"];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(CORE_ASSETS);
    try {
      const response = await fetch("/index.html", { cache: "no-store" });
      if (response.ok) {
        const html = await response.clone().text();
        const assets = [...html.matchAll(/(?:src|href)="(\/assets\/[^"]+)"/g)].map(match => match[1]);
        await cache.addAll(assets);
      }
    } catch { /* The current app shell remains cached. */ }
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name => name.startsWith("kasira-offline-") && name !== CACHE_NAME).map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(request);
        if (fresh.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put("/index.html", fresh.clone());
        }
        return fresh;
      } catch {
        return (await caches.match(request)) || (await caches.match("/index.html")) || Response.error();
      }
    })());
    return;
  }

  if (url.pathname.startsWith("/assets/") || CORE_ASSETS.includes(url.pathname)) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;
      try {
        const fresh = await fetch(request);
        if (fresh.ok) await cache.put(request, fresh.clone());
        return fresh;
      } catch {
        return cached || Response.error();
      }
    })());
  }
});
