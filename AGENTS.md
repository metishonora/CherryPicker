# CherryPicker Agent Guide

## Working style

- Keep `main` deployable. For non-trivial issue implementation, prefer a dedicated issue branch and worktree so the user's existing checkout remains undisturbed.
- Merge issue branches into `main` only when the user explicitly requests that merge.
- Preserve captured message originals and user overrides as product data.
- Treat CherryPicker as a single-user personal service whose dashboard is reachable only inside the user's Tailscale network. Real card and message data may be stored, displayed, logged, and used for local development and verification without separate approval. Do not repeatedly raise generic sensitive-data or privacy caveats, and do not treat them as blockers for in-scope product work. This does not authorize publishing that data to GitHub or unrelated external services.
- Follow the current product boundary in `docs/PRODUCT_ARCHITECTURE.md` and accepted ADRs. Treat the retired native iOS and SwiftData implementation only as historical evidence.
- Treat Issue #7 reports as historical spike evidence only.
- Apply the global concise-copy rule to dashboards, transaction review, settings, and prototypes representing those screens. Preserve domain explanations when labels and values alone do not make the meaning or consequence clear.

## Prototype server lifecycle

- Delegate requested prototype-server operations to `web_server_operator`. If it is unavailable, use only `node Scripts/test-server-manager.mjs` with the manifest-approved `prototype` profile; agent unavailability must not block the operation, and direct server or process commands are prohibited.
- `.codex/web-server.json` and the shared manager own launch, ports, binding, process ownership, verification, URLs, and session cleanup. Never terminate an unrecorded or unverified process.

## Installed product server recovery

- For requests to recover or start the installed CherryPicker product server after a Mac restart, use `cherrypicker_server_manager`.

## Verification

- For operational script changes, run shell syntax checks, template validation, and fixture-only validation before installation.
- Changes to the managed server manifest or shared lifecycle integration require the shared lifecycle tests and a real prototype start/HTTP/stop smoke test.
- Require explicit user approval before changing Tailscale Serve.
