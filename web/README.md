# Badwater Ignition — web app (`ignition.badwater.guide`)

A standalone, offline-capable web build of the Badwater Ignition field tool
(Humidity · Ignition · **Obs**). Everything runs in the browser — the IRPG
(PMS 461) tables, the belt‑weather‑kit psychrometrics, the radio script, and the
IMET `.xlsx` export are all computed locally, so it works with no signal on the
fireline and sends no data anywhere.

## What's in this folder

| File | Purpose |
|---|---|
| `index.html` | App shell + styles (inline CSS); loads the two scripts below. |
| `engine.js` | **Pure calculation engine** — the JS twin of `Sources/BadwaterCore` (IRPG tables, psychrometrics, radio script, IMET `.xlsx`). No DOM/storage/clock, so Node loads it for conformance testing. |
| `app.js` | UI layer — state, rendering, event wiring (the twin of `App/`). |
| `manifest.webmanifest` | PWA manifest (installable, standalone display). |
| `sw.js` | Service worker — caches the app for **offline** use. **Bump `CACHE` on every web change** or field devices keep the old app. |
| `icon.svg`, `icon-512.png`, `apple-touch-icon.png` | App icons / favicon. |
| `netlify.toml` | Publish dir + security headers + caching. |
| `robots.txt` | Allow indexing. |

This is a **static site — there is no build step** and no dependencies. The
port's fidelity to `BadwaterCore` is not taken on trust: CI replays golden
vectors generated from the Swift core against `engine.js` on every push
(`node conformance/check-web.js` — see [`docs/PARITY.md`](../docs/PARITY.md)),
down to byte-exact `.xlsx` output. Still: decision support only — verify
numbers against your own IRPG.

## Deploy to Netlify

### Option A — from this Git repo (recommended; auto‑deploys on push)

1. In Netlify: **Add new site → Import an existing project → GitHub →
   `domalhambra/badwater-ignition`**.
2. Build settings:
   - **Base directory:** `web`
   - **Build command:** *(leave empty)*
   - **Publish directory:** `.` (relative to the base — i.e. `web/`)
   - Netlify will read `web/netlify.toml` for the headers.
3. **Deploy.** You'll get a `random-name.netlify.app` URL to confirm it works.

### Option B — drag‑and‑drop (fastest one‑off)

Drag this **`web/` folder** onto the Netlify **Sites** page
(Add new site → Deploy manually). Done.

## Point `ignition.badwater.guide` at it

You own `badwater.guide`, so add the **`ignition`** subdomain:

1. Netlify site → **Domain management → Add a domain** → enter
   `ignition.badwater.guide` → **Verify / Add**.
2. Create the DNS record at your `badwater.guide` DNS host:
   - **If your DNS is elsewhere (Cloudflare, Namecheap, etc.):** add a
     **CNAME** record — Host/Name `ignition`, Value **`<your-site>.netlify.app`**
     (the exact target Netlify shows on the domain screen). On Cloudflare, set
     the record to **DNS only** (grey cloud) at least until HTTPS is issued.
   - **If you use Netlify DNS for `badwater.guide`:** Netlify adds the record
     for you — just confirm.
3. Wait for DNS to propagate (usually minutes, up to a few hours). Netlify then
   **auto‑provisions a Let's Encrypt certificate** — no action needed. Enable
   **Force HTTPS** once the cert is issued.

That's it — `https://ignition.badwater.guide` will serve the app, installable to a
phone home screen ("Add to Home Screen"), and usable offline after the first
load.

## Updating

- **Option A:** push to the branch Netlify tracks; it redeploys automatically.
- **Option B:** drag the folder again.

When you change any cached asset, bump the cache name in `sw.js`
(`badwater-ignition-v4` → `-v5`) so returning devices fetch the new version.

## Notes / limitations

- This JS port is kept in sync with the Swift `BadwaterCore` by hand; the Swift
  test suite is the source of truth for the numbers.
- Data (the current shift, site/radio header) lives in the browser's local
  storage on that device — it is not synced or backed up. Export the `.xlsx`
  for a durable record.
- Decision‑support only; not affiliated with or endorsed by NWS/NWCG.
