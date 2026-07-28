// Tombstone service worker for the retired badwater.guide origin.
//
// This origin no longer serves the app. It lives at
// https://ignition.plateworks.org/ now. An installed PWA cannot follow an HTTP
// redirect: its service worker answers fetches before the network, so the old
// app would keep running from cache forever. This worker replaces the old one
// on its next update check, deletes every cache, unregisters itself, and sends
// any open windows to the new origin.
//
// Deployed from the `tombstone` branch, which the legacy badwater-ignition
// Netlify site is pinned to. `main` still carries the live app, serving from
// the plateworks-ignition site. Do not merge this branch.

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (e) => {
  e.waitUntil((async () => {
    await self.clients.claim();
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: "window" });
    clients.forEach((c) => c.navigate("https://ignition.plateworks.org/"));
  })());
});

// Never answer from cache again. Every fetch goes to the network, which now
// serves the tombstone page and its redirect.
self.addEventListener("fetch", (e) => {
  e.respondWith(fetch(e.request));
});
