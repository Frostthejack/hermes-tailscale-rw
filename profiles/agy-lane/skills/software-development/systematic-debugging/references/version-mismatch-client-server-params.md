# Version Mismatch Debugging: Client/Server API Parameter Drift

## Pattern

A persistent warning like:
```
Unknown parameters ignored: [time_field] for GET /v1/default/banks/hermes/stats/memories-timeseries
```
repeated every few seconds, with no obvious source in your own code.

## Root Cause Shape

This is almost always a **version mismatch** between:
- A **dashboard/UI client** (e.g., Control Plane, admin panel) that was updated to send new API parameters
- An **API server** that hasn't been updated yet and doesn't recognize those parameters

The client sends query parameters that the server doesn't declare in its endpoint signature. The server's "unknown params" middleware then logs a warning on every request.

## Diagnostic Steps

### 1. Confirm it's aversion mismatch

Check the server version:
```bash
# For pipx-installed Python servers
pipx list | grep <package>

# For npm-installed servers
npm list -g <package>
```

Check the client version:
```bash
# For Next.js/npm clients — check the bundled JS source
# Download the package tarball:
npm pack @scope/package --pack-destination /tmp/
tar -xzf /tmp/package.tgz -C /tmp/ctrlplane
grep -rn "unknown_param" /tmp/ctrlplane/ --include="*.js" -l
```

### 2. Find the offending parameter in the client source

Search the extracted client bundle for the parameter name:
```bash
grep -rn "time_field" /tmp/ctrlplane/ --include="*.js" | head -20
```

Look for the `getMemoriesTimeseries` (or equivalent) method — it will show the parameter being appended to the URL:
```js
async getMemoriesTimeseries(t, e, a = "created_at") {
  return this.fetchApi(
    n(t, `/memories-timeseries?period=${encodeURIComponent(e)}&time_field=${encodeURIComponent(a)}`)
  )
}
```

### 3. Find the server endpoint signature

Search the server's installed source for the endpoint handler:
```bash
grep -rn "memories.timeseries\|memories-timeseries" \
  ~/.local/share/pipx/venvs/<server>/lib/python*/site-packages/<server>/api/ \
  --include="*.py"
```

Check the function signature — whatever's NOT in the signature but IS in the client URL is the mismatch.

### 4. Consult the changelog

Look at the **server's** changelog for the version that added the parameter:
- `https://<project-url>/changelog`
- GitHub releases page

The version that added the parameter support will be noted as something like:
```
feat(stats): add time_field toggle to memories-timeseries chart
```

### 5. Identify the fix direction

- **Upgrade the server** to match the client (recommended) — the server needs to accept the parameter
- **Downgrade the client** to match the server — but harder to pin with `npx`
- **Suppress the warning** — doesn't fix the real issue if the parameter is actually needed for correct behavior

## Real-World Example

- **Server**: `hindsight-api` v0.5.6 (installed via pipx) — only accepts `period` on `/stats/memories-timeseries`
- **Client**: `@vectorize-io/hindsight-control-plane` v0.6.2 (run via `npx`) — sends `time_field=created_at` by default
- **Warning**: Logged every ~5 seconds (polling interval of the Control Plane dashboard)
- **Fix**: Upgrade `hindsight-api` to v0.6.x to match the Control Plane

## Key Insight

When you see repeated "unknown parameter" warnings from a server middleware, **always suspect version drift between a UI client and the API server**. The client was updated to send a new parameter before the server was updated to accept it. The `npx` command always fetches the latest client, but pipx/apt/etc. server packages may lag behind.

## Common Client/Server Mismatch Patterns

| Client | Server | Typical Mismatch |
|--------|--------|-----------------|
| Next.js dashboard (npx) | Python API server (pipx) | npm latest vs. pipx pinned |
| Flutter/mobile app | REST API | app store release vs. server deploy |
| Browser extension | Backend API | auto-upgraded extension vs. staged backend |
